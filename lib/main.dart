import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'screens/city_dashboard_screen.dart';
import 'screens/news_screen.dart';
import 'screens/nickname_setup_screen.dart';
import 'screens/admin_chat_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/reports_list_screen.dart';
import 'screens/notifications_list_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  OneSignal.initialize("e9668216-1dc4-4567-8951-0eb406a75c46");
  OneSignal.Notifications.requestPermission(true);
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
            routes: {
              '/home': (context) => const MainNavigation(),
              '/nickname_setup': (context) => NicknameSetupScreen(),
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
          final nickname = user.userMetadata?['nickname'];
          if (nickname != null && nickname.toString().isNotEmpty) return const MainNavigation();
          return NicknameSetupScreen();
        }
        return const MainNavigation();
      },
    );
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
  bool _hasNewNotification = false;

  List<Widget> get _screens {
    final user = _authService.currentUser;
    final bool hasAdminPrivileges = user?.userMetadata?['is_admin'] == true ||
        user?.userMetadata?['is_moderator'] == true ||
        user?.userMetadata?['is_yb'] == true;

    return [
      const HomeScreen(),
      hasAdminPrivileges ? AdminChatScreen() : const ReportScreen(),
      const ReportsListScreen(),
      const CityDashboardScreen(),
      ProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      extendBody: true, // Crucial for glassmorphism effect
      body: _screens[_currentIndex],
      bottomNavigationBar: _buildGlassNavigationBar(isDarkMode),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: (isDarkMode ? Colors.black : Colors.white).withOpacity(0.7),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
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
    final activeColor = AppTheme.primaryRed;
    
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: EdgeInsets.all(isAction ? 10 : 6),
            decoration: isAction && isSelected
                ? BoxDecoration(
                    color: activeColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  )
                : null,
            child: Icon(
              icon,
              color: isSelected ? activeColor : (isDarkMode ? Colors.white60 : Colors.black45),
              size: isAction ? 28 : 24,
            ),
          ),
          if (!isAction) ...[
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? activeColor : (isDarkMode ? Colors.white60 : Colors.black45),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
