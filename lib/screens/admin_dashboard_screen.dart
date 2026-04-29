import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../cubit/reports_cubit.dart';
import '../models/assaffal_report.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReportsCubit>().refreshReports();
    });
  }

  String _formatDateTime(DateTime date) {
    return DateFormat('d MMM yyyy, h:mm a').format(date.toLocal());
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _maximizePhoto(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: InteractiveViewer(
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                      errorWidget: (context, url, error) => const Icon(Icons.error),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteReport(AssaffalReport report) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Padam Laporan?'),
        content: Text('Adakah anda pasti mahu memadam laporan di "${report.areaName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Padam', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isProcessing = true);
      try {
        await _supabaseService.deleteReport(report.id);
        if (mounted) {
          await context.read<ReportsCubit>().refreshReports();
          _showSnackBar('Laporan berjaya dipadam');
        }
      } catch (e) {
        if (mounted) _showSnackBar('Gagal memadam: $e', isError: true);
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Sahabat Assaffal', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<ReportsCubit>().refreshReports(),
          ),
        ],
      ),
      body: BlocBuilder<ReportsCubit, ReportsState>(
        builder: (context, state) {
          if (state is ReportsLoading) return const Center(child: CircularProgressIndicator());
          if (state is ReportsLoaded) {
            final reports = state.reports;
            if (reports.isEmpty) return const Center(child: Text('Tiada laporan dijumpai'));
            
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: reports.length,
              itemBuilder: (context, index) {
                final report = reports[index];
                final isResolved = report.status == 'resolved';

                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: GestureDetector(
                          onTap: () => _maximizePhoto(report.imageUrl),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: report.imageUrl,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(color: Colors.grey[300], child: const Icon(Icons.image)),
                                  errorWidget: (context, url, error) => const Icon(Icons.image_not_supported),
                                ),
                              ),
                              const Icon(Icons.zoom_in, color: Colors.white70, size: 20),
                            ],
                          ),
                        ),
                        title: Text(report.areaName ?? 'Kawasan Tidak Diketahui', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(report.category, style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 11)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.person, size: 12, color: Colors.grey),
                                const SizedBox(width: 4),
                                Expanded(child: Text('Oleh: ${report.reporterName ?? 'Anonym'}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.gps_fixed, size: 12, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text('${report.latitude.toStringAsFixed(5)}, ${report.longitude.toStringAsFixed(5)}', style: const TextStyle(fontSize: 10, color: Colors.indigo)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.access_time, size: 12, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(_formatDateTime(report.createdAt), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Community Stats for Admin
                            Row(
                              children: [
                                _buildMiniStat(Icons.check_circle_outline, Colors.green, report.verifiedResolved),
                                const SizedBox(width: 8),
                                _buildMiniStat(Icons.error_outline, AppTheme.primaryRed, report.verifiedStillExists),
                                const SizedBox(width: 8),
                                _buildMiniStat(Icons.block_flipped, Colors.orange, report.verifiedFake),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (report.resolvedImageUrl != null) ...[
                              const Text('BUKTI SELESAI:', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.green)),
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () => _maximizePhoto(report.resolvedImageUrl!),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: report.resolvedImageUrl!,
                                    width: 100,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(color: Colors.grey[200]),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isResolved 
                                    ? Colors.green.withOpacity(0.1) 
                                    : (report.status == 'fake' 
                                        ? Colors.red.withOpacity(0.1) 
                                        : (report.upvoteCount > 0 
                                            ? AppTheme.primaryRed.withOpacity(0.1) 
                                            : Colors.orange.withOpacity(0.1))),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isResolved 
                                    ? 'SELESAI' 
                                    : (report.status == 'fake' 
                                        ? 'PALSU' 
                                        : (report.upvoteCount > 0 ? 'AKTIF' : 'PENDING')),
                                style: TextStyle(
                                  color: isResolved 
                                      ? Colors.green 
                                      : (report.status == 'fake' 
                                          ? Colors.red 
                                          : (report.upvoteCount > 0 ? AppTheme.primaryRed : Colors.orange)),
                                  fontSize: 9, 
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: _isProcessing ? null : () => _deleteReport(report),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          }
          return const SizedBox();
        },
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, Color color, int count) {
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 2),
        Text('$count', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
