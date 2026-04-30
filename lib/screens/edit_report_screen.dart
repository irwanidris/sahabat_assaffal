import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/assaffal_report.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/full_screen_image.dart';
import '../cubit/reports_cubit.dart';

class EditReportScreen extends StatefulWidget {
  final AssaffalReport report;

  const EditReportScreen({super.key, required this.report});

  @override
  State<EditReportScreen> createState() => _EditReportScreenState();
}

class _EditReportScreenState extends State<EditReportScreen> {
  late TextEditingController _areaNameController;
  late TextEditingController _descriptionController;
  late TextEditingController _dateTimeController;
  late TextEditingController _departmentController;
  bool _isLoading = false;
  final SupabaseService _supabaseService = SupabaseService();
  
  bool _isAdmin = false;
  bool _isModerator = false;
  String? _currentUserId;
  String? _nickname;

  @override
  void initState() {
    super.initState();
    _areaNameController = TextEditingController(text: widget.report.areaName);
    _descriptionController = TextEditingController(text: widget.report.description);
    _dateTimeController = TextEditingController(text: widget.report.duration);
    _departmentController = TextEditingController(text: widget.report.department);
    
    _checkPermissions();
  }

  void _checkPermissions() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      setState(() {
        _currentUserId = user.id;
        _isAdmin = user.userMetadata?['is_admin'] == true;
        _isModerator = user.userMetadata?['is_moderator'] == true;
        _nickname = user.userMetadata?['nickname'] ?? 'Sahabat';
      });
    }
  }

  Future<void> _selectDateTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      if (!mounted) return;
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );

      if (pickedTime != null) {
        setState(() {
          final selectedDateTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          _dateTimeController.text = DateFormat('dd/MM/yyyy HH:mm').format(selectedDateTime);
        });
      }
    }
  }

  Future<void> _updateReport() async {
    if (_areaNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nama kawasan tidak boleh kosong.')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _supabaseService.updateReportData(widget.report.id, {
        if (_isAdmin) 'area_name': _areaNameController.text.trim(),
        if (_isAdmin) 'description': _descriptionController.text.trim(),
        if (_isAdmin) 'duration': _dateTimeController.text,
        if (_isAdmin) 'edit_count': widget.report.editCount + 1,
        if (_isModerator || _isAdmin) 'department': _departmentController.text.trim(),
      });

      if (mounted) {
        context.read<ReportsCubit>().loadReports();
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maklumat laporan berjaya dikemaskini!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ralat: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSoftDelete() async {
    final confirmCtrl = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Padam Laporan?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sila Taip \'Padam\' untuk mengesahkan anda mahu memadam laporan ini.'),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Taip Padam di sini',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('BATAL')),
          TextButton(
            onPressed: () {
              if (confirmCtrl.text.trim().toLowerCase() == 'padam') {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sila taip perkataan \'Padam\' dengan betul.')));
              }
            },
            child: const Text('SAHKAN PADAM', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await _supabaseService.softDeleteReport(widget.report.id, _nickname ?? 'Pengguna');
        if (mounted) {
          context.read<ReportsCubit>().loadReports();
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Laporan telah ditandakan untuk pemadaman.')));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ralat: $e')));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleRestore() async {
    setState(() => _isLoading = true);
    try {
      await _supabaseService.restoreReport(widget.report.id);
      if (mounted) {
        context.read<ReportsCubit>().loadReports();
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Laporan telah dipulihkan!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ralat: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor = Colors.blue;
    if (widget.report.isSoftDeleted()) {
      statusColor = Colors.grey;
    } else if (widget.report.status == 'pending') {
      statusColor = Colors.orange.shade800;
    } else if (widget.report.status == 'processing' || widget.report.status == 'active') {
      statusColor = Colors.red.shade800;
    } else if (widget.report.status == 'resolved') {
      statusColor = Colors.green;
    }

    final bool isUserOnly = !_isAdmin && !_isModerator;
    final bool isSoftDeleted = widget.report.isSoftDeleted();

    return Scaffold(
      appBar: AppBar(
        title: Text(isUserOnly ? 'Perincian Laporan' : 'Edit Maklumat Laporan'),
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
        actions: [
          if (isUserOnly && !isSoftDeleted)
            IconButton(
              icon: const Icon(Icons.delete_forever_rounded),
              onPressed: _handleSoftDelete,
              tooltip: 'Padam Laporan',
            ),
        ],
      ),
      body: Opacity(
        opacity: isSoftDeleted ? 0.6 : 1.0,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Paparan Info Status (Read Only)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(isSoftDeleted ? Icons.delete_sweep_rounded : Icons.info_outline, color: statusColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isSoftDeleted 
                          ? 'STATUS: AKAN DIPADAM (3 HARI)\nLaporan ini telah dipadam oleh anda.'
                          : 'Status: ${widget.report.status.toUpperCase()}\n(Status kini ditentukan oleh verifikasi komuniti)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor),
                      ),
                    ),
                    if (isSoftDeleted && widget.report.canRestore())
                      ElevatedButton(
                        onPressed: _handleRestore,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 30),
                        ),
                        child: const Text('RESTORE', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              _buildDetailItem(Icons.tag_rounded, 'Nombor Laporan', widget.report.reportCode ?? 'TK0000'),

              _buildDetailItem(
                Icons.person_pin_rounded, 
                'Dilaporkan Oleh', 
                (widget.report.reporterNickname != null && widget.report.reporterNickname!.isNotEmpty)
                    ? widget.report.reporterNickname!
                    : (widget.report.reporterName != null && widget.report.reporterName!.isNotEmpty)
                        ? widget.report.reporterName!
                        : 'Sahabat Komuniti',
              ),

              const Text('Gambar Laporan', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FullScreenImage(
                        imageUrl: widget.report.imageUrl,
                        tag: 'report-${widget.report.id}',
                        report: widget.report,
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Hero(
                    tag: 'report-${widget.report.id}',
                    child: Image.network(
                      widget.report.imageUrl,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              if (isUserOnly) ...[
                _buildDetailItem(Icons.category, 'Kategori', widget.report.category),
                _buildDetailItem(Icons.location_on, 'Kawasan', widget.report.areaName ?? 'Tidak Dinyatakan'),
                _buildDetailItem(Icons.place, 'Alamat', widget.report.address ?? 'Tiada maklumat alamat'),
                _buildDetailItem(Icons.gps_fixed, 'Koordinat GPS', '${widget.report.latitude}, ${widget.report.longitude}'),
                _buildDetailItem(Icons.calendar_today, 'Tarikh & Masa Kejadian', widget.report.duration ?? 'Baru'),
                _buildDetailItem(Icons.description, 'Keterangan', widget.report.description ?? 'Tiada keterangan tambahan'),
                if (widget.report.department != null && widget.report.department!.isNotEmpty)
                  _buildDetailItem(Icons.business, 'Jabatan Bertanggungjawab', widget.report.department!),
              ] else ...[
                const Text('Maklumat Pentadbiran', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                const SizedBox(height: 15),

                TextField(
                  controller: _departmentController,
                  decoration: const InputDecoration(
                    labelText: 'Jabatan / Agensi Bertanggungjawab',
                    border: OutlineInputBorder(),
                    hintText: 'Contoh: JKR, Majlis Daerah...',
                  ),
                ),
                const SizedBox(height: 20),

                if (_isAdmin) ...[
                  TextField(
                    controller: _areaNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Kawasan / Taman / Jalan',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _dateTimeController,
                    readOnly: true,
                    onTap: _selectDateTime,
                    decoration: const InputDecoration(
                      labelText: 'Tarikh & Masa Berlaku',
                      prefixIcon: Icon(Icons.calendar_today),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                TextField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Maklumat Tambahan / Nota Pentadbir',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _updateReport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : const Text('Simpan Perubahan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryRed),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _areaNameController.dispose();
    _descriptionController.dispose();
    _dateTimeController.dispose();
    _departmentController.dispose();
    super.dispose();
  }
}
