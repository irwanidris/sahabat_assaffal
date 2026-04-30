import 'dart:async';
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
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/theme_cubit.dart';
import 'edit_report_screen.dart';
import 'admin_chat_screen.dart';
import 'verification_application_screen.dart';
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
  bool _isEditingMode = false;
  Map<String, dynamic>? _profileData;
  Map<String, dynamic> _personalStats = {};
  List<AssaffalReport> _userReports = [];

  final TextEditingController _nickCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();

  bool _isAdmin = false, _isModerator = false, _isYB = false, _isVerified = false;
  int _totalVerifications = 0, _totalReports = 0, _totalExistsVerifications = 0;
  String? _deviceId;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    _authSubscription = _authService.authStateChanges.listen((data) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _nickCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      _deviceService.clearCache();
      final user = _authService.currentUser;
      _deviceId = await _deviceService.getDeviceId();
      final profile = await _deviceService.getOrCreateProfile();

      if (user != null) {
        setState(() {
          _isAdmin = user.userMetadata?['is_admin'] == true;
          _isModerator = user.userMetadata?['is_moderator'] == true;
          _isYB = user.userMetadata?['is_yb'] == true;
          _isVerified = profile['is_verified'] == true;
          _totalVerifications = profile['total_verifications'] ?? 0;
          _totalReports = profile['total_reports'] ?? 0;
          _totalExistsVerifications = profile['total_exists_verifications'] ?? 0;

          _profileData = {
            'full_name': _isYB ? 'Assaffal Hj Panglima Alian' : (user.userMetadata?['full_name'] ?? 'Pengguna'),
            'nickname': profile['nickname'] ?? 'Sahabat',
            'avatar_url': user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'] ?? '',
            'phone': user.userMetadata?['phone'] ?? '-',
            'fb': user.userMetadata?['fb'] ?? '-',
            'tiktok': user.userMetadata?['tiktok'] ?? '-',
            'ig': user.userMetadata?['ig'] ?? '-',
            'yt': user.userMetadata?['yt'] ?? '-',
          };

          _nickCtrl.text = _profileData?['nickname'] ?? '';
          _phoneCtrl.text = _profileData?['phone'] ?? '';
        });
      }

      final results = await Future.wait([
        _analyticsService.getPersonalStats(_deviceId!).catchError((e) => <String, dynamic>{}),
        _supabaseService.fetchReports(isAdmin: _isAdmin || _isModerator || _isYB).catchError((e) => <AssaffalReport>[]),
      ]);

      if (mounted) {
        setState(() {
          _personalStats = results[0] as Map<String, dynamic>;
          _personalStats['points'] = profile['points'] ?? 0;
          final allReports = results[1] as List<AssaffalReport>;
          _userReports = allReports.where((r) => r.reporterName == _profileData?['full_name'] || r.deviceId == _deviceId).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final user = _authService.currentUser;

    return Scaffold(
      backgroundColor: isDarkMode ? AppTheme.darkBackground : const Color(0xFFF8F9FA),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildGlassHeader(isDarkMode),
                Expanded(
                  child: _isLoading && _profileData == null
                      ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryRed))
                      : RefreshIndicator(
                    onRefresh: _loadData,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildProfileHeader(isDarkMode),
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                const SizedBox(height: 24),
                                _buildSocialSection(isDarkMode),
                                // Bahagian impak, verifikasi, laporan, dan log keluar telah dipadamkan/disembunyikan untuk minimalis[cite: 5]
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (user == null) _buildNotLoggedInState(isDarkMode),
        ],
      ),
    );
  }

  Widget _buildGlassHeader(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(icon: Icon(Icons.arrow_back_ios_new, color: isDarkMode ? Colors.white : Colors.black, size: 20), onPressed: () => Navigator.pop(context)),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsListScreen())),
            icon: Icon(Icons.notifications_none_rounded, color: isDarkMode ? Colors.white70 : Colors.black87),
          ),
          IconButton(
            onPressed: () => context.read<ThemeCubit>().toggleTheme(),
            icon: Icon(isDarkMode ? Icons.wb_sunny_rounded : Icons.nightlight_round, color: isDarkMode ? Colors.amber : Colors.indigo, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(bool isDarkMode) {
    final String avatarUrl = _profileData?['avatar_url'] ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ), child: Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty ? const Icon(Icons.person, size: 50) : null,
            ),
            Positioned(
              top: -5, right: -10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                child: Text('${_personalStats['points'] ?? 0} 👑', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black)),
              ),
            ),
            Positioned(
              bottom: 0, right: 0,
              child: GestureDetector(
                onTap: _showAvatarEditOptions,
                child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: AppTheme.primaryRed, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, size: 14, color: Colors.white)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(_profileData?['full_name'] ?? 'Pengguna', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        _buildRoleLabel(),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => setState(() => _isEditingMode = !_isEditingMode),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                minimumSize: const Size(0, 32),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text(_isEditingMode ? 'Tutup Edit' : 'Edit Profile', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
            const SizedBox(width: 5),
            IconButton(
              onPressed: _showImpactBottomSheet,
              icon: const Icon(Icons.analytics_outlined, color: AppTheme.primaryBlue, size: 22),
              tooltip: 'Impak Saya',
            ),
            IconButton(
              onPressed: _showVerificationBottomSheet,
              icon: const Icon(Icons.verified_user_outlined, color: Colors.green, size: 22),
              tooltip: 'Status Verifikasi',
            ),
            IconButton(
              onPressed: _navigateToMyReports,
              icon: const Icon(Icons.assignment_outlined, color: Colors.orange, size: 22),
              tooltip: 'Laporan Saya',
            ),
          ],
        ),
        if (_isEditingMode) _buildInlineEditForm(isDarkMode),
      ],
    ),
    );
  }

  Widget _buildRoleLabel() {
    String label = "Ahli Sahabat Assaffal";
    Color color = AppTheme.primaryRed;
    if (_isYB) { label = "Penaung"; color = const Color(0xFFD4AF37); }
    else if (_isAdmin) { label = "Super Admin"; color = Colors.blue.shade800; }
    return Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold));
  }

  Widget _buildImpactSection(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [AppTheme.primaryRed, AppTheme.primaryBlue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildImpactStatItem('Laporan', '${_userReports.length}', Icons.flag_rounded),
              _buildImpactStatItem('Selesai', '${_personalStats['resolvedReports'] ?? 0}', Icons.check_circle_rounded),
              _buildImpactStatItem('Mata', '${_personalStats['points'] ?? 0}', Icons.star_rounded),
            ],
          ),
          const Divider(color: Colors.white24, height: 32),
          Text(
            'Anda telah membantu membaiki anggaran ${(_personalStats['roadsImprovedMeters'] ?? 0).toStringAsFixed(0)}m jalan raya!',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildImpactStatItem(String label, String value, IconData icon) {
    return Column(children: [Icon(icon, color: Colors.white70, size: 24), const SizedBox(height: 8), Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))]);
  }

  Widget _buildVerificationProgress(bool isDarkMode) {
    final bool isEligible = _totalReports >= 3 || _totalVerifications >= 6 || _totalExistsVerifications >= 10;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [const Icon(Icons.shield, color: Colors.green, size: 24), const SizedBox(width: 10), const Text('Kelayakan Verified User', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
          const SizedBox(height: 16),
          _buildProgressBar('Laporan Lubang', _totalReports, 3, Colors.red),
          _buildProgressBar('Undian Sahkan', _totalVerifications, 6, Colors.blue),
          _buildProgressBar('Pantauan Merah', _totalExistsVerifications, 10, AppTheme.primaryRed),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: isEligible ? () => _navigateToVerificationForm() : null, style: ElevatedButton.styleFrom(backgroundColor: isEligible ? Colors.blue : Colors.grey.shade300), child: Text(isEligible ? 'MOHON SEKARANG' : 'BELUM LAYAK', style: TextStyle(color: isEligible ? Colors.white : Colors.grey)))),
        ],
      ),
    );
  }

  Widget _buildProgressBar(String label, int current, int target, Color color) {
    double progress = (current / target).clamp(0.0, 1.0);
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 11)), Text('$current/$target', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color))]), const SizedBox(height: 4), LinearProgressIndicator(value: progress, backgroundColor: color.withOpacity(0.1), valueColor: AlwaysStoppedAnimation<Color>(color), minHeight: 6)]));
  }

  Widget _buildSocialSection(bool isDarkMode) {
    return Wrap(spacing: 12, runSpacing: 12, children: [
      _socialBadge('Facebook', _profileData?['fb'], Colors.blue),
      _socialBadge('TikTok', _profileData?['tiktok'], Colors.black),
      _socialBadge('Instagram', _profileData?['ig'], Colors.pink),
      _socialBadge('YouTube', _profileData?['yt'], Colors.red),
    ]);
  }

  Widget _socialBadge(String platform, String? username, Color color) {
    if (username == null || username == '-') return const SizedBox.shrink();
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.3))), child: Row(mainAxisSize: MainAxisSize.min, children: [Text(platform, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(width: 4), Text(username, style: const TextStyle(fontSize: 12))]));
  }

  Widget _buildReportsSection(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Laporan Saya', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), TextButton(onPressed: _navigateToMyReports, child: const Text('Lihat Semua'))]),
        const SizedBox(height: 12),
        _buildReportsList(isDarkMode),
      ],
    );
  }

  Widget _buildReportsList(bool isDarkMode) {
    if (_userReports.isEmpty) return const Center(child: Text('Tiada laporan lagi.'));
    return ListView.separated(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _userReports.length > 3 ? 3 : _userReports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final r = _userReports[index];
        return Card(
          elevation: 0, color: Colors.grey.withOpacity(0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ListTile(title: Text(r.category, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(r.areaName ?? '-'), onTap: () => _navigateToEdit(r)),
        );
      },
    );
  }

  void _showAvatarEditOptions() {
    showModalBottomSheet(context: context, builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galeri'), onTap: () { Navigator.pop(context); _updateAvatarFromGallery(); }),
      ListTile(leading: const Icon(Icons.account_circle), title: const Text('Gambar Google'), onTap: () { Navigator.pop(context); _restoreGoogleAvatar(); }),
    ]));
  }

  Future<void> _updateAvatarFromGallery() async {
    final picker = ImagePicker(); final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      setState(() => _isLoading = true);
      try {
        final url = await _supabaseService.uploadImage(File(image.path), applyWatermark: false);
        await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'avatar_url': url}));
        await _deviceService.updateAvatar(url); _loadData();
      } catch (e) { debugPrint('$e'); } finally { setState(() => _isLoading = false); }
    }
  }

  Future<void> _restoreGoogleAvatar() async {
    final user = _authService.currentUser; final googleAvatar = user?.userMetadata?['picture'] ?? user?.userMetadata?['google_avatar_url'];
    if (googleAvatar != null) {
      setState(() => _isLoading = true);
      try { await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'avatar_url': googleAvatar})); await _deviceService.updateAvatar(googleAvatar); _loadData(); }
      catch (e) { debugPrint('$e'); } finally { setState(() => _isLoading = false); }
    }
  }

  Widget _buildInlineEditForm(bool isDarkMode) {
    return Column(children: [
      const SizedBox(height: 20),
      _buildTextField(_nickCtrl, Icons.alternate_email, 'Nickname'),
      _buildTextField(_phoneCtrl, Icons.phone, 'No Telefon'),
      const SizedBox(height: 10),
      ElevatedButton(onPressed: _saveProfileInline, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed), child: const Text('Simpan', style: TextStyle(color: Colors.white))),
    ]);
  }

  Widget _buildTextField(TextEditingController ctrl, IconData icon, String label) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: ctrl, decoration: InputDecoration(prefixIcon: Icon(icon), labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)))));
  }

  Future<void> _saveProfileInline() async {
    setState(() => _isLoading = true);
    final error = await _deviceService.updateNickname(_nickCtrl.text);
    if (error != null) { setState(() => _isLoading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error))); return; }
    try { await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'nickname': _nickCtrl.text, 'phone': _phoneCtrl.text})); setState(() => _isEditingMode = false); _loadData(); }
    catch (e) { setState(() => _isLoading = false); }
  }

  void _navigateToMyReports() { Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(appBar: AppBar(title: const Text('Laporan Saya'), backgroundColor: AppTheme.primaryRed, foregroundColor: Colors.white), body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: _buildReportsList(Theme.of(context).brightness == Brightness.dark))))); }
  void _navigateToVerificationForm() { Navigator.push(context, MaterialPageRoute(builder: (context) => const VerificationApplicationScreen())).then((_) => _loadData()); }
  void _navigateToEdit(AssaffalReport r) { Navigator.push(context, MaterialPageRoute(builder: (context) => EditReportScreen(report: r))).then((_) => _loadData()); }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('Adakah anda pasti mahu keluar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ya', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _authService.signOut();
      _loadData();
    }
  }

  Widget _buildNotLoggedInState(bool isDarkMode) {
    return Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.black.withOpacity(0.5), child: Center(child: Card(margin: const EdgeInsets.all(32), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.account_circle, size: 80, color: AppTheme.primaryRed), const SizedBox(height: 20), const Text('Log Masuk Diperlukan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 30), ElevatedButton(onPressed: () => _authService.signInWithGoogle().then((_) => _loadData()), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Log Masuk Google', style: TextStyle(color: Colors.white)))])))))));
  }

  void _showImpactBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkBackground : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Text('Impak Komuniti Anda', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            _buildImpactSection(Theme.of(context).brightness == Brightness.dark),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showVerificationBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkBackground : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Text('Status & Kelayakan User', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            _buildVerificationProgress(Theme.of(context).brightness == Brightness.dark),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}