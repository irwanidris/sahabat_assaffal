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
  static const int POINTS_REPORT = 100; // Dinaikkan dari 50
  static const int POINTS_VOTE = 5;
  static const int POINTS_VERIFY = 20;
  static const int POINTS_FIRST_LOGIN = 30;
  static const int POINTS_REFERRAL = 95; // Nilai Promosi (90 Hari)
  static const int POINTS_REFERRAL_BASE = 30; // Nilai Asas selepas promo
  static const int POINTS_DAILY_LOGIN = 10;
  static const int POINTS_FALSE_REPORT = -50;
  static const int POINTS_VERIFIED_MEMBER = 500;
  static const int POINTS_BONUS_REPORTER_RESOLVED = 200;
  static const int POINTS_BONUS_VOTER_RESOLVED = 50;

  // ============================================
  // NOTIFICATIONS ENGINE
  // ============================================

  Future<List<Map<String, dynamic>>> fetchNotifications({String? userId}) async {
    try {
      // 1. Auto-Expiry: Padam notifikasi > 14 hari
      final fourteenDaysAgo = DateTime.now().subtract(const Duration(days: 14)).toIso8601String();
      try {
        await _client
            .from('notifications')
            .delete()
            .lt('created_at', fourteenDaysAgo);
      } catch (e) {
        debugPrint('Auto-expiry error: $e');
      }

      // 2. Ambil notifikasi
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
      // Cuba tukar ID kepada Integer jika ia adalah nombor,
      // kerana Supabase biasanya menggunakan Integer untuk Primary Key
      final dynamic finalId = int.tryParse(notificationId) ?? notificationId;

      await _client.from('notifications').update({
        'is_read': true,
      }).eq('id', finalId);

      debugPrint('Notification $notificationId marked as read in DB');
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> markAllNotificationsAsRead(String? userId) async {
    try {
      var query = _client.from('notifications').update({'is_read': true});
      if (userId != null) {
        // Tanda semua notifikasi peribadi DAN global sebagai baca
        query = query.or('user_id.eq.$userId,user_id.is.null');
      } else {
        // Jika tidak login, hanya tanda yang global
        query = query.isFilter('user_id', null);
      }
      await query;
      debugPrint('All notifications marked as read for user: $userId');
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

  Future<File> _applyWatermark(
    File imageFile, {
    bool isThumbnail = true,
    String? nickname,
    String? coords,
    String? dateTime,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);
      if (originalImage == null) return imageFile;

      // 1. Lukis Logo di tengah
      final ByteData watermarkData = await rootBundle.load('assets/images/logo_s_assaffal.png');
      final List<int> watermarkBytes = watermarkData.buffer.asUint8List();
      img.Image? watermark = img.decodeImage(Uint8List.fromList(watermarkBytes));

      if (watermark != null) {
        int watermarkSize = isThumbnail ? 120 : 180;
        watermark = img.copyResize(watermark, width: watermarkSize);
        int posX = (originalImage.width - watermark.width) ~/ 2;
        int posY = (originalImage.height - watermark.height) ~/ 2 - 40;

        img.compositeImage(
          originalImage,
          watermark,
          dstX: posX,
          dstY: posY,
          blend: img.BlendMode.alpha
        );
      }

      // 2. Lukis Teks Metadata di bawah Logo
      if (nickname != null || coords != null || dateTime != null) {
        String watermarkText = "";
        if (nickname != null) watermarkText += "Oleh: $nickname\n";
        if (dateTime != null) watermarkText += "$dateTime\n";
        if (coords != null) watermarkText += "GPS: $coords";

        int textY = (originalImage.height ~/ 2) + 60;

        img.drawString(
          originalImage,
          watermarkText,
          font: img.arial24,
          x: (originalImage.width ~/ 2) - 148,
          y: textY + 2,
          color: img.ColorRgba8(0, 0, 0, 160)
        );

        img.drawString(
          originalImage,
          watermarkText,
          font: img.arial24,
          x: (originalImage.width ~/ 2) - 150,
          y: textY,
          color: img.ColorRgba8(255, 255, 255, 255)
        );
      }

      final watermarkedBytes = img.encodeJpg(originalImage, quality: 85);

      // Guna path sementara untuk elak overwrite fail asal (elak overlapping jika retry)
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/wm_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(watermarkedBytes);

      return tempFile;
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
    Map<String, dynamic>? data,
  }) async {
    try {
      final Map<String, dynamic> body = {
        'app_id': OneSignalConfig.appId,
        'headings': {'en': title},
        'contents': {'en': message},
        'android_accent_color': 'FFE53935',
        'small_icon': 'ic_stat_onesignal_default',
        'android_sound': 'assaffal_sound',
        'ios_sound': 'assaffal_sound.wav',
        if (data != null) 'data': data,
      };

      if (toAll) {
        // 'Subscribed Users' adalah segmen default yang paling dipercayai
        body['included_segments'] = ['Subscribed Users'];
      } else if (filters != null && filters.isNotEmpty) {
        body['filters'] = filters;
      } else if (targetPushIds != null && targetPushIds.isNotEmpty) {
        // Gunakan include_subscription_ids untuk SDK versi baru
        body['include_subscription_ids'] = targetPushIds;
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
      debugPrint('OneSignal Response: ${response.body}');
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
          .from('device_users')
          .select()
          .eq('user_id', userId)
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

  Future<List<AssaffalReport>> fetchReports({bool isAdmin = false}) async {
    try {
      var query = _client
          .from('pothole_reports')
          .select('*'); // <--- Ambil data report sahaja tanpa join

      // Jika bukan admin, tapis mengikut logik privasi
      if (!isAdmin) {
        query = query.or('category.eq.Lubang Jalan,status.neq.pending');
      }

      final response = await query.order('created_at', ascending: false);

      return (response as List).map((data) {
        final json = Map<String, dynamic>.from(data);
        // Map joined data to model fields
        if (json['device_users'] != null) {
          json['reporter_nickname'] = json['device_users']['nickname'];
          json['reporter_avatar'] = json['device_users']['avatar_url'];
          json['nickname'] = json['device_users']['nickname'];
        }
        return AssaffalReport.fromJson(json);
      }).toList();
    } catch (e) {
      debugPrint('Error in fetchReports: $e');
      // Fallback to simple select if join fails
      try {
        var fallbackQuery = _client.from('pothole_reports').select('*');
        if (!isAdmin) {
          fallbackQuery = fallbackQuery.or('category.eq.Lubang Jalan,status.neq.pending');
        }
        final fallbackResponse = await fallbackQuery.order('created_at', ascending: false);
        return (fallbackResponse as List).map((data) {
          return AssaffalReport.fromJson(Map<String, dynamic>.from(data));
        }).toList();
      } catch (e2) {
        throw Exception('Failed to fetch reports: $e2');
      }
    }
  }

  Future<String> uploadImage(
    File imageFile, {
    bool applyWatermark = false,
    String? nickname,
    String? coords,
    String? dateTime,
  }) async {
    try {
      File fileToUpload = imageFile;
      if (applyWatermark) {
        fileToUpload = await _applyWatermark(
          imageFile,
          isThumbnail: false,
          nickname: nickname,
          coords: coords,
          dateTime: dateTime,
        );
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

      // Gunakan 5 angka terakhir dari timestamp untuk menjamin keunikan kod
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String uniqueSuffix = timestamp.substring(timestamp.length - 5);
      final reportCode = 'TK$uniqueSuffix';

      // --- KEMASKINI DI SINI: Buang .select().single() untuk elak ralat 42P10 ---
      // Gantikan blok insert sedia ada dengan ini
      await _client.from('pothole_reports').insert({
        'image_url': imageUrl,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'area_name': areaName,
        'description': description,
        'duration': duration,
        'status': 'pending',
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

// Memandangkan kita tak guna .select().single(),
// kita tak dapat ID untuk notifikasi, jadi kita guna reportCode sebagai rujukan buat masa ni.
      final String actualId = reportCode;

      // 3. Logic Notifikasi
      if (category == 'Lubang Jalan') {
        await _sendPushNotification(
          toAll: true,
          title: "ADUAN BERHAMPIRAN ANDA 📍",
          message: "Aduan baru di $areaName. Sila bantu sahkan keadaan jalan ini demi keselamatan bersama!",
          data: {'type': 'report', 'id': actualId, 'report_code': reportCode},
        );

        await _sendPushNotification(
          filters: [
            {"field": "tag", "key": "role", "relation": "=", "value": "admin_staff"}
          ],
          title: "🚨 PERHATIAN ADMIN",
          message: "Aduan Baru $reportCode memerlukan semakan di $areaName",
          data: {'type': 'report', 'id': actualId},
        );

        await saveNotification(
          title: "ADUAN SAHABAT ASSAFFAL",
          message: "Aduan Baru: $category di $areaName",
          type: 'new_report',
          relatedId: actualId,
        );
      } else {
        await _sendInternalEmailRaw(
          category: category,
          areaName: areaName,
          address: address,
          latitude: latitude,
          longitude: longitude,
          reporterName: reporterName,
          reporterContact: reporterContact,
          imageUrl: imageUrl,
          description: description,
        );
      }

      // Agihan Mata
      await _deviceService.addPoints(POINTS_REPORT, reason: 'Lapor Masalah');
      await _deviceService.incrementReportCount();

    } catch (e) {
      throw Exception('Failed to submit report: $e');
    }
  }

  Future<void> verifyReportCommunity(String reportId, String userId, String type, {String? imageUrl}) async {
    try {
      final intId = int.tryParse(reportId);

      // 1. Semak jika ini adalah aduan sendiri
      final reportCheck = await _client
          .from('pothole_reports')
          .select('user_id, device_id')
          .eq('id', intId ?? reportId)
          .single();

      if (reportCheck['user_id'] == userId) {
        throw Exception('Pengadu tidak dibenarkan mengundi laporan sendiri.');
      }

      // 2. Semak status Verified pengundi untuk menentukan Kuasa Undi
      final voterProfile = await _client
          .from('device_users')
          .select('is_verified, total_verifications')
          .eq('user_id', userId)
          .single();

      final bool isVoterVerified = voterProfile['is_verified'] == true;
      final int currentVoterVerifications = voterProfile['total_verifications'] ?? 0;
      final int voteWeight = isVoterVerified ? 2 : 1; // Kuasa undi berganda jika verified

      // 3. Simpan rekod verifikasi
      await _client.from('report_verifications').insert({
        'report_id': intId ?? reportId,
        'user_id': userId,
        'verification_type': type,
        'proof_image_url': imageUrl,
      });

      // 4. Kemaskini kaunter dalam pothole_reports
      String column = '';
      if (type == 'exists') column = 'verified_still_exists';
      else if (type == 'resolved') column = 'verified_resolved';
      else if (type == 'fake') column = 'verified_fake';

      if (column.isNotEmpty) {
        final currentData = await _client
            .from('pothole_reports')
            .select('$column, resolved_image_url, status')
            .eq('id', intId ?? reportId)
            .single();

        final int currentCount = currentData[column] ?? 0;
        final String currentStatus = currentData['status'] ?? 'pending';
        final String? existingResolvedImage = currentData['resolved_image_url'];

        final Map<String, dynamic> updateData = {
          column: currentCount + voteWeight
        };

        if (type == 'resolved' && imageUrl != null && existingResolvedImage == null) {
          updateData['resolved_image_url'] = imageUrl;
        }

        await _client
            .from('pothole_reports')
            .update(updateData)
            .eq('id', intId ?? reportId);

        // 5. Kemaskini jumlah verifikasi pengundi
        final Map<String, dynamic> userUpdate = {
          'total_verifications': currentVoterVerifications + 1,
          'updated_at': DateTime.now().toIso8601String(),
        };

        // Syarat Tambahan: Jika sahkan "Masih Ada" pada laporan MERAH
        if (type == 'exists' && (currentStatus == 'active' || currentStatus == 'processing')) {
          final profileRes = await _client.from('device_users').select('total_exists_verifications').eq('user_id', userId).single();
          int currentExistsVer = profileRes['total_exists_verifications'] ?? 0;
          userUpdate['total_exists_verifications'] = currentExistsVer + 1;
        }

        await _client.from('device_users').update(userUpdate).eq('user_id', userId);

        // 6. Logik Automatik Status
        if (type == 'resolved' && (currentCount + voteWeight) >= 5) {
          await updateReportStatus(reportId, 'resolved');

          final String reporterUserId = reportCheck['user_id'] ?? '';
          if (reporterUserId.isNotEmpty) {
            await _deviceService.addPointsToUserByUserId(reporterUserId, POINTS_BONUS_REPORTER_RESOLVED, reason: 'Bonus: Aduan Selesai Disahkan');
          }
        }

        if (type == 'fake' && (currentCount + voteWeight) >= 3) {
          await updateReportStatus(reportId, 'fake');
          final String reporterUserId = reportCheck['user_id'] ?? '';
          if (reporterUserId.isNotEmpty) {
            await _deviceService.addPointsToUserByUserId(reporterUserId, POINTS_FALSE_REPORT, reason: 'Aduan Palsu (Komuniti)');
          }
        }

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

      String title = "";
      String message = "";
      final String pushId = reportData['reporter_push_id'] ?? '';
      final String? ownerUserId = reportData['user_id'];
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
        } else if (ownerUserId != null) {
          await _sendPushNotification(
            filters: [
              {"field": "tag", "key": "user_id", "relation": "=", "value": ownerUserId}
            ],
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
        } else if (ownerUserId != null) {
          await _sendPushNotification(
            filters: [
              {"field": "tag", "key": "user_id", "relation": "=", "value": ownerUserId}
            ],
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
  Future<void> softDeleteReport(String reportId, String nickname) async {
    try {
      final intId = int.tryParse(reportId);
      final now = DateTime.now().toIso8601String();

      await _client.from('pothole_reports').update({
        'deleted_at': now,
        'status': 'deleted_by_user',
      }).eq('id', intId ?? reportId);

      // Maklumkan Admin
      await saveNotification(
        title: "LAPORAN DIPADAM PENGGUNA",
        message: "Laporan #$reportId telah dipadam oleh $nickname",
        type: 'report_deleted',
        relatedId: reportId,
      );
    } catch (e) {
      throw Exception('Gagal memadam laporan: $e');
    }
  }

  Future<void> restoreReport(String reportId) async {
    try {
      final intId = int.tryParse(reportId);
      await _client.from('pothole_reports').update({
        'deleted_at': null,
        'status': 'pending', // Kembalikan ke pending
      }).eq('id', intId ?? reportId);
    } catch (e) {
      throw Exception('Gagal memulihkan laporan: $e');
    }
  }

  Future<bool> sendEmailAutomated(AssaffalReport report) async {
    return _sendInternalEmailRaw(
      category: report.category,
      areaName: report.areaName ?? '',
      address: report.address ?? '',
      latitude: report.latitude,
      longitude: report.longitude,
      reporterName: report.reporterName,
      reporterContact: report.reporterContact,
      imageUrl: report.imageUrl,
      description: report.description,
    );
  }

  Future<bool> _sendInternalEmailRaw({
    required String category,
    required String areaName,
    required String address,
    required double latitude,
    required double longitude,
    String? reporterName,
    String? reporterContact,
    required String imageUrl,
    String? description,
  }) async {
    try {
      final String recipientEmail = category == 'Lain-lain'
          ? 'sahabatassaffal@gmail.com'
          : 'sahabatassaffal@gmail.com'; // Default ke email team management

      final response = await _client.functions.invoke(
        'send-report-email',
        body: {
          'to': recipientEmail,
          'cc': 'sahabatassaffal@gmail.com',
          'category': category,
          'area': areaName,
          'address': address,
          'gps': '$latitude, $longitude',
          'reporter': reporterName ?? 'Anonim',
          'contact': reporterContact ?? '-',
          'image': imageUrl,
          'description': description ?? '-',
        },
      );
      return response.status == 200;
    } catch (e) {
      debugPrint('Error sending internal email: $e');
      return false;
    }
  }

  Future<void> submitVerificationRequest({
    required String fullName,
    required String icNumber,
    required String address,
    required String phoneNumber,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Sila log masuk semula.');

    try {
      await _client.from('verification_requests').insert({
        'user_id': user.id,
        'full_name_ic': fullName,
        'ic_number': icNumber,
        'home_address': address,
        'phone_number': phoneNumber,
        'status': 'pending',
      });

      // Kemaskini status profil kepada pending
      await _client.from('device_users').update({
        'verification_status': 'pending',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('user_id', user.id);

      // Notifikasi Admin
      await _sendPushNotification(
        filters: [
            {"field": "tag", "key": "role", "relation": "=", "value": "admin_staff"}
        ],
        title: "🛡️ PERMOHONAN VERIFIKASI",
        message: "Seorang pengguna baru memohon status Verified User. Sila semak dokumen.",
      );
    } catch (e) {
      throw Exception('Gagal menghantar permohonan: $e');
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

  Future<void> deleteReport(String reportId) async {
    try {
      final intId = int.tryParse(reportId);
      await _client.from('pothole_reports').delete().eq('id', intId ?? reportId);
    } catch (e) {
      throw Exception('Gagal memadam laporan: $e');
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
