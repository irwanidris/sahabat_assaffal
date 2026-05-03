import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../services/device_service.dart';
import '../main.dart';

class UsernameSetupScreen extends StatefulWidget {
  final bool isPreview;
  const UsernameSetupScreen({super.key, this.isPreview = false});

  @override
  State<UsernameSetupScreen> createState() => _UsernameSetupScreenState();
}

class _UsernameSetupScreenState extends State<UsernameSetupScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _referrerController = TextEditingController();

  late int _currentStep;
  bool _isLoading = false;
  String? _errorText;
  String _savedUsername = '';

  @override
  void initState() {
    super.initState();
    DeviceService().clearCache();
    _currentStep = widget.isPreview ? 2 : 0;
    if (widget.isPreview) {
      _savedUsername = 'Admin Preview';
    }
  }

  // LANGKAH 1: Simpan Username
  Future<void> _proceedToReferrer() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() => _errorText = 'Sila masukkan username');
      return;
    }

    if (username.length < 3) {
      setState(() => _errorText = 'Username terlalu pendek (min 3 aksara)');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      final deviceService = DeviceService();

      if (user != null) {
        final existing = await supabase
            .from('profiles')
            .select('id')
            .eq('username', username)
            .maybeSingle();

        if (existing != null) {
          setState(() {
            _errorText = 'Username ini sudah digunakan. Sila pilih yang lain.';
            _isLoading = false;
          });
          return;
        }

        await supabase.from('profiles').upsert({
          'id': user.id,
          'username': username,
          'updated_at': DateTime.now().toIso8601String(),
        });

        deviceService.clearCache();

        setState(() {
          _savedUsername = username;
          _currentStep = 1;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorText = 'Gagal menyimpan username: $e';
        _isLoading = false;
      });
    }
  }

  // LANGKAH 2: Proses Referrer
  Future<void> _submitReferrer({bool skip = false}) async {
    if (skip) {
      setState(() => _currentStep = 2);
      return;
    }

    final referrerUsername = _referrerController.text.trim();
    if (referrerUsername.isEmpty) {
      setState(() => _errorText = 'Sila masukkan username rakan atau Langkau');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final deviceService = DeviceService();
      final error = await deviceService.processReferral(referrerUsername);

      if (error == null) {
        setState(() {
          _currentStep = 2;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorText = error;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorText = 'Ralat sistem. Sila Langkau jika masalah berterusan.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sila lengkapkan profil anda untuk meneruskan.'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
        body: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDarkMode
                      ? [const Color(0xFF1a1a2e), const Color(0xFF16213e)]
                      : [Colors.white, Colors.blue.shade50],
                ),
              ),
            ),
            SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: _buildCurrentStep(isDarkMode),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStep(bool isDarkMode) {
    if (_currentStep == 0) return _buildUsernameStep(isDarkMode);
    if (_currentStep == 1) return _buildReferrerStep(isDarkMode);
    return _buildRewardView(isDarkMode);
  }

  Widget _buildUsernameStep(bool isDarkMode) {
    return Padding(
      key: const ValueKey('step0'),
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildIconHeader(Icons.face_retouching_natural_rounded),
          const SizedBox(height: 40),
          const Text('Satu Langkah Lagi!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('Hi! Boleh kami tahu username pilihan kamu?', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
          const SizedBox(height: 20),
          _buildTextField(_usernameController, 'Masukkan Username...', Icons.alternate_email_rounded, isDarkMode),
          const SizedBox(height: 12),
          const Text(
            'Nota: Sila pilih dengan bijak. Username ini adalah identiti utama anda.',
            style: TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold),
          ),
          if (_errorText != null) _buildErrorDisplay(),
          const SizedBox(height: 40),
          _buildActionButton('SETERUSNYA', _proceedToReferrer),
        ],
      ),
    );
  }

  Widget _buildReferrerStep(bool isDarkMode) {
    return Padding(
      key: const ValueKey('step1'),
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildIconHeader(Icons.group_add_rounded),
          const SizedBox(height: 40),
          const Text(
              'Satu lagi...',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryRed)
          ),
          const SizedBox(height: 10),
          const Text(
            'Siapa yang kenalkan kamu dengan Aplikasi ini? Kamu bakal terima +95 mata jika isi username dia dibawah.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 30),
          _buildTextField(_referrerController, 'Username Rakan...', Icons.person_search_rounded, isDarkMode),
          if (_errorText != null) _buildErrorDisplay(),
          const SizedBox(height: 40),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _isLoading ? null : () => _submitReferrer(skip: true),
                  child: Text('LANGKAU', style: TextStyle(color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.3))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionButton('HANTAR', _submitReferrer),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRewardView(bool isDarkMode) {
    return Padding(
      key: const ValueKey('step2'),
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildLargeMedal(),
          const SizedBox(height: 30),
          const Text('Tahniah!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          const Text(
            'Selamat Datang dan bersama kita majukan Tungku.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, height: 1.5, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 50),
          _buildActionButton('SELAMAT BERKONGSI', () async {
            setState(() => _isLoading = true);
            try {
              await Supabase.instance.client.auth.updateUser(
                UserAttributes(data: {'username': _savedUsername}),
              );
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const MainNavigation(initialIndex: 4)),
                      (route) => false,
                );
              }
            } catch (e) {
              setState(() => _isLoading = false);
            }
          }),
        ],
      ),
    );
  }

  // --- HELPER WIDGETS ---
  Widget _buildIconHeader(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.primaryBlue.withOpacity(0.1), shape: BoxShape.circle),
      child: Icon(icon, size: 80, color: AppTheme.primaryBlue),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, bool isDarkMode) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1)),
          ),
          child: TextField(
            controller: controller,
            maxLength: 15,
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              counterText: '',
              prefixIcon: Icon(icon, color: AppTheme.primaryBlue, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildErrorDisplay() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(_errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
    );
  }

  Widget _buildLargeMedal() {
    return Container(
      width: 150, height: 150,
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.2),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.3), blurRadius: 30)],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Text('🏅', style: TextStyle(fontSize: 80)),
          Positioned(
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
              ),
              child: const Text(
                '+95',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.orange),
              ),
            ),
          ),
        ],
      ),
    );
  }
}