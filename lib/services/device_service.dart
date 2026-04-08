import 'dart:io';
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
      id = androidInfo.id; // Android ID
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      id = iosInfo.identifierForVendor ?? DateTime.now().millisecondsSinceEpoch.toString();
    } else {
      id = DateTime.now().millisecondsSinceEpoch.toString();
    }

    return 'device_$id';
  }

  // Get or create user profile
  Future<Map<String, dynamic>> getOrCreateProfile() async {
    if (_userProfile != null) return _userProfile!;

    final deviceId = await getDeviceId();

    try {
      // Try to fetch existing profile
      final response = await _client
          .from('device_users')
          .select()
          .eq('device_id', deviceId)
          .maybeSingle();

      if (response != null) {
        _userProfile = response;
        return _userProfile!;
      }

      // Create new profile
      final newProfile = await _client.from('device_users').insert({
        'device_id': deviceId,
        'nickname': 'Hero #${DateTime.now().millisecondsSinceEpoch % 10000}',
        'points': 0,
        'total_reports': 0,
        'badges': [],
      }).select().single();

      _userProfile = newProfile;
      return _userProfile!;
    } catch (e) {
      // Return default if error
      return {
        'device_id': deviceId,
        'points': 0,
        'total_reports': 0,
        'badges': [],
      };
    }
  }

  // Add points and check for new badges
  Future<List<String>> addPoints(int points, {String? reason}) async {
    final deviceId = await getDeviceId();
    List<String> newBadges = [];

    try {
      // Get current profile
      final profile = await getOrCreateProfile();
      final currentPoints = (profile['points'] as int?) ?? 0;
      final totalReports = (profile['total_reports'] as int?) ?? 0;
      final currentBadges = List<String>.from(profile['badges'] ?? []);

      // Update points
      await _client.from('device_users').update({
        'points': currentPoints + points,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('device_id', deviceId);

      // Check for new badges based on reports
      final badgesToCheck = {
        'first_report': 1,
        'reporter_5': 5,
        'reporter_10': 10,
        'reporter_25': 25,
        'reporter_50': 50,
        'reporter_100': 100,
      };

      for (final entry in badgesToCheck.entries) {
        if (!currentBadges.contains(entry.key) && totalReports >= entry.value) {
          newBadges.add(entry.key);
          currentBadges.add(entry.key);
        }
      }

      // Update badges if new ones earned
      if (newBadges.isNotEmpty) {
        await _client.from('device_users').update({
          'badges': currentBadges,
        }).eq('device_id', deviceId);
      }

      // Clear cache to refresh
      _userProfile = null;

      return newBadges;
    } catch (e) {
      return [];
    }
  }

  // Increment report count
  Future<void> incrementReportCount() async {
    final deviceId = await getDeviceId();
    final profile = await getOrCreateProfile();
    final currentCount = (profile['total_reports'] as int?) ?? 0;
    final lastReportDate = profile['last_report_date'];
    final currentStreak = (profile['current_streak'] as int?) ?? 0;
    final longestStreak = (profile['longest_streak'] as int?) ?? 0;

    // Calculate streak
    int newStreak = 1;
    final today = DateTime.now();
    
    if (lastReportDate != null) {
      final lastDate = DateTime.parse(lastReportDate);
      final difference = today.difference(lastDate).inDays;
      
      if (difference == 1) {
        // Consecutive day
        newStreak = currentStreak + 1;
      } else if (difference == 0) {
        // Same day
        newStreak = currentStreak;
      }
    }

    final newLongestStreak = newStreak > longestStreak ? newStreak : longestStreak;

    try {
      await _client.from('device_users').update({
        'total_reports': currentCount + 1,
        'last_report_date': today.toIso8601String().split('T')[0],
        'current_streak': newStreak,
        'longest_streak': newLongestStreak,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('device_id', deviceId);

      _userProfile = null; // Clear cache
    } catch (e) {
      // Ignore errors
    }
  }

  // Get leaderboard
  Future<List<Map<String, dynamic>>> getLeaderboard({int limit = 10}) async {
    try {
      final response = await _client
          .from('device_users')
          .select('nickname, points, total_reports, badges')
          .order('points', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  // Get user rank
  Future<int> getUserRank() async {
    final deviceId = await getDeviceId();
    try {
      final profile = await getOrCreateProfile();
      final userPoints = profile['points'] ?? 0;

      final response = await _client
          .from('device_users')
          .select('id')
          .gt('points', userPoints);

      return (response as List).length + 1;
    } catch (e) {
      return 0;
    }
  }

  // Clear cached profile
  void clearCache() {
    _userProfile = null;
  }
}
