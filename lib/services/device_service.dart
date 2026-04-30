import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class DeviceService {
  static final DeviceService _instance = DeviceService._internal();

  factory DeviceService() => _instance;

  DeviceService._internal();

  final SupabaseClient _client = Supabase.instance.client;
  String? _deviceId;
  Map<String, dynamic>? _userProfile;

  // Get unique device ID
  Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');

    if (_deviceId == null) {
      _deviceId = await _generateDeviceId();
      await prefs.setString('device_id', _deviceId!);
    }

    return _deviceId!;
  }

  // Generate device ID from hardware info
  Future<String> _generateDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    String id;

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      id = androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      id = iosInfo.identifierForVendor ?? DateTime
          .now()
          .millisecondsSinceEpoch
          .toString();
    } else {
      id = DateTime
          .now()
          .millisecondsSinceEpoch
          .toString();
    }

    return 'device_$id';
  }

  // Get or create user profile
  Future<Map<String, dynamic>> getOrCreateProfile() async {
    if (_userProfile != null) return _userProfile!;

    final deviceId = await getDeviceId();
    final user = _client.auth.currentUser;

    try {
      dynamic response;

      // 1. Cuba cari mengikut user_id (Akaun Google)
      if (user != null) {
        response = await _client
            .from('device_users')
            .select()
            .eq('user_id', user.id)
            .maybeSingle();
      }

      // 2. Jika tak jumpa, cari mengikut device_id
      if (response == null) {
        response = await _client
            .from('device_users')
            .select()
            .eq('device_id', deviceId)
            .filter('user_id', 'is', null)
            .maybeSingle();
      }

      if (response == null) {
        // Create new profile
        final Map<String, dynamic> insertData = {
          'device_id': deviceId,
          'nickname': 'Sahabat #${DateTime.now().millisecondsSinceEpoch % 10000}',
          'points': 30,
          'total_reports': 0,
          'badges': [],
          'last_login_date': DateTime.now().toIso8601String().split('T')[0],
        };

        if (user != null) {
          insertData['user_id'] = user.id;
          final avatarUrl = user.userMetadata?['avatar_url'] ??
              user.userMetadata?['picture'] ??
              user.userMetadata?['google_avatar_url'];
          if (avatarUrl != null) insertData['avatar_url'] = avatarUrl;
        }

        response = await _client.from('device_users').insert(insertData).select().single();
      } else {
        // Update profile with latest info
        final Map<String, dynamic> updateData = {'device_id': deviceId};
        if (user != null && response['user_id'] == null) {
          updateData['user_id'] = user.id;
        }

        if (updateData.isNotEmpty) {
          final updated = await _client
              .from('device_users')
              .update(updateData)
              .eq('id', response['id'])
              .select()
              .single();
          response = updated;
        }
      }

      // Check for Daily Login
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      if (response['last_login_date'] != todayStr) {
        final currentPoints = (response['points'] as int?) ?? 0;
        await _client.from('device_users').update({
          'points': currentPoints + 10,
          'last_login_date': todayStr,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', response['id']);

        response = await _client
            .from('device_users')
            .select()
            .eq('id', response['id'])
            .single();
      }

      _userProfile = response;
      return _userProfile!;
    } catch (e) {
      debugPrint('CRITICAL PROFILE ERROR: $e');
      return {
        'id': null,
        'device_id': deviceId,
        'nickname': null,
        'points': 0,
        'total_reports': 0,
        'badges': [],
      };
    }
  }

  // Update Avatar in Database
  Future<void> updateAvatar(String avatarUrl) async {
    try {
      final profile = await getOrCreateProfile();
      // Pastikan id tidak null dan bukan 0 (mod pelawat ralat)
      if (profile['id'] == null || profile['id'] == 0) return;

      await _client.from('device_users').update({
        'avatar_url': avatarUrl,
        'updated_at': DateTime.now().toIso8601String()
      }).eq('id', profile['id']);

      _userProfile = null; // Reset cache supaya data terbaru diambil semula
    } catch (e) {
      debugPrint('Error updating avatar in DB: $e');
    }
  }

  // Add points and check for new badges
  Future<List<String>> addPoints(int points, {String? reason}) async {
    try {
      final profile = await getOrCreateProfile();
      final id = profile['id'];
      if (id == null || id == 0) return [];

      final currentPoints = (profile['points'] as int?) ?? 0;
      final totalReports = (profile['total_reports'] as int?) ?? 0;
      final currentBadges = List<String>.from(profile['badges'] ?? []);

      final newBadges = await _applyPointsAndCheckBadges(
          id, currentPoints, points, totalReports, currentBadges,
          reason: reason);
      _userProfile = null;
      return newBadges;
    } catch (e) {
      debugPrint('Error adding points: $e');
      return [];
    }
  }

  Future<List<String>> _applyPointsAndCheckBadges(dynamic id, int currentPoints,
      int pointsToAdd, int totalReports, List<String> currentBadges,
      {String? reason}) async {
    final List<String> newBadges = [];
    final int newPoints = currentPoints + pointsToAdd;

    await _client
        .from('device_users')
        .update(
        {'points': newPoints, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', id);

    final pointBadges = {
      'bronze_hero': 500,
      'silver_hero': 2500,
      'gold_hero': 5000,
      'diamond_hero': 10000
    };
    bool badgesChanged = false;
    for (final entry in pointBadges.entries) {
      if (!currentBadges.contains(entry.key) && newPoints >= entry.value) {
        newBadges.add(entry.key);
        currentBadges.add(entry.key);
        badgesChanged = true;
      }
    }

    final reportBadges = {
      'first_report': 1,
      'reporter_5': 5,
      'reporter_10': 10,
      'reporter_25': 25,
      'reporter_50': 50,
      'reporter_100': 100
    };
    for (final entry in reportBadges.entries) {
      if (!currentBadges.contains(entry.key) && totalReports >= entry.value) {
        newBadges.add(entry.key);
        currentBadges.add(entry.key);
        badgesChanged = true;
      }
    }

    if (badgesChanged) {
      await _client.from('device_users').update({
        'badges': currentBadges,
        'updated_at': DateTime.now().toIso8601String()
      }).eq('id', id);
    }
    return newBadges;
  }

  Future<void> incrementReportCount() async {
    final profile = await getOrCreateProfile();
    final id = profile['id'];
    if (id == null || id == 0) return;

    final currentCount = (profile['total_reports'] as int?) ?? 0;
    try {
      await _client.from('device_users').update({
        'total_reports': currentCount + 1,
        'last_report_date': DateTime.now().toIso8601String().split('T')[0],
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      _userProfile = null;
    } catch (e) {}
  }

  bool _isReferralPromoActive() {
    final now = DateTime.now();
    final promoStart = DateTime(2026, 5, 1);
    final promoEnd = promoStart.add(const Duration(days: 90));
    return now.isAfter(promoStart) && now.isBefore(promoEnd);
  }

  Future<String?> processReferral(String code) async {
    try {
      final currentProfile = await getOrCreateProfile();
      if (currentProfile['id'] == null || currentProfile['id'] == 0) return 'Profil tidak tersedia.';
      if (currentProfile['referred_by'] != null)
        return 'Anda telah menggunakan kod rujukan sebelum ini.';
      if (currentProfile['nickname'] == code)
        return 'Anda tidak boleh menggunakan kod rujukan sendiri.';

      final referrer = await _client.from('device_users').select().eq(
          'nickname', code).maybeSingle();
      if (referrer == null) return 'Kod rujukan tidak sah.';

      final int referralPoints = _isReferralPromoActive()
          ? SupabaseService.POINTS_REFERRAL
          : SupabaseService.POINTS_REFERRAL_BASE;

      await addPointsToUser(referrer['id'], referralPoints,
          reason: 'Referral Success: ${currentProfile['nickname']}');
      await addPoints(referralPoints, reason: 'Referral Code Used: $code');
      await _client.from('device_users').update({'referred_by': code}).eq(
          'id', currentProfile['id']);
      return null;
    } catch (e) {
      return 'Ralat: $e';
    }
  }

  Future<void> addPointsToUser(dynamic id, int points, {String? reason}) async {
    try {
      final profile = await _client.from('device_users').select(
          'points, total_reports, badges').eq('id', id).single();
      await _applyPointsAndCheckBadges(
          id, profile['points'] ?? 0, points, profile['total_reports'] ?? 0,
          List<String>.from(profile['badges'] ?? []), reason: reason);
    } catch (e) {}
  }

  Future<String?> updateNickname(String nickname) async {
    final profile = await getOrCreateProfile();
    if (profile['id'] == null || profile['id'] == 0) return 'Sila log masuk semula.';
    if (profile['nickname'] == nickname) return null;

    final changeCount = (profile['nickname_change_count'] as int?) ?? 0;
    final lastChangedStr = profile['nickname_changed_at'];
    if (lastChangedStr != null) {
      final lastChanged = DateTime.parse(lastChangedStr);
      Duration restrictionDuration;
      if (changeCount == 1)
        restrictionDuration = const Duration(days: 14);
      else if (changeCount == 2)
        restrictionDuration = const Duration(days: 30);
      else
        restrictionDuration = const Duration(days: 60);

      final nextAllowedDate = lastChanged.add(restrictionDuration);
      if (DateTime.now().isBefore(nextAllowedDate)) {
        final difference = nextAllowedDate.difference(DateTime.now());
        if (difference.inDays > 0)
          return 'Anda hanya boleh menukar nickname semula dalam masa ${difference.inDays} hari lagi.';
        return 'Anda boleh menukar nickname semula dalam masa ${difference.inHours} jam lagi.';
      }
    }

    try {
      await _client.from('device_users').update({
        'nickname': nickname,
        'nickname_changed_at': DateTime.now().toIso8601String(),
        'nickname_change_count': changeCount + 1,
        'updated_at': DateTime.now().toIso8601String()
      }).eq('id', profile['id']);
      _userProfile = null;
      return null;
    } catch (e) {
      return 'Ralat sistem: Gagal mengemaskini nickname.';
    }
  }

  void clearCache() {
    _userProfile = null;
  }
  // Tambah fungsi ini untuk hilangkan Error 1 & 2
  Future<void> addPointsToUserByUserId(String userId, int points, {String? reason}) async {
    try {
      final profile = await _client.from('device_users').select('id, points, total_reports, badges').eq('user_id', userId).maybeSingle();
      if (profile != null) {
        await _applyPointsAndCheckBadges(profile['id'], profile['points'] ?? 0, points, profile['total_reports'] ?? 0, List<String>.from(profile['badges'] ?? []), reason: reason);
      }
    } catch (e) {
      debugPrint('Error adding points by user id: $e');
    }
  }

  // Tambah fungsi ini untuk hilangkan Error 4
  Future<List<Map<String, dynamic>>> getLeaderboard({int limit = 20}) async {
    try {
      final response = await _client
          .from('device_users')
          .select('nickname, points, avatar_url, badges')
          .order('points', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching leaderboard: $e');
      return [];
    }
  }
}