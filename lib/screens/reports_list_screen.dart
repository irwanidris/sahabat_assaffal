import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../cubit/reports_cubit.dart';
import '../models/assaffal_report.dart';
import '../theme/app_theme.dart';
import '../widgets/inline_comments_section.dart';
import '../services/share_service.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../services/device_service.dart';
import '../services/community_service.dart';
import 'home_screen.dart';
import 'in_app_camera_screen.dart';
import '../widgets/full_screen_image.dart';

class ReportsListScreen extends StatefulWidget {
  const ReportsListScreen({super.key});

  @override
  State<ReportsListScreen> createState() => ReportsListScreenState();
}

class ReportsListScreenState extends State<ReportsListScreen> {
  final Map<String, bool> _upvoteStatus = {};
  final AuthService _authService = AuthService();
  final SupabaseService _supabaseService = SupabaseService();
  final ShareService _shareService = ShareService();
  final CommunityService _communityService = CommunityService();
  final DeviceService _deviceService = DeviceService();
  String? _deviceId;
  
  List<AssaffalReport> _shuffledRakyatReports = [];
  List<AssaffalReport>? _lastReports;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _getDeviceId();

    // Pantau perubahan status auth untuk kemaskini UI
    _authSubscription = _authService.authStateChanges.listen((data) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _getDeviceId() async {
    final id = await _deviceService.getDeviceId();
    if (mounted) {
      setState(() {
        _deviceId = id;
      });
    }
  }

  void _updateShuffledReports(List<AssaffalReport> reports) {
    if (_lastReports != reports) {
      _lastReports = reports;
      if (reports.length > 3) {
        _shuffledRakyatReports = reports.skip(3).toList()..shuffle();
      } else {
        _shuffledRakyatReports = [];
      }
    }
  }

  void showReportFromExternal(AssaffalReport report) {
    _showReportDetails(report);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final isLoggedIn = _authService.currentUser != null;

    return Scaffold(
      backgroundColor: isDarkMode ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: Stack(
        children: [
          BlocBuilder<ReportsCubit, ReportsState>(
            builder: (context, state) {
              if (state is ReportsLoading) {
                return const Center(child: CircularProgressIndicator());
              } else if (state is ReportsLoaded) {
                final reports = state.reports;
                if (reports.isEmpty) {
                  return const Center(child: Text('Tiada laporan dijumpai.'));
                }
                
                _updateShuffledReports(reports);
                final latestReports = reports.take(3).toList();

                return RefreshIndicator(
                  onRefresh: () async {
                    _lastReports = null; // Force reshuffle on manual refresh
                    await context.read<ReportsCubit>().loadReports();
                  },
                  child: CustomScrollView(
                    slivers: [
                      // Ruang kosong untuk mengelakkan kandungan bertindih dengan Glass Header
                      SliverToBoxAdapter(
                        child: SizedBox(height: MediaQuery.of(context).padding.top + 90),
                      ),
                      // Laporan Terkini Section
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            'Laporan Terkini',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.85,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildTerkiniItem(latestReports[index], isDarkMode),
                            childCount: latestReports.length,
                          ),
                        ),
                      ),

                      // Laporan Rakyat Section
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 32, 16, 12),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            'Laporan Rakyat',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.9,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildRakyatItem(_shuffledRakyatReports[index], isDarkMode),
                            childCount: _shuffledRakyatReports.length,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              } else if (state is ReportsError) {
                return Center(child: Text('Ralat: ${state.message}'));
              }
              return const Center(child: Text('Sila muat semula.'));
            },
          ),
          
          // Lapisan Blur jika tidak login
          if (!isLoggedIn)
            _buildNotLoggedInState(isDarkMode),
        ],
      ),
    );
  }

  Widget _buildTerkiniItem(AssaffalReport report, bool isDarkMode) {
    return InkWell(
      onTap: () => _showReportDetails(report),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: report.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => _buildPlaceholder(),
                      errorWidget: (context, url, error) => _buildPlaceholder(isError: true),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _buildStatusOverlay(report, fontSize: 6),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            report.areaName ?? 'Lokasi',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            report.category.toUpperCase(),
            style: const TextStyle(
              color: AppTheme.primaryRed,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              CircleAvatar(
                radius: 6,
                backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                backgroundImage: (report.reporterAvatar != null && report.reporterAvatar!.isNotEmpty)
                    ? NetworkImage(report.reporterAvatar!)
                    : null,
                child: (report.reporterAvatar == null || report.reporterAvatar!.isEmpty)
                    ? Icon(Icons.person, size: 7, color: AppTheme.primaryBlue.withOpacity(0.5))
                    : null,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  (report.reporterNickname != null && report.reporterNickname!.isNotEmpty)
                      ? report.reporterNickname!
                      : (report.reporterName != null && report.reporterName!.isNotEmpty)
                          ? report.reporterName!
                          : 'Anonim',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white60 : Colors.black54,
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRakyatItem(AssaffalReport report, bool isDarkMode) {
    return Card(
      elevation: 4,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showReportDetails(report),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: report.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => _buildPlaceholder(),
                    errorWidget: (context, url, error) => _buildPlaceholder(isError: true),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _buildStatusOverlay(report, fontSize: 8),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.areaName ?? 'Lokasi',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          report.category.toUpperCase(),
                          style: TextStyle(
                            color: AppTheme.primaryRed,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 7,
                              backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                              backgroundImage: (report.reporterAvatar != null && report.reporterAvatar!.isNotEmpty)
                                  ? NetworkImage(report.reporterAvatar!)
                                  : null,
                              child: (report.reporterAvatar == null || report.reporterAvatar!.isEmpty)
                                  ? Icon(Icons.person, size: 8, color: AppTheme.primaryBlue.withOpacity(0.5))
                                  : null,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                (report.reporterNickname != null && report.reporterNickname!.isNotEmpty)
                                    ? report.reporterNickname!
                                    : (report.reporterName != null && report.reporterName!.isNotEmpty)
                                        ? report.reporterName!
                                        : 'Anonim',
                                style: TextStyle(
                                  color: isDarkMode ? Colors.white60 : Colors.black54,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Text(
                      DateFormat('dd/MM/yyyy').format(report.createdAtMYT),
                      style: const TextStyle(color: Colors.grey, fontSize: 8),
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

  Widget _buildPlaceholder({bool isError = false}) {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Opacity(
          opacity: 0.3,
          child: Image.asset(
            'assets/images/logo_s_assaffal.png',
            width: 40,
            errorBuilder: (context, error, stackTrace) => Icon(
              isError ? Icons.broken_image_rounded : Icons.image_rounded,
              color: Colors.grey[400],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return Colors.green;
      case 'active':
      case 'processing':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.orange;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return 'SELESAI';
      case 'active':
      case 'processing':
        return 'AWAS';
      case 'pending':
        return 'BELUM SAH';
      default:
        return 'BELUM SAH';
    }
  }

  Widget _buildStatusOverlay(AssaffalReport report, {double fontSize = 8}) {
    final color = _getStatusColor(report.status);
    final label = _getStatusText(report.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMiniStatusBadge(String status) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: _getStatusColor(status),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final color = _getStatusColor(status);
    final label = _getStatusText(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStatusItem(String label, int count, Color color, bool isDarkMode) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildNotLoggedInState(bool isDarkMode) {
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: (isDarkMode ? Colors.black : Colors.white).withOpacity(0.4),
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(32),
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
                      child: const Icon(Icons.assignment_rounded, color: AppTheme.primaryRed, size: 40),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Laporan Terhad',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Log masuk diperlukan untuk melihat senarai laporan komuniti dan status terkini masalah jalan raya.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () async {
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
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: const Text(
                        'Log Masuk Sekarang',
                        style: TextStyle(fontWeight: FontWeight.bold),
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
              padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 40),
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
                  // Paparan Gambar
                  Stack(
                    children: [
                      Column(
                        children: [
                          if (report.resolvedImageUrl != null) ...[
                            const Text(
                              'BUKTI SELESAI (OLEH KOMUNITI):',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, letterSpacing: 1),
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => FullScreenImage(
                                      imageUrl: report.resolvedImageUrl!,
                                      tag: 'report-resolved-${report.id}',
                                      report: report,
                                    ),
                                  ),
                                ),
                                child: CachedNetworkImage(
                                  imageUrl: report.resolvedImageUrl!,
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => _buildPlaceholder(),
                                  errorWidget: (context, url, error) => _buildPlaceholder(isError: true),
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
                            child: InkWell(
                              onTap: () => Navigator.push(
                                context,
                                  MaterialPageRoute(
                                    builder: (context) => FullScreenImage(
                                      imageUrl: report.imageUrl,
                                      tag: 'report-main-${report.id}',
                                      report: report,
                                    ),
                                  ),
                                ),
                              child: CachedNetworkImage(
                                imageUrl: report.imageUrl,
                                height: report.resolvedImageUrl != null ? 120 : 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => _buildPlaceholder(),
                                errorWidget: (context, url, error) => _buildPlaceholder(isError: true),
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
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
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
                      const SizedBox(width: 8),
                      // STATUS BADGE
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getStatusColor(report.status),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _getStatusText(report.status),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    report.areaName ?? 'Lokasi Tidak Diketahui',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
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
                  const SizedBox(height: 8),
                  // DILAPORKAN OLEH
                  Row(
                    children: [
                      Text(
                        'Dilaporkan Oleh : ',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                      ),
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                        backgroundImage: (report.reporterAvatar != null && report.reporterAvatar!.isNotEmpty) ? NetworkImage(report.reporterAvatar!) : null,
                        child: (report.reporterAvatar == null || report.reporterAvatar!.isEmpty) ? const Icon(Icons.person, size: 12, color: AppTheme.primaryBlue) : null,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        (report.reporterNickname != null && report.reporterNickname!.isNotEmpty)
                            ? report.reporterNickname!
                            : (report.reporterName != null && report.reporterName!.isNotEmpty)
                                ? report.reporterName!
                                : 'Anonim',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

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
                                      const Text(
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

                  InlineCommentsSection(
                    reportId: report.id,
                    communityService: _communityService,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: 24),

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
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'TUTUP',
                        style: TextStyle(
                          color: isDarkMode ? Colors.white60 : Colors.grey,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void _verifyReport(AssaffalReport report, String type) async {
  final user = _authService.currentUser;
  if (user == null) {
    _showAuthRequiredDialog();
    return;
  }

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
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    double distanceInMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      report.latitude,
      report.longitude,
    );

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

    String? proofImageUrl;
    if (type == 'resolved') {
      // Guna InAppCameraScreen sebagai ganti ImagePicker untuk konsistensi watermark
      final File? imageFile = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const InAppCameraScreen(category: 'Bukti Selesai'),
        ),
      );

      if (imageFile == null) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Memuat naik gambar bukti...'), duration: Duration(seconds: 2)),
        );
      }

      try {
        proofImageUrl = await _supabaseService.uploadImage(imageFile);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal muat naik gambar: $e'), backgroundColor: Colors.red),
          );
        }
        return;
      }
    }

    await _supabaseService.verifyReportCommunity(report.id, user.id, type, imageUrl: proofImageUrl);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Terima kasih! Maklum balas anda telah direkodkan.'),
          backgroundColor: Colors.green,
        ),
      );
      context.read<ReportsCubit>().loadReports();
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
            _buildActionItem(
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
            _buildActionItem(
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
            child: const Text('BATAL'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem({
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
            Text('$count', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
