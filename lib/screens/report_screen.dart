import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../services/ai_severity_service.dart';
import '../services/watermark_service.dart';
import 'in_app_camera_screen.dart';
import 'notifications_list_screen.dart';

class AnimatedProgressIndicator extends StatelessWidget {
  final double value;
  final Color color;
  const AnimatedProgressIndicator({super.key, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(value: value, color: color, backgroundColor: color.withOpacity(0.2));
  }
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();
  final DeviceService _deviceService = DeviceService();
  final AISeverityService _aiService = AISeverityService();
  final ImagePicker _picker = ImagePicker();
  
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _areaNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _reporterNameController = TextEditingController();
  
  final MapController _mapController = MapController();
  
  List<File> _images = [];
  LatLng? _location;
  String _detectedSeverity = 'medium';
  String _category = 'Lubang Jalan';
  final List<String> _categories = [
    'Lubang Jalan',
    'Longkang Tersumbat',
    'Lampu Jalan Padam',
    'Sampah Sarap',
    'Pokok Tumbang',
    'Lain-lain'
  ];
  bool _isLoading = false;
  bool _isAnalyzingImage = false;
  String? _aiMessage;
  String? _aiDetails;
  bool? _isAiValid;
  DateTime? _incidentDateTime;
  bool _safetyWarningAccepted = false;
  List<Map<String, dynamic>> _searchResults = [];
  bool _showSearchResults = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _setInitialReporterName();
  }

  void _setInitialReporterName() {
    final user = _authService.currentUser;
    if (user != null) {
      _reporterNameController.text = user.userMetadata?['nickname'] ?? '';
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _location = LatLng(position.latitude, position.longitude);
      });
      _mapController.move(_location!, 16);
      _updateAddress(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  Future<void> _updateAddress(double lat, double lon) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          _addressController.text = '${place.street}, ${place.locality}, ${place.postalCode}, ${place.administrativeArea}';
          if (_areaNameController.text.isEmpty) {
             _areaNameController.text = place.subLocality ?? place.locality ?? '';
          }
        });
      }
    } catch (e) {
      debugPrint('Error getting address: $e');
    }
  }

  bool _isInAllowedArea(LatLng? point) {
    if (point == null) return false;
    return point.latitude >= 4.9 && point.latitude <= 5.3 &&
           point.longitude >= 118.1 && point.longitude <= 119.3;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppTheme.primaryRed : Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _showImagePicker() async {
    if (_authService.currentUser == null) {
      _showSnackBar('Sila log masuk untuk menggunakan kamera.', isError: true);
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

  Future<void> _processImage(File imageFile, {bool isRetry = false}) async {
    if (!isRetry && _images.length >= 5) {
      _showSnackBar('Maksimum 5 foto sahaja.', isError: true);
      return;
    }

    setState(() { 
      _isAnalyzingImage = true; 
    });

    try {
      setState(() {
        _aiMessage = "Menganalisis imej...";
        _aiDetails = null;
        _isAiValid = null;
      });

      File fileToAnalyze = imageFile;

      // Hanya tambah watermark jika bukan percubaan semula (isRetry)
      // Kerana isRetry biasanya menggunakan file yang sudah di-watermark
      if (!isRetry) {
        fileToAnalyze = await WatermarkService.addWatermark(
          imageFile, 
          lat: _location?.latitude, 
          lon: _location?.longitude,
          nickname: _reporterNameController.text.trim(),
        );
      }
      
      // 2. PENGESAHAN AI (Pastikan imej sepadan dengan kategori)
      final validation = await _aiService.validateImageByCategory(fileToAnalyze, _category);
      
      if (!validation.isValid) {
        setState(() { 
          _isAnalyzingImage = false; 
          _aiMessage = validation.message;
          _aiDetails = validation.details;
          _isAiValid = false;
        });
        _showSnackBar(validation.message, isError: true);
        return;
      }

      // 3. Analisis Tahap Bahaya
      final result = await _aiService.analyzeSeverity(fileToAnalyze, _category);
      
      setState(() { 
        if (!isRetry) {
          _images.add(fileToAnalyze);
        }
        _detectedSeverity = result.severity; 
        _isAnalyzingImage = false; 
        _aiMessage = validation.message;
        _aiDetails = validation.details;
        _isAiValid = true;
      });
    } catch (e) {
      debugPrint('Error processing image: $e');
      setState(() { _isAnalyzingImage = false; });
      _showSnackBar('Gagal memproses imej.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: Column(
        children: [
          _buildGlassHeader(isDarkMode),
          Expanded(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Foto Kejadian', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    // Kategori Dropdown
                    DropdownButtonFormField<String>(
                      value: _category,
                      decoration: InputDecoration(
                        labelText: 'Kategori Aduan',
                        filled: true,
                        fillColor: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.03),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.category_outlined),
                      ),
                      items: _categories.map((String category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _category = newValue;
                          });
                          // Jika sudah ada gambar, beri amaran atau analisis semula
                          if (_images.isNotEmpty && newValue != 'Lain-lain') {
                            _processImage(_images.last, isRetry: true);
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _images.length + 1,
                        itemBuilder: (context, index) {
                          if (index == _images.length) {
                            return GestureDetector(
                              onTap: _showImagePicker,
                              child: Container(
                                width: 120,
                                decoration: BoxDecoration(
                                  color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1)),
                                ),
                                child: const Icon(Icons.add_a_photo_outlined, color: AppTheme.primaryRed),
                              ),
                            );
                          }
                          return Container(
                            width: 120,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              image: DecorationImage(image: FileImage(_images[index]), fit: BoxFit.cover),
                              border: Border.all(color: AppTheme.primaryRed.withOpacity(0.3)),
                            ),
                          );
                        },
                      ),
                    ),
                    if (_isAnalyzingImage || _aiMessage != null) ...[
                      const SizedBox(height: 16),
                      _buildAIFeedbackOverlay(isDarkMode),
                    ],
                    const SizedBox(height: 24),
                    const Text('Lokasi Kejadian', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                      ),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _location ?? const LatLng(5.0884, 118.3251),
                                initialZoom: 15,
                                onTap: (tapPosition, point) {
                                  setState(() {
                                    _location = point;
                                  });
                                  _updateAddress(point.latitude, point.longitude);
                                },
                              ),
                              children: [
                                TileLayer(
                                  key: ValueKey(isDarkMode ? 'dark' : 'light'),
                                  urlTemplate: isDarkMode 
                                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                                    : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  subdomains: const ['a', 'b', 'c'],
                                  tileBuilder: (context, tileWidget, tile) {
                                    return AnimatedOpacity(
                                      duration: const Duration(milliseconds: 500),
                                      opacity: 1.0,
                                      child: tileWidget,
                                    );
                                  },
                                ),
                                if (_location != null)
                                  MarkerLayer(markers: [
                                    Marker(
                                      point: _location!, 
                                      width: 40,
                                      height: 40,
                                      child: const Icon(Icons.location_on, color: AppTheme.primaryRed, size: 40)
                                    ),
                                  ]),
                              ],
                            ),
                          ),
                          Positioned(
                            bottom: 10,
                            right: 10,
                            child: FloatingActionButton.small(
                              onPressed: _getCurrentLocation,
                              backgroundColor: Colors.white,
                              child: const Icon(Icons.my_location, color: AppTheme.primaryRed),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Sentuh peta untuk ubah lokasi',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _areaNameController,
                      decoration: InputDecoration(
                        labelText: 'Nama Jalan / Kawasan',
                        hintText: 'Cth: Jalan Utama Semarak',
                        prefixIcon: const Icon(Icons.map_outlined),
                        filled: true,
                        fillColor: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.03),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Keterangan Tambahan',
                        hintText: 'Sila jelaskan keadaan masalah...',
                        filled: true,
                        fillColor: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.03),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryRed.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: (_isLoading || _images.isEmpty) ? null : _submitReport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryRed,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 55),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          elevation: 0,
                        ),
                        child: _isLoading 
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('HANTAR ADUAN SEKARANG', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildAIFeedbackOverlay(bool isDarkMode) {
    if (_aiMessage == null && !_isAnalyzingImage) return const SizedBox.shrink();

    final Color statusColor = _isAiValid == true 
        ? Colors.green 
        : (_isAiValid == false ? AppTheme.primaryRed : AppTheme.primaryBlue);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(top: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withOpacity(0.3), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_isAnalyzingImage)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primaryBlue),
                      )
                    else
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 500),
                        builder: (context, value, child) {
                          return Transform.scale(
                            scale: value,
                            child: Icon(
                              _isAiValid == true ? Icons.verified_rounded : Icons.report_problem_rounded,
                              color: statusColor,
                              size: 24,
                            ),
                          );
                        },
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isAnalyzingImage ? 'Analisis Pintar AI...' : (_isAiValid == true ? 'Imej Disahkan' : 'Imej Ditolak'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: statusColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    if (!_isAnalyzingImage)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _getSeverityEmoji(_detectedSeverity),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _aiMessage ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                if (_aiDetails != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _aiDetails!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.6),
                    ),
                  ),
                ],
                if (_isAnalyzingImage) ...[
                  const SizedBox(height: 16),
                  Stack(
                    children: [
                      Container(
                        height: 6,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      AnimatedProgressIndicator(
                        value: _isAnalyzingImage ? 0.7 : 1.0, 
                        color: statusColor
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getSeverityEmoji(String severity) {
    switch (severity.toLowerCase()) {
      case 'low': return '🟢 Tahap Rendah';
      case 'medium': return '🟡 Tahap Sederhana';
      case 'high': return '🟠 Tahap Tinggi';
      case 'critical': return '🔴 Kritikal';
      default: return '🟡';
    }
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
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hantar Laporan',
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitReport() async {
    if (_location == null) {
      _showSnackBar('Sila tunggu sehingga lokasi dikesan atau pilih lokasi pada peta.', isError: true);
      return;
    }

    if (!_isInAllowedArea(_location)) {
      _showSnackBar('Maaf, aduan hanya dibenarkan di kawasan Tungku dan sekitarnya sahaja buat masa ini.', isError: true);
      return;
    }

    if (_areaNameController.text.isEmpty) {
      _showSnackBar('Sila masukkan nama kawasan.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _authService.currentUser;
      final String nickname = _reporterNameController.text.trim();

      final reportData = {
        'user_id': user?.id,
        'description': _descriptionController.text,
        'location_lat': _location?.latitude,
        'location_lng': _location?.longitude,
        'address': _addressController.text,
        'area_name': _areaNameController.text,
        'severity': _detectedSeverity,
        'category': _category,
        'status': 'pending',
        'reporter_name': nickname.isNotEmpty ? nickname : 'Anonim',
      };

      // final response = await _supabaseService.createReport(reportData, _images);
      
      // Menggunakan submitReport yang sedia ada
      // Perlu memuat naik imej dahulu jika perlu, tetapi submitReport memerlukan imageUrl tunggal.
      // Jika _images tidak kosong, muat naik imej pertama.
      String imageUrl = '';
      if (_images.isNotEmpty) {
        imageUrl = await _supabaseService.uploadImage(_images.first);
      }

      await _supabaseService.submitReport(
        imageUrl: imageUrl,
        latitude: _location?.latitude ?? 0.0,
        longitude: _location?.longitude ?? 0.0,
        address: _addressController.text,
        areaName: _areaNameController.text,
        duration: 'Baru',
        description: _descriptionController.text,
        category: _category,
        reporterName: nickname.isNotEmpty ? nickname : 'Anonim',
        deviceId: await _deviceService.getDeviceId(),
        userId: user?.id,
        severity: _detectedSeverity,
      );

      _showSnackBar('Laporan berjaya dihantar! Terima kasih atas keprihatinan anda.');
      Navigator.pop(context);
    } catch (e) {
      _showSnackBar('Gagal menghantar laporan: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
