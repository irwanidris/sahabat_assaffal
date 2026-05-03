import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

import '../cubit/reports_cubit.dart';
import '../services/supabase_service.dart';
import '../services/device_service.dart';
import '../services/ai_severity_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../models/assaffal_report.dart';
import 'in_app_camera_screen.dart';
import 'disclaimer_screen.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<File> _images = [];
  LatLng? _location;
  
  final TextEditingController _addressController = TextEditingController(text: 'Mendapatkan lokasi...');
  final TextEditingController _areaNameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _reporterNameController = TextEditingController();
  final TextEditingController _reporterContactController = TextEditingController(text: '60');
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _dateTimeController = TextEditingController();

  String _category = 'Lubang Jalan';
  final List<String> _otherCategories = [
    'Lampu Jalan Padam', 'Gangguan Elektrik', 
    'Sampah Sarap', 'Longkang Tersumbat', 'Pokok Tumbang', 'Lain-lain'
  ];

  bool _isLoading = false;
  bool _isLoggingIn = false;
  bool _showSearchResults = false;
  bool _isAnalyzingImage = false;
  bool _isAgreed = false;
  String _detectedSeverity = 'medium';
  List<dynamic> _searchResults = [];
  DateTime? _incidentDateTime;

  final MapController _mapController = MapController();
  final ImagePicker _picker = ImagePicker();
  final SupabaseService _supabaseService = SupabaseService();
  final DeviceService _deviceService = DeviceService();
  final AISeverityService _aiService = AISeverityService();
  final AuthService _authService = AuthService();

  // Kawasan Lahad Datu & Tungku
  final double _defaultLat = 5.0392;
  final double _defaultLon = 118.6313;
  final double _minLat = 4.8000;
  final double _maxLat = 5.3500;
  final double _minLon = 118.1500;
  final double _maxLon = 119.3000;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    _getCurrentLocation();
    _updateReporterName();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    setState(() {
      if (_tabController.index == 0) {
        _category = 'Lubang Jalan';
      } else {
        // Jika tukar ke tab lain dan category masih 'Lubang Jalan', reset ke default tab 2
        if (_category == 'Lubang Jalan') {
          _category = _otherCategories[0];
        }
      }
    });
  }

  Future<void> _updateReporterName() async {
    final profile = await _deviceService.getOrCreateProfile();
    if (mounted) {
      setState(() {
        _reporterNameController.text = profile['nickname'] ?? '';
      });
    }
  }

  bool _isInAllowedArea(LatLng? pos) {
    // MODIFIKASI UJIAN: Sentiasa benar supaya boleh lapor dari mana-mana
    return true; 
    /* Asal:
    if (pos == null) return false;
    return pos.latitude >= _minLat && pos.latitude <= _maxLat && 
           pos.longitude >= _minLon && pos.longitude <= _maxLon;
    */
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final newPos = LatLng(position.latitude, position.longitude);
      
      // MODIFIKASI UJIAN: Abaikan sekatan kawasan
      setState(() { _location = newPos; });
      _mapController.move(newPos, 15);
      _updateAddress(position.latitude, position.longitude);
      
      /* Asal:
      if (!_isInAllowedArea(newPos)) {
        setState(() { _location = null; _addressController.text = 'Luar kawasan perkhidmatan'; });
        return;
      }
      setState(() { _location = newPos; });
      _updateAddress(position.latitude, position.longitude);
      */
    } catch (e) { debugPrint(e.toString()); }
  }

  Future<void> _updateAddress(double lat, double lng) async {
    final response = await http.get(Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&addressdetails=1&zoom=18'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        _addressController.text = data['display_name'] ?? '';
        _areaNameController.text = data['address']['neighbourhood'] ?? data['address']['suburb'] ?? '';
      });
    }
  }

  Future<void> _processImage(File imageFile) async {
    setState(() { _images.add(imageFile); _isAnalyzingImage = true; });
    final result = await _aiService.analyzeSeverity(imageFile, _category);
    setState(() { _detectedSeverity = result.severity; _isAnalyzingImage = false; });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final user = _authService.currentUser;
    final isLoggedIn = user != null;
    final isVerified = user?.userMetadata?['phone_verified'] == true;
    final bool showAkanDatang = _tabController.index == 1 && !isVerified;

    return Scaffold(
      backgroundColor: isDarkMode ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            SizedBox(height: MediaQuery.of(context).padding.top + 90),
            const Text('Lapor Masalah', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            
            // Tab Bar Lapor
            Container(
              margin: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.white10 : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(15),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(
                    colors: [AppTheme.primaryRed, AppTheme.primaryBlue],
                  ),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: isDarkMode ? Colors.white70 : Colors.black54,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Lapor Lubang'),
                  Tab(text: 'Lapor Masalah Lain'),
                ],
              ),
            ),

            if (showAkanDatang) ...[
              const SizedBox(height: 20),
              const Icon(Icons.verified_user_outlined, size: 80, color: Colors.green),
              const SizedBox(height: 20),
              const Text(
                'AKAN DATANG',
                style: TextStyle(
                  fontSize: 24, 
                  fontWeight: FontWeight.bold, 
                  letterSpacing: 2,
                  color: Colors.grey
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text.rich(
                  TextSpan(
                    text: 'Ciri "Masalah Lain" terhad untuk pengguna yang sudah disahkan (',
                    children: [
                      TextSpan(
                        text: 'Verified',
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: ') sahaja.'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.1),
              _buildSubmitButton(isLoggedIn, isVerified: isVerified),
            ] else ...[
              // Dropdown Kategori (Hanya untuk Tab Masalah Lain)
              if (_tabController.index == 1) ...[
                DropdownButtonFormField<String>(
                  value: _otherCategories.contains(_category) ? _category : _otherCategories[0],
                  decoration: InputDecoration(
                    labelText: 'Pilih Kategori Masalah',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDarkMode ? Colors.white10 : Colors.black.withOpacity(0.02),
                  ),
                  items: _otherCategories.map((String cat) {
                    return DropdownMenuItem<String>(
                      value: cat,
                      child: Text(cat),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _category = newValue;
                      });
                    }
                  },
                ),
                const SizedBox(height: 20),
              ],

              // Foto
              _buildPhotoSection(isDarkMode),
              const SizedBox(height: 20),

              // Peta
              _buildLocationSection(),
              const SizedBox(height: 20),

              // Keterangan Tambahan
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Keterangan Tambahan (Opsional)',
                  hintText: 'Berikan butiran lanjut tentang masalah...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),

              // Checkbox Disclaimer
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: Checkbox(
                      value: _isAgreed,
                      onChanged: (v) => setState(() => _isAgreed = v ?? false),
                      activeColor: AppTheme.primaryRed,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isAgreed = !_isAgreed),
                      child: const Text(
                        'Dengan menanda kotak ini, anda bertanggungjawab penuh dengan maklumat yang anda muatnaik dan anda sedar bahawa laporan ini untuk kepentingan orang ramai dan bagi mendapat perhatian pihak bertanggungjawab.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              // Submit
              _buildSubmitButton(isLoggedIn, isVerified: isVerified),
            ],
            const SizedBox(height: 80), // Kotak transparent sebesar header
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSection(bool isDarkMode) {
    return Column(
      children: [
        Text(
          _tabController.index == 0 
              ? 'Sila gambar Jalan Lubang maksimum 5 Foto.'
              : 'Sila gambar masalah maksimum 5 Foto.',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        if (_images.length < 5)
          Center(
            child: GestureDetector(
              onTap: () => _openInAppCamera(),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white10 : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDarkMode ? Colors.white24 : Colors.black12,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.camera_alt_rounded,
                  size: 40,
                  color: AppTheme.primaryRed,
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (_isAnalyzingImage) 
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 4),
                const Text('Menganalisis imej...', style: TextStyle(fontSize: 10)),
              ],
            ),
          ),
        Center(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _images.asMap().entries.map((entry) {
              int index = entry.key;
              File img = entry.value;
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(img, width: 70, height: 70, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: -2,
                    right: -2,
                    child: GestureDetector(
                      onTap: () => setState(() => _images.removeAt(index)),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Future<void> _openInAppCamera() async {
    final File? capturedImage = await Navigator.push(context, MaterialPageRoute(builder: (context) => InAppCameraScreen(category: _category)));
    if (capturedImage != null) _processImage(capturedImage);
  }

  Future<void> _selectDateTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _incidentDateTime ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      if (!mounted) return;
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_incidentDateTime ?? DateTime.now()),
      );

      if (pickedTime != null) {
        setState(() {
          _incidentDateTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          _dateTimeController.text = DateFormat('dd/MM/yyyy HH:mm').format(_incidentDateTime!);
        });
      }
    }
  }

  Widget _buildLocationSection() {
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: _location ?? LatLng(_defaultLat, _defaultLon), initialZoom: 15),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.sahabatassaffal.hero',
              ),
              if (_location != null) MarkerLayer(markers: [Marker(point: _location!, child: const Icon(Icons.location_pin, color: Colors.red))]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: TextEditingController(
            text: _location != null 
              ? '${_location!.latitude.toStringAsFixed(6)}, ${_location!.longitude.toStringAsFixed(6)}' 
              : 'Mendapatkan koordinat...'
          ),
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Koordinat GPS (Automatik)',
            prefixIcon: Icon(Icons.gps_fixed, size: 20),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _areaNameController, 
          decoration: const InputDecoration(
            labelText: 'Kawasan/Taman (pilihan)',
            hintText: 'Contoh : Depan Masjid Tungku',
            hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
            border: OutlineInputBorder(),
          )
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _dateTimeController,
          readOnly: true,
          onTap: _selectDateTime,
          decoration: const InputDecoration(
            labelText: 'Tarikh & Masa Kejadian',
            prefixIcon: Icon(Icons.calendar_today),
            border: OutlineInputBorder(),
            hintText: 'Pilih tarikh dan masa',
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton(bool isLoggedIn, {bool isVerified = false}) {
    final bool isTabMasalahLain = _tabController.index == 1;
    final bool isRestricted = isTabMasalahLain && !isVerified;
    
    bool canSubmit = isLoggedIn && _isAgreed && !_isLoading && !isRestricted;
    
    return GestureDetector(
      onTap: canSubmit ? () => _submitReportFlow() : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        height: 55,
        decoration: BoxDecoration(
          color: canSubmit 
              ? AppTheme.primaryRed 
              : AppTheme.primaryRed.withOpacity(0.3),
          borderRadius: BorderRadius.circular(15),
          boxShadow: canSubmit ? [
            BoxShadow(
              color: AppTheme.primaryRed.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            )
          ] : [],
        ),
        alignment: Alignment.center,
        child: _isLoading 
          ? const SizedBox(
              height: 20, 
              width: 20, 
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
            ) 
          : const Text(
              'Hantar', 
              style: TextStyle(
                color: Colors.white, 
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
      ),
    );
  }

  Future<void> _submitReportFlow() async {
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sila ambil sekurang-kurangnya satu foto.')),
      );
      return;
    }

    if (_location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sila pastikan lokasi anda dikesan.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 2. Get User Info (Gunakan Nickname dari Profil)
      final user = _authService.currentUser;
      final deviceId = await _deviceService.getDeviceId();
      final profile = await _deviceService.getOrCreateProfile();
      
      // Pastikan nickname tidak kosong
      String nickname = profile['nickname'] ?? 'Sahabat';
      if (nickname.isEmpty) nickname = 'Sahabat';

      final String coords = "${_location!.latitude.toStringAsFixed(4)}, ${_location!.longitude.toStringAsFixed(4)}";
      final String dateTime = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

      // 1. Upload Images
      List<String> uploadedUrls = [];
      for (var image in _images) {
        // Panggil uploadImage tanpa sebarang parameter tambahan
        final url = await _supabaseService.uploadImage(image);
        uploadedUrls.add(url);
      }
      final imageUrlsString = uploadedUrls.join(',');

      // 3. Submit Report
      await _supabaseService.submitReport(
        imageUrl: imageUrlsString,
        latitude: _location!.latitude,
        longitude: _location!.longitude,
        address: _addressController.text,
        areaName: _areaNameController.text.isEmpty ? 'Kawasan Tidak Dinyatakan' : _areaNameController.text,
        duration: _dateTimeController.text.isEmpty ? 'Baru' : _dateTimeController.text,
        description: _descriptionController.text,
        // deviceId: deviceId, <--- Baris ini telah dipadam
        userId: user?.id,
        severity: _detectedSeverity,
        category: _category,
        reporterName: nickname,
        reporterContact: _reporterContactController.text,
      );

      if (mounted) {
        // Muat semula data laporan di seluruh aplikasi
        context.read<ReportsCubit>().loadReports();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Laporan Anda Telah Berjaya. Dan tertakluk kepada verifikasi masyarakat setempat. Sila lihat Laporan anda di Tab Laporan.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
        
        // Reset Form
        setState(() {
          _images.clear();
          _descriptionController.clear();
          _isAgreed = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menghantar laporan: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _addressController.dispose();
    _areaNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
