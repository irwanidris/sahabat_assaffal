import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/assaffal_report.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

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
  final TextEditingController _commentController = TextEditingController();
  DateTime? _incidentDateTime;
  bool _isLoading = false;
  final SupabaseService _supabaseService = SupabaseService();
  
  bool _isAdmin = false;
  bool _isModerator = false;
  String? _currentUserId;
  List<Map<String, dynamic>> _comments = [];

  @override
  void initState() {
    super.initState();
    _areaNameController = TextEditingController(text: widget.report.areaName);
    _descriptionController = TextEditingController(text: widget.report.description);
    _dateTimeController = TextEditingController(text: widget.report.duration);
    _departmentController = TextEditingController(text: widget.report.department);
    
    _checkPermissions();
    _loadComments();
    
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
        _currentUserId = user.id;
        _isAdmin = user.userMetadata?['is_admin'] == true;
        _isModerator = user.userMetadata?['is_moderator'] == true;
      });
    }
  }

  Future<void> _loadComments() async {
    try {
      final comments = await _supabaseService.fetchComments(widget.report.id);
      if (mounted) {
        setState(() {
          _comments = comments;
        });
      }
    } catch (e) {
      debugPrint('Error loading comments: $e');
    }
  }

  Future<void> _addComment() async {
    if (_commentController.text.trim().isEmpty) return;

    try {
      await _supabaseService.addComment(widget.report.id, _commentController.text.trim());
      _commentController.clear();
      _loadComments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _editComment(Map<String, dynamic> comment) async {
    final editCtrl = TextEditingController(text: comment['comment']);
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Komen'),
        content: TextField(
          controller: editCtrl,
          maxLines: 3,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (confirm == true && editCtrl.text.trim().isNotEmpty) {
      try {
        await _supabaseService.updateComment(comment['id'], editCtrl.text.trim());
        _loadComments();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _deleteComment(dynamic commentId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Padam Komen?'),
        content: const Text('Adakah anda pasti mahu memadam komen ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Padam', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabaseService.deleteComment(commentId);
        _loadComments();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
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
      await _supabaseService.updateReportData(widget.report.id, {
        if (_isAdmin) 'area_name': _areaNameController.text.trim(),
        if (_isAdmin) 'description': _descriptionController.text.trim(),
        if (_isAdmin) 'duration': _dateTimeController.text,
        if (_isAdmin) 'edit_count': widget.report.editCount + 1,
        if (_isModerator || _isAdmin) 'department': _departmentController.text.trim(),
      });

      if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Maklumat Laporan'),
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Paparan Info Status (Read Only)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Status: ${widget.report.status.toUpperCase()}\n(Status kini ditentukan oleh verifikasi komuniti)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            const Text('Gambar Laporan', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                widget.report.imageUrl,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
              ),
            ),
            const SizedBox(height: 24),

            if (_isAdmin || _isModerator) ...[
              const Text('Maklumat Pentadbiran', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              const SizedBox(height: 15),

              // JABATAN / AGENSI
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
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text('Komen & Perbincangan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            // Input Komen
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Tulis komen anda...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _addComment,
                  icon: const Icon(Icons.send, color: AppTheme.primaryRed),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Senarai Komen
            _comments.isEmpty
                ? const Center(child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text('Tiada komen lagi. Jadilah yang pertama!'),
                  ))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _comments.length,
                    itemBuilder: (context, index) {
                      final comment = _comments[index];
                      final bool isMyComment = comment['user_id'] == _currentUserId;
                      final bool canManage = isMyComment || _isAdmin;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.withOpacity(0.1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      comment['sender_name'] ?? 'Sahabat',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: (comment['sender_role'] == 'Penaung' ? Colors.amber : Colors.blue).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        comment['sender_role'] ?? 'User',
                                        style: TextStyle(
                                          color: comment['sender_role'] == 'Penaung' ? Colors.amber.shade800 : Colors.blue,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (canManage)
                                  Row(
                                    children: [
                                      if (isMyComment)
                                        IconButton(
                                          icon: const Icon(Icons.edit_note, size: 20, color: Colors.blue),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _editComment(comment),
                                        ),
                                      const SizedBox(width: 10),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => _deleteComment(comment['id']),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(comment['comment'] ?? '', style: const TextStyle(fontSize: 14)),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('dd/MM HH:mm').format(DateTime.parse(comment['created_at']).toLocal()),
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            const SizedBox(height: 40),
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
