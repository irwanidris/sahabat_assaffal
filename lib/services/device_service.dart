import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeviceService {
  static final DeviceService _instance = DeviceService._internal();
  factory DeviceService() => _instance;
  DeviceService._internal();

  final SupabaseClient _client = Supabase.instance.client;
  String? _deviceId;
  Map<String, dynamic>? _userProfile;

  Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');
    if (_deviceId == null) {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceId = 'device_${androidInfo.id}';
      } else {
        _deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
      }
      await prefs.setString('device_id', _deviceId!);
    }
    return _deviceId!;
  }

  Future<Map<String, dynamic>> getOrCreateProfile() async {
    if (_userProfile != null) return _userProfile!;

    final user = _client.auth.currentUser;
    final deviceId = await getDeviceId();

    try {
      dynamic response;

      if (user == null) {
        // Logik untuk Pelawat (Anonymous)
        response = await _client.from('device_users').select()
            .eq('device_id', deviceId).isFilter('user_id', null).maybeSingle();

        if (response == null) {
          response = await _client.from('device_users').insert({
            'device_id': deviceId,
            'user_id': null,
            'username': 'Pelawat #${DateTime.now().millisecondsSinceEpoch % 10000}',
            'points': 30,
            'total_reports': 0,
            'last_login_date': DateTime.now().toIso8601String().split('T')[0],
          }).select().single();
        }
      } else {
        // Logik untuk Pengguna Google (Guna user_id UUID)
        response = await _client.from('device_users').select()
            .eq('user_id', user.id).maybeSingle();

        if (response == null) {
          final Map<String, dynamic> insertData = {
            'user_id': user.id,
            'device_id': deviceId,
            'username': user.userMetadata?['full_name'] ?? 'Sahabat #${DateTime.now().millisecondsSinceEpoch % 10000}',
            'points': 30,
            'total_reports': 0,
            'last_login_date': DateTime.now().toIso8601String().split('T')[0],
          };

          final avatarUrl = user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'];
          if (avatarUrl != null) insertData['avatar_url'] = avatarUrl;

          response = await _client.from('device_users').insert(insertData).select().single();
        }
      }

      // Daily Login Points
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      if (response != null && response['last_login_date'] != todayStr) {
        await _client.from('device_users').update({
          'points': (response['points'] as int? ?? 0) + 10,
          'last_login_date': todayStr,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', response['id']);
        response = await _client.from('device_users').select().eq('id', response['id']).single();
      }

      _userProfile = response;

      // Backward compatibility: Pastikan UI yang cari 'nickname' tetap berfungsi
      if (_userProfile != null) {
        _userProfile!['nickname'] = _userProfile!['username'];
      }

      return _userProfile!;
    } catch (e) {
      debugPrint('CRITICAL PROFILE ERROR: $e');
      return {'id': 0, 'username': 'Pelawat', 'nickname': 'Pelawat', 'points': 0};
    }
  }

  Future<void> updateAvatar(String avatarUrl) async {
    try {
      final profile = await getOrCreateProfile();
      await _client.from('device_users').update({
        'avatar_url': avatarUrl,
        'updated_at': DateTime.now().toIso8601String()
      }).eq('id', profile['id']);
      _userProfile = null;
    } catch (e) {}
  }

  Future<void> addPoints(int points, {String? reason}) async {
    try {
      final profile = await getOrCreateProfile();
      final int newPoints = ((profile['points'] as int?) ?? 0) + points;
      await _client.from('device_users').update({
        'points': newPoints,
        'updated_at': DateTime.now().toIso8601String()
      }).eq('id', profile['id']);
      _userProfile = null;
    } catch (e) {}
  }

  Future<void> incrementReportCount() async {
    try {
      final profile = await getOrCreateProfile();
      final int currentCount = (profile['total_reports'] as int?) ?? 0;
      await _client.from('device_users').update({
        'total_reports': currentCount + 1,
        'updated_at': DateTime.now().toIso8601String()
      }).eq('id', profile['id']);
      _userProfile = null;
    } catch (e) {}
  }

  Future<String?> processReferral(String usernameCode) async {
    try {
      final currentProfile = await getOrCreateProfile();
      if (currentProfile['referred_by'] != null) return 'Anda telah menggunakan kod rujukan.';

      final referrer = await _client.from('device_users').select().eq('username', usernameCode).maybeSingle();
      if (referrer == null) return 'Username rujukan tidak sah.';

      await addPoints(30, reason: 'Referral');
      await _client.from('device_users').update({'referred_by': usernameCode}).eq('id', currentProfile['id']);
      return null;
    } catch (e) { return 'Ralat: $e'; }
  }

  // Digunakan oleh ProfileScreen
  Future<String?> updateNickname(String newUsername) async {
    try {
      final profile = await getOrCreateProfile();
      await _client.from('device_users').update({
        'username': newUsername,
        'updated_at': DateTime.now().toIso8601String()
      }).eq('id', profile['id']);
      _userProfile = null;
      return null;
    } catch (e) { return 'Ralat mengemaskini maklumat.'; }
  }

  Future<void> addPointsToUserByUserId(String userId, int points, {String? reason}) async {
    try {
      final profile = await _client.from('device_users').select('id, points').eq('user_id', userId).maybeSingle();
      if (profile != null) {
        await _client.from('device_users').update({
          'points': (profile['points'] ?? 0) + points
        }).eq('id', profile['id']);
      }
    } catch (e) {}
  }

  Future<List<Map<String, dynamic>>> getLeaderboard({int limit = 20}) async {
    try {
      final response = await _client.from('device_users')
          .select('username, points, avatar_url')
          .order('points', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) { return []; }
  }

  void clearCache() { _userProfile = null; }
}