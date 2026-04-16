import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/full_screen_image.dart';
import '../widgets/inline_comments_section.dart';
import '../cubit/reports_cubit.dart';
import '../cubit/theme_cubit.dart';
import '../models/assaffal_report.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';
import '../services/device_service.dart';
import '../services/community_service.dart';
import '../services/share_service.dart';
import '../services/auth_service.dart';
import 'notifications_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final SupabaseService _supabaseService = SupabaseService();
  final DeviceService _deviceService = DeviceService();
  final CommunityService _communityService = CommunityService();
  final ShareService _shareService = ShareService();
  final AuthService _authService = AuthService();
  late AnimationController _beepController;
  LatLng? _currentLocation;
  LatLng? _selectedLocation;
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  String? _deviceId;
  Map<String, bool> _upvoteStatus = {};
  String _activeFilter = 'Semua'; // Penapis aktif: Semua, Minggu Ini, Minggu Lalu, Bulan Lalu

  final double _defaultLat = 5.0392;
  final double _defaultLon = 118.6313;

  @override
  void initState() {
    super.initState();
    _beepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _getCurrentLocation();
    _loadDeviceId();
    _checkFirstLaunch();
    context.read<ReportsCubit>().loadReports();
    _setupLocationListener();
  }

  void _setupLocationListener() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50, // Trigger setiap 50 meter
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
        _checkNearbyReports(position);
      }
    });
  }

  void _checkNearbyReports(Position position) async {
    final state = context.read<ReportsCubit>().state;
    if (state is! ReportsLoaded) return;

    final prefs = await SharedPreferences.getInstance();
    final String lastNotifiedId = prefs.getString('last_notified_report_id') ?? '';

    for (var report in state.reports) {
      // Hanya laporan yang belum disahkan (upvote_count == 0 atau status 'active' tapi masih baru)
      // Dan bukan laporan sendiri
      if (report.status != 'resolved' && report.status != 'fake' && report.upvoteCount == 0) {
        double distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          report.latitude,
          report.longitude,
        );

        // Jika dalam radius 200 meter
        if (distance < 200 && report.id != lastNotifiedId) {
          _showNearbyNotification(report);
          await prefs.setString('last_notified_report_id', report.id);
          break; // Elakkan spam banyak notifikasi serentak
        }
      }
    }
  }

  void _showNearbyNotification(AssaffalReport report) {
    // 1. Tunjukkan Notifikasi Tempatan (Local UI Snackbar/Dialog)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Aduan Berhampiran: ${report.category} di ${report.areaName}. Sila bantu sahkan!',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'LIHAT',
          textColor: Colors.amber,
          onPressed: () {
            _mapController.move(LatLng(report.latitude, report.longitude), 17);
            _showReportDetails(report);
          },
        ),
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      ),
    );
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenWelcome = prefs.getBool('hasSeenWelcome') ?? false;
    
    if (!hasSeenWelcome) {
      if (mounted) {
        Future.delayed(const Duration(seconds: 1), () {
          _showWelcomeDialog();
        });
      }
    }
  }

  void _showWelcomeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Sahabat Assaffal',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
              const SizedBox(height: 16),
              // Gambar Sahabat Assaffal
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/images/sahabat_assaffal.png',
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 100,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.person_rounded, size: 50, color: Colors.grey),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              // Barisan Logo Penyelenggara
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPartnerLogo('assets/images/logo_globinaco.png', 'Globinaco'),
                  _buildPartnerLogo('assets/images/logo_majlis_daerah.png', 'Majlis Daerah'),
                  _buildPartnerLogo('assets/images/logo_jkr.png', 'JKR'),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Inisiatif peribadi YB Assaffal bagi memberi ruang kepada masyarakat untuk menarik perhatian Syarikat Konsesi, Majlis Daerah, JKR dan perhatian umum terhadap isu jalan raya.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 20),
              _buildFeatureInfo(
                Icons.campaign_rounded,
                'Lapor & Pantau',
                'Tarik perhatian syarikat penyelenggara (Globinaco), Majlis Daerah, dan JKR melalui kuasa pemantauan komuniti.'
              ),
              const SizedBox(height: 12),
              _buildFeatureInfo(
                Icons.stars_rounded,
                'Sumbang & Kumpul Mata',
                'Dapatkan mata ganjaran bagi setiap aduan dan verifikasi yang anda lakukan untuk komuniti.'
              ),
              const SizedBox(height: 20),
              const Text(
                'Bersama Kita Pastikan Jalan Raya Selamat',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('hasSeenWelcome', true);
                if (context.mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Mula Sekarang', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartnerLogo(String path, String label) {
    return Column(
      children: [
        Image.asset(
          path,
          height: 36,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.business_rounded, size: 18, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildFeatureInfo(IconData icon, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppTheme.primaryBlue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _loadDeviceId() async {
    _deviceId = await _deviceService.getDeviceId();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _currentLocation = LatLng(_defaultLat, _defaultLon);
          _isLoading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _currentLocation = LatLng(_defaultLat, _defaultLon);
            _isLoading = false;
          });
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _currentLocation = LatLng(_defaultLat, _defaultLon);
          _isLoading = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error getting location: $e');
      setState(() {
        _currentLocation = LatLng(_defaultLat, _defaultLon);
        _isLoading = false;
      });
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.length < 3) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final lat = _currentLocation?.latitude ?? _defaultLat;
      final lon = _currentLocation?.longitude ?? _defaultLon;

      const bbox = '118.3,5.0,119.0,5.1';
      final response = await http.get(Uri.parse(
        'https://photon.komoot.io/api/?q=${Uri.encodeComponent(query)}&bbox=$bbox&lat=$lat&lon=$lon&limit=8&lang=ms',
      ));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;

        setState(() {
          _searchResults = features.map((f) {
            final props = f['properties'] as Map<String, dynamic>;
            final coords = f['geometry']['coordinates'] as List;
            return {
              'name': props['name'] ?? 'Unknown',
              'city': props['city'] ?? props['county'] ?? '',
              'state': props['state'] ?? '',
              'lat': coords[1],
              'lon': coords[0],
            };
          }).toList();
          _showSearchResults = true;
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
    } finally {
      setState(() => _isSearching = false);
    }
  }

  void _selectLocation(Map<String, dynamic> location) {
    final lat = location['lat'] as double;
    final lon = location['lon'] as double;
    _mapController.move(LatLng(lat, lon), 16);
    setState(() {
      _searchController.text = location['name'];
      _showSearchResults = false;
      _selectedLocation = LatLng(lat, lon);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          if (_isLoading)
            Container(
              color: isDarkMode ? AppTheme.darkBackground : AppTheme.lightBackground,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            )
          else
            SizedBox(
              width: size.width,
              height: size.height,
              child: BlocBuilder<ReportsCubit, ReportsState>(
                builder: (context, state) {
                  final allReports = state is ReportsLoaded ? state.reports : <AssaffalReport>[];
                  
                  // LOGIK PENAPIS MASA
                  final now = DateTime.now();
                  final filteredByTime = allReports.where((report) {
                    if (_activeFilter == 'Semua') return true;
                    
                    final reportDate = report.createdAt;
                    
                    if (_activeFilter == 'Minggu Ini') {
                      final firstDayOfWeek = now.subtract(Duration(days: now.weekday - 1));
                      final start = DateTime(firstDayOfWeek.year, firstDayOfWeek.month, firstDayOfWeek.day);
                      return reportDate.isAfter(start);
                    }
                    
                    if (_activeFilter == 'Minggu Lalu') {
                      final firstDayOfThisWeek = now.subtract(Duration(days: now.weekday - 1));
                      final firstDayOfLastWeek = firstDayOfThisWeek.subtract(const Duration(days: 7));
                      final lastDayOfLastWeek = firstDayOfThisWeek.subtract(const Duration(milliseconds: 1));
                      return reportDate.isAfter(firstDayOfLastWeek) && reportDate.isBefore(lastDayOfLastWeek);
                    }
                    
                    if (_activeFilter == 'Bulan Lalu') {
                      final firstDayOfLastMonth = DateTime(now.year, now.month - 1, 1);
                      final lastDayOfLastMonth = DateTime(now.year, now.month, 0, 23, 59, 59);
                      return reportDate.isAfter(firstDayOfLastMonth) && reportDate.isBefore(lastDayOfLastMonth);
                    }
                    
                    return true;
                  }).toList();

                  // TAPISAN: Sembunyikan laporan 'fake' dari pandangan awam
                  final reports = filteredByTime.where((r) => r.status != 'fake').toList();

                  return FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _currentLocation!,
                      initialZoom: 15,
                      minZoom: 5,
                      maxZoom: 18,
                    ),
                    children: [
                      TileLayer(
                        key: ValueKey(isDarkMode ? 'dark' : 'light'),
                        urlTemplate: isDarkMode
                            ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                            : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        subdomains: const ['a', 'b', 'c'],
                        userAgentPackageName: 'com.rhinoresources.sahabat_assaffal',
                        maxZoom: 19,
                        tileBuilder: (context, tileWidget, tile) {
                          return AnimatedOpacity(
                            duration: const Duration(milliseconds: 500),
                            opacity: 1.0,
                            child: tileWidget,
                          );
                        },
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _currentLocation!,
                            width: 60,
                            height: 60,
                            child: _buildCurrentLocationMarker(),
                          ),
                          if (_selectedLocation != null)
                            Marker(
                              point: _selectedLocation!,
                              width: 50,
                              height: 50,
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Colors.red,
                                size: 50,
                              ),
                            ),
                          ...reports.where((report) {
                            // Sembunyikan laporan resolved yang sudah lebih 72 jam DAN disahkan komuniti (5 undi)
                            if (report.status == 'resolved' && report.verifiedResolved >= 5) {
                              final ageInHours = DateTime.now().difference(report.createdAt).inHours;
                              return ageInHours < 72;
                            }
                            return true;
                          }).map((report) => Marker(
                                point: LatLng(report.latitude, report.longitude),
                                width: 140, // Besarkan sedikit untuk tooltip yang panjang
                                height: 110,
                                alignment: Alignment.center,
                                child: GestureDetector(
                                  onTap: () => _showReportDetails(report),
                                  child: _buildPotholeMarker(report),
                                ),
                              )),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),

          // GLASS HEADER UNTUK HOME
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: _buildGlassHeader(isDarkMode),
          ),

          // SEARCH BAR & FILTERS (DITURUNKAN)
          Positioned(
            top: MediaQuery.of(context).padding.top + 90,
            left: 20,
            right: 20,
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      decoration: BoxDecoration(
                        color: (isDarkMode ? Colors.black : Colors.white).withOpacity(0.7),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1),
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: _searchLocation,
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                          decoration: InputDecoration(
                            hintText: 'Cari di Tungku...',
                            hintStyle: TextStyle(
                              color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.5),
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.5),
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? GestureDetector(
                                    onTap: () {
                                      _searchController.clear();
                                      setState(() {
                                        _searchResults = [];
                                        _showSearchResults = false;
                                      });
                                    },
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.5),
                                    ),
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // PENAPIS MASA (FILTER CHIPS)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('Semua', Icons.map_rounded, isDarkMode),
                        _buildFilterChip('Minggu Ini', Icons.calendar_view_week_rounded, isDarkMode),
                        _buildFilterChip('Minggu Lalu', Icons.history_rounded, isDarkMode),
                        _buildFilterChip('Bulan Lalu', Icons.event_note_rounded, isDarkMode),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_showSearchResults && _searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            decoration: BoxDecoration(
                              color: (isDarkMode ? Colors.black : Colors.white).withOpacity(0.85),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1),
                              ),
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _searchResults.length,
                              itemBuilder: (context, index) {
                                final result = _searchResults[index];
                                return ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryBlue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.place_rounded,
                                      color: AppTheme.primaryBlue,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    result['name'],
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isDarkMode ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${result['city']}, ${result['state']}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
                                    ),
                                  ),
                                  onTap: () => _selectLocation(result),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          Positioned(
            right: 16,
            bottom: 100,
            child: Column(
              children: [
                _buildGlassButton(
                  icon: Icons.add_rounded,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  ),
                  isDarkMode: isDarkMode,
                ),
                const SizedBox(height: 8),
                _buildGlassButton(
                  icon: Icons.remove_rounded,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                  isDarkMode: isDarkMode,
                ),
                const SizedBox(height: 16),
                _buildGlassButton(
                  icon: Icons.my_location_rounded,
                  onTap: () {
                    if (_currentLocation != null) {
                      _mapController.move(_currentLocation!, 16);
                    }
                  },
                  isDarkMode: isDarkMode,
                  isAccent: true,
                ),
              ],
            ),
          ),

          Positioned(
            left: 16,
            bottom: 100,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: (isDarkMode ? Colors.black : Colors.white).withOpacity(0.7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLegendItem(Colors.orange, 'Belum Disahkan', isDarkMode),
                      const SizedBox(height: 8),
                      _buildLegendItem(AppTheme.primaryRed, 'Aktif', isDarkMode),
                      const SizedBox(height: 8),
                      _buildLegendItem(Colors.green, 'Selesai', isDarkMode),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDarkMode,
    bool isAccent = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: isAccent
                  ? const LinearGradient(colors: [AppTheme.primaryRed, AppTheme.primaryBlue])
                  : null,
              color: isAccent ? null : (isDarkMode ? Colors.black : Colors.white).withOpacity(0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1),
              ),
            ),
            child: Icon(
              icon,
              size: 22,
              color: isAccent ? Colors.white : (isDarkMode ? Colors.white : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassHeader(bool isDarkMode) {
    return ClipRRect(
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
                    'Sahabat Assaffal',
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
    );
  }

  Widget _buildCurrentLocationMarker() {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Outer glow/pulse area
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
        ),
        // Human Icon
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.primaryBlue, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.person_pin_circle_rounded,
            color: AppTheme.primaryBlue,
            size: 24,
          ),
        ),
        // Tooltip "Anda Disini"
        Positioned(
          top: -35,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'Anda Disini',
                  style: TextStyle(
                    color: AppTheme.primaryBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              CustomPaint(
                size: const Size(10, 5),
                painter: _TrianglePainter(Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPotholeMarker(AssaffalReport report) {
    final isResolved = report.status == 'resolved';
    final isActive = report.upvoteCount > 0;
    final isPending = !isResolved && !isActive;
    final color = isResolved 
        ? Colors.green 
        : (isActive ? AppTheme.primaryRed : Colors.orange);

    Widget markerIcon = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(
        isResolved ? Icons.check_rounded : Icons.warning_rounded,
        color: Colors.white,
        size: 20,
      ),
    );

    if (isPending || isActive) {
      final tooltipText = isPending ? 'Perlu Undian Anda' : 'AWAS! LUBANG JALAN';
      final tooltipColor = isPending ? Colors.orange : AppTheme.primaryRed;
      final bgColor = isPending ? Colors.white : AppTheme.primaryRed;
      final textColor = isPending ? (Theme.of(context).brightness == Brightness.dark ? Colors.orange.shade400 : Colors.orange) : Colors.white;

      return RepaintBoundary(
        child: AnimatedBuilder(
          animation: _beepController,
          child: markerIcon,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Beeping/Pulsing effect
                Container(
                  width: 44 + (20 * _beepController.value),
                  height: 44 + (20 * _beepController.value),
                  decoration: BoxDecoration(
                    color: tooltipColor.withOpacity(0.5 * (1 - _beepController.value)),
                    shape: BoxShape.circle,
                  ),
                ),
                child!,
                // Tooltip
                Positioned(
                  top: -38,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          tooltipText,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      CustomPaint(
                        size: const Size(12, 6),
                        painter: _TrianglePainter(bgColor),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return markerIcon;
  }

  Widget _buildLegendItem(Color color, String label, bool isDarkMode) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDarkMode ? Colors.white70 : Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, IconData icon, bool isDarkMode) {
    final isSelected = _activeFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => setState(() => _activeFilter = label),
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected 
                    ? AppTheme.primaryBlue.withOpacity(0.8) 
                    : (isDarkMode ? Colors.black : Colors.white).withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppTheme.primaryBlue : (isDarkMode ? Colors.white24 : Colors.black12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon, 
                    size: 14, 
                    color: isSelected ? Colors.white : (isDarkMode ? Colors.white70 : Colors.black87)
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : (isDarkMode ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ],
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
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: (isDarkMode ? const Color(0xFF1a1a2e) : Colors.white).withOpacity(0.9),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
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
                                        tag: 'home-resolved-${report.id}',
                                      ),
                                    ),
                                  );
                                },
                                child: Hero(
                                  tag: 'home-resolved-${report.id}',
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
                                      tag: 'home-main-${report.id}',
                                    ),
                                  ),
                                );
                              },
                              child: Hero(
                                tag: 'home-main-${report.id}',
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
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          report.category.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    report.areaName ?? 'Unknown Area',
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
                            // BUTANG SHARE BARU
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
                  
                  InlineCommentsSection(
                    reportId: report.id,
                    communityService: _communityService,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: 24),

                  // BUTANG UTAMA UNTUK BUKA POP-UP VOTING
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
                ],
              ),
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

  void _verifyReport(AssaffalReport report, String type) async {
    final user = _authService.currentUser;
    if (user == null) {
      _showAuthRequiredDialog();
      return;
    }

    // Tunjukkan loading sekejap semasa semak GPS (LAKUKAN SEMAKAN GPS SEBELUM KAMERA)
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

      // Jika pilih 'Dah Selesai', minta gambar bukti (HANYA SELEPAS SEMAKAN GPS BERJAYA)
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

      // 4. Jika dalam radius, teruskan proses verifikasi
      await _supabaseService.verifyReportCommunity(report.id, user.id, type, imageUrl: proofImageUrl);
      
      if (mounted) {
        Navigator.pop(context); // Tutup bottom sheet
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

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'low': return Colors.green;
      case 'medium': return Colors.orange;
      case 'high': return Colors.deepOrange;
      case 'critical': return Colors.red;
      default: return Colors.orange;
    }
  }

  String _getSeverityEmoji(String severity) {
    switch (severity.toLowerCase()) {
      case 'low': return '🟢';
      case 'medium': return '🟡';
      case 'high': return '🟠';
      case 'critical': return '🔴';
      default: return '🟡';
    }
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul', 'Ogo', 'Sep', 'Okt', 'Nov', 'Dis'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  void _maximizePhoto(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: InteractiveViewer(
                    child: Image.network(
                      imageUrl,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, url, error) => const Icon(Icons.error),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _beepController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width / 2, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


