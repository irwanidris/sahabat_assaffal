import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/assaffal_report.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  // ============ CITY STATISTICS ============

  /// Get overall city statistics
  Future<Map<String, dynamic>> getCityStats() async {
    try {
      final allReports = await _client
          .from('pothole_reports')
          .select('id, status, created_at, severity')
          .order('created_at', ascending: false);

      final reports = allReports as List;
      
      int total = reports.length;
      int pending = reports.where((r) => r['status'] == 'pending' || r['status'] == 'processing').length;
      int resolved = reports.where((r) => r['status'] == 'resolved').length;
      
      // Severity breakdown
      int critical = reports.where((r) => r['severity'] == 'critical').length;
      int high = reports.where((r) => r['severity'] == 'high').length;
      int medium = reports.where((r) => r['severity'] == 'medium').length;
      int low = reports.where((r) => r['severity'] == 'low').length;

      return {
        'total': total,
        'pending': pending,
        'resolved': resolved,
        'resolutionRate': total > 0 ? (resolved / total * 100).round() : 0,
        'severity': {
          'critical': critical,
          'high': high,
          'medium': medium,
          'low': low,
        },
      };
    } catch (e) {
      debugPrint('Error getting city stats: $e');
      return {
        'total': 0,
        'pending': 0,
        'resolved': 0,
        'resolutionRate': 0,
        'severity': {'critical': 0, 'high': 0, 'medium': 0, 'low': 0},
      };
    }
  }

  /// Get reports grouped by area for heatmap
  Future<List<Map<String, dynamic>>> getAreaHeatmapData() async {
    try {
      final reports = await _client
          .from('pothole_reports')
          .select('area_name, latitude, longitude, status, severity, upvote_count');

      final areaMap = <String, Map<String, dynamic>>{};
      
      for (var report in reports as List) {
        final area = report['area_name'] ?? 'Unknown';
        if (!areaMap.containsKey(area)) {
          areaMap[area] = {
            'area': area,
            'count': 0,
            'pending': 0,
            'resolved': 0,
            'lat': report['latitude'],
            'lon': report['longitude'],
            'totalUpvotes': 0,
          };
        }
        areaMap[area]!['count'] = (areaMap[area]!['count'] as int) + 1;
        areaMap[area]!['totalUpvotes'] = (areaMap[area]!['totalUpvotes'] as int) + (report['upvote_count'] ?? 0);
        if (report['status'] != 'resolved') {
          areaMap[area]!['pending'] = (areaMap[area]!['pending'] as int) + 1;
        } else if (report['status'] == 'resolved') {
          areaMap[area]!['resolved'] = (areaMap[area]!['resolved'] as int) + 1;
        }
      }

      final sortedAreas = areaMap.values.toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
      
      return sortedAreas;
    } catch (e) {
      debugPrint('Error getting heatmap data: $e');
      return [];
    }
  }

  /// Get monthly trend data
  Future<List<Map<String, dynamic>>> getMonthlyTrends() async {
    try {
      final reports = await _client
          .from('pothole_reports')
          .select('created_at, status')
          .order('created_at', ascending: true);

      final monthlyData = <String, Map<String, int>>{};
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

      for (var report in reports as List) {
        final date = DateTime.parse(report['created_at']);
        final monthKey = '${months[date.month - 1]} ${date.year}';
        
        if (!monthlyData.containsKey(monthKey)) {
          monthlyData[monthKey] = {'reported': 0, 'resolved': 0};
        }
        monthlyData[monthKey]!['reported'] = (monthlyData[monthKey]!['reported'] ?? 0) + 1;
        if (report['status'] == 'resolved') {
          monthlyData[monthKey]!['resolved'] = (monthlyData[monthKey]!['resolved'] ?? 0) + 1;
        }
      }

      return monthlyData.entries.map((e) => {
        'month': e.key,
        'reported': e.value['reported'],
        'resolved': e.value['resolved'],
      }).toList();
    } catch (e) {
      debugPrint('Error getting monthly trends: $e');
      return [];
    }
  }

  // ============ PERSONAL IMPACT STATS ============

  /// Get personal impact statistics for a device
  Future<Map<String, dynamic>> getPersonalStats(String deviceId) async {
    try {
      // Get user profile
      final profile = await _client
          .from('device_users')
          .select()
          .eq('device_id', deviceId)
          .maybeSingle();

      // Get user's reports - Termasuk category untuk pengiraan spesifik
      final userReports = await _client
          .from('pothole_reports')
          .select('id, status, severity, upvote_count, created_at, category')
          .eq('device_id', deviceId);

      final reports = userReports as List;
      int totalReports = reports.length;
      int resolvedReports = reports.where((r) => r['status'] == 'resolved').length;
      int totalUpvotes = reports.fold(0, (sum, r) => sum + ((r['upvote_count'] ?? 0) as int));
      
      // PENGKHUSUSAN: Hanya Lubang Jalan yang 'resolved' dikira untuk jarak
      final int resolvedPotholesCount = reports.where((r) => 
        r['status'] == 'resolved' && r['category'] == 'Lubang Jalan'
      ).length;

      // Anggaran setiap 1 lubang jalan yang dibaiki = 5 meter impak
      double roadsImproved = resolvedPotholesCount * 5.0;

      // Get upvotes given by this user
      final upvotesGiven = await _client
          .from('pothole_upvotes')
          .select('id')
          .eq('device_id', deviceId)
          .count(CountOption.exact);

      return {
        'totalReports': totalReports,
        'resolvedReports': resolvedReports,
        'pendingReports': totalReports - resolvedReports,
        'totalUpvotesReceived': totalUpvotes,
        'upvotesGiven': upvotesGiven.count ?? 0,
        'roadsImprovedMeters': roadsImproved,
        'points': profile?['points'] ?? 0,
        'currentStreak': profile?['current_streak'] ?? 0,
        'longestStreak': profile?['longest_streak'] ?? 0,
        'badges': List<String>.from(profile?['badges'] ?? []),
        'rank': await _calculateRank(deviceId),
      };
    } catch (e) {
      debugPrint('Error getting personal stats: $e');
      return {
        'totalReports': 0,
        'resolvedReports': 0,
        'pendingReports': 0,
        'totalUpvotesReceived': 0,
        'upvotesGiven': 0,
        'roadsImprovedMeters': 0,
        'points': 0,
        'currentStreak': 0,
        'longestStreak': 0,
        'badges': <String>[],
        'rank': 0,
      };
    }
  }

  /// Calculate user's rank among all users
  Future<int> _calculateRank(String deviceId) async {
    try {
      final allUsers = await _client
          .from('device_users')
          .select('device_id, total_reports')
          .order('total_reports', ascending: false);

      int rank = 1;
      for (var user in allUsers as List) {
        if (user['device_id'] == deviceId) {
          return rank;
        }
        rank++;
      }
      return rank;
    } catch (e) {
      return 0;
    }
  }

  /// Get leaderboard
  Future<List<Map<String, dynamic>>> getLeaderboard({int limit = 10}) async {
    try {
      final users = await _client
          .from('device_users')
          .select('device_id, display_name, total_reports, points, badges')
          .order('total_reports', ascending: false)
          .limit(limit);

      return (users as List).map((u) => {
        'deviceId': u['device_id'],
        'name': u['display_name'] ?? 'Anonymous Hero',
        'reports': u['total_reports'] ?? 0,
        'points': u['points'] ?? 0,
        'badges': List<String>.from(u['badges'] ?? []),
      }).toList();
    } catch (e) {
      debugPrint('Error getting leaderboard: $e');
      return [];
    }
  }

  // ============ TOP PRIORITY AREAS ============

  /// Get areas with most pending critical issues
  Future<List<Map<String, dynamic>>> getTopPriorityAreas({int limit = 5}) async {
    try {
      final reports = await _client
          .from('pothole_reports')
          .select('area_name, severity, upvote_count')
          .eq('status', 'pending')
          .order('upvote_count', ascending: false);

      final areaScores = <String, int>{};
      
      for (var report in reports as List) {
        final area = report['area_name'] ?? 'Unknown';
        int score = report['upvote_count'] ?? 0;
        
        // Add severity weight
        switch (report['severity']) {
          case 'critical':
            score += 10;
            break;
          case 'high':
            score += 5;
            break;
          case 'medium':
            score += 2;
            break;
          default:
            score += 1;
        }
        
        areaScores[area] = (areaScores[area] ?? 0) + score;
      }

      final sortedAreas = areaScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return sortedAreas.take(limit).map((e) => {
        'area': e.key,
        'priorityScore': e.value,
      }).toList();
    } catch (e) {
      debugPrint('Error getting priority areas: $e');
      return [];
    }
  }
}
