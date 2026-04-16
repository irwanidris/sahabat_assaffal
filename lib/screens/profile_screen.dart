import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../services/analytics_service.dart';
import '../services/device_service.dart';
import '../models/assaffal_report.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../cubit/theme_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'edit_report_screen.dart';
import 'resolved_reports_screen.dart';
import 'admin_chat_screen.dart';
import 'add_news_screen.dart';
import 'manage_news_screen.dart';
import 'notifications_list_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final SupabaseService _supabaseService = SupabaseService();
  final AnalyticsService _analyticsService = AnalyticsService();
  final DeviceService _deviceService = DeviceService();

  bool _isLoading = true;
  Map<String, dynamic>? _profileData;
  Map<String, dynamic> _personalStats = {};
  List<AssaffalReport> _userReports = [];
  List<AssaffalReport> _resolvedReports = [];
  List<Map<String, dynamic>> _myNews = [];
  List<Map<String, dynamic>> _pendingApprovals = [];
  bool _isAdmin = false;
  bool _isAdminNews = false;
  bool _isModerator = false;
  bool _isYB = false;
  bool _isVerified = false;
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = _authService.currentUser;
      _deviceId = await _deviceService.getDeviceId();
      
      // Ambil profile device_users tanpa mengira user log masuk atau tidak
      final profile = await _deviceService.getOrCreateProfile();
      
      final List<Future> futures = [
        _analyticsService.getPersonalStats(_deviceId!),
        _supabaseService.fetchReports(),
      ];

      if (user != null) {
        if (user.userMetadata?['is_admin'] == true) {
          // Super Admin ambil semua berita untuk kelulusan
          futures.add(_supabaseService.fetchNews(approvedOnly: false));
        } else if (user.userMetadata?['is_admin_news'] == true) {
          // Admin News ambil berita sendiri sahaja
          futures.add(_supabaseService.fetchNews(approvedOnly: false, author: user.userMetadata?['full_name']));
        }
      }

      final results = await Future.wait(futures);

      _personalStats = results[0] as Map<String, dynamic>;
      _personalStats['points'] = profile['points'] ?? 0;

      final allReports = results[1] as List<AssaffalReport>;
      
      if (user != null) {
        _isAdmin = user.userMetadata?['is_admin'] == true;
        _isAdminNews = user.userMetadata?['is_admin_news'] == true;
        _isModerator = user.userMetadata?['is_moderator'] == true;
        _isYB = user.userMetadata?['is_yb'] == true;
        _isVerified = user.userMetadata?['phone_verified'] == true;

        if (_isAdmin) {
          final allNews = results.length > 2 ? List<Map<String, dynamic>>.from(results[2]) : <Map<String, dynamic>>[];
          _pendingApprovals = allNews.where((n) => n['status'] == 'pending').toList();
        } else if (_isAdminNews) {
          _myNews = results.length > 2 ? List<Map<String, dynamic>>.from(results[2]) : <Map<String, dynamic>>[];
        }

        _profileData = {
          'full_name': _isYB ? 'Assaffal Hj Panglima Alian' : (user.userMetadata?['full_name'] ?? 'Pengguna'),
          'nickname': profile['nickname'] ?? (user.userMetadata?['nickname'] ?? 'Sahabat'),
          'avatar_url': user.userMetadata?['avatar_url'] ?? '',
          'phone': user.userMetadata?['phone'] ?? '-',
          'dob': user.userMetadata?['dob'] ?? '-',
          'area': user.userMetadata?['area'] ?? '-',
          'fb': user.userMetadata?['fb'] ?? '-',
          'tiktok': user.userMetadata?['tiktok'] ?? '-',
          'ig': user.userMetadata?['ig'] ?? '-',
          'yt': user.userMetadata?['yt'] ?? '-',
        };

        if (_isAdmin || _isModerator || _isYB) {
          // Admin, Moderator, dan YB nampak SEMUA laporan
          final allSorted = allReports..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _userReports = allSorted.where((r) => r.status != 'resolved').toList();
          _resolvedReports = allSorted.where((r) => r.status == 'resolved').toList();
        } else {
          // Matching by reporterName OR deviceId as fallback if metadata is lost
          final myReports = allReports.where((r) => r.reporterName == _profileData!['full_name']).toList();
          myReports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _userReports = myReports;
          _resolvedReports = [];
        }
      } else {
        // Jika tidak log masuk, kita masih boleh tunjuk statistik berdasarkan deviceId
        _profileData = {
          'full_name': profile['nickname'] ?? 'Sahabat Baru',
          'avatar_url': '',
        };
        _userReports = allReports.where((r) => r.deviceId == _deviceId).toList();
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _handleDelete(AssaffalReport report) async {
    // YB tidak menguruskan pemadaman secara teknikal
    if (_isYB) return;

    if (!_isAdmin && !report.canDelete()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Laporan tidak boleh dipadam pada masa ini.'))
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Padam Laporan?'),
        content: const Text('Adakah anda pasti mahu memadam laporan ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Padam', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabaseService.deleteReport(report.id);
        _loadData();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Laporan telah dipadam.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memadam: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _navigateToEdit(AssaffalReport report) async {
    // YB boleh melihat perincian tanpa had, tetapi tidak perlu label "Edit"
    if (_isYB) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => EditReportScreen(report: report)),
      );
      return;
    }

    if (!_isAdmin && !report.canEdit()) {
      String message = 'Laporan tidak boleh dikemaskini lagi.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => EditReportScreen(report: report)),
    );

    if (result == true) {
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final user = _authService.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: isDarkMode ? AppTheme.darkBackground : AppTheme.lightBackground,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_circle_outlined, size: 80, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Sila log masuk untuk melihat profil.'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _handleGoogleLogin(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text('Log Masuk Sekarang'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDarkMode ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildGlassHeader(isDarkMode),
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildProfileHeader(isDarkMode),
                          if (_isAdmin && _pendingApprovals.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _buildSuperAdminApprovalSection(isDarkMode),
                          ],
                          if (_isAdminNews) ...[
                            const SizedBox(height: 24),
                            _buildAdminNewsActions(isDarkMode),
                            const SizedBox(height: 24),
                            _buildMyNewsSection(isDarkMode),
                          ],
                          const SizedBox(height: 24),
                          _buildImpactSection(isDarkMode),
                          const SizedBox(height: 24),
                          _buildSocialSection(isDarkMode),
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                (_isAdmin || _isModerator || _isYB) ? 'Laporan Umum' : 'Laporan Saya',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              if ((_isAdmin || _isModerator || _isYB) && _resolvedReports.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ResolvedReportsScreen(
                                          reports: _resolvedReports,
                                          isAdmin: _isAdmin,
                                          isYB: _isYB,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.check_circle_outline, size: 18, color: AppTheme.primaryBlue),
                                  label: const Text(
                                    'Laporan Selesai', 
                                    style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildReportsList(isDarkMode),
                        ],
                      ),
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassHeader(bool isDarkMode) {
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
                GestureDetector(
                  onLongPress: _handleLogout,
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
                      'Profil Saya',
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
                IconButton(
                  icon: Icon(Icons.edit_note_rounded, size: 24, color: isDarkMode ? Colors.white70 : Colors.black87),
                  onPressed: () => _showEditProfileDialog(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(bool isDarkMode) {
    final String avatarUrl = _profileData?['avatar_url'] ?? '';
    final String fullName = _profileData?['full_name'] ?? 'Pengguna';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isAdminNews 
            ? const Color(0xFFFFE4E1) 
            : (isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Hi Nickname di sebelah kiri atas
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Hi, ${_profileData?['nickname'] ?? 'Sahabat'}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryRed.withOpacity(0.8),
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Avatar di Center
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primaryRed, width: 2),
                ),
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _showAvatarEditOptions,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryRed,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Nama Penuh (Center)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  fullName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              if (_isVerified) ...[
                const SizedBox(width: 4),
                const Icon(Icons.verified, color: Colors.blue, size: 20),
              ],
            ],
          ),
          
          // Title/Role Label (Center)
          _buildRoleLabel(),
          const SizedBox(height: 16),

          // Butang Icon-Only (Center)
          if (_isAdmin || _isModerator || _isYB)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isAdmin)
                  _buildHeaderIconButton(
                    icon: Icons.approval_rounded,
                    color: Colors.orange,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ManageNewsScreen()),
                      );
                    },
                  ),
                if (_isAdmin) const SizedBox(width: 12),
                _buildHeaderIconButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  color: AppTheme.primaryRed,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AdminChatScreen()),
                    );
                  },
                ),
              ],
            ),
          
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.phone, 'No. Telefon', _profileData?['phone'], isPhone: true),
          _buildInfoRow(Icons.cake, 'Tarikh Lahir', _profileData?['dob']),
          _buildInfoRow(Icons.location_on, 'Kampung/Kawasan', _profileData?['area']),
        ],
      ),
    );
  }

  // Helper untuk bina butang ikon yang kemas
  Widget _buildHeaderIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: color, size: 20),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout Sekarang?'),
        content: const Text('Adakah anda pasti mahu keluar dari akaun ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Tidak'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ya', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.signOut();
      if (mounted) {
        // Halaman akan auto refresh melalui listener di main.dart atau refresh manual di sini
        _loadData(); 
      }
    }
  }

  Future<void> _handleGoogleLogin() async {
    try {
      await _authService.signInWithGoogle();
      final profile = await _deviceService.getOrCreateProfile();
      
      // Jika nickname masih Sahabat #xxxx, minta pengguna masukkan nickname baru
      if (profile['nickname'] != null && profile['nickname'].startsWith('Sahabat #')) {
        _showNicknameDialog();
      } else {
        _loadData(); // Refresh jika sudah ada nickname
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal Log Masuk: $e')));
      }
    }
  }

  Widget _buildRoleLabel() {
    String label = "Ahli Sahabat Assaffal";
    Color color = AppTheme.primaryRed;

    if (_isYB) {
      label = "Penaung";
      color = const Color(0xFFD4AF37); // Gold Color
    } else if (_isAdmin) {
      label = "Super Admin";
      color = Colors.blue.shade800;
    } else if (_isAdminNews) {
      label = "News & Blog";
      color = Colors.teal;
    } else if (_isModerator) {
      label = "Sukarelawan Sahabat Assaffal";
      color = Colors.blue.shade500;
    }

    return Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
        shadows: _isYB ? [const Shadow(color: Colors.black12, blurRadius: 2, offset: Offset(1, 1))] : null,
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String? value, {bool isPhone = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Colors.grey)),
          Expanded(child: Text(value ?? '-', style: const TextStyle(fontWeight: FontWeight.w500))),
          if (isPhone && !_isVerified && value != null && value != '-' && value.isNotEmpty)
            TextButton(
              onPressed: () => _showVerifyOTPDialog(value),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 30)),
              child: const Text('Verify OTP', style: TextStyle(fontSize: 12, color: Colors.red)),
            ),
        ],
      ),
    );
  }

  void _showVerifyOTPDialog(String phone) async {
    final otpCtrl = TextEditingController();
    bool codeSent = false;
    bool dialogLoading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(codeSent ? 'Masukkan OTP' : 'Sahkan No. Telefon'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!codeSent)
                  Text('Kod OTP akan dihantar ke $phone. Sila pastikan format antarabangsa (cth: +60123456789).')
                else
                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Kod OTP 6-Digit',
                      hintText: '123456',
                    ),
                  ),
                if (dialogLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 16.0),
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: dialogLoading ? null : () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: dialogLoading ? null : () async {
                  setDialogState(() => dialogLoading = true);
                  try {
                    if (!codeSent) {
                      await _authService.sendOTP(phone);
                      setDialogState(() {
                        codeSent = true;
                        dialogLoading = false;
                      });
                    } else {
                      await _authService.verifyOTP(phone, otpCtrl.text);
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Tahniah! Akaun anda kini Disahkan (Verified).'), backgroundColor: AppTheme.primaryBlue),
                        );
                        _loadData();
                      }
                    }
                  } catch (e) {
                    setDialogState(() => dialogLoading = false);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ralat: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                child: Text(codeSent ? 'Sahkan' : 'Hantar OTP'),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildSuperAdminApprovalSection(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Menunggu Kelulusan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_pendingApprovals.length}',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.red.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.pending_actions_rounded, color: Colors.red),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Terdapat berita baru yang memerlukan tindakan anda.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ManageNewsScreen()),
                    );
                    if (result == true) {
                      _loadData();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.approval_rounded),
                  label: const Text('Urus Kelulusan Sekarang'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdminNewsActions(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pengurusan Berita & Blog',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.teal.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.teal.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.newspaper_rounded, color: Colors.teal),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Kemas kini kandungan Dashboard Berita Sahabat Assaffal.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddNewsScreen(
                              authorName: _profileData?['full_name'] ?? 'Admin News',
                            ),
                          ),
                        );
                        if (result == true) {
                          _loadData();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.edit_document),
                      label: const Text('Tulis Berita Baru'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '* Berita yang dihantar atau diedit akan memerlukan kelulusan Super Admin sebelum dipaparkan.',
                style: TextStyle(fontSize: 10, color: Colors.teal, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMyNewsSection(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Berita Saya',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (_myNews.isEmpty)
          const Center(child: Text('Tiada berita yang telah dihantar.'))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _myNews.length,
            itemBuilder: (context, index) {
              final news = _myNews[index];
              final bool isApproved = news['status'] == 'approved';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: news['image_url'] != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(news['image_url'], width: 50, height: 50, fit: BoxFit.cover),
                        )
                      : const Icon(Icons.newspaper),
                  title: Text(news['title'] ?? 'Tiada Tajuk', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isApproved 
                              ? Colors.blue.withOpacity(0.1) 
                              : (news['status'] == 'rejected' ? Colors.orange.withOpacity(0.1) : Colors.red.withOpacity(0.1)),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isApproved 
                                ? Colors.blue.withOpacity(0.5) 
                                : (news['status'] == 'rejected' ? Colors.orange.withOpacity(0.5) : Colors.red.withOpacity(0.5)),
                          ),
                        ),
                        child: Text(
                          isApproved 
                              ? 'Approved' 
                              : (news['status'] == 'rejected' ? 'Rejected / Need Edit' : 'Pending Approval'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isApproved 
                                ? Colors.blue 
                                : (news['status'] == 'rejected' ? Colors.orange : Colors.red),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(news['category'] ?? 'Berita', style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_note_rounded, color: Colors.blue),
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AddNewsScreen(
                            authorName: _profileData?['full_name'] ?? 'Admin News',
                            newsToEdit: news,
                          ),
                        ),
                      );
                      if (result == true) {
                        _loadData();
                      }
                    },
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  void _launchFacebookAdmin() async {
    final Uri url = Uri.parse('https://www.facebook.com/assaffal.lahaddatu');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuka Facebook: $e'))
        );
      }
    }
  }

  Widget _buildImpactSection(bool isDarkMode) {
    if (_personalStats.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Impak Saya',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryRed, AppTheme.primaryBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryRed.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildImpactStatItem(
                    'Laporan',
                    '${_personalStats['totalReports'] ?? 0}',
                    Icons.flag_rounded,
                  ),
                  _buildImpactStatItem(
                    'Selesai',
                    '${_personalStats['resolvedReports'] ?? 0}',
                    Icons.check_circle_rounded,
                  ),
                  _buildImpactStatItem(
                    'Mata',
                    '${_personalStats['points'] ?? 0}',
                    Icons.star_rounded,
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 32),
              Row(
                children: [
                  const Icon(Icons.trending_up_rounded, color: Colors.white70, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Anda telah membantu membaiki anggaran ${(_personalStats['roadsImprovedMeters'] ?? 0).toStringAsFixed(0)}m jalan raya!',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImpactStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildSocialSection(bool isDarkMode) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _socialBadge('Facebook', _profileData?['fb'], Colors.blue),
        _socialBadge('TikTok', _profileData?['tiktok'], Colors.black),
        _socialBadge('Instagram', _profileData?['ig'], Colors.pink),
        _socialBadge('YouTube', _profileData?['yt'], Colors.red),
      ],
    );
  }

  Widget _socialBadge(String platform, String? username, Color color) {
    if (username == null || username == '-') return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(platform, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 4),
          Text(username, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildReportsList(bool isDarkMode) {
    if (_userReports.isEmpty) {
      return const Center(child: Text('Tiada laporan dihantar lagi.'));
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _userReports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final report = _userReports[index];
        final bool canEdit = _isAdmin || report.canEdit();
        final bool canDelete = _isAdmin || report.canDelete();

        Color? cardColor;
        Color textColor = isDarkMode ? Colors.white : Colors.black87;
        Color subTextColor = isDarkMode ? Colors.white70 : Colors.black54;
        Color iconColor = AppTheme.primaryRed;

        if (_isAdmin || _isModerator) {
          if (report.status == 'pending') {
            cardColor = Colors.blue.shade900;
            textColor = Colors.white;
            subTextColor = Colors.white70;
            iconColor = Colors.white70;
          } else if (report.status == 'processing') {
            cardColor = Colors.orange.shade800;
            textColor = Colors.white;
            subTextColor = Colors.white70;
            iconColor = Colors.white70;
          }
        }

        // Ambil gambar pertama jika terdapat berbilang gambar (dipisahkan oleh koma)
        final List<String> imageUrls = report.imageUrl.split(',');
        final String firstImageUrl = imageUrls.isNotEmpty ? imageUrls[0] : '';

        return Card(
          color: cardColor,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _navigateToEdit(report),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                leading: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cardColor != null ? Colors.white24 : Colors.grey.shade300),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: firstImageUrl.isNotEmpty 
                      ? Image.network(
                          firstImageUrl, 
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(Icons.broken_image, color: cardColor != null ? Colors.white70 : Colors.grey),
                        )
                      : Icon(Icons.image, color: cardColor != null ? Colors.white70 : Colors.grey),
                  ),
                ),
                title: Text(
                  report.category, 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 14, color: iconColor),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            report.areaName ?? '-',
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: subTextColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 14, color: subTextColor),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(report.createdAtMYT),
                          style: TextStyle(fontSize: 12, color: subTextColor),
                        ),
                      ],
                    ),
                  ],
                ),
                trailing: Theme(
                  data: Theme.of(context).copyWith(
                    iconTheme: IconThemeData(color: textColor),
                  ),
                  child: PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: cardColor != null ? Colors.white : null),
                    onSelected: (val) {
                      if (val == 'edit') {
                        _navigateToEdit(report);
                      } else if (val == 'delete') {
                        _handleDelete(report);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_note_rounded, size: 20, color: (canEdit || _isYB) ? Colors.blue : Colors.grey),
                              const SizedBox(width: 10),
                              Text((_isYB) ? 'Lihat Perincian' : (canEdit ? 'Lihat & Edit' : 'Lihat Perincian')),
                            ],
                          )),
                      if (!_isYB)
                        PopupMenuItem(
                            value: 'delete',
                            enabled: canDelete,
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded, size: 20, color: canDelete ? Colors.red : Colors.grey),
                                const SizedBox(width: 10),
                                Text('Padam ${canDelete ? '' : '(Tamat)'}'),
                              ],
                            )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showEditProfileDialog() {
    final nameCtrl = TextEditingController(text: _profileData?['full_name']);
    final nickCtrl = TextEditingController(text: _profileData?['nickname']);
    final phoneCtrl = TextEditingController(text: _profileData?['phone']);
    final dobCtrl = TextEditingController(text: _profileData?['dob']);
    final areaCtrl = TextEditingController(text: _profileData?['area']);
    final fbCtrl = TextEditingController(text: _profileData?['fb']);
    final ttCtrl = TextEditingController(text: _profileData?['tiktok']);
    final igCtrl = TextEditingController(text: _profileData?['ig']);
    final ytCtrl = TextEditingController(text: _profileData?['yt']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profil'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Demi privasi & keselamatan, anda tidak digalakkan menggunakan nama atau gambar profil sebenar. Sila pilih Nickname unik.',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 10),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama Penuh')),
              TextField(controller: nickCtrl, decoration: const InputDecoration(labelText: 'Nickname')),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'No Telefon')),
              TextField(controller: dobCtrl, decoration: const InputDecoration(labelText: 'Tarikh Lahir (DD/MM/YYYY)')),
              TextField(controller: areaCtrl, decoration: const InputDecoration(labelText: 'Kampung/Kawasan')),
              TextField(controller: fbCtrl, decoration: const InputDecoration(labelText: 'Facebook')),
              TextField(controller: ttCtrl, decoration: const InputDecoration(labelText: 'TikTok')),
              TextField(controller: igCtrl, decoration: const InputDecoration(labelText: 'Instagram')),
              TextField(controller: ytCtrl, decoration: const InputDecoration(labelText: 'YouTube')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              setState(() => _isLoading = true);
              // Simpan ke device_users (dengan sekatan berperingkat: 48j, 30h, 60h)
              final error = await _deviceService.updateNickname(nickCtrl.text);

              if (error != null) {
                setState(() => _isLoading = false);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error), backgroundColor: Colors.red),
                  );
                }
                return;
              }

              // Jika nickname berjaya/tidak berubah, simpan data lain ke metadata Supabase User
              try {
                await Supabase.instance.client.auth.updateUser(
                  UserAttributes(
                    data: {
                      'full_name': nameCtrl.text,
                      'nickname': nickCtrl.text,
                      'phone': phoneCtrl.text,
                      'dob': dobCtrl.text,
                      'area': areaCtrl.text,
                      'fb': fbCtrl.text,
                      'tiktok': ttCtrl.text,
                      'ig': igCtrl.text,
                      'yt': ytCtrl.text,
                    },
                  ),
                );
                if (mounted) Navigator.pop(context);
                _loadData();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ralat profil: $e'), backgroundColor: Colors.red),
                  );
                }
              } finally {
                setState(() => _isLoading = false);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showAvatarEditOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pilih dari Galeri'),
              onTap: () {
                Navigator.pop(context);
                _updateAvatarFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_circle),
              title: const Text('Gunakan Gambar Akaun Google'),
              onTap: () {
                Navigator.pop(context);
                _restoreGoogleAvatar();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateAvatarFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (image != null) {
      setState(() => _isLoading = true);
      try {
        final String publicUrl = await _supabaseService.uploadImage(File(image.path), applyWatermark: false);
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(data: {'avatar_url': publicUrl}),
        );
        _loadData();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gambar profil berjaya ditukar!')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menukar gambar: $e')));
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _restoreGoogleAvatar() async {
    final user = _authService.currentUser;
    final googleAvatar = user?.userMetadata?['google_avatar_url'];

    if (googleAvatar != null && googleAvatar.toString().isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(data: {'avatar_url': googleAvatar}),
        );
        _loadData();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gambar profil Google dipulihkan!')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memulihkan gambar: $e')));
      } finally {
        setState(() => _isLoading = false);
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tiada data gambar Google ditemui.')));
    }
  }

  void _showNicknameDialog() {
    final nicknameCtrl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Tetapkan Nickname'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sila pilih nickname unik untuk dipaparkan di Papan Pendahulu.'),
            const SizedBox(height: 16),
            TextField(
              controller: nicknameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nickname',
                hintText: 'Cth: SahabatAssaffal',
              ),
              maxLength: 15,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              if (nicknameCtrl.text.trim().isNotEmpty) {
                final error = await _deviceService.updateNickname(nicknameCtrl.text.trim());
                if (error != null) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error), backgroundColor: Colors.red),
                    );
                  }
                  return;
                }
                if (mounted) {
                  Navigator.pop(context);
                  _loadData();
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
