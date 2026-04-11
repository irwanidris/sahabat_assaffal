import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../cubit/reports_cubit.dart';
import '../models/pothole_report.dart';
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
  final ImagePicker _picker = ImagePicker();

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

  Future<void> _updateStatus(PotholeReport report, String newStatus) async {
    if (_isProcessing) return;
    
    // Dapatkan ID & Nama Moderator semasa (cth: dari AuthService)
    final currentUser = Supabase.instance.client.auth.currentUser;
    final currentUserId = currentUser?.id;
    final currentUserName = currentUser?.userMetadata?['full_name'] ?? 'Moderator';

    // Logik Sekatan: Jika klik Selesai, pastikan dia yang memproses
    if (newStatus == 'resolved' && report.status == 'processing') {
      if (report.assignedTo != null && report.assignedTo != currentUserId) {
        _showSnackBar('Aduan ini sedang diuruskan oleh ${report.assignedName ?? 'moderator lain'}.', isError: true);
        return;
      }
    }

    String? resolvedImageUrl;

    if (newStatus == 'resolved') {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Ambil Gambar Baru (Selesai)'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Pilih dari Galeri'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1080,
      );

      if (pickedFile == null) return;

      setState(() => _isProcessing = true);
      try {
        resolvedImageUrl = await _supabaseService.uploadImage(File(pickedFile.path));
      } catch (e) {
        if (mounted) _showSnackBar('Gagal muat naik gambar: $e', isError: true);
        setState(() => _isProcessing = false);
        return;
      }
    } else {
      setState(() => _isProcessing = true);
    }

    try {
      await _supabaseService.updateReportStatus(
        report.id, 
        newStatus, 
        resolvedImageUrl: resolvedImageUrl,
        assignedTo: newStatus == 'processing' ? currentUserId : (newStatus == 'resolved' ? report.assignedTo : null),
        assignedName: newStatus == 'processing' ? currentUserName : (newStatus == 'resolved' ? report.assignedName : null),
      );

      if (mounted) {
        await context.read<ReportsCubit>().refreshReports();
        String label = 'STATUS';
        if (newStatus == 'resolved') label = 'SELESAI';
        if (newStatus == 'processing') label = 'PROSES';
        if (newStatus == 'pending') label = 'BARU';
        
        _showSnackBar('Status berjaya ditukar kepada $label');
      }
    } catch (e) {
      if (mounted) _showSnackBar('Gagal menukar status: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _deleteReport(PotholeReport report) async {
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
        title: const Text('Dashboard Admin', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
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
                final isProcessingStatus = report.status == 'processing';
                final isPending = report.status == 'pending';

                final currentUser = Supabase.instance.client.auth.currentUser;
                final currentUserId = currentUser?.id;
                
                // Cek adakah saya yang sedang memproses?
                final isMyTask = report.assignedTo == currentUserId;
                final isAssignedToOther = isProcessingStatus && report.assignedTo != null && !isMyTask;

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
                            Text(report.category, style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w600, fontSize: 11)),
                            const SizedBox(height: 6),
                            // INFO TAMBAHAN: PELAPOR & GPS
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
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isResolved 
                                    ? Colors.green.withOpacity(0.1) 
                                    : (isProcessingStatus ? Colors.blue.withOpacity(0.1) : Colors.orange.withOpacity(0.1)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isResolved ? 'SELESAI' : (isProcessingStatus ? 'PROSES' : 'BARU'),
                                style: TextStyle(
                                  color: isResolved ? Colors.green : (isProcessingStatus ? Colors.blue : Colors.orange), 
                                  fontSize: 9, 
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            ),
                            if (isProcessingStatus && report.assignedName != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  isMyTask ? 'Ditangani oleh Anda' : 'Oleh: ${report.assignedName}',
                                  style: TextStyle(
                                    fontSize: 9, 
                                    color: isMyTask ? Colors.blue : Colors.red,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: isMyTask ? FontWeight.bold : FontWeight.normal,
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
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Text('Status:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: (isPending && !isAssignedToOther) && !_isProcessing 
                                  ? () => _updateStatus(report, 'processing') 
                                  : null,
                              style: TextButton.styleFrom(
                                backgroundColor: isProcessingStatus ? Colors.blue.withOpacity(0.1) : null,
                                foregroundColor: isAssignedToOther ? Colors.grey : Colors.blue,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                minimumSize: const Size(0, 32),
                              ),
                              child: Text(isAssignedToOther ? 'DIURUSKAN' : 'PROSES', style: const TextStyle(fontSize: 11)),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: (isProcessingStatus && isMyTask) && !_isProcessing 
                                  ? () => _updateStatus(report, 'resolved') 
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isResolved ? Colors.green.withOpacity(0.1) : (isAssignedToOther ? Colors.grey[300] : Colors.green),
                                foregroundColor: isResolved ? Colors.green : (isAssignedToOther ? Colors.grey : Colors.white),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                minimumSize: const Size(0, 32),
                              ),
                              child: const Text('SELESAI', style: TextStyle(fontSize: 11)),
                            ),
                          ],
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
}
