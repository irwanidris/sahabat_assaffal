import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class NicknameSetupScreen extends StatefulWidget {
  const NicknameSetupScreen({super.key});

  @override
  State<NicknameSetupScreen> createState() => _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends State<NicknameSetupScreen> {
  final TextEditingController _nicknameController = TextEditingController();
  bool _isLoading = false;
  String? _errorText;

  Future<void> _saveNickname() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      setState(() => _errorText = 'Sila masukkan nickname');
      return;
    }

    if (nickname.length < 3) {
      setState(() => _errorText = 'Nickname terlalu pendek (min 3 aksara)');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user != null) {
        // 1. Simpan nickname ke dalam jadual 'profiles' di Supabase
        await supabase
            .from('profiles')
            .upsert({
              'id': user.id,
              'nickname': nickname,
              'updated_at': DateTime.now().toIso8601String(),
            });

        // 2. Juga simpan ke metadata untuk akses pantas (Optional)
        await supabase.auth.updateUser(
          UserAttributes(
            data: {'nickname': nickname},
          ),
        );
        
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      }
    } catch (e) {
      setState(() => _errorText = 'Gagal menyimpan nickname. Cuba lagi.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.face_retouching_natural_rounded, size: 80, color: AppTheme.primaryBlue),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    'Satu Langkah Lagi!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sila tetapkan nickname anda untuk mula menggunakan Sahabat Assaffal.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 40),
                  
                  // Nickname Input
                  ClipRRect(
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
                          controller: _nicknameController,
                          maxLength: 15,
                          style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            hintText: 'Masukkan Nickname...',
                            hintStyle: TextStyle(color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.3)),
                            border: InputBorder.none,
                            counterText: '',
                            prefixIcon: Icon(Icons.alternate_email_rounded, color: AppTheme.primaryBlue, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  if (_errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(_errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                  
                  const SizedBox(height: 40),
                  
                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveNickname,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _isLoading 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Mula Sekarang', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  Text(
                    'Nama sebenar anda akan dirahsiakan untuk privasi.',
                    style: TextStyle(fontSize: 11, color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.4)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
