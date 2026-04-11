import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/supabase_config.dart';
import 'theme/app_theme.dart';
import 'cubit/theme_cubit.dart';
import 'cubit/reports_cubit.dart';
import 'services/supabase_service.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/report_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/admin_login_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/city_dashboard_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/admin_chat_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Inisialisasi Supabase
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  // 2. Inisialisasi OneSignal dengan App ID anda
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  OneSignal.initialize("e9668216-1dc4-4567-8951-0eb406a75c46");
  
  // Minta kebenaran notifikasi
  OneSignal.Notifications.requestPermission(true);

  // Set tags berdasarkan metadata user jika sudah login
  final user = Supabase.instance.client.auth.currentUser;
  if (user != null) {
    final bool isAdmin = user.userMetadata?['is_admin'] == true;
    final bool isModerator = user.userMetadata?['is_moderator'] == true;
    final bool isYB = user.userMetadata?['is_yb'] == true;
    
    if (isAdmin || isModerator || isYB) {
      OneSignal.User.addTagWithKey("role", "admin_staff");
    } else {
      OneSignal.User.removeTag("role");
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ThemeCubit()),
        BlocProvider(create: (_) => ReportsCubit(SupabaseService())),
      ],
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          return MaterialApp(
            title: 'Sahabat Assaffal',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeState.themeMode,
            home: const AppWrapper(),
          );
        },
      ),
    );
  }
}

class AppWrapper extends StatefulWidget {
  const AppWrapper({super.key});

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return SplashScreen(
        onComplete: () {
          setState(() {
            _showSplash = false;
          });
        },
      );
    }
    return const MainNavigation();
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final AuthService _authService = AuthService();
  bool _hasNewChat = false;
  StreamSubscription? _chatSubscription;

  @override
  void initState() {
    super.initState();
    _setupChatListener();
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    super.dispose();
  }

  void _setupChatListener() {
    _chatSubscription = Supabase.instance.client
        .from('admin_chats')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(1)
        .listen((data) {
      if (data.isNotEmpty) {
        final lastMessage = data.first;
        final lastMessageId = lastMessage['id'].toString();
        final lastSenderId = lastMessage['user_id'].toString();
        final currentUserId = _authService.currentUser?.id;

        // Jika mesej bukan dari diri sendiri dan tab sembang tidak aktif
        if (lastSenderId != currentUserId && _currentIndex != 1) {
          _checkIfMessageIsNew(lastMessageId);
        }
      }
    });
  }

  void _checkIfMessageIsNew(String messageId) async {
    final prefs = await SharedPreferences.getInstance();
    final lastReadId = prefs.getString('last_read_chat_id') ?? '';
    
    if (lastReadId != messageId && mounted) {
      setState(() {
        _hasNewChat = true;
      });
    }
  }

  void _markChatAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    // Dapatkan ID mesej terakhir untuk disimpan sebagai 'sudah baca'
    try {
      final lastMsg = await Supabase.instance.client
          .from('admin_chats')
          .select('id')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      
      if (lastMsg != null) {
        await prefs.setString('last_read_chat_id', lastMsg['id'].toString());
      }
    } catch (e) {
      debugPrint('Error marking chat as read: $e');
    }

    if (mounted) {
      setState(() {
        _hasNewChat = false;
      });
    }
  }

  List<Widget> get _screens {
    final user = _authService.currentUser;
    final bool hasAdminPrivileges = user?.userMetadata?['is_admin'] == true ||
        user?.userMetadata?['is_moderator'] == true ||
        user?.userMetadata?['is_yb'] == true;

    return [
      const HomeScreen(),
      hasAdminPrivileges ? const AdminChatScreen() : const ReportScreen(),
      const DashboardScreen(),
      const CityDashboardScreen(),
      const ProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        margin: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: bottomPadding + 16,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDarkMode
                      ? [
                          const Color(0xFF1a1a2e).withOpacity(0.9),
                          const Color(0xFF16213e).withOpacity(0.9),
                        ]
                      : [
                          Colors.white.withOpacity(0.9),
                          Colors.grey.shade50.withOpacity(0.9),
                        ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: isDarkMode
                      ? Colors.white.withOpacity(0.1)
                      : Colors.black.withOpacity(0.05),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDarkMode
                        ? Colors.black.withOpacity(0.4)
                        : Colors.black.withOpacity(0.1),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildNavItem(
                      imagePath: 'assets/images/nav_explore.png',
                      label: 'Teroka',
                      index: 0,
                      isDarkMode: isDarkMode,
                    ),
                  ),
                  Expanded(
                    child: _buildAddReportNavItem(isDarkMode),
                  ),
                  Expanded(
                    child: _buildNavItem(
                      imagePath: 'assets/images/nav_reports.png',
                      label: 'Laporan',
                      index: 2,
                      isDarkMode: isDarkMode,
                    ),
                  ),
                  Expanded(
                    child: _buildNavItem(
                      imagePath: 'assets/images/nav_stats.png',
                      label: 'Statistik',
                      index: 3,
                      isDarkMode: isDarkMode,
                    ),
                  ),
                  Expanded(
                    child: _buildNavItem(
                      imagePath: 'assets/images/nav_profile.png',
                      label: 'Profil',
                      index: 4,
                      isDarkMode: isDarkMode,
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

  Widget _buildNavItem({
    required String imagePath,
    required String label,
    required int index,
    required bool isDarkMode,
  }) {
    final isSelected = _currentIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [AppTheme.primaryRed, AppTheme.primaryBlue],
                      )
                    : null,
                color: isSelected ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Image.asset(
                imagePath,
                width: 22,
                height: 22,
                color: isSelected
                    ? Colors.white
                    : (isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600),
                errorBuilder: (context, error, stackTrace) {
                  IconData icon;
                  switch (index) {
                    case 0: icon = Icons.explore; break;
                    case 2: icon = Icons.list_alt; break;
                    case 3: icon = Icons.bar_chart; break;
                    case 4: icon = Icons.person; break;
                    default: icon = Icons.help_outline;
                  }
                  return Icon(
                    icon,
                    size: 22,
                    color: isSelected ? Colors.white : Colors.grey,
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? (isDarkMode ? Colors.white : AppTheme.primaryRed)
                    : (isDarkMode ? Colors.grey.shade500 : Colors.grey.shade600),
                letterSpacing: isSelected ? 0.5 : 0,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddReportNavItem(bool isDarkMode) {
    final isSelected = _currentIndex == 1;
    final user = _authService.currentUser;
    final bool hasAdminPrivileges = user?.userMetadata?['is_admin'] == true ||
        user?.userMetadata?['is_moderator'] == true ||
        user?.userMetadata?['is_yb'] == true;

    return GestureDetector(
      onTap: () {
        setState(() => _currentIndex = 1);
        if (hasAdminPrivileges) {
          _markChatAsRead();
        }
      },
      onLongPress: _showAdminLogin,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  width: isSelected ? 42 : 38,
                  height: isSelected ? 42 : 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.primaryRed, AppTheme.primaryBlue],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryRed.withOpacity(isSelected ? 0.5 : 0.3),
                        blurRadius: isSelected ? 12 : 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    hasAdminPrivileges ? Icons.chat_bubble_rounded : Icons.add_rounded,
                    size: isSelected ? 24 : 22,
                    color: Colors.white,
                  ),
                ),
                if (hasAdminPrivileges && _hasNewChat && !isSelected)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                        ],
                      ),
                      child: const Text(
                        '!',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? (isDarkMode ? Colors.white : AppTheme.primaryRed)
                    : (isDarkMode ? Colors.grey.shade500 : Colors.grey.shade600),
                letterSpacing: isSelected ? 0.5 : 0,
              ),
              child: Text(hasAdminPrivileges ? 'Sembang' : 'Lapor'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAdminLogin() async {
    final user = Supabase.instance.client.auth.currentUser;
    final bool isGoogleAdmin = user?.userMetadata?['is_admin'] == true;

    // 1. Jika pengguna adalah Admin melalui Google Login, terus masuk tanpa had
    if (isGoogleAdmin) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
        );
      }
      return;
    }

    // 2. SEMAK SESI ADMIN TRADISIONAL (SECRET BUTTON LAMA)
    final prefs = await SharedPreferences.getInstance();
    final bool isAdminLoggedIn = prefs.getBool('isAdminLoggedIn') ?? false;
    final int lastAction = prefs.getInt('lastAdminAction') ?? 0;
    final int now = DateTime.now().millisecondsSinceEpoch;

    // Jika sudah login manual dan belum 3 minit idle
    if (isAdminLoggedIn && (now - lastAction < 180000)) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
        );
      }
      return;
    }

    // 3. Jika bukan Google Admin dan tiada sesi aktif, barulah ke screen login
    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const AdminLoginScreen()),
    );

    if (result == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
      );
    }
  }
}
