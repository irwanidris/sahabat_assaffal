import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/onesignal_config.dart';
import '../models/assaffal_report.dart';
import 'package:image/image.dart' as img;
import 'device_service.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;
  final DeviceService _deviceService = DeviceService();

  static const int POINTS_REPORT = 100;
  static const int POINTS_VOTE = 5;
  static const int POINTS_VERIFY = 20;
  static const int POINTS_DAILY_LOGIN = 10;
  static const int POINTS_FALSE_REPORT = -50;
  static const int POINTS_BONUS_REPORTER_RESOLVED = 200;

  // ============================================
  // NOTIFICATIONS ENGINE
  // ============================================

  Future<List<Map<String, dynamic>>> fetchNotifications({String? userId}) async {
    try {
      final fourteenDaysAgo = DateTime.now().subtract(const Duration(days: 14)).toIso8601String();
      try {
        await _client.from('notifications').delete().lt('created_at', fourteenDaysAgo);
      } catch (e) {}

      var query = _client.from('notifications').select();
      if (userId != null) {
        query = query.or('user_id.eq.$userId,user_id.is.null');
      }

      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
      return [];
    }
  }

  Future<void> submitReport({
    required String imageUrl,
    required double latitude,
    required double longitude,
    required String address,
    required String areaName,
    required String duration,
    String? description,
    String? userId,
    String severity = 'medium',
    required String category,
    String? reporterName,
    String? reporterContact,
    String? reporterPushId,
    int editCount = 0,
  }) async {
    try {
      // 1. Dapatkan profil (Guna username/user_id baru)
      final profile = await _deviceService.getOrCreateProfile();

      // Generate report code
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String reportCode = 'TK${timestamp.substring(timestamp.length - 5)}';

      // 2. Masukkan data ke Database pothole_reports
      // Kita gunakan profile['id'] (bigint) dan profile['username']
      await _client.from('pothole_reports').insert({
        'image_url': imageUrl,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'area_name': areaName,
        'description': description,
        'duration': duration,
        'status': 'pending',
        'device_id': profile['device_id'], // <--- PEMBETULAN DI SINI
        'user_id': userId ?? _client.auth.currentUser?.id,
        'severity': severity,
        'category': category,
        'reporter_name': profile['username'] ?? reporterName ?? 'Sahabat',
        'report_code': reportCode,
        'verified_still_exists': 0,
        'verified_resolved': 0,
        'verified_fake': 0,
      });

      // 3. Logic Notifikasi & Mata
      if (category == 'Lubang Jalan') {
        // Kita tidak gunakan 'await' supaya ralat notifikasi (seperti timeout)
        // tidak menyekat atau menggagalkan laporan utama.
        _sendPushNotification(
          toAll: true,
          title: "ADUAN BARU: $category 📍",
          message: "Aduan baru di $areaName. Sila bantu sahkan keadaan jalan ini!",
          data: {'type': 'report', 'id': reportCode, 'report_code': reportCode},
        ).catchError((e) => debugPrint('Push Notification failed (non-critical): $e'));
      }

      await saveNotification(
        title: "LAPORAN BERJAYA",
        message: "Laporan $reportCode anda di $areaName telah didaftarkan.",
        type: 'new_report',
        relatedId: reportCode,
        userId: userId ?? _client.auth.currentUser?.id,
      );

      await _deviceService.addPoints(POINTS_REPORT, reason: 'Lapor Masalah');
      await _deviceService.incrementReportCount();

    } catch (e) {
      debugPrint('Error in submitReport: $e');
      throw Exception('Gagal menghantar laporan: $e');
    }
  }

  // ============================================
  // REPORTS LOGIC
  // ============================================

  Future<List<AssaffalReport>> fetchReports({bool isAdmin = false}) async {
    try {
      // ✅ Guna profiles dengan foreign key yang betul
      var query = _client
          .from('pothole_reports')
          .select('*, profiles!pothole_reports_user_id_fkey(username, avatar_url)');

      if (!isAdmin) {
        query = query.or('category.eq.Lubang Jalan,status.neq.pending');
      }

      final response = await query.order('created_at', ascending: false);

      return (response as List).map((data) {
        final json = Map<String, dynamic>.from(data);

        // ✅ Rujuk profiles (bukan device_users)
        if (json['profiles'] != null) {
          final profileData = json['profiles'] as Map<String, dynamic>;
          final String latestName = profileData['username'] ?? 'Sahabat';

          json['reporter_name'] = latestName;  // ✅ Dari profiles, bukan table
          json['nickname'] = latestName;
          json['reporter_avatar'] = profileData['avatar_url'];
        }

        return AssaffalReport.fromJson(json);
      }).toList();

    } catch (e) {
      debugPrint('Error in fetchReports: $e');
      return [];
    }
  }

  Future<int> getReportCount() async {
    try {
      final response = await _client.from('pothole_reports').select('id').count(CountOption.exact);
      return response.count;
    } catch (e) { return 0; }
  }

  Future<void> deleteReport(String reportId) async {
    try {
      await _client.from('pothole_reports').delete().eq('id', int.tryParse(reportId) ?? reportId);
    } catch (e) { throw Exception('Gagal memadam laporan: $e'); }
  }

  // ============================================
  // UPVOTES & COMMUNITY
  // ============================================

  Future<bool> toggleUpvote(String reportId, String userId) async {
    try {
      final intId = int.tryParse(reportId);
      final existingUpvote = await _client.from('pothole_upvotes').select().eq('report_id', intId ?? reportId).eq('user_id', userId).maybeSingle();
      if (existingUpvote != null) {
        await _client.from('pothole_upvotes').delete().eq('report_id', intId ?? reportId).eq('user_id', userId);
        await _updateUpvoteCount(reportId, -1);
        return false;
      } else {
        await _client.from('pothole_upvotes').insert({'report_id': intId ?? reportId, 'user_id': userId});
        await _updateUpvoteCount(reportId, 1);
        await _deviceService.addPoints(POINTS_VOTE, reason: 'Sokong Aduan');
        return true;
      }
    } catch (e) { throw Exception('Failed to toggle upvote: $e'); }
  }

  Future<void> _updateUpvoteCount(String reportId, int delta) async {
    final intId = int.tryParse(reportId);
    final report = await _client.from('pothole_reports').select('upvote_count').eq('id', intId ?? reportId).single();
    final currentCount = report['upvote_count'] ?? 0;
    await _client.from('pothole_reports').update({'upvote_count': (currentCount + delta).clamp(0, 999999)}).eq('id', intId ?? reportId);
  }

  Future<void> verifyReportCommunity(String reportId, String userId, String type, {String? imageUrl}) async {
    try {
      final intId = int.tryParse(reportId);
      await _client.from('report_verifications').insert({'report_id': intId ?? reportId, 'user_id': userId, 'verification_type': type, 'proof_image_url': imageUrl});

      String column = type == 'exists' ? 'verified_still_exists' : (type == 'resolved' ? 'verified_resolved' : 'verified_fake');
      final currentData = await _client.from('pothole_reports').select(column).eq('id', intId ?? reportId).single();
      await _client.from('pothole_reports').update({column: (currentData[column] ?? 0) + 1}).eq('id', intId ?? reportId);
      await _deviceService.addPoints(POINTS_VERIFY, reason: 'Verifikasi');
    } catch (e) {}
  }

  // ============================================
  // NEWS ENGINE
  // ============================================

  Future<List<Map<String, dynamic>>> fetchNews({bool approvedOnly = true, String? author}) async {
    try {
      var query = _client.from('news').select();
      if (approvedOnly) query = query.eq('status', 'approved');
      if (author != null) query = query.eq('author', author);
      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) { return []; }
  }

  Future<void> createNews({required String title, required String content, String? imageUrl, required String author, required String authorId, required String category, String status = 'pending'}) async {
    await _client.from('news').insert({'title': title, 'content': content, 'image_url': imageUrl, 'author': author, 'author_id': authorId, 'category': category, 'status': status});
  }

  Future<void> updateNews({required dynamic id, required String title, required String content, String? imageUrl, required String category, String status = 'pending'}) async {
    await _client.from('news').update({'title': title, 'content': content, 'image_url': imageUrl, 'category': category, 'status': status}).eq('id', int.tryParse(id.toString()) ?? id);
  }

  Future<void> updateNewsStatus(dynamic newsId, String status) async {
    await _client.from('news').update({'status': status}).eq('id', newsId);
  }

  Future<void> deleteNews(dynamic newsId) async {
    await _client.from('news').delete().eq('id', newsId);
  }


  // ============================================
  // IMAGE HELPERS
  // ============================================

  // ============================================
  // IMAGE HELPERS
  // ============================================

  Future<String> uploadImage(File imageFile) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await imageFile.readAsBytes();

      await _client.storage.from('pothole-images').uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg')
      );

      return _client.storage.from('pothole-images').getPublicUrl(fileName);
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }

  // Pastikan TIADA fungsi _applyWatermark di bawah ini.


  // JANGAN LETAK LAGI FUNGSI _applyWatermark DI SINI

  Future<void> submitVerificationRequest({required String fullName, required String icNumber, required String address, required String phoneNumber, required File icFront, required File icBack}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final String frontUrl = await uploadImage(icFront);
    final String backUrl = await uploadImage(icBack);
    await _client.from('verification_requests').insert({'user_id': user.id, 'full_name_ic': fullName, 'ic_number': icNumber, 'home_address': address, 'phone_number': phoneNumber, 'ic_front_url': frontUrl, 'ic_back_url': backUrl, 'status': 'pending'});
    await _client.from('device_users').update({'verification_status': 'pending'}).eq('user_id', user.id);
  }

  Future<bool> verifyAdminCredentials(String username, String password) async {
    final response = await _client.from('admin_credentials').select('password').eq('username', username).eq('is_active', true).maybeSingle();
    return response != null && response['password'] == password;
  }

  // ============================================
  // HELPERS
  // ============================================

  Future<void> saveNotification({required String title, required String message, String? type, String? relatedId, String? userId}) async {
    try {
      await _client.from('notifications').insert({'title': title, 'message': message, 'type': type, 'related_id': relatedId, 'user_id': userId, 'is_read': false, 'created_at': DateTime.now().toIso8601String()});
    } catch (e) {}
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    final dynamic finalId = int.tryParse(notificationId) ?? notificationId;
    await _client.from('notifications').update({'is_read': true}).eq('id', finalId);
  }

  Future<void> markAllNotificationsAsRead(String? userId) async {
    var query = _client.from('notifications').update({'is_read': true});
    if (userId != null) query = query.or('user_id.eq.$userId,user_id.is.null');
    else query = query.isFilter('user_id', null);
    await query;
  }

  Future<void> updateReportStatus(String reportId, String status, {String? resolvedImageUrl, String? assignedTo, String? assignedName}) async {
    final Map<String, dynamic> updatePayload = {'status': status};
    if (resolvedImageUrl != null) updatePayload['resolved_image_url'] = resolvedImageUrl;
    if (assignedTo != null) updatePayload['assigned_to'] = assignedTo;
    if (assignedName != null) updatePayload['assigned_name'] = assignedName;
    await _client.from('pothole_reports').update(updatePayload).eq('id', int.tryParse(reportId) ?? reportId);
  }

  Future<void> softDeleteReport(String reportId, String nickname) async {
    await _client.from('pothole_reports').update({'deleted_at': DateTime.now().toIso8601String(), 'status': 'deleted_by_user'}).eq('id', int.tryParse(reportId) ?? reportId);
  }

  Future<void> restoreReport(String reportId) async {
    await _client.from('pothole_reports').update({'deleted_at': null, 'status': 'pending'}).eq('id', int.tryParse(reportId) ?? reportId);
  }

  Future<AssaffalReport?> checkForDuplicate(double latitude, double longitude, String? areaName) async {
    final response = await _client.from('pothole_reports').select().gte('latitude', latitude - 0.00045).lte('latitude', latitude + 0.00045).gte('longitude', longitude - 0.00045).lte('longitude', longitude + 0.00045).limit(1).maybeSingle();
    return response != null ? AssaffalReport.fromJson(response) : null;
  }

  Future<void> _sendPushNotification({List<String>? targetPushIds, bool toAll = false, List<Map<String, dynamic>>? filters, required String title, required String message, Map<String, dynamic>? data}) async {
    final Map<String, dynamic> body = {'app_id': OneSignalConfig.appId, 'headings': {'en': title}, 'contents': {'en': message}, if (data != null) 'data': data};
    if (toAll) body['included_segments'] = ['Subscribed Users'];
    else if (filters != null) body['filters'] = filters;
    else if (targetPushIds != null) body['include_subscription_ids'] = targetPushIds;
    await http.post(Uri.parse('https://api.onesignal.com/api/v1/notifications'), headers: {'Content-Type': 'application/json; charset=utf-8', 'Authorization': 'Basic ${OneSignalConfig.restApiKey}'}, body: jsonEncode(body)).timeout(const Duration(seconds: 10));
  }

  Future<void> sendChatNotification({required String senderName, required String message, required String senderUserId}) async {
    await _sendPushNotification(filters: [{"field": "tag", "key": "role", "relation": "=", "value": "admin_staff"}, {"operator": "AND"}, {"field": "tag", "key": "user_id", "relation": "!=", "value": senderUserId}], title: "Mesej Baru: $senderName", message: message);
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    return await _client.from('device_users').select().eq('user_id', userId).maybeSingle();
  }

  Future<List<Map<String, dynamic>>> fetchLeaderboard() async {
    final response = await _client.from('device_users').select('device_id, username, points').order('points', ascending: false).limit(20);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> updateReportData(String reportId, Map<String, dynamic> data) async {
    await _client.from('pothole_reports').update(data).eq('id', int.tryParse(reportId) ?? reportId);
  }
}