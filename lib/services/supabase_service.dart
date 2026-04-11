import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/onesignal_config.dart';
import '../models/pothole_report.dart';
import 'package:image/image.dart' as img;

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

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
        'android_accent_color': 'FF0000',
        'small_icon': 'ic_stat_onesignal_default',
        // BUNYI CUSTOM
        'android_sound': 'assaffal_sound',
        'ios_sound': 'assaffal_sound.wav',
      };

      if (toAll) {
        body['included_segments'] = ['Subscribed Users'];
      } else if (filters != null && filters.isNotEmpty) {
        body['filters'] = filters;
      } else if (targetPushIds != null && targetPushIds.isNotEmpty) {
        body['include_player_ids'] = targetPushIds;
      } else {
        return;
      }

      await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic ${OneSignalConfig.restApiKey}',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      debugPrint('Error sending notification: $e');
    }
  }

  // ============================================
  // REPORTS LOGIC
  // ============================================

  Future<List<PotholeReport>> fetchReports() async {
    try {
      final response = await _client
          .from('pothole_reports')
          .select()
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => PotholeReport.fromJson(json))
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
    String severity = 'medium',
    required String category,
    String? reporterName,
    String? reporterContact,
    String? reporterPushId,
    int editCount = 0,
  }) async {
    try {
      // Generate unique report code
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
        'status': 'pending',
        'device_id': deviceId,
        'severity': severity,
        'category': category,
        'reporter_name': reporterName,
        'reporter_contact': reporterContact,
        'reporter_push_id': reporterPushId,
        'edit_count': editCount,
        'report_code': reportCode,
      });

      await _sendPushNotification(
        toAll: true,
        title: "ADUAN SAHABAT ASSAFFAL",
        message: "Aduan Baru: $category di $areaName",
      );

    } catch (e) {
      throw Exception('Failed to submit report: $e');
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
          .select('reporter_push_id, category, area_name, assigned_to')
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

      final String pushId = reportData['reporter_push_id'] ?? '';
      if (pushId.isNotEmpty) {
        String title = "";
        String message = "Aduan anda bagi ${reportData['category']} di ${reportData['area_name']}";

        if (status == 'processing') {
          title = "ADUAN KINI DIPROSES";
          message = "$message sedang diambil tindakan oleh pihak berwajib.";
          
          await _sendPushNotification(
            targetPushIds: [pushId],
            title: title,
            message: message,
          );
        } else if (status == 'resolved') {
          title = "ADUAN SELESAI ✅";
          message = "Berita Baik! Aduan bagi ${reportData['category']} di ${reportData['area_name']} telah berjaya diselesaikan.";
          
          // Hantar kepada SEMUA orang supaya nampak kerja buat YB & Team
          await _sendPushNotification(
            toAll: true,
            title: title,
            message: message,
          );
        }
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

  Future<bool> sendEmailAutomated(PotholeReport report) async {
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

  Future<bool> toggleUpvote(String reportId, String deviceId) async {
    try {
      final intId = int.tryParse(reportId);
      final existingUpvote = await _client.from('pothole_upvotes').select().eq('report_id', intId ?? reportId).eq('device_id', deviceId).maybeSingle();
      if (existingUpvote != null) {
        await _client.from('pothole_upvotes').delete().eq('report_id', intId ?? reportId).eq('device_id', deviceId);
        await _updateUpvoteCount(reportId, -1);
        return false;
      } else {
        await _client.from('pothole_upvotes').insert({'report_id': intId ?? reportId, 'device_id': deviceId});
        await _updateUpvoteCount(reportId, 1);
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

  Future<PotholeReport?> checkForDuplicate(double latitude, double longitude, String? areaName) async {
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
      return PotholeReport.fromJson(response.first);
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
            return PotholeReport.fromJson(report);
          }
        }
      }
    }

    return null;
  }
}
