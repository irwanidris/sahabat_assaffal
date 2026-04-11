import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../cubit/reports_cubit.dart';
import '../cubit/theme_cubit.dart';
import '../services/supabase_service.dart';
import '../services/device_service.dart';
import '../services/ai_severity_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'in_app_camera_screen.dart';
import '../models/pothole_report.dart';
import 'disclaimer_screen.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final List<File> _images = [];
  LatLng? _location;
  
  final TextEditingController _addressController = TextEditingController(text: 'Mendapatkan lokasi...');
  final TextEditingController _areaNameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _reporterNameController = TextEditingController();
  final TextEditingController _reporterContactController = TextEditingController(text: '60');
  
  String _category = 'Lubang Jalan';
  final List<String> _categories = [
    'Lubang Jalan',
    'Lampu Jalan Padam',
    'Gangguan Elektrik',
    'Sampah Sarap',
    'Longkang Tersumbat',
    'Pokok Tumbang',
    'Lain-lain'
  ];

  DateTime? _incidentDateTime;
  final TextEditingController _dateTimeController = TextEditingController();
  
  bool _isLoading = false;
  bool _isLoggingIn = false;
  
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _showSearchResults = false;

  final double _defaultLat = 5.0392;
  final double _defaultLon = 118.6313;
  
  String _detectedSeverity = 'medium';
  bool _isAnalyzingImage = false;

  final MapController _mapController = MapController();
  final ImagePicker _picker = ImagePicker();
  final SupabaseService _supabaseService = SupabaseService();
  final DeviceService _deviceService = DeviceService();
  final AISeverityService _aiService = AISeverityService();
  final AuthService _authService = AuthService();

  final double _minLat = 4.8000;
  final double _maxLat = 5.3500;
  final double _minLon = 118.1500;
  final double _maxLon = 119.3000;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _updateReporterName();
  }

  void _updateReporterName() {
    if (_authService.currentUser != null) {
      final String fullName = _authService.currentUser!.userMetadata?['full_name'] ?? '';
      _reporterNameController.text = fullName;
    }
  }

  bool _isInAllowedArea(LatLng? pos) {
    if (pos == null) return false;
    return pos.latitude >= _minLat && 
           pos.latitude <= _maxLat && 
           pos.longitude >= _minLon && 
           pos.longitude <= _maxLon;
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isLoggingIn = true);
    try {
      await _authService.signInWithGoogle();
      if (mounted) {
        _updateReporterName();
        _showSnackBar('Log masuk berjaya! Anda kini boleh menghantar laporan.');
      }
    } catch (e) {
      if (mounted) _showSnackBar('Gagal log masuk: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _location = null; // Jangan beri lokasi lalai jika GPS tutup
            _addressController.text = 'Sila hidupkan GPS anda';
          });
          _showSnackBar('Perkhidmatan lokasi dimatikan. Sila hidupkan GPS.', isError: true);
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            _showSnackBar('Kebenaran lokasi dinafi.', isError: true);
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          _showSnackBar('Kebenaran lokasi dinafi secara kekal. Sila tukar di tetapan.', isError: true);
        }
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final newPos = LatLng(position.latitude, position.longitude);
      
      // SEMAK KAWASAN SERTA-MERTA
      if (!_isInAllowedArea(newPos)) {
        if (mounted) {
          setState(() {
            _location = null;
            _addressController.text = 'Di luar kawasan perkhidmatan';
          });
          _showSnackBar('Anda berada di luar kawasan Lahad Datu / Tungku.', isError: true);
        }
        return;
      }

      if (mounted) {
        setState(() {
          _location = newPos;
        });
        await _updateAddress(position.latitude, position.longitude);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _location = null;
          _addressController.text = 'Gagal mendapatkan lokasi';
        });
      }
    }
  }

  Future<void> _updateAddress(double lat, double lng) async {
    try {
      final response = await http.get(Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&addressdetails=1&zoom=18',
      ), headers: {
        'User-Agent': 'SahabatAssaffal/1.0',
        'Accept-Language': 'ms',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String displayName = data['display_name'] ?? '';
        final address = data['address'] as Map<String, dynamic>?;
        
        String bestAreaName = '';
        if (address != null) {
          // Cubaan mendapatkan nama mengikut hierarki data peta
          bestAreaName = address['neighbourhood'] ?? 
                         address['suburb'] ?? 
                         address['road'] ?? // Tambah rujukan nama JALAN
                         address['village'] ?? // Tambah rujukan nama KAMPUNG
                         address['hamlet'] ??
                         address['town'] ??
                         '';
        }
        
        setState(() {
          _addressController.text = displayName.isNotEmpty ? displayName : 'Alamat tidak dijumpai';
          // Pre-fill nama kawasan jika dijumpai, jika tidak biarkan kosong untuk diisi manual
          _areaNameController.text = bestAreaName;
        });
      }
    } catch (e) {
      debugPrint('Nominatim error: $e');
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }

    try {
      final enhancedQuery = query.toLowerCase().contains('lahad datu') ? query : '$query, Lahad Datu';
      final photonUrl = 'https://photon.komoot.io/api/?q=${Uri.encodeComponent(enhancedQuery)}&lat=$_defaultLat&lon=$_defaultLon&limit=10&lang=ms';
      final response = await http.get(Uri.parse(photonUrl)).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;
        final results = features.map((f) {
          final props = f['properties'] as Map<String, dynamic>;
          final coords = f['geometry']['coordinates'] as List;
          return {
            'name': props['name'] ?? 'Tidak diketahui',
            'city': props['city'] ?? 'Lahad Datu',
            'state': props['state'] ?? 'Sabah',
            'lat': coords[1],
            'lon': coords[0],
          };
        }).toList();

        setState(() {
          _searchResults = results;
          _showSearchResults = true;
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }
  }

  void _selectLocation(Map<String, dynamic> location) {
    final lat = location['lat'] as double;
    final lon = location['lon'] as double;
    final point = LatLng(lat, lon);
    
    // SEMAK KAWASAN SEBELUM PILIH
    if (!_isInAllowedArea(point)) {
      _showSnackBar('Lokasi ini di luar kawasan Lahad Datu / Tungku.', isError: true);
      return;
    }

    _mapController.move(point, 16);
    setState(() {
      _location = point;
      _searchController.text = location['name'];
      _showSearchResults = false;
      FocusScope.of(context).unfocus();
    });
    _updateAddress(lat, lon);
  }

  Future<void> _showImagePicker() async {
    if (_authService.currentUser == null) {
      _showSnackBar('Sila log masuk terlebih dahulu untuk menggunakan kamera.', isError: true);
      return;
    }

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: (isDarkMode ? const Color(0xFF1a1a2e) : Colors.white).withOpacity(0.9),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(3))),
                const SizedBox(height: 28),
                const Text('Tambah Foto', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildPickerOption(icon: Icons.camera_alt_rounded, label: 'Kamera', onTap: () => _openInAppCamera(), isDarkMode: isDarkMode),
                    _buildPickerOption(icon: Icons.photo_library_rounded, label: 'Galeri', onTap: () => _captureImage(ImageSource.gallery), isDarkMode: isDarkMode),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPickerOption({required IconData icon, required String label, required VoidCallback onTap, required bool isDarkMode}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppTheme.primaryRed, AppTheme.primaryBlue]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, size: 36, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _openInAppCamera() async {
    Navigator.pop(context);
    final File? capturedImage = await Navigator.push<File>(context, MaterialPageRoute(builder: (context) => InAppCameraScreen(category: _category)));
    if (capturedImage != null) _processImage(capturedImage);
  }

  Future<void> _captureImage(ImageSource source) async {
    Navigator.pop(context);
    final XFile? image = await _picker.pickImage(source: source, imageQuality: 70);
    if (image != null) _processImage(File(image.path));
  }

  Future<void> _processImage(File imageFile) async {
    if (_images.length >= 5) {
      _showSnackBar('Maksimum 5 foto sahaja.', isError: true);
      return;
    }

    setState(() { 
      _images.add(imageFile); 
      _isAnalyzingImage = true; 
    });
    try {
      final validation = await _aiService.validateImageByCategory(imageFile, _category);
      if (!validation.isValid) {
        setState(() { 
          _images.remove(imageFile); 
          _isAnalyzingImage = false; 
        });
        _showValidationError(validation);
        return;
      }
      final result = await _aiService.analyzeSeverity(imageFile, _category);
      setState(() { _detectedSeverity = result.severity; _isAnalyzingImage = false; });
      _showSeverityResult(result);
    } catch (e) {
      setState(() { _isAnalyzingImage = false; });
    }
  }

  void _showSeverityResult(SeverityResult result) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Tahap Bahaya: ${result.severity.toUpperCase()}\n${result.details}'),
      backgroundColor: AISeverityService.getSeverityColor(result.severity),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showValidationError(ValidationResult validation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Imej Tidak Sah'),
        content: Text(validation.message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
      ),
    );
  }

  Future<bool> _showConfirmationDialog() async {
    bool isAgreed = false;
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppTheme.primaryBlue),
                  SizedBox(width: 10),
                  Text('Pengesahan Aduan'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Laporan ini adalah bagi memaklumkan kepada Pejabat Adun agar dipanjangkan kepada pihak yang sepatutnya. Sebarang hasil aduan bergantung kepada pihak berkuasa.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  CheckboxListTile(
                    value: isAgreed,
                    onChanged: (val) => setState(() => isAgreed = val ?? false),
                    title: const Text('Saya faham dan setuju', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppTheme.primaryBlue,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Batal', style: TextStyle(color: Colors.grey)),
                ),
                if (isAgreed)
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryRed,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Teruskan', style: TextStyle(color: Colors.white)),
                  ),
              ],
            );
          },
        );
      },
    ) ?? false;
  }

  Future<void> _submitReportFlow() async {
    if (_authService.currentUser == null) {
      _showSnackBar('Sila log masuk untuk menghantar laporan.', isError: true);
      return;
    }

    if (_reporterNameController.text.trim().isEmpty) {
      _showSnackBar('Sila pastikan nama anda dipaparkan.', isError: true);
      return;
    }
    
    // PENGESAHAN MANDATORI NAMA KAWASAN YANG LEBIH TEGAS
    final areaName = _areaNameController.text.trim();
    if (areaName.isEmpty || areaName.toLowerCase() == 'kawasan tidak diketahui') {
      _showSnackBar('Sila masukkan nama kawasan, taman, atau nama jalan!', isError: true);
      return;
    }

    final phone = _reporterContactController.text.trim();
    if (phone == '60' || phone.length < 10) {
      _showSnackBar('Sila masukkan nombor telefon yang sah bermula dengan 60.', isError: true);
      return;
    }

    if (_images.isEmpty || _location == null) {
      _showSnackBar('Sila ambil sekurang-kurangnya satu foto dan pastikan lokasi dikesan.', isError: true);
      return;
    }

    if (!_isInAllowedArea(_location)) {
      _showSnackBar('Maaf, aduan hanya diterima untuk kawasan Lahad Datu & Tungku.', isError: true);
      return;
    }

    final confirmed = await _showConfirmationDialog();
    if (!confirmed) return;

    setState(() => _isLoading = true);
    
    try {
      final areaName = _areaNameController.text.trim();
      final duplicate = await _supabaseService.checkForDuplicate(_location!.latitude, _location!.longitude, areaName);
      if (duplicate != null) {
        setState(() => _isLoading = false);
        final bool proceed = await _showDuplicateWarning(duplicate);
        if (!proceed) return;
        setState(() => _isLoading = true);
      }

      List<String> imageUrls = [];
      for (var img in _images) {
        final url = await _supabaseService.uploadImage(img);
        imageUrls.add(url);
      }
      final imageUrl = imageUrls.join(',');

      final deviceId = await _deviceService.getDeviceId();
      
      String? pushId = OneSignal.User.pushSubscription.id;
      
      await _supabaseService.submitReport(
        imageUrl: imageUrl,
        latitude: _location!.latitude,
        longitude: _location!.longitude,
        address: _addressController.text,
        areaName: areaName,
        duration: _incidentDateTime != null ? DateFormat('dd/MM/yyyy HH:mm').format(_incidentDateTime!) : 'Tidak dinyatakan',
        description: _descriptionController.text,
        deviceId: deviceId,
        severity: _detectedSeverity,
        category: _category,
        reporterName: _reporterNameController.text.trim(),
        reporterContact: _reporterContactController.text.trim(),
        reporterPushId: pushId,
      );

      await _deviceService.incrementReportCount();
      
      if (mounted) {
        context.read<ReportsCubit>().refreshReports();
        _showSnackBar('Aduan anda berjaya dihantar! 🎉');
        _resetForm();
      }
    } catch (e) {
      if (mounted) _showSnackBar('Ralat: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _showDuplicateWarning(PotholeReport duplicate) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aduan Serupa Ditemui'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aduan di kawasan ini telah pun dilaporkan sebelum ini.'),
            const SizedBox(height: 10),
            Text('Kod: ${duplicate.reportCode}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Status: ${duplicate.status.toUpperCase()}'),
            const SizedBox(height: 10),
            const Text('Adakah anda mahu meneruskan laporan baru ini?'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Teruskan')),
        ],
      ),
    ) ?? false;
  }

  void _resetForm() {
    setState(() {
      _images.clear();
      _descriptionController.clear();
      _areaNameController.clear();
      _incidentDateTime = null;
      _dateTimeController.clear();
      _category = 'Lubang Jalan';
      _reporterContactController.text = '60';
    });
    _getCurrentLocation();
    _updateReporterName();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message), 
      backgroundColor: isError ? Colors.red : Colors.green, 
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return StreamBuilder<AuthState>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        final isLoggedIn = _authService.currentUser != null;

        return Scaffold(
          backgroundColor: isDarkMode ? AppTheme.darkBackground : AppTheme.lightBackground,
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(isDarkMode, isLoggedIn),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Lapor Masalah', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                        
                        if (!isLoggedIn) _buildLoginPrompt(isDarkMode),
                        
                        const SizedBox(height: 28),
                        _buildCategoryDropdown(isDarkMode),
                        const SizedBox(height: 20),
                        
                        if (isLoggedIn) _buildReporterInfo(isDarkMode),
                        const SizedBox(height: 20),
                        
                        _buildPhotoSection(isDarkMode),
                        const SizedBox(height: 20),
                        
                        _buildLocationSection(isDarkMode),
                        const SizedBox(height: 20),
                        
                        _buildDurationSection(isDarkMode),
                        const SizedBox(height: 20),
                        
                        _buildDescriptionSection(isDarkMode),
                        const SizedBox(height: 32),
                        
                        _buildSubmitButton(isLoggedIn),
                        const SizedBox(height: 16),
                        
                        Center(
                          child: TextButton(
                            onPressed: () => DisclaimerScreen.show(context),
                            child: Text('Penafian', style: TextStyle(color: Colors.grey.shade600, decoration: TextDecoration.underline, fontSize: 14)),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildHeader(bool isDarkMode, bool isLoggedIn) {
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
              border: Border.all(color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    width: 24,
                    height: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lapor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginPrompt(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryRed.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryRed.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Text(
            'Log masuk diperlukan untuk menghantar aduan bagi tujuan integriti maklumat.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          _isLoggingIn 
            ? const CircularProgressIndicator()
            : ElevatedButton.icon(
                onPressed: _handleGoogleLogin,
                icon: Image.network('https://upload.wikimedia.org/wikipedia/commons/5/53/Google_%22G%22_Logo.svg', height: 20),
                label: const Text('Log Masuk dengan Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildCategoryDropdown(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Jenis Aduan', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _category,
              isExpanded: true,
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReporterInfo(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Maklumat Pengadu (Integriti)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        TextField(
          controller: _reporterNameController,
          readOnly: true, 
          decoration: InputDecoration(
            labelText: 'Nama Penuh Pengadu (Dari Google)', 
            filled: true, 
            fillColor: Colors.grey.withOpacity(0.1), 
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('No. Telefon ', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Text(
                '(Laporan anda akan ditolak jika nombor anda tidak dapat dihubungi. WAJIB)',
                style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _reporterContactController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: 'Contoh: 60123456789',
            filled: true, 
            fillColor: Colors.grey.withOpacity(0.1), 
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            prefixIcon: const Icon(Icons.phone, size: 20),
          ),
          onChanged: (value) {
            if (!value.startsWith('60')) {
              _reporterContactController.text = '60';
              _reporterContactController.selection = TextSelection.fromPosition(
                TextPosition(offset: _reporterContactController.text.length)
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildPhotoSection(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Foto ', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Text(
                '(Gambar pertama akan dijadikan gambar utama, Maksimum 5)',
                style: TextStyle(
                  fontSize: 11,
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Butang Tambah Foto Utama
        if (_images.length < 5)
          GestureDetector(
            onTap: _showImagePicker,
            child: Container(
              width: double.infinity,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.primaryRed.withOpacity(0.5),
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_rounded, color: AppTheme.primaryRed, size: 32),
                  const SizedBox(height: 8),
                  const Text('Klik untuk Tambah Gambar', style: TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        
        if (_images.isNotEmpty) ...[
          const SizedBox(height: 16),
          // Senarai Gambar Di Bawah
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1,
            ),
            itemCount: _images.length,
            itemBuilder: (context, index) {
              return Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: index == 0 
                        ? Border.all(color: Colors.green, width: 3) 
                        : Border.all(color: Colors.grey.shade300),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.file(_images[index], width: double.infinity, height: double.infinity, fit: BoxFit.cover),
                    ),
                  ),
                  if (index == 0)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.only(topLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
                        ),
                        child: const Text('UTAMA', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  Positioned(
                    top: 5,
                    right: 5,
                    child: GestureDetector(
                      onTap: () => setState(() => _images.removeAt(index)),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
        if (_images.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Center(
              child: Text(
                'Sila muat naik sekurang-kurangnya satu foto aduan.',
                style: TextStyle(color: Colors.red.shade400, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLocationSection(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Lokasi', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        TextField(
          controller: _searchController,
          onChanged: _searchLocation,
          decoration: InputDecoration(hintText: 'Cari lokasi...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
        if (_showSearchResults) ..._searchResults.map((r) => ListTile(title: Text(r['name']), subtitle: Text(r['city']), onTap: () => _selectLocation(r))),
        const SizedBox(height: 10),
        SizedBox(
          height: 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _location ?? LatLng(_defaultLat, _defaultLon), 
                initialZoom: 15, 
                onTap: (_, p) { setState(() => _location = p); _updateAddress(p.latitude, p.longitude); }
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.rhinoresources.sahabat_assaffal',
                ),
                if (_location != null) MarkerLayer(markers: [Marker(point: _location!, child: const Icon(Icons.location_pin, color: Colors.red, size: 40))]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(controller: _areaNameController, decoration: const InputDecoration(labelText: 'Nama Kawasan / Taman / Jalan (*Wajib)')),
        TextField(controller: _addressController, maxLines: 2, decoration: const InputDecoration(labelText: 'Alamat Penuh')),
      ],
    );
  }

  Future<void> _selectDateTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryRed,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      if (!mounted) return;
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
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

  Widget _buildDurationSection(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tarikh & Masa Berlaku', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        TextField(
          controller: _dateTimeController,
          readOnly: true,
          onTap: _selectDateTime,
          decoration: InputDecoration(
            hintText: 'Pilih tarikh dan masa...',
            prefixIcon: const Icon(Icons.calendar_today_rounded, size: 20),
            filled: true,
            fillColor: Colors.grey.withOpacity(0.1),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildDescriptionSection(bool isDarkMode) {
    return TextField(
      controller: _descriptionController,
      maxLines: 3,
      decoration: const InputDecoration(labelText: 'Maklumat Tambahan (Pilihan)', hintText: 'Terangkan keadaan lubang/masalah...'),
    );
  }

  Widget _buildSubmitButton(bool isLoggedIn) {
    bool isLocationValid = _location != null && _isInAllowedArea(_location);

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: (_isLoading || !isLoggedIn || !isLocationValid) ? null : _submitReportFlow,
        style: ElevatedButton.styleFrom(
          backgroundColor: (isLoggedIn && isLocationValid) ? AppTheme.primaryRed : Colors.grey, 
          foregroundColor: Colors.white, 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
        ),
        child: _isLoading 
            ? const CircularProgressIndicator(color: Colors.white) 
            : Text(
                !isLoggedIn 
                  ? 'Log Masuk untuk Lapor' 
                  : (!isLocationValid ? 'Di Luar Kawasan' : 'Hantar Laporan'), 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
              ),
      ),
    );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _areaNameController.dispose();
    _reporterNameController.dispose();
    _reporterContactController.dispose();
    _searchController.dispose();
    _dateTimeController.dispose();
    super.dispose();
  }
}
