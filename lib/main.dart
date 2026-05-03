import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'config/supabase_config.dart';
import 'theme/app_theme.dart';
import 'cubit/theme_cubit.dart';
import 'cubit/reports_cubit.dart';
import 'services/supabase_service.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/report_screen.dart';
import 'screens/city_dashboard_screen.dart';
import 'screens/username_setup_screen.dart';
import 'screens/admin_chat_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/reports_list_screen.dart';
import 'screens/notifications_list_screen.dart';
import 'screens/admin_login_screen.dart';
import 'services/auth_service.dart';
import 'models/assaffal_report.dart';

// 1. Tambah Navigator Key Global
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );
  
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  OneSignal.initialize("e9668216-1dc4-4567-8951-0eb406a75c46");
  OneSignal.Notifications.requestPermission(true);
  
  // Dayakan perkongsian lokasi untuk targeting notifikasi "berhampiran" di masa hadapan
  OneSignal.Location.setShared(true);

  // Log Subscription ID untuk debugging
  Timer(const Duration(seconds: 5), () {
    final subId = OneSignal.User.pushSubscription.id;
    debugPrint('OneSignal Subscription ID: $subId');
  });

  // 2. Kendalikan klik notifikasi OneSignal
  OneSignal.Notifications.addClickListener((event) {
    final data = event.notification.additionalData;
    debugPrint('OneSignal Notification Data: $data');
    if (data != null) {
      final String? type = data['type'];
      final dynamic id = data['related_id'] ?? data['id'];

      if (id != null) {
        if (type == 'report' || type == 'new_report' || type == 'report_resolved') {
          _handleReportDeepLink(id.toString());
        } else if (type == 'news_approved' || type == 'news') {
          _handleNewsDeepLink();
        }
      }
    }
  });

  // 3. Kendalikan klik In-App Message (Banner Hitam)
  OneSignal.InAppMessages.addClickListener((event) {
    debugPrint('OneSignal IAM Click Data: ${event.result.actionId}');
    final actionId = event.result.actionId;
    
    // Jika ada ID laporan dalam URL atau action data
    // Biasanya OneSignal IAM hantar data dalam URL atau kita set actionId
    if (actionId != null && actionId.isNotEmpty) {
      if (actionId.startsWith('TK') || actionId.length > 5) {
        _handleReportDeepLink(actionId);
      }
    }
  });

  runApp(const MyApp());
}

void _handleReportDeepLink(String reportId) {
  final context = navigatorKey.currentContext;
  if (context == null) return;

  // Pastikan reports dimuatkan dahulu
  context.read<ReportsCubit>().loadReports();

  // Tunggu sekejap untuk data sampai atau cuba cari dalam list sedia ada
  Future.delayed(const Duration(milliseconds: 500), () {
    final state = context.read<ReportsCubit>().state;
    if (state is ReportsLoaded) {
      // Cari mengikut ID atau report_code
      final report = state.reports.firstWhere(
        (r) => r.id == reportId || r.reportCode == reportId, 
        orElse: () => state.reports.first, // Fallback ke yang terbaru jika tak jumpa
      );

      _navigateToReportsAndShow(context, report);
    }
  });
}

void _handleNewsDeepLink() {
  final state = mainNavKey.currentState;
  if (state != null) {
    state.jumpToNews();
  }
}

void _navigateToReportsAndShow(BuildContext context, AssaffalReport report) {
  final state = mainNavKey.currentState;
  if (state != null) {
    state.jumpToReport(report);
  }
}

final GlobalKey<MainNavigationState> mainNavKey = GlobalKey<MainNavigationState>();

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
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeState.themeMode,
            routes: {
              '/home': (context) => const MainNavigation(),
              '/nickname_setup': (context) => UsernameSetupScreen(),
            },
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
      return SplashScreen(onComplete: () => setState(() => _showSplash = false));
    }
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;
        final user = session?.user;

        if (user != null) {
          // 1. Semak jika pengguna sudah mendaftar username
          // Kita guna metadata 'username' yang diset semasa pendaftaran
          final String? username = user.userMetadata?['username'];

          if (username == null || username.isEmpty) {
            // 2. Jika login Google berjaya tapi belum ada username,
            // hantar ke skrin Setup yang baru anda buat
            return const UsernameSetupScreen();
          }

          // 3. Jika sudah ada username, terus ke apps utama
          return MainNavigation(key: mainNavKey);
        }

        // 4. Jika tidak login Google (Pelawat), terus ke apps utama
        return MainNavigation(key: mainNavKey);
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  final int initialIndex;
  const MainNavigation({super.key, this.initialIndex = 0});
  @override
  State<MainNavigation> createState() => MainNavigationState();
}

class MainNavigationState extends State<MainNavigation> {
  late int _currentIndex;
  final AuthService _authService = AuthService();
  final GlobalKey<ReportsListScreenState> _reportsListKey = GlobalKey<ReportsListScreenState>();
  final GlobalKey<State<ProfileScreen>> _profileKey = GlobalKey<State<ProfileScreen>>();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void jumpToReport(AssaffalReport report) {
    setState(() {
      _currentIndex = 2; // Index tab Laporan
    });
    
    Future.delayed(const Duration(milliseconds: 500), () {
      final reportsListState = _reportsListKey.currentState;
      if (reportsListState != null) {
        reportsListState.showReportFromExternal(report);
      }
    });
  }

  void jumpToNews() {
    setState(() {
      _currentIndex = 0; // Index tab Home (Berita)
    });
  }

  void _showSecretDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AdminLoginScreen()),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout Sekarang?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tidak'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _authService.signOut();
              if (mounted) {
                setState(() {
                  _currentIndex = 0;
                });
              }
            },
            child: const Text('Ya', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showLoginRequiredDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: AppTheme.primaryRed),
            SizedBox(width: 10),
            Text('Log Masuk Diperlukan', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('Sila log masuk terlebih dahulu untuk melihat notifikasi peribadi dan laporan komuniti.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('KEMUDIAN', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _authService.signInWithGoogle();
                if (mounted) setState(() {});
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal Log Masuk: $e'))
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('LOG MASUK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  List<Widget> get _screens {
    final user = _authService.currentUser;
    final bool hasAdminPrivileges = user?.userMetadata?['is_admin'] == true ||
        user?.userMetadata?['is_moderator'] == true ||
        user?.userMetadata?['is_yb'] == true;

    return [
      const HomeScreen(),
      hasAdminPrivileges ? AdminChatScreen() : const ReportScreen(),
      ReportsListScreen(key: _reportsListKey),
      const CityDashboardScreen(),
      ProfileScreen(key: _profileKey),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          _screens[_currentIndex],
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: _buildGlassHeader(isDarkMode),
          ),
        ],
      ),
      bottomNavigationBar: _buildGlassNavigationBar(isDarkMode),
    );
  }

  Widget _buildGlassHeader(bool isDarkMode) {
    return ClipRRect(
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
                onLongPress: () => _showLogoutDialog(context),
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
                    'Sahabat Assaffal',
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
              Stack(
                children: [
                  IconButton(
                    onPressed: () {
                      if (_authService.currentUser == null) {
                        _showLoginRequiredDialog();
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const NotificationsListScreen()),
                      ).then((_) => setState(() {})); // Refresh badge apabila kembali
                    },
                    icon: Icon(
                      Icons.notifications_none_rounded,
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                      size: 24,
                    ),
                  ),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: SupabaseService().fetchNotifications(userId: _authService.currentUser?.id),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        final unreadCount = snapshot.data!.where((n) => n['is_read'] == false).length;
                        if (unreadCount > 0) {
                          return Positioned(
                            right: 4,
                            top: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isDarkMode ? Colors.black : Colors.white, width: 1.5),
                              ),
                              child: Text(
                                unreadCount > 9 ? '9+' : '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
              IconButton(
                onPressed: () => context.read<ThemeCubit>().toggleTheme(),
                icon: Icon(
                  isDarkMode ? Icons.wb_sunny_rounded : Icons.nightlight_round, 
                  color: isDarkMode ? Colors.amber : Colors.indigo,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassNavigationBar(bool isDarkMode) {
    final user = _authService.currentUser;
    final bool hasAdminPrivileges = user?.userMetadata?['is_admin'] == true ||
        user?.userMetadata?['is_moderator'] == true ||
        user?.userMetadata?['is_yb'] == true;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      height: 70,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDarkMode 
                    ? [Colors.black.withOpacity(0.8), Colors.black.withOpacity(0.6)]
                    : [Colors.white.withOpacity(0.9), Colors.white.withOpacity(0.7)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNavItem(0, Icons.explore_rounded, 'Teroka', isDarkMode),
                _buildNavItem(1, hasAdminPrivileges ? Icons.chat_bubble_rounded : Icons.add_circle_rounded, hasAdminPrivileges ? 'Admin' : 'Lapor', isDarkMode, isAction: !hasAdminPrivileges),
                _buildNavItem(2, Icons.grid_view_rounded, 'Laporan', isDarkMode),
                _buildNavItem(3, Icons.analytics_rounded, 'Impak', isDarkMode),
                _buildNavItem(4, Icons.person_rounded, 'Profil', isDarkMode),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, bool isDarkMode, {bool isAction = false}) {
    final isSelected = _currentIndex == index;
    // Highlight if selected OR if it's the primary "Lapor" action button
    final bool shouldHighlight = isSelected || isAction;
    
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      onLongPress: () {
        if (index == 4) {
          _showLogoutDialog(context);
        } else if (index == 1) {
          _showSecretDialog(context);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: EdgeInsets.all(isAction ? 10 : (isSelected ? 8 : 6)),
            decoration: shouldHighlight
                ? BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primaryRed, AppTheme.primaryBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryRed.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  )
                : null,
            child: Icon(
              icon,
              color: shouldHighlight ? Colors.white : (isDarkMode ? Colors.white60 : Colors.black45),
              size: isAction ? 28 : 24,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: shouldHighlight ? FontWeight.bold : FontWeight.normal,
              color: shouldHighlight ? AppTheme.primaryRed : (isDarkMode ? Colors.white60 : Colors.black45),
            ),
          ),
        ],
      ),
    );
  }
}
