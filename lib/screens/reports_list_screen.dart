import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../cubit/reports_cubit.dart';
import '../cubit/theme_cubit.dart';
import '../models/assaffal_report.dart';
import '../theme/app_theme.dart';
import '../widgets/full_screen_image.dart';
import '../services/share_service.dart';
import '../services/auth_service.dart';
import 'notifications_list_screen.dart';

class ReportsListScreen extends StatefulWidget {
  const ReportsListScreen({super.key});

  @override
  State<ReportsListScreen> createState() => _ReportsListScreenState();
}

class _ReportsListScreenState extends State<ReportsListScreen> {
  final ShareService _shareService = ShareService();
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: Column(
        children: [
          _buildGlassHeader(isDarkMode),
          Expanded(
            child: BlocBuilder<ReportsCubit, ReportsState>(
                builder: (context, state) {
                  if (state is ReportsLoading) return const Center(child: CircularProgressIndicator());
                  if (state is ReportsError) return const Center(child: Text('Gagal memuat laporan'));
                  if (state is ReportsLoaded) {
                    final reports = state.reports.where((r) => r.status != 'fake').toList();
                    if (reports.isEmpty) return const Center(child: Text('Tiada laporan'));

                    final latestReports = reports.take(3).toList();
                    final otherReports = reports.skip(3).toList();

                    return RefreshIndicator(
                      onRefresh: () => context.read<ReportsCubit>().refreshReports(shuffle: true),
                      color: AppTheme.primaryRed,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryRed,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Laporan Terkini',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverGrid(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 0.65,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => _buildLazadaCard(latestReports[index], isDarkMode, isSmall: true),
                                childCount: latestReports.length,
                              ),
                            ),
                          ),
                          if (otherReports.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                                child: Text(
                                  'Semua Laporan',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDarkMode ? Colors.white70 : Colors.black54,
                                  ),
                                ),
                              ),
                            ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            sliver: SliverGrid(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.75,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => _buildLazadaCard(otherReports[index], isDarkMode),
                                childCount: otherReports.length,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassHeader(bool isDarkMode) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPadding > 0 ? 10 : 20, 16, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onLongPress: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Logout Sekarang?'),
                        content: const Text('Adakah anda pasti mahu keluar dari akaun ini?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Tidak')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ya', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _authService.signOut();
                      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.report_problem),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Senarai Laporan',
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
                const Spacer(),
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const NotificationsListScreen()),
                    );
                  },
                  icon: Icon(
                    Icons.notifications_none_rounded,
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                    size: 24,
                  ),
                ),
                IconButton(
                  onPressed: () => context.read<ThemeCubit>().toggleTheme(),
                  icon: Icon(
                    isDarkMode ? Icons.wb_sunny_rounded : Icons.nightlight_round, 
                    color: isDarkMode ? Colors.amber : Colors.indigo,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLazadaCard(AssaffalReport report, bool isDarkMode, {bool isSmall = false}) {
    final isLoggedIn = _authService.currentUser != null;
    
    // Logik Warna mengikut permintaan:
    // Jingga - Pending (upvote 0)
    // Merah - Aktif (upvote > 0)
    // Hijau - Selesai (resolved)
    Color statusColor;
    String statusLabel;
    
    if (report.status == 'resolved') {
      statusColor = Colors.green;
      statusLabel = 'SELESAI';
    } else if (report.upvoteCount > 0) {
      statusColor = Colors.red;
      statusLabel = 'AKTIF';
    } else {
      statusColor = Colors.orange;
      statusLabel = 'PENDING';
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FullScreenImage(
              imageUrl: report.firstImage,
              tag: 'grid-${report.id}',
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          // Kotak berwarna mengikut status (Border & Shadow)
          border: Border.all(
            color: statusColor.withOpacity(0.5),
            width: isSmall ? 1 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: statusColor.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Section
            Expanded(
              flex: isSmall ? 4 : 3,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                    child: Hero(
                      tag: 'grid-${report.id}',
                      child: CachedNetworkImage(
                        imageUrl: report.firstImage,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: Colors.grey[200]),
                      ),
                    ),
                  ),
                  if (!isLoggedIn)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: Container(color: Colors.black.withOpacity(0.1)),
                        ),
                      ),
                    ),
                  // Label Status di atas imej
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 2)
                        ],
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isSmall ? 7 : 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content Section
            Expanded(
              flex: isSmall ? 3 : 2,
              child: Padding(
                padding: EdgeInsets.all(isSmall ? 6.0 : 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.areaName ?? 'Kawasan',
                      style: TextStyle(
                        fontSize: isSmall ? 11 : 14,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      report.category.toUpperCase(),
                      style: TextStyle(
                        fontSize: isSmall ? 8 : 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                    if (!isSmall) ...[
                      const SizedBox(height: 4),
                      Text(
                        report.address ?? '',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat('dd/MM').format(report.createdAtMYT),
                          style: TextStyle(fontSize: isSmall ? 8 : 10, color: Colors.grey[400]),
                        ),
                        if (!isSmall)
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 10,
                            color: Colors.grey[400],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
