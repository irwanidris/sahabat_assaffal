import 'dart:async';
import 'dart:ui';
import 'dart:io'; // Tambah Import[cite: 1]
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../theme/app_theme.dart';
import 'ic_capture_screen.dart'; // Import skrin AI[cite: 1]

class VerificationApplicationScreen extends StatefulWidget {
  const VerificationApplicationScreen({super.key});

  @override
  State<VerificationApplicationScreen> createState() => _VerificationApplicationScreenState();
}

class _VerificationApplicationScreenState extends State<VerificationApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _icController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController(text: '+60');
  final _otpController = TextEditingController();

  bool _isLoading = true;
  bool _otpSent = false;
  bool _phoneVerified = false;

  // Data Kelayakan
  int _totalReports = 0;
  int _totalVerifications = 0;
  int _totalExistsVerifications = 0;
  bool _isEligible = false;

  // Variable dokumen IC
  File? _icFront; // Tambah Variable[cite: 1]
  File? _icBack;  // Tambah Variable[cite: 1]

  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();
  final DeviceService _deviceService = DeviceService();

  @override
  void initState() {
    super.initState();
    _loadUserStats();
  }

  Future<void> _loadUserStats() async {
    setState(() => _isLoading = true);
    try {
      final profile = await _deviceService.getOrCreateProfile();
      setState(() {
        _totalReports = profile['total_reports'] ?? 0;
        _totalVerifications = profile['total_verifications'] ?? 0;
        _totalExistsVerifications = profile['total_exists_verifications'] ?? 0;

        _isEligible = _totalReports >= 3 ||
            _totalVerifications >= 6 ||
            _totalExistsVerifications >= 10;

        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading stats: $e');
      setState(() => _isLoading = false);
    }
  }

  // 2. Logik Pengambilan Gambar IC[cite: 1]
  Future<void> _captureIC(String side) async {
    final File? result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ICCaptureScreen(side: side)),
    );

    if (result != null) {
      setState(() {
        if (side == 'DEPAN') _icFront = result;
        else _icBack = result;
      });
    }
  }

  Future<void> _sendOTP() async {
    if (_phoneController.text.length < 10) return;
    setState(() => _isLoading = true);
    try {
      await _authService.sendOTP(_phoneController.text.trim());
      setState(() { _otpSent = true; _isLoading = false; });
    } catch (e) { setState(() => _isLoading = false); }
  }

  Future<void> _verifyOTP() async {
    setState(() => _isLoading = true);
    try {
      await _authService.verifyOTP(_phoneController.text.trim(), _otpController.text.trim());
      setState(() { _phoneVerified = true; _isLoading = false; });
    } catch (e) { setState(() => _isLoading = false); }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_user_rounded, color: Colors.green, size: 70),
            const SizedBox(height: 20),
            const Text(
                'Permohonan STATUS VERIFIED Dihantar',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)
            ),
            const SizedBox(height: 10),
            const Text(
              'Permohonan anda akan disemak oleh pihak pentadbir.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context, true);
                },
                child: const Text('TERIMA KASIH', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitRequest() async {
    // Pastikan form sah, telefon sah, dan kedua-dua gambar IC ada
    if (!_formKey.currentState!.validate() || !_phoneVerified || _icFront == null || _icBack == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sila lengkapkan semua maklumat dan dokumen IC.')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _supabaseService.submitVerificationRequest(
        fullName: _fullNameController.text.trim(),
        icNumber: _icController.text.trim(),
        address: _addressController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        icFront: _icFront!, // Hantar fail depan
        icBack: _icBack!,   // Hantar fail belakang
      );

      setState(() => _isLoading = false);
      if (mounted) _showSuccessDialog();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ralat: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Borang STATUS VERIFIED'),
        backgroundColor: AppTheme.primaryRed,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Column(
          children: [
            _buildProgressHeader(),
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Permohonan STATUS VERIFIED (Rasmi)',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      _buildMainForm(),
                    ],
                  ),
                ),

                if (!_isEligible)
                  Positioned.fill(
                    child: AbsorbPointer(
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                          child: Container(
                            color: Colors.white.withOpacity(0.4),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                margin: const EdgeInsets.symmetric(horizontal: 40),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(15),
                                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                                ),
                                child: const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.lock_outline, color: Colors.orange, size: 40),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Borang Dikunci',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Sila penuhi salah satu kriteria di atas untuk mengaktifkan borang ini.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Kriteria Kelayakan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 15),
          _buildMiniBar('Laporan (Min 3)', _totalReports, 3, Colors.red),
          _buildMiniBar('Undian Sahkan (Min 6)', _totalVerifications, 6, Colors.blue),
          _buildMiniBar('Pantauan Aktif (Min 10)', _totalExistsVerifications, 10, AppTheme.primaryRed),
        ],
      ),
    );
  }

  Widget _buildMiniBar(String label, int current, int target, Color color) {
    double progress = (current / target).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 11)),
              Text('$current/$target', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ],
      ),
    );
  }

  Widget _buildMainForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Maklumat Peribadi IC', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          TextFormField(
            controller: _fullNameController,
            decoration: const InputDecoration(labelText: 'Nama Penuh (Seperti Dalam IC)', border: OutlineInputBorder()),
            validator: (v) => v!.isEmpty ? 'Wajib diisi' : null,
          ),
          const SizedBox(height: 15),
          TextFormField(
            controller: _icController,
            decoration: const InputDecoration(labelText: 'No. Kad Pengenalan', border: OutlineInputBorder()),
            validator: (v) => v!.length < 12 ? 'Format salah' : null,
          ),
          const SizedBox(height: 15),
          TextFormField(
            controller: _addressController,
            decoration: const InputDecoration(labelText: 'Alamat Tetap', border: OutlineInputBorder()),
            maxLines: 2,
          ),

          // 3. UI Butang & Preview IC[cite: 1]
          const SizedBox(height: 30),
          const Text('Dokumen Sokongan (IC)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Row(
            children: [
              // Bahagian DEPAN
              Expanded(
                child: _buildICButton(
                  label: 'BAHAGIAN DEPAN',
                  file: _icFront,
                  onTap: () => _captureIC('DEPAN'),
                ),
              ),
              const SizedBox(width: 15),
              // Bahagian BELAKANG
              Expanded(
                child: _buildICButton(
                  label: 'BAHAGIAN BELAKANG',
                  file: _icBack,
                  onTap: () => _captureIC('BELAKANG'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),
          const Text('Pengesahan Telefon', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _phoneController,
                  enabled: !_phoneVerified,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(onPressed: _phoneVerified ? null : _sendOTP, child: const Text('OTP')),
            ],
          ),
          if (_otpSent && !_phoneVerified) ...[
            const SizedBox(height: 10),
            TextField(controller: _otpController, decoration: const InputDecoration(hintText: 'Masukkan 6 Digit OTP')),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _verifyOTP, child: const Text('Verify')),
          ],
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              // 5. Butang SUBMIT hanya aktif jika IC ada[cite: 1]
              onPressed: (_phoneVerified && _icFront != null && _icBack != null) ? _submitRequest : null,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
              child: const Text('HANTAR PERMOHONAN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // 4. Helper Widget _buildICButton[cite: 1]
  Widget _buildICButton({required String label, File? file, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: file != null ? Colors.green : Colors.grey.shade300),
        ),
        child: file != null
            ? ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(file, fit: BoxFit.cover),
              const Positioned(
                top: 5,
                right: 5,
                child: Icon(Icons.check_circle, color: Colors.green, size: 24),
              ),
            ],
          ),
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined, color: Colors.grey, size: 30),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}