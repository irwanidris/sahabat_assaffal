import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Buang import platform spesifik yang menyebabkan konflik
import '../services/analytics_service.dart';
import '../services/device_service.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'news_screen.dart';
import 'notifications_list_screen.dart';

class CityDashboardScreen extends StatefulWidget {
  const CityDashboardScreen({super.key});

  @override
  State<CityDashboardScreen> createState() => _CityDashboardScreenState();
}

class _CityDashboardScreenState extends State<CityDashboardScreen> with SingleTickerProviderStateMixin {
  final AnalyticsService _analyticsService = AnalyticsService();
  final DeviceService _deviceService = DeviceService();
  final AuthService _authService = AuthService();
  final SupabaseService _supabaseService = SupabaseService();
  
  late TabController _tabController;
  StreamSubscription<AuthState>? _authSubscription;
  
  Map<String, dynamic> _cityStats = {};
  List<Map<String, dynamic>> _areaData = [];
  List<Map<String, dynamic>> _monthlyTrends = [];
  Map<String, dynamic> _personalStats = {};
  List<Map<String, dynamic>> _leaderboard = [];
  List<Map<String, dynamic>> _priorityAreas = [];
  List<Map<String, dynamic>> _newsList = [];
  
  bool _isLoading = true;
  bool _isNewsLoading = true;
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    
    // Dengar perubahan status login
    _authSubscription = _authService.authStateChanges.listen((data) {
      if (mounted) {
        setState(() {});
        _loadData();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      _deviceId = await _deviceService.getDeviceId();
      
      final results = await Future.wait([
        _analyticsService.getCityStats(),
        _analyticsService.getAreaHeatmapData(),
        _analyticsService.getMonthlyTrends(),
        _analyticsService.getPersonalStats(_deviceId ?? 'unknown'),
        _analyticsService.getLeaderboard(),
        _analyticsService.getTopPriorityAreas(),
        _supabaseService.fetchNews(),
      ]).timeout(const Duration(seconds: 15));
      
      if (mounted) {
        setState(() {
          _cityStats = results[0] as Map<String, dynamic>;
          _areaData = results[1] as List<Map<String, dynamic>>;
          _monthlyTrends = results[2] as List<Map<String, dynamic>>;
          _personalStats = results[3] as Map<String, dynamic>;
          _leaderboard = results[4] as List<Map<String, dynamic>>;
          _priorityAreas = results[5] as List<Map<String, dynamic>>;
          _newsList = results[6] as List<Map<String, dynamic>>;
          _isLoading = false;
          _isNewsLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading stats: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isNewsLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memuatkan data terkini.'))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final isLoggedIn = _authService.currentUser != null;
    
    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0a0a1a) : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Stack(
          children: [
            // KANDUNGAN ASAL
            Column(
              children: [
                _buildHeader(isDarkMode),
                _buildTabBar(isDarkMode),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildBeritaTerbaru(isDarkMode),
                            _buildCityOverview(isDarkMode),
                            _buildAreaAnalytics(isDarkMode),
                          ],
                        ),
                ),
              ],
            ),

            // LAPISAN BLUR JIKA TIDAK LOGIN
            if (!isLoggedIn)
              Positioned.fill(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: (isDarkMode ? Colors.black : Colors.white).withOpacity(0.4),
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 32),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: isDarkMode ? const Color(0xFF1a1a2e) : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, spreadRadius: 5)
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryRed.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.analytics_outlined, color: AppTheme.primaryRed, size: 40),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Analisis Terhad',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Log masuk diperlukan untuk melihat analisis data komuniti dan impak peribadi anda.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey, fontSize: 14),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: () async {
                                  try {
                                    await _authService.signInWithGoogle();
                                    _loadData();
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Gagal Log Masuk: $e'))
                                      );
                                    }
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryRed,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  minimumSize: const Size(double.infinity, 48),
                                ),
                                child: const Text('Log Masuk Sekarang', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1),
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.report_problem),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Statistik',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        'Suara Kita Semua',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.italic,
                          color: AppTheme.primaryRed,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const NotificationsListScreen()),
                    );
                  },
                  icon: Icon(
                    Icons.notifications_none_rounded,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                ),
                IconButton(
                  onPressed: _loadData,
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primaryRed, AppTheme.primaryBlue],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: isDarkMode ? Colors.white60 : Colors.black54,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Berita'),
          Tab(text: 'Ringkasan'),
          Tab(text: 'Kawasan'),
        ],
      ),
    );
  }

  Widget _buildBeritaTerbaru(bool isDarkMode) {
    if (_isNewsLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryRed));
    }

    if (_newsList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.newspaper, size: 64, color: (isDarkMode ? Colors.white24 : Colors.black12)),
            const SizedBox(height: 16),
            const Text('Tiada berita buat masa ini.'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _newsList.length,
        itemBuilder: (context, index) {
          final news = _newsList[index];
          return NewsCard(
            news: news, 
            isDarkMode: isDarkMode, 
            onTap: () => _showNewsDetail(news),
          );
        },
      ),
    );
  }

  void _showNewsDetail(Map<String, dynamic> news) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.6,
        maxChildSize: 0.97,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDarkMode ? AppTheme.darkBackground : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  children: [
                    if (news['image_url'] != null)
                      Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.network(
                              news['image_url'],
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryRed.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          (news['category'] ?? 'Umum').toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.primaryRed,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      news['title'] ?? '',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppTheme.primaryRed.withOpacity(0.1),
                          child: const Icon(Icons.person, size: 18, color: AppTheme.primaryRed),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              news['author'] ?? 'Admin',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isDarkMode ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              DateFormat('dd MMMM yyyy, hh:mm a').format(DateTime.parse(news['created_at'])),
                              style: TextStyle(
                                color: isDarkMode ? Colors.white38 : Colors.black38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Divider(),
                    ),
                    Text(
                      news['content'] ?? '',
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.8,
                        letterSpacing: 0.2,
                        color: isDarkMode ? Colors.white.withOpacity(0.9) : Colors.black87.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCityOverview(bool isDarkMode) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Jumlah Laporan',
                    '${_cityStats['total'] ?? 0}',
                    Icons.report_rounded,
                    AppTheme.primaryRed,
                    isDarkMode,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Selesai',
                    '${_cityStats['resolved'] ?? 0}',
                    Icons.check_circle_rounded,
                    Colors.green,
                    isDarkMode,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Dalam Proses',
                    '${_cityStats['pending'] ?? 0}',
                    Icons.pending_rounded,
                    Colors.orange,
                    isDarkMode,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Kadar Penyelesaian',
                    '${_cityStats['resolutionRate'] ?? 0}%',
                    Icons.trending_up_rounded,
                    Colors.green,
                    isDarkMode,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Pecahan Tahap Bahaya', isDarkMode),
            const SizedBox(height: 12),
            _buildSeverityChart(isDarkMode),
            const SizedBox(height: 24),
            _buildSectionTitle('Kawasan Keutamaan Tinggi', isDarkMode),
            const SizedBox(height: 12),
            ..._priorityAreas.take(5).map((area) => _buildPriorityAreaItem(area, isDarkMode)),
            const SizedBox(height: 24),
            _buildSectionTitle('Penyumbang Teratas', isDarkMode),
            const SizedBox(height: 12),
            ..._leaderboard.take(3).toList().asMap().entries.map((entry) => 
              _buildLeaderboardItem(entry.key + 1, entry.value, isDarkMode)),
          ],
        ),
      ),
    );
  }

  Widget _buildAreaAnalytics(bool isDarkMode) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: _areaData.isEmpty
          ? Center(
              child: Text(
                'Tiada data kawasan tersedia',
                style: TextStyle(color: isDarkMode ? Colors.white60 : Colors.black54),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _areaData.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle('Kepadatan Laporan mengikut Kawasan', isDarkMode),
                      const SizedBox(height: 8),
                      Text(
                        'Kawasan disusun mengikut jumlah laporan',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDarkMode ? Colors.white38 : Colors.black38,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                }
                final area = _areaData[index - 1];
                final maxCount = _areaData.isNotEmpty ? _areaData[0]['count'] as int : 1;
                return _buildAreaHeatmapItem(area, maxCount, isDarkMode);
              },
            ),
    );
  }

  Widget _buildPersonalImpact(bool isDarkMode) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImpactSummaryCard(isDarkMode),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildPersonalStatCard(
                    'Laporan',
                    '${_personalStats['totalReports'] ?? 0}',
                    Icons.flag_rounded,
                    Colors.blue,
                    isDarkMode,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildPersonalStatCard(
                    'Selesai',
                    '${_personalStats['resolvedReports'] ?? 0}',
                    Icons.check_circle_outline_rounded,
                    AppTheme.primaryBlue,
                    isDarkMode,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildPersonalStatCard(
                    'Undian Diterima',
                    '${_personalStats['totalUpvotesReceived'] ?? 0}',
                    Icons.thumb_up_rounded,
                    Colors.purple,
                    isDarkMode,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildPersonalStatCard(
                    'Kedudukan Anda',
                    '#${_personalStats['rank'] ?? 0}',
                    Icons.emoji_events_rounded,
                    Colors.amber,
                    isDarkMode,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Pencapaian', isDarkMode),
            const SizedBox(height: 12),
            _buildBadgesSection(isDarkMode),
            const SizedBox(height: 24),
            _buildShareImpactButton(isDarkMode),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, bool isDarkMode) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 16),
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode ? Colors.white60 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPersonalStatCard(String label, String value, IconData icon, Color color, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDarkMode ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDarkMode) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: isDarkMode ? Colors.white : Colors.black87,
      ),
    );
  }

  Widget _buildSeverityChart(bool isDarkMode) {
    final severity = _cityStats['severity'] as Map<String, dynamic>? ?? {};
    final total = (severity['critical'] ?? 0) + (severity['high'] ?? 0) + 
                  (severity['medium'] ?? 0) + (severity['low'] ?? 0);
    
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            'Tiada data tahap bahaya',
            style: TextStyle(color: isDarkMode ? Colors.white60 : Colors.black54),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          _buildSeverityBar('Kritikal', severity['critical'] ?? 0, total, Colors.red, '🔴', isDarkMode),
          const SizedBox(height: 12),
          _buildSeverityBar('Tinggi', severity['high'] ?? 0, total, Colors.deepOrange, '🟠', isDarkMode),
          const SizedBox(height: 12),
          _buildSeverityBar('Sederhana', severity['medium'] ?? 0, total, Colors.orange, '🟡', isDarkMode),
          const SizedBox(height: 12),
          _buildSeverityBar('Rendah', severity['low'] ?? 0, total, Colors.green, '🟢', isDarkMode),
        ],
      ),
    );
  }

  Widget _buildSeverityBar(String label, int count, int total, Color color, String emoji, bool isDarkMode) {
    final percentage = total > 0 ? count / total : 0.0;
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 13, color: isDarkMode ? Colors.white70 : Colors.black54))),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: percentage, backgroundColor: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1), valueColor: AlwaysStoppedAnimation(color), minHeight: 8))),
        const SizedBox(width: 12),
        SizedBox(width: 30, child: Text('$count', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87))),
      ],
    );
  }

  Widget _buildPriorityAreaItem(Map<String, dynamic> area, bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.priority_high_rounded, color: Colors.red, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Text(area['area'] ?? 'Tidak diketahui', style: TextStyle(fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : Colors.black87))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Text('Skor: ${area['priorityScore']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red))),
        ],
      ),
    );
  }

  Widget _buildLeaderboardItem(int rank, Map<String, dynamic> user, bool isDarkMode) {
    final colors = [Colors.amber, Colors.grey.shade400, Colors.brown.shade300];
    final rankColor = rank <= 3 ? colors[rank - 1] : Colors.grey;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(width: 32, height: 32, decoration: BoxDecoration(color: rankColor.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: Center(child: Text('#$rank', style: TextStyle(fontWeight: FontWeight.bold, color: rankColor)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(user['name'] ?? 'Tanpa Nama', style: TextStyle(fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : Colors.black87)), Text('${user['reports']} laporan', style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.white60 : Colors.black54))])),
          Text('${user['points']} mata', style: TextStyle(fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white70 : Colors.black54)),
        ],
      ),
    );
  }

  Widget _buildAreaHeatmapItem(Map<String, dynamic> area, int maxCount, bool isDarkMode) {
    final count = area['count'] as int;
    final pending = area['pending'] as int;
    final resolved = area['resolved'] as int;
    final intensity = maxCount > 0 ? count / maxCount : 0.0;
    final color = Color.lerp(Colors.orange, AppTheme.primaryRed, intensity)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.3), width: 2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))), const SizedBox(width: 12), Expanded(child: Text(area['area'] ?? 'Tidak diketahui', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDarkMode ? Colors.white : Colors.black87))), Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)), child: Text('$count laporan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)))]),
          const SizedBox(height: 12),
          Row(children: [_buildMiniStat('Proses', pending, Colors.orange, isDarkMode), const SizedBox(width: 16), _buildMiniStat('Selesai', resolved, Colors.green, isDarkMode), const Spacer(), Text('👍 ${area['totalUpvotes']}', style: TextStyle(fontSize: 13, color: isDarkMode ? Colors.white60 : Colors.black54))]),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, int value, Color color, bool isDarkMode) {
    return Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 6), Text('$label: $value', style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.white60 : Colors.black54))]);
  }

  Widget _buildImpactSummaryCard(bool isDarkMode) {
    final roadFixed = (_personalStats['roadsImprovedMeters'] ?? 0).toDouble();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.primaryRed, AppTheme.primaryBlue], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: AppTheme.primaryRed.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 32), const SizedBox(width: 12), const Text('Impak Anda', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)), child: Text('Tangga #${_personalStats['rank'] ?? 0}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))]),
          const SizedBox(height: 20),
          Text('Laporan anda telah membantu membaiki', style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8))),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('${roadFixed.toStringAsFixed(0)}m', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white)), const Padding(padding: EdgeInsets.only(bottom: 10, left: 8), child: Text('jalan raya 🛣️', style: TextStyle(fontSize: 18, color: Colors.white70)))]),
          const SizedBox(height: 12),
          Row(children: [const Icon(Icons.local_fire_department_rounded, color: Colors.orange, size: 20), const SizedBox(width: 6), Text('Streak ${_personalStats['currentStreak'] ?? 0} hari', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)), const SizedBox(width: 16), const Icon(Icons.star_rounded, color: Colors.amber, size: 20), const SizedBox(width: 6), Text('${_personalStats['points'] ?? 0} mata', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))]),
        ],
      ),
    );
  }

  Widget _buildBadgesSection(bool isDarkMode) {
    final badges = _personalStats['badges'] as List<String>? ?? [];
    final allBadges = [
      {'id': 'first_report', 'name': 'Laporan Pertama', 'icon': '🏅', 'desc': 'Hantar laporan pertama anda'},
      {'id': 'reporter_10', 'name': '10 Laporan', 'icon': '🥉', 'desc': 'Hantar 10 laporan'},
      {'id': 'reporter_25', 'name': '25 Laporan', 'icon': '🥈', 'desc': 'Hantar 25 laporan'},
      {'id': 'reporter_50', 'name': '50 Laporan', 'icon': '🥇', 'desc': 'Hantar 50 laporan'},
      {'id': 'reporter_100', 'name': '100 Laporan', 'icon': '🏆', 'desc': 'Hantar 100 laporan'},
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: allBadges.map((badge) {
        final earned = badges.contains(badge['id']);
        return Container(
          width: (MediaQuery.of(context).size.width - 52) / 2,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: earned ? AppTheme.primaryRed.withOpacity(0.15) : (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: earned ? Border.all(color: AppTheme.primaryRed, width: 2) : null),
          child: Column(children: [Text(badge['icon'] as String, style: TextStyle(fontSize: 32, color: earned ? null : Colors.grey)), const SizedBox(height: 8), Text(badge['name'] as String, style: TextStyle(fontWeight: FontWeight.bold, color: earned ? (isDarkMode ? Colors.white : Colors.black87) : Colors.grey)), if (!earned) Text(badge['desc'] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.grey))]),
        );
      }).toList(),
    );
  }

  Widget _buildShareImpactButton(bool isDarkMode) {
    return GestureDetector(
      onTap: _shareImpact,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.primaryRed, AppTheme.primaryBlue]), borderRadius: BorderRadius.circular(16)),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.share_rounded, color: Colors.white), SizedBox(width: 12), Text('Kongsi Impak Anda', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))]),
      ),
    );
  }

  void _shareImpact() {
    final reports = _personalStats['totalReports'] ?? 0;
    final resolved = _personalStats['resolvedReports'] ?? 0;
    final roads = (_personalStats['roadsImprovedMeters'] ?? 0).toDouble();
    final text = '''
🦸 Sahabat Assaffal Impact 🦸

📊 Statistik Saya:
• Laporan Dihantar: $reports
• Isu Selesai: $resolved
• Jalan Diperbaiki: ${roads.toStringAsFixed(0)}m

www.sahabatassaffal.com 🛣️

Sertai saya di Sahabat Assaffal dan lapor kerosakan jalan di kawasan anda! 
Bersama kita baiki jalan raya kita! 💪

#SahabatAssaffal #LahadDatu #Tungku
''';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Salin: $text'), action: SnackBarAction(label: 'Salin', onPressed: () {})));
  }
}
