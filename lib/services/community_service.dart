import 'dart:convert';
import 'package:flutter/foundation.dart';
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
  // UPVOTES (Deprecated in favor of SupabaseService)
  // ============================================

  @Deprecated('Use SupabaseService.toggleUpvote instead')
  Future<bool> hasUpvoted(String reportId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    try {
      final response = await _client
          .from('pothole_upvotes')
          .select('id')
          .eq('report_id', int.parse(reportId))
          .eq('user_id', user.id)
          .maybeSingle();
      return response != null;
    } catch (e) {
      return false;
    }
  }

  @Deprecated('Use SupabaseService.toggleUpvote instead')
  Future<bool> toggleUpvote(String reportId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    
    // We should transition all calls to SupabaseService.toggleUpvote(reportId, user.id)
    return false;
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
    final avatarUrl = user.userMetadata?['avatar_url'] ?? '';
    final isVerified = user.userMetadata?['phone_verified'] == true;
    
    try {
      await _client.from('pothole_comments').insert({
        'report_id': int.parse(reportId),
        'device_id': deviceId,
        'user_id': user.id,
        'user_name': fullName,
        'avatar_url': avatarUrl,
        'content': content.trim(),
        'user_metadata': {
          'phone_verified': isVerified,
        },
      });
      
      await _deviceService.addPoints(3, reason: 'comment');

      _notifyOwner(reportId, "Komen Baru!", "$fullName memberi komen: \"${content.trim()}\"");
      
      return true;
    } catch (e) {
      debugPrint('Error adding comment: $e');
      return false;
    }
  }

  Future<void> _notifyOwner(String reportId, String title, String message) async {
    try {
      final reportIdInt = int.tryParse(reportId);
      if (reportIdInt == null) return;

      final report = await _client
          .from('pothole_reports')
          .select('reporter_push_id, user_id')
          .eq('id', reportIdInt)
          .single();
      
      final pushId = report['reporter_push_id'];
      final ownerId = report['user_id'];
      final currentUser = _client.auth.currentUser;

      // Jangan hantar notifikasi jika pengomen adalah pemilik laporan itu sendiri
      if (currentUser != null && ownerId == currentUser.id) {
        return;
      }

      if (pushId != null && pushId.toString().isNotEmpty) {
        await _sendNotification(
          targetPushId: pushId.toString(),
          title: title,
          message: message,
        );
      }
    } catch (e) {
      debugPrint('Failed to notify owner: $e');
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
