import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/device_service.dart';
import '../theme/app_theme.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final DeviceService _deviceService = DeviceService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _topUsers = [];

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    try {
      final deviceService = DeviceService();
      final data = await deviceService.getLeaderboard(limit: 20);
      if (mounted) {
        setState(() {
          _topUsers = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading leaderboard: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Papan Pendahulu', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildPodium(isDarkMode),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 20),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _topUsers.length > 3 ? _topUsers.length - 3 : 0,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final user = _topUsers[index + 3];
                        final avatarUrl = user['avatar_url'] as String?;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                            backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
                            child: (avatarUrl == null || avatarUrl.isEmpty) 
                              ? Text('${index + 4}', style: const TextStyle(fontWeight: FontWeight.bold))
                              : null,
                          ),
                          title: Text(
                            user['nickname'] ?? 'Pengguna Anonim',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(_getBadgeName(user['badges'])),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                              const SizedBox(width: 4),
                              Text(
                                '${user['points']}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPodium(bool isDarkMode) {
    if (_topUsers.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // No 2
          if (_topUsers.length > 1) _buildPodiumItem(_topUsers[1], 2, 100, isDarkMode),
          // No 1
          _buildPodiumItem(_topUsers[0], 1, 140, isDarkMode),
          // No 3
          if (_topUsers.length > 2) _buildPodiumItem(_topUsers[2], 3, 80, isDarkMode),
        ],
      ),
    );
  }

  Widget _buildPodiumItem(Map<String, dynamic> user, int rank, double height, bool isDarkMode) {
    final avatarUrl = user['avatar_url'] as String?;
    return Column(
      children: [
        CircleAvatar(
          radius: rank == 1 ? 35 : 25,
          backgroundColor: rank == 1 ? Colors.amber : (rank == 2 ? Colors.grey.shade400 : Colors.orange.shade300),
          backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
          child: (avatarUrl == null || avatarUrl.isEmpty) ? const Icon(Icons.person, color: Colors.white) : null,
        ),
        const SizedBox(height: 8),
        Text(
          user['nickname']?.split(' ')[0] ?? 'User',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Container(
          width: 80,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                rank == 1 ? Colors.amber : (rank == 2 ? Colors.grey.shade400 : Colors.orange.shade300),
                rank == 1 ? Colors.amber.shade700 : (rank == 2 ? Colors.grey.shade600 : Colors.orange.shade600),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '#$rank',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
              ),
              const Icon(Icons.star_rounded, color: Colors.white70, size: 16),
              Text(
                '${user['points']}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getBadgeName(dynamic badges) {
    if (badges == null || (badges is List && badges.isEmpty)) return 'Sahabat Komuniti';
    final List list = badges is List ? badges : [];
    if (list.contains('diamond_hero')) return 'Diamond Hero 💎';
    if (list.contains('gold_hero')) return 'Gold Hero 🥇';
    if (list.contains('silver_hero')) return 'Silver Hero 🥈';
    if (list.contains('bronze_hero')) return 'Bronze Hero 🥉';
    if (list.contains('reporter_100')) return 'Wira 100 Aduan';
    if (list.contains('reporter_50')) return 'Wira 50 Aduan';
    return 'Sahabat Komuniti';
  }
}
