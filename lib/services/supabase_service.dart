import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/pothole_report.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  static const String _oneSignalAppId = "e9668216-1dc4-4567-8951-0eb406a75c46";
  static const String _oneSignalRestKey = "os_v2_app_5ftiefq5yrcwpckrb22anj24i32rjfdxzimuk7mury6kjtc3sz3nzca2vpwdsaymnkqebnjgolx2wckyz2eqypfringry4haupxgmqq";

  // ============================================
  // NOTIFICATION HELPERS
  // ============================================

  Future<void> _sendPushNotification({
    List<String>? targetPushIds,
    bool toAll = false,
    required String title,
    required String message,
  }) async {
    try {
      final Map<String, dynamic> body = {
        'app_id': _oneSignalAppId,
        'headings': {'en': title},
        'contents': {'en': message},
        'android_accent_color': 'FF0000',
      };

      if (toAll) {
        body['included_segments'] = ['Subscribed Users'];
      } else if (targetPushIds != null && targetPushIds.isNotEmpty) {
        body['include_player_ids'] = targetPushIds;
      } else {
        return;
      }

      await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic $_oneSignalRestKey',
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

  Future<String> uploadImage(File imageFile) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await imageFile.readAsBytes();

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
    String? reporterPushId, // Tambah push id pelapor
  }) async {
    try {
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
      });

      // NOTIFIKASI BARU: Hantar ke semua pengguna
      await _sendPushNotification(
        toAll: true,
        title: "ADUAN SAHABAT ASSAFFAL",
        message: "Aduan Baru: $category di $areaName",
      );

    } catch (e) {
      throw Exception('Failed to submit report: $e');
    }
  }

  Future<void> updateReportStatus(String reportId, String status) async {
    try {
      final intId = int.tryParse(reportId);
      
      // Ambil data laporan dahulu untuk dapatkan push_id pelapor
      final reportData = await _client
          .from('pothole_reports')
          .select('reporter_push_id, category, area_name')
          .eq('id', intId ?? reportId)
          .single();

      // Kemaskini status di database
      if (intId != null) {
        await _client.from('pothole_reports').update({'status': status}).eq('id', intId).select();
      } else {
        await _client.from('pothole_reports').update({'status': status}).eq('id', reportId).select();
      }

      // HANTAR NOTIFIKASI STATUS KEPADA PELAPOR
      final String pushId = reportData['reporter_push_id'] ?? '';
      if (pushId.isNotEmpty) {
        String title = "";
        String message = "Aduan anda bagi ${reportData['category']} di ${reportData['area_name']}";

        if (status == 'processing') {
          title = "ADUAN KINI DIPROSES";
          message = "$message sedang diambil tindakan oleh pihak berwajib.";
        } else if (status == 'resolved') {
          title = "ADUAN SELESAI";
          message = "$message telah berjaya diselesaikan. Terima kasih atas kerjasama anda!";
        }

        if (title.isNotEmpty) {
          await _sendPushNotification(
            targetPushIds: [pushId],
            title: title,
            message: message,
          );
        }
      }

    } catch (e) {
      throw Exception('Gagal mengemaskini status: $e');
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

  Future<PotholeReport?> checkForDuplicate(double latitude, double longitude) async {
    final radiusDegrees = 50 / 111000;
    final response = await _client.from('pothole_reports').select().gte('latitude', latitude - radiusDegrees).lte('latitude', latitude + radiusDegrees).gte('longitude', longitude - radiusDegrees).lte('longitude', longitude + radiusDegrees).order('upvote_count', ascending: false);
    if ((response as List).isEmpty) return null;
    return PotholeReport.fromJson(response.first);
  }
}
