import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
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

  // ============================================
  // POINTS CONSTANTS
  // ============================================
  static const int POINTS_REPORT = 50;
  static const int POINTS_VOTE = 5;
  static const int POINTS_VERIFY = 20;

  // ============================================
  // NOTIFICATIONS ENGINE
  // ============================================

  Future<List<Map<String, dynamic>>> fetchNotifications({String? userId}) async {
    try {
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

  Future<void> saveNotification({
    required String title,
    required String message,
    String? type,
    String? relatedId,
    String? userId,
  }) async {
    try {
      await _client.from('notifications').insert({
        'title': title,
        'message': message,
        'type': type,
        'related_id': relatedId,
        'user_id': userId,
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error saving notification: $e');
    }
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _client.from('notifications').update({
        'is_read': true,
      }).eq('id', notificationId);
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> markAllNotificationsAsRead(String? userId) async {
    try {
      var query = _client.from('notifications').update({'is_read': true});
      if (userId != null) {
        query = query.eq('user_id', userId);
      }
      await query;
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
    }
  }

  // ============================================
  // NEWS ENGINE
  // ============================================

  Future<List<Map<String, dynamic>>> fetchNews({bool approvedOnly = true, String? author}) async {
    try {
      var query = _client.from('news').select();
      
      if (approvedOnly) {
        query = query.eq('status', 'approved');
      }

      if (author != null) {
        query = query.eq('author', author);
      }
      
      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching news: $e');
      return [];
    }
  }

  Future<void> createNews({
    required String title,
    required String content,
    String? imageUrl,
    required String author,
    required String authorId,
    required String category,
    String status = 'pending',
  }) async {
    try {
      await _client.from('news').insert({
        'title': title,
        'content': content,
        'image_url': imageUrl,
        'author': author,
        'author_id': authorId,
        'category': category,
        'status': status,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error creating news: $e');
      throw e;
    }
  }

  Future<void> updateNews({
    required dynamic id,
    required String title,
    required String content,
    String? imageUrl,
    required String category,
    String status = 'pending',
  }) async {
    try {
      final intId = id is int ? id : int.tryParse(id.toString());
      await _client.from('news').update({
        'title': title,
        'content': content,
        'image_url': imageUrl,
        'category': category,
        'status': status,
        // Kita buang updated_at dari sini buat sementara jika DB belum ada kolum itu
      }).eq('id', intId ?? id);
    } catch (e) {
      debugPrint('Error updating news: $e');
      throw e;
    }
  }

  Future<void> updateNewsStatus(dynamic newsId, String status) async {
    try {
      final finalId = newsId; // Gunakan ID asal (String/UUID)
      debugPrint('Updating news $finalId to status $status');
      
      // 1. Dapatkan data berita dahulu
      final newsData = await _client.from('news')
          .select('title, category, author_id')
          .eq('id', finalId)
          .single();
      
      // 2. Kemaskini status
      await _client.from('news')
          .update({'status': status})
          .eq('id', finalId);

      debugPrint('Update command sent for news $finalId');

      // 3. Hantar notifikasi & Simpan Sejarah (Gunakan try-catch supaya tidak mengganggu update)
      try {
        if (status == 'approved') {
          final String title = newsData['title'] ?? 'Berita Baru';
          final String category = newsData['category'] ?? 'Berita';
          
          await _sendPushNotification(
            toAll: true,
            title: "BERITA SAHABAT ASSAFFAL",
            message: "[$category] $title",
          );

          await saveNotification(
            title: "BERITA SAHABAT ASSAFFAL",
            message: "[$category] $title",
            type: 'news_approved',
            relatedId: finalId.toString(),
          );
        } else if (status == 'rejected') {
          final String authorId = newsData['author_id'] ?? '';
          if (authorId.isNotEmpty) {
            await _sendPushNotification(
              filters: [
                {"field": "tag", "key": "user_id", "relation": "=", "value": authorId}
              ],
              title: "STATUS BERITA: PERLU KEMASKINI",
              message: "Sila Kemaskini Laporan Berita untuk Approval.",
            );

            await saveNotification(
              title: "STATUS BERITA: PERLU KEMASKINI",
              message: "Sila Kemaskini Laporan Berita untuk Approval.",
              type: 'news_rejected',
              relatedId: finalId.toString(),
              userId: authorId,
            );
          }
        }
      } catch (e) {
        debugPrint('Notification Silenced Error: $e');
        // Kita tidak throw ralat supaya UI tidak menunjukkan kegagalan 
        // sedangkan data DB sudah berjaya dikemaskini.
      }
    } catch (e) {
      debugPrint('Error updating news status: $e');
      throw e;
    }
  }

  Future<void> deleteNews(dynamic newsId) async {
    try {
      await _client.from('news').delete().eq('id', newsId);
    } catch (e) {
      debugPrint('Error deleting news: $e');
      throw e;
    }
  }

  // ============================================
  // IMAGE WATERMARK HELPERS
  // ============================================

  Future<File> _applyWatermark(File imageFile, {bool isThumbnail = true}) async {
    try {
      final bytes = await imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);
      if (originalImage == null) return imageFile;

      // Load watermark from assets
      final ByteData watermarkData = await rootBundle.load('assets/images/logo_s_assaffal.png');
      final List<int> watermarkBytes = watermarkData.buffer.asUint8List();
      img.Image? watermark = img.decodeImage(Uint8List.fromList(watermarkBytes));
      if (watermark == null) return imageFile;

      // Calculate watermark size (100-120 for thumbnails, 150 for full view)
      int watermarkSize = isThumbnail ? 120 : 150;
      watermark = img.copyResize(watermark, width: watermarkSize);

      // Set watermark opacity (0.5)
      // Note: image library doesn't have a direct opacity function for the whole image easily
      // but we can draw it with a composite function if needed, 
      // or just assume the asset itself is already semi-transparent or use it as is.
      // For simplicity in this implementation, we use drawImage.

      // Position: Center
      int posX = (originalImage.width - watermark.width) ~/ 2;
      int posY = (originalImage.height - watermark.height) ~/ 2;

      img.compositeImage(
        originalImage, 
        watermark, 
        dstX: posX, 
        dstY: posY,
        blend: img.BlendMode.alpha
      );

      final watermarkedBytes = img.encodeJpg(originalImage, quality: 80);
      final watermarkedFile = File(imageFile.path)..writeAsBytesSync(watermarkedBytes);
      return watermarkedFile;
    } catch (e) {
      debugPrint('Error applying watermark: $e');
      return imageFile;
    }
  }

  // ============================================
  // NOTIFICATION HELPERS
  // ============================================

  Future<void> _sendPushNotification({
    List<String>? targetPushIds,
    bool toAll = false,
    List<Map<String, String>>? filters,
    required String title,
    required String message,
  }) async {
    try {
      final Map<String, dynamic> body = {
        'app_id': OneSignalConfig.appId,
        'headings': {'en': title},
        'contents': {'en': message},
      };

      if (toAll) {
        body['included_segments'] = ['All'];
      } else if (filters != null && filters.isNotEmpty) {
        body['filters'] = filters;
      } else if (targetPushIds != null && targetPushIds.isNotEmpty) {
        body['include_player_ids'] = targetPushIds;
      } else {
        return;
      }

      // Gunakan timeout yang munasabah untuk mengelakkan UI 'freeze' lama
      final response = await http.post(
        Uri.parse('https://api.onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic ${OneSignalConfig.restApiKey}',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint('OneSignal API Error: ${response.statusCode} - ${response.body}');
        return;
      }
      
      final responseData = jsonDecode(response.body);
      debugPrint('OneSignal Success: ${responseData['recipients'] ?? 0} recipients');
    } catch (e) {
      // Kita log ralat tetapi tidak rethrow supaya tidak mengganggu flow utama (DB/Points/UI)
      debugPrint('Notification suppressed error: $e');
    }
  }

  // ============================================
  // USER PROFILES
  // ============================================

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchLeaderboard() async {
    try {
      final response = await _client
          .from('device_users')
          .select('device_id, display_name, points')
          .order('points', ascending: false)
          .limit(20);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching leaderboard: $e');
      return [];
    }
  }

  // ============================================
  // REPORTS LOGIC
  // ============================================

  Future<List<AssaffalReport>> fetchReports() async {
    try {
      final response = await _client
          .from('pothole_reports')
          .select()
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => AssaffalReport.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch reports: $e');
    }
  }

  Future<String> uploadImage(File imageFile, {bool applyWatermark = true}) async {
    try {
      File fileToUpload = imageFile;
      if (applyWatermark) {
        fileToUpload = await _applyWatermark(imageFile, isThumbnail: false);
      }
      
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await fileToUpload.readAsBytes();

      await _client.storage.from('pothole-images').uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );

      return _client.storage.from('pothole-images').getPublicUrl(fileName);
    } catch (e) {
      throw Exception('Failed to upload image: $e');
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
    String? deviceId,
    String? userId,
    String severity = 'medium',
    required String category,
    String? reporterName,
    String? reporterContact,
    String? reporterPushId,
    int editCount = 0,
  }) async {
    try {
      // 1. Anti-Spam Check: Limit 1 report per device every 3 minutes
      if (deviceId != null) {
        final threeMinutesAgo = DateTime.now().subtract(const Duration(minutes: 3)).toIso8601String();
        
        final existingReport = await _client
            .from('pothole_reports')
            .select('id')
            .eq('device_id', deviceId)
            .gt('created_at', threeMinutesAgo)
            .maybeSingle();

        if (existingReport != null) {
          throw Exception('Sila tunggu 3 minit sebelum menghantar laporan baru bagi mengelakkan spam.');
        }
      }

      // 2. Generate unique report code
      final countResponse = await _client.from('pothole_reports').select('id').count(CountOption.exact);
      final count = (countResponse.count ?? 0) + 1;
      final reportCode = 'AA${count.toString().padLeft(4, '0')}';

      await _client.from('pothole_reports').insert({
        'image_url': imageUrl,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'area_name': areaName,
        'description': description,
        'duration': duration,
        'status': 'active', // Terus aktif tanpa moderator
        'device_id': deviceId,
        'user_id': userId,
        'severity': severity,
        'category': category,
        'reporter_name': reporterName,
        'reporter_contact': reporterContact,
        'reporter_push_id': reporterPushId,
        'edit_count': editCount,
        'report_code': reportCode,
        'verified_still_exists': 0,
        'verified_resolved': 0,
        'verified_fake': 0,
      });

      await _sendPushNotification(
        toAll: true,
        title: "ADUAN SAHABAT ASSAFFAL",
        message: "Aduan Baru: $category di $areaName",
      );

      await saveNotification(
        title: "ADUAN SAHABAT ASSAFFAL",
        message: "Aduan Baru: $category di $areaName",
        type: 'new_report',
        relatedId: reportCode,
      );

      // Agihan Mata: Laporan Baru
      await _deviceService.addPoints(POINTS_REPORT, reason: 'Lapor Lubang');
      await _deviceService.incrementReportCount();

    } catch (e) {
      throw Exception('Failed to submit report: $e');
    }
  }

  Future<void> verifyReportCommunity(String reportId, String userId, String type, {String? imageUrl}) async {
    try {
      final intId = int.tryParse(reportId);
      
      // 1. Semak jika ini adalah aduan sendiri (Owner cannot vote)
      final reportCheck = await _client
          .from('pothole_reports')
          .select('user_id, device_id')
          .eq('id', intId ?? reportId)
          .single();
      
      if (reportCheck['user_id'] == userId) {
        throw Exception('Pengadu tidak dibenarkan mengundi laporan sendiri.');
      }

      // 2. Simpan rekod verifikasi (Unique constraint akan halang double vote dari user sama)
      await _client.from('report_verifications').insert({
        'report_id': intId ?? reportId,
        'user_id': userId,
        'verification_type': type,
        'proof_image_url': imageUrl,
      });

      // 2. Kemaskini kaunter dalam pothole_reports
      String column = '';
      if (type == 'exists') column = 'verified_still_exists';
      else if (type == 'resolved') column = 'verified_resolved';
      else if (type == 'fake') column = 'verified_fake';

      if (column.isNotEmpty) {
        final currentData = await _client
            .from('pothole_reports')
            .select('$column, resolved_image_url')
            .eq('id', intId ?? reportId)
            .single();
        
        final int currentCount = currentData[column] ?? 0;
        final String? existingResolvedImage = currentData['resolved_image_url'];
        
        final Map<String, dynamic> updateData = {
          column: currentCount + 1
        };

        // Jika ini adalah bukti selesai pertama atau kita mahu kemaskini bukti utama
        if (type == 'resolved' && imageUrl != null && existingResolvedImage == null) {
          updateData['resolved_image_url'] = imageUrl;
        }
        
        await _client
            .from('pothole_reports')
            .update(updateData)
            .eq('id', intId ?? reportId);

        // 3. Logik Automatik: Jika 'resolved' mencapai 5 undian, tukar status terus
        if (type == 'resolved' && (currentCount + 1) >= 5) {
          await updateReportStatus(reportId, 'resolved');
        }
        
        // 4. Logik Automatik: Jika 'fake' mencapai 3 undian, tandakan sebagai fake/archived
        if (type == 'fake' && (currentCount + 1) >= 3) {
          await updateReportStatus(reportId, 'fake');
        }

        // Agihan Mata: Verifikasi Komuniti
        await _deviceService.addPoints(POINTS_VERIFY, reason: 'Verifikasi Komuniti');
      }
    } catch (e) {
      if (e.toString().contains('unique_violation') || e.toString().contains('409')) {
        throw Exception('Anda sudah memberi maklum balas untuk aduan ini.');
      }
      throw Exception('Gagal menghantar maklum balas: $e');
    }
  }

  Future<void> updateReportData(String reportId, Map<String, dynamic> data) async {
    try {
      final intId = int.tryParse(reportId);
      await _client
          .from('pothole_reports')
          .update(data)
          .eq('id', intId ?? reportId);
    } catch (e) {
      throw Exception('Gagal mengemaskini laporan: $e');
    }
  }

  Future<void> updateReportStatus(
    String reportId, 
    String status, {
    String? resolvedImageUrl,
    String? assignedTo,
    String? assignedName,
  }) async {
    try {
      final intId = int.tryParse(reportId);
      
      final reportData = await _client
          .from('pothole_reports')
          .select('reporter_push_id, category, area_name, assigned_to, user_id')
          .eq('id', intId ?? reportId)
          .single();

      // Logik Sekatan: Jika sedang diproses, hanya moderator yang sama boleh ubah
      if (status == 'resolved' && assignedTo != null) {
         final currentAssignedTo = reportData['assigned_to'];
         if (currentAssignedTo != null && currentAssignedTo != assignedTo) {
           throw Exception('Aduan ini sedang diuruskan oleh moderator lain.');
         }
      }

      final Map<String, dynamic> updatePayload = {'status': status};
      if (resolvedImageUrl != null) {
        updatePayload['resolved_image_url'] = resolvedImageUrl;
      }
      
      // Simpan siapa yang ambil tugasan
      if (assignedTo != null) {
        updatePayload['assigned_to'] = assignedTo;
      }
      if (assignedName != null) {
        updatePayload['assigned_name'] = assignedName;
      }

      await _client
          .from('pothole_reports')
          .update(updatePayload)
          .eq('id', intId ?? reportId);

      // Notification Logic
      String title = "";
      String message = "";
      final String pushId = reportData['reporter_push_id'] ?? '';
      final String category = reportData['category'] ?? 'Aduan';
      final String area = reportData['area_name'] ?? 'Kawasan';

      if (status == 'processing') {
        title = "ADUAN KINI DIPROSES";
        message = "Aduan anda bagi $category di $area sedang diambil tindakan oleh pihak berwajib.";
        
        if (pushId.isNotEmpty) {
          await _sendPushNotification(
            targetPushIds: [pushId],
            title: title,
            message: message,
          );
        }

        await saveNotification(
          title: title,
          message: message,
          type: 'report_processing',
          relatedId: reportId,
          userId: reportData['user_id'],
        );
      } else if (status == 'resolved') {
        title = "ADUAN SELESAI ✅";
        message = "Berita Baik! Aduan bagi $category di $area telah berjaya diselesaikan.";
        
        // Hantar kepada SEMUA orang supaya nampak kerja buat YB & Team
        await _sendPushNotification(
          toAll: true,
          title: title,
          message: message,
        );

        await saveNotification(
          title: title,
          message: message,
          type: 'report_resolved',
          relatedId: reportId,
        );
      } else if (status == 'fake') {
        title = "STATUS ADUAN: PALSU/ARKIB";
        message = "Aduan anda bagi $category di $area telah ditandakan sebagai tidak sah oleh komuniti.";

        if (pushId.isNotEmpty) {
          await _sendPushNotification(
            targetPushIds: [pushId],
            title: title,
            message: message,
          );
        }

        await saveNotification(
          title: title,
          message: message,
          type: 'report_fake',
          relatedId: reportId,
          userId: reportData['user_id'],
        );
      }
    } catch (e) {
      throw Exception('Gagal mengemaskini status: $e');
    }
  }

  Future<void> sendChatNotification({
    required String senderName,
    required String message,
    required String senderUserId,
  }) async {
    await _sendPushNotification(
      filters: [
        {"field": "tag", "key": "role", "relation": "=", "value": "admin_staff"},
        {"operator": "AND"},
        {"field": "tag", "key": "user_id", "relation": "!=", "value": senderUserId}
      ],
      title: "Mesej Baru: $senderName",
      message: message,
    );
  }

  // ============================================
  // COMMENTS LOGIC
  // ============================================

  Future<List<Map<String, dynamic>>> fetchComments(String reportId) async {
    try {
      final intId = int.tryParse(reportId);
      final response = await _client
          .from('report_comments')
          .select()
          .eq('report_id', intId ?? reportId)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching comments: $e');
      return [];
    }
  }

  Future<void> addComment(String reportId, String comment) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('Sila log masuk untuk memberi komen.');

      String role = 'User';
      if (user.userMetadata?['is_yb'] == true) role = 'Penaung';
      else if (user.userMetadata?['is_admin'] == true) role = 'Admin';
      else if (user.userMetadata?['is_moderator'] == true) role = 'Moderator';

      final intId = int.tryParse(reportId);
      await _client.from('report_comments').insert({
        'report_id': intId ?? reportId,
        'user_id': user.id,
        'comment': comment,
        'sender_name': user.userMetadata?['full_name'] ?? 'Sahabat',
        'sender_role': role,
      });
    } catch (e) {
      throw Exception('Gagal menghantar komen: $e');
    }
  }

  Future<void> updateComment(dynamic commentId, String newComment) async {
    try {
      await _client.from('report_comments').update({
        'comment': newComment,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', commentId);
    } catch (e) {
      throw Exception('Gagal mengemaskini komen: $e');
    }
  }

  Future<void> deleteComment(dynamic commentId) async {
    try {
      await _client.from('report_comments').delete().eq('id', commentId);
    } catch (e) {
      throw Exception('Gagal memadam komen: $e');
    }
  }

  // --- Fungsi Lain ---
  Future<void> deleteReport(String reportId) async {
    try {
      final intId = int.tryParse(reportId);
      if (intId != null) {
        await _client.from('pothole_reports').delete().eq('id', intId).select();
      } else {
        await _client.from('pothole_reports').delete().eq('id', reportId).select();
      }
    } catch (e) {
      throw Exception('Failed to delete report: $e');
    }
  }

  Future<bool> sendEmailAutomated(AssaffalReport report) async {
    try {
      final String recipientEmail = report.category == 'Lain-lain' 
          ? 'sahabatassaffal@gmail.com' 
          : 'irwanyzan@gmail.com';

      final response = await _client.functions.invoke(
        'send-report-email',
        body: {
          'to': recipientEmail,
          'cc': 'sahabatassaffal@gmail.com',
          'category': report.category,
          'area': report.areaName,
          'address': report.address,
          'gps': '${report.latitude}, ${report.longitude}',
          'reporter': report.reporterName,
          'contact': report.reporterContact,
          'image': report.imageUrl,
          'description': report.description,
        },
      );
      return response.status == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyAdminCredentials(String username, String password) async {
    try {
      final response = await _client
          .from('admin_credentials')
          .select('password')
          .eq('username', username)
          .eq('is_active', true)
          .maybeSingle();
      if (response == null) return false;
      return response['password'] as String == password;
    } catch (e) {
      return false;
    }
  }

  Future<int> getReportCount() async {
    try {
      final response = await _client.from('pothole_reports').select('id').count(CountOption.exact);
      return response.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<bool> toggleUpvote(String reportId, String userId) async {
    try {
      final intId = int.tryParse(reportId);

      // 1. Semak jika aduan sendiri
      final reportCheck = await _client
          .from('pothole_reports')
          .select('user_id, device_id')
          .eq('id', intId ?? reportId)
          .single();
      
      if (reportCheck['user_id'] == userId) {
        throw Exception('Anda tidak boleh menyokong laporan anda sendiri.');
      }

      final existingUpvote = await _client.from('pothole_upvotes').select().eq('report_id', intId ?? reportId).eq('user_id', userId).maybeSingle();
      if (existingUpvote != null) {
        await _client.from('pothole_upvotes').delete().eq('report_id', intId ?? reportId).eq('user_id', userId);
        await _updateUpvoteCount(reportId, -1);
        return false;
      } else {
        await _client.from('pothole_upvotes').insert({'report_id': intId ?? reportId, 'user_id': userId});
        await _updateUpvoteCount(reportId, 1);
        
        // Agihan Mata: Sokongan (Upvote)
        await _deviceService.addPoints(POINTS_VOTE, reason: 'Sokong Aduan');

        return true;
      }
    } catch (e) {
      throw Exception('Failed to toggle upvote: $e');
    }
  }

  Future<void> _updateUpvoteCount(String reportId, int delta) async {
    final intId = int.tryParse(reportId);
    final report = await _client.from('pothole_reports').select('upvote_count').eq('id', intId ?? reportId).single();
    final currentCount = report['upvote_count'] ?? 0;
    await _client.from('pothole_reports').update({'upvote_count': (currentCount + delta).clamp(0, 999999)}).eq('id', intId ?? reportId);
  }

  String _normalizeAreaName(String name) {
    return name
        .toLowerCase()
        .replaceAll('kg ', 'kampung ')
        .replaceAll('kg.', 'kampung ')
        .replaceAll('tmn ', 'taman ')
        .replaceAll('tmn.', 'taman ')
        .replaceAll('jln ', 'jalan ')
        .replaceAll('jln.', 'jalan ')
        .trim();
  }

  Future<AssaffalReport?> checkForDuplicate(double latitude, double longitude, String? areaName) async {
    // 1. Semak berdasarkan koordinat (radius 50 meter)
    final radiusDegrees = 50 / 111000;
    final response = await _client
        .from('pothole_reports')
        .select()
        .gte('latitude', latitude - radiusDegrees)
        .lte('latitude', latitude + radiusDegrees)
        .gte('longitude', longitude - radiusDegrees)
        .lte('longitude', longitude + radiusDegrees)
        .order('upvote_count', ascending: false);

    if ((response as List).isNotEmpty) {
      return AssaffalReport.fromJson(response.first);
    }

    // 2. Jika koordinat tidak tepat, semak berdasarkan nama kawasan yang dinormalisasi
    if (areaName != null && areaName.isNotEmpty) {
      final normalizedInput = _normalizeAreaName(areaName);
      
      // Ambil laporan terbaru untuk semakan nama (limit 100 untuk prestasi)
      final allReports = await _client
          .from('pothole_reports')
          .select('id, area_name, image_url, latitude, longitude, status, created_at, upvote_count, category')
          .order('created_at', ascending: false)
          .limit(100);

      for (var report in allReports) {
        final existingName = report['area_name'] as String?;
        if (existingName != null) {
          if (_normalizeAreaName(existingName) == normalizedInput) {
            return AssaffalReport.fromJson(report);
          }
        }
      }
    }

    return null;
  }
}
