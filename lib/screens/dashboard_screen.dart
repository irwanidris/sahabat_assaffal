import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import '../cubit/reports_cubit.dart';
import '../models/assaffal_report.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';
import '../services/device_service.dart';
import '../services/share_service.dart';
import '../services/community_service.dart';
import '../services/auth_service.dart';
import '../widgets/full_screen_image.dart';
import '../widgets/inline_comments_section.dart';
import 'reports_list_screen.dart';
import 'home_screen.dart';
import 'leaderboard_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SupabaseService _supabaseService = SupabaseService();
  final DeviceService _deviceService = DeviceService();
  final ShareService _shareService = ShareService();
  final CommunityService _communityService = CommunityService();
  final AuthService _authService = AuthService();
  String? _deviceId;
  Map<String, bool> _upvoteStatus = {};
  int _userPoints = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDeviceId();
    _loadUserStats();
    context.read<ReportsCubit>().loadReports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserStats() async {
    try {
      final profile = await _deviceService.getOrCreateProfile();
      if (mounted) {
        setState(() {
          _userPoints = profile['points'] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading user stats: $e');
    }
  }

  Future<void> _loadDeviceId() async {
    final id = await _deviceService.getDeviceId();
    if (mounted) {
      setState(() {
        _deviceId = id;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Statistik & Laporan', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryRed,
          labelColor: AppTheme.primaryRed,
          unselectedLabelColor: isDarkMode ? Colors.white70 : Colors.black54,
          tabs: const [
            Tab(text: 'Statistik'),
            Tab(text: 'Laporan'),
            Tab(text: 'Juara'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStatsOverview(isDarkMode),
          _buildReportsFeed(isDarkMode),
          const LeaderboardScreen(), // Reuse existing Leaderboard
        ],
      ),
    );
  }

  Widget _buildStatsOverview(bool isDarkMode) {
    return BlocBuilder<ReportsCubit, ReportsState>(
      builder: (context, state) {
        if (state is ReportsLoaded) {
          final reports = state.reports;
          final resolved = reports.where((r) => r.status == 'resolved').length;
          final pending = reports.where((r) => r.status != 'resolved' && r.status != 'fake').length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildStatsBar(isDarkMode),
              const SizedBox(height: 24),
              Row(
                children: [
                  _buildStatCard('Selesai', resolved.toString(), AppTheme.primaryBlue, Icons.check_circle, isDarkMode),
                  const SizedBox(width: 12),
                  _buildStatCard('Aktif', pending.toString(), AppTheme.primaryRed, Icons.error_outline, isDarkMode),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Ringkasan Komuniti', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    _buildSimpleRow('Jumlah Aduan', reports.length.toString(), isDarkMode),
                  ],
                ),
              ),
            ],
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon, bool isDarkMode) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 12),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleRow(String label, String value, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black54)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildReportsFeed(bool isDarkMode) {
    return BlocBuilder<ReportsCubit, ReportsState>(
      builder: (context, state) {
        if (state is ReportsLoading) return const Center(child: CircularProgressIndicator());
        if (state is ReportsLoaded) {
          final reports = state.reports.where((r) => r.status != 'fake').toList();
          if (reports.isEmpty) return const Center(child: Text('Tiada laporan'));

          final recentReports = reports.take(3).toList();
          final remainingReports = reports.skip(3).toList();

          return RefreshIndicator(
            onRefresh: () => context.read<ReportsCubit>().refreshReports(shuffle: true),
            color: AppTheme.primaryRed,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
                  child: Text('Laporan Terkini', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = (constraints.maxWidth - 24) / 3; 
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: recentReports.map((r) => _buildHorizontalCard(r, isDarkMode, itemWidth)).toList(),
                    );
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0, horizontal: 4),
                  child: Text('Laporan Lain', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: remainingReports.length,
                  itemBuilder: (context, index) => _buildGridCard(remainingReports[index], isDarkMode),
                ),
              ],
            ),
          );
        }
        return const Center(child: Text('Ralat memuatkan data'));
      },
    );
  }

  Widget _buildStatsBar(bool isDarkMode) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const LeaderboardScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1)),
        ),
        child: Row(
          children: [
            const Icon(Icons.stars_rounded, color: Colors.amber, size: 24),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mata Ganjaran',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                ),
                Text(
                  '$_userPoints Mata',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right_rounded,
              color: isDarkMode ? Colors.white54 : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainCard(AssaffalReport report, bool isDarkMode) {
    return GestureDetector(
      onTap: _navigateToFullList,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          image: DecorationImage(
            image: CachedNetworkImageProvider(report.imageUrl),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.areaName ?? 'Lokasi',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridCard(AssaffalReport report, bool isDarkMode) {
    final bool isResolved = report.status == 'resolved';
    final bool isActive = report.upvoteCount > 0;
    
    final Color bgColor = isResolved 
        ? (isDarkMode ? AppTheme.primaryBlue.withOpacity(0.1) : Colors.blue.shade50)
        : (isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey.shade100);

    return GestureDetector(
      onTap: () => _showReportDetails(report),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: CachedNetworkImage(
                  imageUrl: report.firstImage,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.grey.shade200),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.areaName ?? 'Lokasi',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontalCard(AssaffalReport report, bool isDarkMode, double width) {
    final bool isResolved = report.status == 'resolved';
    final bool isActive = report.upvoteCount > 0;

    final Color bgColor = isResolved 
        ? (isDarkMode ? AppTheme.primaryBlue.withOpacity(0.1) : Colors.blue.shade50)
        : (isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey.shade100);

    return GestureDetector(
      onTap: () => _showReportDetails(report),
      child: Container(
        width: width,
        height: width + 40, // Tinggi automatik berdasarkan lebar
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: CachedNetworkImage(
                  imageUrl: report.firstImage,
                  width: width,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.grey.shade200),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.areaName ?? 'Lokasi',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToFullList() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ReportsListScreen()),
    );
  }

  void _showReportDetails(AssaffalReport report) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    bool hasUpvoted = _upvoteStatus[report.id] ?? false;
    int upvoteCount = report.upvoteCount;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: (isDarkMode ? const Color(0xFF1a1a2e) : Colors.white).withOpacity(0.9),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 50,
                        height: 5,
                        decoration: BoxDecoration(
                          color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Paparan Gambar (Before/After logic)
                    Stack(
                      children: [
                        Column(
                          children: [
                            if (report.resolvedImageUrl != null) ...[
                              const Text(
                                'BUKTI SELESAI (OLEH KOMUNITI):',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, letterSpacing: 1),
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => FullScreenImage(
                                          imageUrl: report.resolvedImageUrl!,
                                          tag: 'dash-resolved-${report.id}',
                                        ),
                                      ),
                                    );
                                  },
                                  child: Hero(
                                    tag: 'dash-resolved-${report.id}',
                                    child: Image.network(
                                      report.resolvedImageUrl!,
                                      height: 200,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'GAMBAR ASAL ADUAN:',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
                              ),
                              const SizedBox(height: 8),
                            ],
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => FullScreenImage(
                                        imageUrl: report.imageUrl,
                                        tag: 'dash-main-${report.id}',
                                      ),
                                    ),
                                  );
                                },
                                child: Hero(
                                  tag: 'dash-main-${report.id}',
                                  child: Image.network(
                                    report.imageUrl,
                                    height: report.resolvedImageUrl != null ? 120 : 180,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      height: 180,
                                      color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200,
                                      child: const Icon(Icons.broken_image_rounded, size: 50),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Lencana "Disahkan Komuniti"
                        if (report.verifiedStillExists >= 5 && report.status != 'resolved')
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade700,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified_rounded, color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'Disahkan Komuniti',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Lencana "Selesai" (5 undian & < 72 jam)
                        if (report.status == 'resolved' && 
                            report.verifiedResolved >= 5 && 
                            DateTime.now().difference(report.createdAt).inHours < 72)
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.task_alt_rounded, color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'Selesai',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (report.allImages.length > 1 && report.resolvedImageUrl == null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 80,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: report.allImages.length - 1,
                          separatorBuilder: (context, index) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final imgUrl = report.allImages[index + 1];
                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => FullScreenImage(
                                      imageUrl: imgUrl,
                                      tag: 'dash-thumb-$index-${report.id}',
                                    ),
                                  ),
                                );
                              },
                              child: Hero(
                                tag: 'dash-thumb-$index-${report.id}',
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: CachedNetworkImage(
                                    imageUrl: imgUrl,
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(color: Colors.grey.shade200),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: report.status == 'resolved' 
                                ? AppTheme.primaryBlue.withOpacity(0.15) 
                                : (report.upvoteCount > 0 ? AppTheme.primaryRed.withOpacity(0.15) : Colors.grey.withOpacity(0.15)),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            report.status == 'resolved' 
                                ? 'SELESAI' 
                                : (report.upvoteCount > 0 ? 'AKTIF' : 'BELUM DISAHKAN'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: report.status == 'resolved' 
                                  ? AppTheme.primaryBlue 
                                  : (report.upvoteCount > 0 ? AppTheme.primaryRed : Colors.grey),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // KOORDINAT GPS BUTTON
                        InkWell(
                          onTap: () async {
                            final url = 'https://www.google.com/maps/search/?api=1&query=${report.latitude},${report.longitude}';
                            if (await canLaunchUrl(Uri.parse(url))) {
                              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.blue.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.navigation_rounded, size: 14, color: Colors.blue),
                                const SizedBox(width: 4),
                                Text(
                                  '${report.latitude.toStringAsFixed(4)}, ${report.longitude.toStringAsFixed(4)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      report.areaName ?? 'Lokasi Tidak Diketahui',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.place_rounded, size: 16, color: Colors.grey.shade500),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            report.address ?? 'Tiada alamat tersedia',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 6),
                        Text(
                          'Dilapor pada: ${DateFormat('dd/MM/yyyy HH:mm').format(report.createdAtMYT)}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // BAHAGIAN UNDIAN (VOTING) & SHARE
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () async {
                                  final user = _authService.currentUser;
                                  if (user == null) {
                                    _showAuthRequiredDialog();
                                    return;
                                  }
                                  
                                  // Sekat jika aduan sendiri
                                  if (report.isOwnReport(user.id, currentDeviceId: _deviceId)) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Anda tidak boleh menyokong laporan anda sendiri.')),
                                    );
                                    return;
                                  }

                                  try {
                                    final isNowUpvoted = await _supabaseService.toggleUpvote(report.id, user.id);
                                    setModalState(() {
                                      hasUpvoted = isNowUpvoted;
                                      upvoteCount += isNowUpvoted ? 1 : -1;
                                    });
                                    setState(() {
                                      _upvoteStatus[report.id] = isNowUpvoted;
                                    });
                                    if (mounted) {
                                      context.read<ReportsCubit>().loadReports();
                                    }
                                  } catch (e) {
                                    debugPrint('Upvote failed: $e');
                                  }
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    gradient: hasUpvoted
                                        ? const LinearGradient(
                                            colors: [AppTheme.primaryRed, AppTheme.primaryBlue],
                                          )
                                        : null,
                                    color: hasUpvoted ? null : (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        hasUpvoted ? Icons.thumb_up : Icons.thumb_up_outlined,
                                        size: 20,
                                        color: hasUpvoted ? Colors.white : (isDarkMode ? Colors.white70 : Colors.black54),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$upvoteCount',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: hasUpvoted ? Colors.white : (isDarkMode ? Colors.white70 : Colors.black54),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // BUTANG SHARE
                              Expanded(
                                child: InkWell(
                                  onTap: () => _shareService.shareReport(report),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryBlue,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.primaryBlue.withOpacity(0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.share_rounded, color: Colors.white, size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          'KONGSI ADUAN',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${upvoteCount + 1} orang menyokong laporan ini',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: isDarkMode ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // SECTION KOMEN
                    InlineCommentsSection(
                      reportId: report.id,
                      communityService: _communityService,
                      isDarkMode: isDarkMode,
                    ),
                    const SizedBox(height: 24),

                    // BUTANG SAHKAN (Jika belum selesai)
                    if (report.status != 'resolved' && report.status != 'fake') ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _showVerificationDialog(report, isDarkMode),
                          icon: const Icon(Icons.verified_user_rounded, color: Colors.white),
                          label: const Text(
                            'BETUL KA ADA LUBANG?',
                            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'TUTUP',
                          style: TextStyle(
                            color: isDarkMode ? Colors.white54 : Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showVerificationDialog(AssaffalReport report, bool isDarkMode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF1a1a2e) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(
          children: [
            const Icon(Icons.verified_user_rounded, size: 40, color: AppTheme.primaryBlue),
            const SizedBox(height: 12),
            Text(
              'SAHKAN STATUS',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              report.verifiedStillExists >= 5 
                ? 'Adakah aduan ini masih di sini?'
                : 'Adakah masalah ini masih wujud?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
                color: isDarkMode ? Colors.white60 : Colors.black54,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          _buildWazeButton(
            icon: Icons.error_outline_rounded,
            label: 'Masih Ada',
            color: report.isOwnReport(_authService.currentUser?.id, currentDeviceId: _deviceId) ? Colors.grey : AppTheme.primaryRed,
            count: report.verifiedStillExists,
            onTap: report.isOwnReport(_authService.currentUser?.id, currentDeviceId: _deviceId)
                ? () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Anda tidak boleh mengundi laporan sendiri.')));
                  }
                : () {
                    Navigator.pop(context);
                    _verifyReport(report, 'exists');
                  },
            isDarkMode: isDarkMode,
          ),
          const SizedBox(height: 12),
          _buildWazeButton(
            icon: Icons.check_circle_outline_rounded,
            label: 'Dah Selesai',
            color: report.isOwnReport(_authService.currentUser?.id, currentDeviceId: _deviceId) ? Colors.grey : AppTheme.primaryBlue,
            count: report.verifiedResolved,
            onTap: report.isOwnReport(_authService.currentUser?.id, currentDeviceId: _deviceId)
                ? () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Anda tidak boleh mengundi laporan sendiri.')));
                  }
                : () {
                    Navigator.pop(context);
                    _verifyReport(report, 'resolved');
                  },
            isDarkMode: isDarkMode,
          ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'BATAL',
              style: TextStyle(color: isDarkMode ? Colors.white54 : Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWazeButton({
    required IconData icon,
    required String label,
    required Color color,
    required int count,
    required VoidCallback onTap,
    required bool isDarkMode,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white.withOpacity(0.9) : Colors.black87,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAuthRequiredDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Column(
          children: [
            Icon(Icons.lock_outline_rounded, size: 48, color: AppTheme.primaryRed),
            SizedBox(height: 16),
            Text(
              'Log Masuk Diperlukan',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'Anda perlu log masuk untuk menyokong laporan atau mengesahkan keadaan di lokasi.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('KEMUDIAN', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _authService.signInWithGoogle();
                if (mounted) setState(() {});
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
            ),
            child: const Text('LOG MASUK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _verifyReport(AssaffalReport report, String type) async {
    final user = _authService.currentUser;
    if (user == null) {
      _showAuthRequiredDialog();
      return;
    }

    // Jika pilih 'Dah Selesai', minta gambar bukti
    String? proofImageUrl;
    if (type == 'resolved') {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1200,
      );

      if (image == null) return; // Batal jika tiada gambar

      // Tunjukkan loading muat naik
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Memuat naik gambar bukti...'), duration: Duration(seconds: 2)),
        );
      }

      try {
        proofImageUrl = await _supabaseService.uploadImage(File(image.path));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal muat naik gambar: $e'), backgroundColor: Colors.red),
          );
        }
        return;
      }
    }

    // Tunjukkan loading sekejap semasa semak GPS
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              SizedBox(width: 15),
              Text('Menyemak lokasi anda...'),
            ],
          ),
          duration: Duration(seconds: 1),
        ),
      );
    }

    try {
      // 1. Dapatkan lokasi terkini yang tepat
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 2. Kira jarak antara pengguna dan aduan (dalam meter)
      double distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        report.latitude,
        report.longitude,
      );

      // 3. Semak radius (1km / 1000m)
      if (distanceInMeters > 1000) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.location_off_rounded, color: Colors.red),
                  SizedBox(width: 10),
                  Text('Tiada Di Lokasi'),
                ],
              ),
              content: const Text(
                'Anda tidak layak mengundi kerana tiada di lokasi berhampiran aduan (Radius > 1km).',
                style: TextStyle(fontSize: 16),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('FAHAM', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
        return;
      }

      // 4. Jika dalam radius, teruskan proses verifikasi
      await _supabaseService.verifyReportCommunity(report.id, user.id, type, imageUrl: proofImageUrl);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Terima kasih! Maklum balas anda telah direkodkan.'),
            backgroundColor: Colors.green,
          ),
        );
        context.read<ReportsCubit>().loadReports(); // Refresh data
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().contains('location') 
              ? 'Sila aktifkan GPS anda untuk mengundi.' 
              : e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
