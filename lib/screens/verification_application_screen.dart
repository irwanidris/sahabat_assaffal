import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../theme/app_theme.dart';

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

        // Syarat: Salah satu dari 3 mesti dipenuhi
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

  // --- Fungsi Logik (OTP & Submit) ---
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

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate() || !_phoneVerified) return;
    setState(() => _isLoading = true);
    try {
      await _supabaseService.submitVerificationRequest(
        fullName: _fullNameController.text.trim(),
        icNumber: _icController.text.trim(),
        address: _addressController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) { setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permohonan Verified User'),
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Column(
          children: [
            // 1. Bahagian Progress (Sentiasa Boleh Dilihat)
            _buildProgressHeader(),

            // 2. Bahagian Borang (Berpantul Kaca jika tidak layak)
            Stack(
              children: [
                // Borang Asal
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: _buildMainForm(),
                ),

                // Efek Kaca (Overlay) jika TIDAK LAYAK
                if (!_isEligible)
                  Positioned.fill(
                    child: AbsorbPointer( // Menghalang sentuhan
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
                                    SizedBox(height: 12),
                                    Text(
                                      'Borang Dikunci',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
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
              onPressed: _phoneVerified ? _submitRequest : null,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
              child: const Text('HANTAR PERMOHONAN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}