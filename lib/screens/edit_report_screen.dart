import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/pothole_report.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class EditReportScreen extends StatefulWidget {
  final PotholeReport report;

  const EditReportScreen({super.key, required this.report});

  @override
  State<EditReportScreen> createState() => _EditReportScreenState();
}

class _EditReportScreenState extends State<EditReportScreen> {
  late TextEditingController _areaNameController;
  late TextEditingController _descriptionController;
  late TextEditingController _dateTimeController;
  late TextEditingController _departmentController;
  DateTime? _incidentDateTime;
  bool _isLoading = false;
  final SupabaseService _supabaseService = SupabaseService();
  
  // Status & Role Handling
  String _currentStatus = 'pending';
  bool _isAdmin = false;
  bool _isModerator = false;
  File? _resolvedImageFile;
  String? _resolvedImageUrl;

  @override
  void initState() {
    super.initState();
    _areaNameController = TextEditingController(text: widget.report.areaName);
    _descriptionController = TextEditingController(text: widget.report.description);
    _dateTimeController = TextEditingController(text: widget.report.duration);
    _departmentController = TextEditingController(text: widget.report.department);
    _currentStatus = widget.report.status;
    _resolvedImageUrl = widget.report.resolvedImageUrl;
    
    _checkPermissions();
    // ...
    try {
      if (widget.report.duration != null && widget.report.duration != 'Tidak dinyatakan') {
        _incidentDateTime = DateFormat('dd/MM/yyyy HH:mm').parse(widget.report.duration!);
      }
    } catch (e) {
      _incidentDateTime = widget.report.createdAt;
    }
  }

  void _checkPermissions() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      setState(() {
        _isAdmin = user.userMetadata?['is_admin'] == true;
        _isModerator = user.userMetadata?['is_moderator'] == true;
      });
    }
  }

  Future<void> _pickResolvedImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (pickedFile != null) {
      setState(() {
        _resolvedImageFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _selectDateTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _incidentDateTime ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      if (!mounted) return;
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_incidentDateTime ?? DateTime.now()),
      );

      if (pickedTime != null) {
        setState(() {
          _incidentDateTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          _dateTimeController.text = DateFormat('dd/MM/yyyy HH:mm').format(_incidentDateTime!);
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
      String? finalResolvedImageUrl = _resolvedImageUrl;

      // Jika ada gambar baru dimuat naik oleh Admin/Moderator
      if (_resolvedImageFile != null) {
        finalResolvedImageUrl = await _supabaseService.uploadImage(_resolvedImageFile!);
      }

      final user = Supabase.instance.client.auth.currentUser;
      final String? userName = user?.userMetadata?['full_name'];

      await _supabaseService.updateReportData(widget.report.id, {
        if (_isAdmin) 'area_name': _areaNameController.text.trim(),
        if (_isAdmin) 'description': _descriptionController.text.trim(),
        if (_isAdmin) 'duration': _dateTimeController.text,
        if (_isAdmin) 'edit_count': widget.report.editCount + 1,
        'status': _currentStatus,
        'resolved_image_url': finalResolvedImageUrl,
        if (_isModerator || _isAdmin) 'department': _departmentController.text.trim(),
        if ((_isModerator || _isAdmin) && _currentStatus == 'resolved') 'resolved_by_name': userName,
      });

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Laporan berjaya dikemaskini!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ralat: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Laporan'),
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Had Edit: ${widget.report.editCount}/2', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
            const SizedBox(height: 20),
            
            // Paparan Gambar Laporan
            const Text('Gambar Laporan', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.report.imageUrl.split(',').length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final images = widget.report.imageUrl.split(',');
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      images[index],
                      width: 150,
                      height: 150,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            if (_isAdmin || _isModerator) ...[
              const Divider(),
              const SizedBox(height: 10),
              const Text('Kawalan Admin / Moderator', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              const SizedBox(height: 15),
              
              // TUKAR STATUS
              DropdownButtonFormField<String>(
                value: _currentStatus,
                decoration: const InputDecoration(labelText: 'Status Laporan', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'pending', child: Text('BARU (Pending)')),
                  DropdownMenuItem(value: 'processing', child: Text('DALAM PROSES')),
                  DropdownMenuItem(value: 'resolved', child: Text('SELESAI (Resolved)')),
                ],
                onChanged: (val) => setState(() => _currentStatus = val!),
              ),
              const SizedBox(height: 20),

              // JABATAN / AGENSI
              TextField(
                controller: _departmentController,
                decoration: const InputDecoration(
                  labelText: 'Jabatan / Agensi Di Laporkan',
                  border: OutlineInputBorder(),
                  hintText: 'Contoh: JKR, Majlis Daerah, SESB...',
                ),
              ),
              const SizedBox(height: 20),

              // MUAT NAIK GAMBAR SELESAI
              const Text('Bukti Foto Selesai (Jika Selesai)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _pickResolvedImage,
                child: Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.5)),
                  ),
                  child: _resolvedImageFile != null
                      ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(_resolvedImageFile!, fit: BoxFit.cover))
                      : (_resolvedImageUrl != null
                          ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(_resolvedImageUrl!, fit: BoxFit.cover))
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo, size: 40, color: Colors.blue),
                                Text('Ambil Foto Hasil Kerja', style: TextStyle(color: Colors.blue)),
                              ],
                            )),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 10),
            ],

            if (_isAdmin || (_isModerator && widget.report.status != 'resolved')) ...[
              if (_isAdmin) ...[
                TextField(
                  controller: _areaNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Kawasan / Taman / Jalan',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              if (_isAdmin) ...[
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
                readOnly: _isModerator,
                decoration: InputDecoration(
                  labelText: _isModerator ? 'Maklumat Tambahan (Read Only)' : 'Maklumat Tambahan (Pilihan)',
                  border: const OutlineInputBorder(),
                  filled: _isModerator,
                  fillColor: _isModerator ? Colors.grey[100] : null,
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
            if (widget.report.status == 'resolved' && !_isAdmin)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Laporan ini telah diselesaikan dan dikunci.',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
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
