import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/onesignal_config.dart';
import 'device_service.dart';

class CommunityService {
  static final CommunityService _instance = CommunityService._internal();
  factory CommunityService() => _instance;
  CommunityService._internal();

  final SupabaseClient _client = Supabase.instance.client;
  final DeviceService _deviceService = DeviceService();

  // ============================================
  // NOTIFICATIONS
  // ============================================

  Future<void> _sendNotification({
    required String targetPushId,
    required String title,
    required String message,
  }) async {
    if (targetPushId.isEmpty) return;

    try {
      await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic ${OneSignalConfig.restApiKey}',
        },
        body: jsonEncode({
          'app_id': OneSignalConfig.appId,
          'include_player_ids': [targetPushId],
          'headings': {'en': title},
          'contents': {'en': message},
          'android_accent_color': 'FF0000',
          'small_icon': 'ic_stat_onesignal_default',
          // TAMBAH BUNYI CUSTOM DI SINI
          'android_sound': 'assaffal_sound', // Nama fail tanpa .mp3
          'ios_sound': 'assaffal_sound.wav', // Nama fail dengan extension
        }),
      );
    } catch (e) {
      print('Error sending push: $e');
    }
  }

  // ============================================
  // UPVOTES
  // ============================================

  Future<bool> hasUpvoted(String reportId) async {
    final deviceId = await _deviceService.getDeviceId();
    try {
      final response = await _client
          .from('upvotes')
          .select('id')
          .eq('report_id', int.parse(reportId))
          .eq('device_id', deviceId)
          .maybeSingle();
      return response != null;
    } catch (e) {
      return false;
    }
  }

  Future<bool> toggleUpvote(String reportId) async {
    final deviceId = await _deviceService.getDeviceId();
    final reportIdInt = int.parse(reportId);
    
    try {
      final hasVoted = await hasUpvoted(reportId);
      
      if (hasVoted) {
        await _client
            .from('upvotes')
            .delete()
            .eq('report_id', reportIdInt)
            .eq('device_id', deviceId);
        
        await _client.rpc('decrement_upvote_count', params: {'p_report_id': reportIdInt});
        return false;
      } else {
        await _client.from('upvotes').insert({
          'report_id': reportIdInt,
          'device_id': deviceId,
        });
        
        await _client.rpc('increment_upvote_count', params: {'p_report_id': reportIdInt});
        await _deviceService.addPoints(5, reason: 'upvote');

        _notifyOwner(reportId, "Seseorang menyokong laporan anda!", "Laporan kerosakan jalan anda mendapat sokongan baru.");
        
        return true;
      }
    } catch (e) {
      return false;
    }
  }

  // ============================================
  // COMMENTS
  // ============================================

  Future<List<Map<String, dynamic>>> getComments(String reportId) async {
    try {
      final response = await _client
          .from('pothole_comments')
          .select()
          .eq('report_id', int.parse(reportId))
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  Future<bool> addComment(String reportId, String content) async {
    final user = _client.auth.currentUser;
    if (user == null || content.trim().isEmpty) return false;
    
    final deviceId = await _deviceService.getDeviceId();
    final fullName = user.userMetadata?['full_name'] ?? 'Pengguna Google';
    final isVerified = user.userMetadata?['phone_verified'] == true;
    
    try {
      await _client.from('pothole_comments').insert({
        'report_id': int.parse(reportId),
        'device_id': deviceId,
        'user_id': user.id,
        'user_name': fullName,
        'content': content.trim(),
        'user_metadata': {
          'phone_verified': isVerified,
        },
      });
      
      await _deviceService.addPoints(3, reason: 'comment');

      _notifyOwner(reportId, "Komen Baru!", "$fullName memberi komen: \"${content.trim()}\"");
      
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _notifyOwner(String reportId, String title, String message) async {
    try {
      final report = await _client
          .from('pothole_reports')
          .select('reporter_push_id')
          .eq('id', int.parse(reportId))
          .single();
      
      final pushId = report['reporter_push_id'];
      if (pushId != null && pushId.toString().isNotEmpty) {
        await _sendNotification(
          targetPushId: pushId.toString(),
          title: title,
          message: message,
        );
      }
    } catch (e) {
      print('Failed to notify owner: $e');
    }
  }

  Future<bool> updateComment(int commentId, String content) async {
    final user = _client.auth.currentUser;
    if (user == null || content.trim().isEmpty) return false;

    try {
      await _client
          .from('pothole_comments')
          .update({'content': content.trim()})
          .eq('id', commentId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteComment(int commentId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    try {
      await _client
          .from('pothole_comments')
          .delete()
          .eq('id', commentId);
      return true;
    } catch (e) {
      return false;
    }
  }

  bool isAdmin() {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final role = user.userMetadata?['role'];
    final isAdminEmail = user.email?.endsWith('@sahabatassaffal.hero') ?? false;
    return role == 'admin' || isAdminEmail;
  }

  // ============================================
  // OTHERS
  // ============================================

  Future<void> incrementShareCount(String reportId) async {
    try {
      final reportIdInt = int.parse(reportId);
      final response = await _client.from('pothole_reports').select('share_count').eq('id', reportIdInt).single();
      final currentCount = (response['share_count'] ?? 0) as int;
      await _client.from('pothole_reports').update({'share_count': currentCount + 1}).eq('id', reportIdInt);
      await _deviceService.addPoints(2, reason: 'share');
    } catch (e) {}
  }
}
