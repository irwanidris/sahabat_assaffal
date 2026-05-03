import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

import 'in_app_camera_screen.dart';
import '../widgets/full_screen_image.dart';
import '../widgets/inline_comments_section.dart';
import '../cubit/reports_cubit.dart';
import '../models/assaffal_report.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import '../services/share_service.dart';
import '../services/community_service.dart';
import '../services/device_service.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();
  final AuthService _authService = AuthService();
  final SupabaseService _supabaseService = SupabaseService();
  final ShareService _shareService = ShareService();
  final CommunityService _communityService = CommunityService();
  final DeviceService _deviceService = DeviceService();
  String? _userAvatar;


  LatLng? _currentLocation;
  StreamSubscription<Position>? _positionStream;
  String _selectedFilter = 'Semua';
  final TextEditingController _searchController = TextEditingController();
  
  String? _deviceId;
  final Map<String, bool> _upvoteStatus = {};

  @override
  void initState() {
    super.initState();
    _initDeviceId();
    _initLocationTracking();
    _loadUserAvatar(); // Tambah ini
    context.read<ReportsCubit>().loadReports();
  }

  Future<void> _loadUserAvatar() async {
    // 1. Ambil dari Profile Database
    final profile = await _deviceService.getOrCreateProfile();
    String? avatar = profile['avatar_url'];

    // 2. Jika Database kosong, cuba ambil terus dari Metadata Google
    if (avatar == null || avatar.isEmpty) {
      final user = _authService.currentUser;
      avatar = user?.userMetadata?['avatar_url'] ??
          user?.userMetadata?['picture'] ??
          user?.userMetadata?['google_avatar_url'];
    }

    if (mounted) {
      setState(() {
        _userAvatar = avatar;
      });
    }
  }


  @override
  void dispose() {
    _positionStream?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      _deviceId = androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      _deviceId = iosInfo.identifierForVendor;
    }
  }

  void _initLocationTracking() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    try {
      Position position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
        _mapController.move(_currentLocation!, 15);
      }
    } catch (e) {
      debugPrint('Error location: $e');
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
      }
    });
  }

  void _moveToUser() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 15);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          BlocBuilder<ReportsCubit, ReportsState>(
            builder: (context, state) {
              List<AssaffalReport> reports = [];
              if (state is ReportsLoaded) {
                reports = _filterReports(state.reports);
              }

              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentLocation ?? const LatLng(5.0392, 118.6313),
                  initialZoom: 13,
                ),
                children: [
                  TileLayer(
                    urlTemplate: isDarkMode 
                      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                      : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'com.sahabatassaffal.hero',
                  ),
                  MarkerLayer(
                    markers: [
                      if (_currentLocation != null)
                        Marker(
                          point: _currentLocation!,
                          width: 100,
                          height: 70,
                          alignment: Alignment.topCenter,
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                ),
                                child: const Text('Anda Disini', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryRed)),
                              ),
                              const SizedBox(height: 4),
                              // Bahagian Avatar
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                                ),
                                child: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: AppTheme.primaryRed,
                                  backgroundImage: (_userAvatar != null && _userAvatar!.isNotEmpty)
                                      ? NetworkImage(_userAvatar!)
                                      : null,
                                  child: (_userAvatar == null || _userAvatar!.isEmpty)
                                      ? const Icon(Icons.person, color: Colors.white, size: 20)
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ...reports.map((report) => Marker(
                        point: LatLng(report.latitude, report.longitude),
                        width: 18,
                        height: 18,
                        child: GestureDetector(
                          onTap: () => _showReportDetails(report),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _getMarkerColor(report),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )),
                    ],
                  ),
                ],
              );
            },
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  _buildHeader(isDarkMode),
                  const SizedBox(height: 16),
                  _buildSearchBar(isDarkMode),
                  const SizedBox(height: 12),
                  _buildFilterChips(isDarkMode),
                ],
              ),
            ),
          ),

          Positioned(
            right: 16,
            bottom: 120,
            child: Column(
              children: [
                _buildMapActionButton(Icons.add, () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1), isDarkMode),
                const SizedBox(height: 8),
                _buildMapActionButton(Icons.remove, () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1), isDarkMode),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _moveToUser,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryRed,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                    ),
                    child: const Icon(Icons.my_location, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            left: 16,
            bottom: 120,
            child: _buildLegendBox(isDarkMode),
          ),
        ],
      ),
    );
  }

  List<AssaffalReport> _filterReports(List<AssaffalReport> reports) {
    DateTime now = DateTime.now();
    if (_selectedFilter == 'Minggu Ini') {
      return reports.where((r) => now.difference(r.createdAtMYT).inDays <= 7).toList();
    } else if (_selectedFilter == 'Minggu Lalu') {
      return reports.where((r) => now.difference(r.createdAtMYT).inDays > 7 && now.difference(r.createdAtMYT).inDays <= 14).toList();
    } else if (_selectedFilter == 'Bulan Lalu') {
      return reports.where((r) => now.difference(r.createdAtMYT).inDays > 14).toList();
    }
    return reports;
  }

  Widget _buildHeader(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isDarkMode ? Colors.black : Colors.white).withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/images/app_icon.png', width: 35, height: 35, errorBuilder: (_, __, ___) => const Icon(Icons.report)),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sahabat Assaffal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('Suara Kita Semua', style: TextStyle(fontSize: 11, color: AppTheme.primaryRed, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600)),
            ],
          ),
          const Spacer(),
          _buildHeaderIcon(Icons.notifications_none, isDarkMode),
          const SizedBox(width: 8),
          _buildHeaderIcon(isDarkMode ? Icons.wb_sunny : Icons.nightlight_round, isDarkMode),
        ],
      ),
    );
  }

  Widget _buildHeaderIcon(IconData icon, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20),
    );
  }

  Widget _buildSearchBar(bool isDarkMode) {
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.black87 : Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: TextField(
        controller: _searchController,
        decoration: const InputDecoration(
          hintText: 'Cari di Tungku...',
          prefixIcon: Icon(Icons.search, color: Colors.grey),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildFilterChips(bool isDarkMode) {
    final filters = ['Semua', 'Minggu Ini', 'Minggu Lalu', 'Bulan Lalu'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          bool isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => setState(() => _selectedFilter = filter),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryBlue : (isDarkMode ? Colors.white10 : Colors.white),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected ? [] : [const BoxShadow(color: Colors.black12, blurRadius: 4)],
                  border: isSelected ? null : Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    if (isSelected) const Icon(Icons.check, color: Colors.white, size: 14),
                    if (isSelected) const SizedBox(width: 6),
                    Text(
                      filter,
                      style: TextStyle(
                        color: isSelected ? Colors.white : (isDarkMode ? Colors.white70 : Colors.black87),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLegendBox(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (isDarkMode ? Colors.black : Colors.white).withOpacity(0.9),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLegendItem(Colors.orange, 'Belum Disahkan'),
          const SizedBox(height: 8),
          _buildLegendItem(Colors.red, 'AWAS LUBANG'),
          const SizedBox(height: 8),
          _buildLegendItem(Colors.green, 'Selesai'),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMapActionButton(IconData icon, VoidCallback onTap, bool isDarkMode) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.black87 : Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Icon(icon, size: 22),
      ),
    );
  }

  Color _getMarkerColor(AssaffalReport report) {
    return _getStatusColor(report.status);
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return Colors.green;    // HIJAU (Selesai)
      case 'active':
      case 'processing':
        return Colors.red;      // MERAH (Awas/Aktif)
      case 'pending':
        return Colors.orange;   // JINGGA (Belum Sah)
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

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return Icons.check_circle;
      case 'active':
        return Icons.warning_rounded;
      case 'pending':
        return Icons.access_time_filled;
      default:
        return Icons.help_outline;
    }
  }

  void _showReportDetails(AssaffalReport report) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final currentUser = _authService.currentUser;
    bool hasUpvoted = _upvoteStatus[report.id] ?? false;
    int upvoteCount = report.upvoteCount;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 40),
              decoration: BoxDecoration(
                color: (isDarkMode ? const Color(0xFF1a1a2e) : Colors.white).withOpacity(0.9),
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
                                    MaterialPageRoute(builder: (_) => FullScreenImage(imageUrl: report.resolvedImageUrl!, tag: 'report-resolved-${report.id}', report: report)),
                                  ),
                                  child: Hero(
                                    tag: 'report-resolved-${report.id}',
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
                                  MaterialPageRoute(builder: (_) => FullScreenImage(imageUrl: report.imageUrl, tag: 'report-main-${report.id}', report: report)),
                                ),
                                child: Hero(
                                  tag: 'report-main-${report.id}',
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
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified_rounded, color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text('Disahkan Komuniti', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
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
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // STATUS BADGE (Sebelah Koordinat)
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
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.place_rounded, size: 16, color: Colors.grey.shade500),
                        const SizedBox(width: 6),
                        Expanded(child: Text(report.address ?? 'Tiada alamat tersedia', style: TextStyle(color: Colors.grey.shade500))),
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
                                  if (currentUser == null) {
                                    _showAuthRequiredDialog();
                                    return;
                                  }
                                  if (report.isOwnReport(currentUser.id, currentDeviceId: _deviceId)) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Anda tidak boleh menyokong laporan anda sendiri.')));
                                    return;
                                  }
                                  try {
                                    final isNowUpvoted = await _supabaseService.toggleUpvote(report.id, currentUser.id);
                                    setModalState(() {
                                      hasUpvoted = isNowUpvoted;
                                      upvoteCount += isNowUpvoted ? 1 : -1;
                                    });
                                    setState(() {
                                      _upvoteStatus[report.id] = isNowUpvoted;
                                    });
                                    if (mounted) context.read<ReportsCubit>().loadReports();
                                  } catch (e) {
                                    debugPrint('Upvote failed: $e');
                                  }
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    gradient: hasUpvoted ? const LinearGradient(colors: [AppTheme.primaryRed, AppTheme.primaryBlue]) : null,
                                    color: hasUpvoted ? null : (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(hasUpvoted ? Icons.thumb_up : Icons.thumb_up_outlined, size: 20, color: hasUpvoted ? Colors.white : (isDarkMode ? Colors.white70 : Colors.black54)),
                                      const SizedBox(width: 8),
                                      Text('$upvoteCount', style: TextStyle(fontWeight: FontWeight.bold, color: hasUpvoted ? Colors.white : (isDarkMode ? Colors.white70 : Colors.black54))),
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
                                      boxShadow: [BoxShadow(color: AppTheme.primaryBlue.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))],
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.share_rounded, color: Colors.white, size: 18),
                                        SizedBox(width: 8),
                                        Text('KONGSI ADUAN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
                            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: isDarkMode ? Colors.white60 : Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    InlineCommentsSection(reportId: report.id, communityService: _communityService, isDarkMode: isDarkMode),
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
}
