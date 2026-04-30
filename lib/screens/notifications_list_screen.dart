import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import '../models/notification_model.dart';
import '../theme/app_theme.dart';
import '../main.dart';
import '../cubit/reports_cubit.dart';

class NotificationsListScreen extends StatefulWidget {
  const NotificationsListScreen({super.key});

  @override
  State<NotificationsListScreen> createState() => _NotificationsListScreenState();
}

class _NotificationsListScreenState extends State<NotificationsListScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  List<NotificationModel> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final user = _authService.currentUser;
      final data = await _supabaseService.fetchNotifications(userId: user?.id);
      
      if (mounted) {
        setState(() {
          _notifications = data.map((json) => NotificationModel.fromJson(json)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat notifikasi: $e')),
        );
      }
    }
  }

  Future<void> _handleNotificationTap(NotificationModel notification) async {
    // 1. Tanda sebagai baca
    if (!notification.isRead) {
      await _supabaseService.markNotificationAsRead(notification.id);
      if (mounted) {
        setState(() {
          final index = _notifications.indexWhere((n) => n.id == notification.id);
          if (index != -1) {
            _notifications[index] = NotificationModel(
              id: notification.id,
              title: notification.title,
              message: notification.message,
              createdAt: notification.createdAt,
              isRead: true,
              type: notification.type,
              relatedId: notification.relatedId,
            );
          }
        });
      }
    }

    // 2. Navigasi mengikut jenis
    final String type = notification.type?.toLowerCase() ?? '';
    final String? relatedId = notification.relatedId;

    if (relatedId == null || relatedId.isEmpty) return;

    if (type.contains('report') || type.contains('new_report')) {
      _navigateToReport(relatedId);
    } else if (type.contains('news')) {
      _navigateToNews();
    }
  }

  void _navigateToReport(String reportId) {
    // Tunjukkan loading sekejap
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // Pastikan reports dimuatkan dahulu
    context.read<ReportsCubit>().loadReports().then((_) {
      if (mounted) {
        Navigator.pop(context); // Tutup loading dialog
        
        final state = context.read<ReportsCubit>().state;
        if (state is ReportsLoaded) {
          try {
            final report = state.reports.firstWhere(
              (r) => r.id.toString() == reportId.toString() || r.reportCode == reportId,
            );
            
            // Tutup screen notifikasi dan lompat ke tab laporan
            Navigator.pop(context);
            mainNavKey.currentState?.jumpToReport(report);
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Laporan tidak dijumpai atau telah dipadam.')),
            );
          }
        }
      }
    });
  }

  void _navigateToNews() {
    Navigator.pop(context);
    mainNavKey.currentState?.jumpToNews();
  }

  Future<void> _markAllAsRead() async {
    final user = _authService.currentUser;
    await _supabaseService.markAllNotificationsAsRead(user?.id);
    _loadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Pusat Notifikasi'),
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
        actions: [
          if (_notifications.any((n) => !n.isRead))
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Tanda semua sudah baca',
              onPressed: _markAllAsRead,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadNotifications,
        color: AppTheme.primaryRed,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _notifications.isEmpty
                ? _buildEmptyState(isDarkMode)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _notifications.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      indent: 72,
                      color: isDarkMode ? Colors.white10 : Colors.black.withOpacity(0.05),
                    ),
                    itemBuilder: (context, index) {
                      final notification = _notifications[index];
                      return _buildNotificationItem(notification, isDarkMode);
                    },
                  ),
      ),
    );
  }

  Widget _buildNotificationItem(NotificationModel notification, bool isDarkMode) {
    IconData iconData;
    Color iconColor;

    final type = notification.type?.toLowerCase() ?? '';

    if (type.contains('news')) {
      iconData = Icons.newspaper_rounded;
      iconColor = Colors.blue;
    } else if (type.contains('report_resolved')) {
      iconData = Icons.check_circle_rounded;
      iconColor = Colors.green;
    } else if (type.contains('report_processing')) {
      iconData = Icons.engineering_rounded;
      iconColor = Colors.orange;
    } else if (type.contains('new_report')) {
      iconData = Icons.add_location_alt_rounded;
      iconColor = AppTheme.primaryRed;
    } else if (type.contains('report_fake')) {
      iconData = Icons.report_off_rounded;
      iconColor = Colors.grey;
    } else if (type.contains('chat')) {
      iconData = Icons.chat_bubble_rounded;
      iconColor = Colors.teal;
    } else {
      iconData = Icons.notifications_rounded;
      iconColor = AppTheme.primaryRed;
    }

    return InkWell(
      onTap: () => _handleNotificationTap(notification),
      child: Container(
        color: notification.isRead 
            ? Colors.transparent 
            : (isDarkMode ? Colors.white.withOpacity(0.05) : AppTheme.primaryRed.withOpacity(0.05)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(iconData, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight: notification.isRead ? FontWeight.w500 : FontWeight.bold,
                            fontSize: 15,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: notification.isRead ? Colors.grey.withOpacity(0.5) : AppTheme.primaryRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notification.timeAgo,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode ? Colors.grey.shade500 : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 80,
            color: isDarkMode ? Colors.white24 : Colors.black12,
          ),
          const SizedBox(height: 16),
          Text(
            'Tiada notifikasi setakat ini',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDarkMode ? Colors.grey.shade500 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
