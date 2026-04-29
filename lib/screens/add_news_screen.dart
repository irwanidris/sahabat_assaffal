import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class AddNewsScreen extends StatefulWidget {
  final String authorName;
  final Map<String, dynamic>? newsToEdit;
  const AddNewsScreen({super.key, required this.authorName, this.newsToEdit});

  @override
  State<AddNewsScreen> createState() => _AddNewsScreenState();
}

class _AddNewsScreenState extends State<AddNewsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  final SupabaseService _supabaseService = SupabaseService();
  
  late String _selectedCategory;
  final List<String> _categories = [
    'Berita Semasa',
    'Berita Tungku',
    'Pengumuman',
    'Blog Pilihan',
  ];

  File? _selectedImage;
  String? _existingImageUrl;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.newsToEdit?['title'] ?? '');
    _contentController = TextEditingController(text: widget.newsToEdit?['content'] ?? '');
    _selectedCategory = widget.newsToEdit?['category'] ?? 'Berita Semasa';
    _existingImageUrl = widget.newsToEdit?['image_url'];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      setState(() => _selectedImage = File(pickedFile.path));
    }
  }

  Future<void> _submitNews() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSubmitting = true);
    try {
      String? imageUrl = _existingImageUrl;
      if (_selectedImage != null) {
        imageUrl = await _supabaseService.uploadImage(_selectedImage!, applyWatermark: false);
      }

      if (widget.newsToEdit != null) {
        // Mode Edit
        await _supabaseService.updateNews(
          id: widget.newsToEdit!['id'],
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
          imageUrl: imageUrl,
          category: _selectedCategory,
          status: 'pending', // Perlu kelulusan semula jika edit
        );
        
        await _supabaseService.saveNotification(
          title: "BERITA DIKEMASKINI",
          message: "Menunggu kelulusan semula: ${_titleController.text.trim()}",
          type: 'news_pending',
          relatedId: widget.newsToEdit!['id'].toString(),
          userId: Supabase.instance.client.auth.currentUser?.id,
        );
      } else {
        // Mode Baru
        final user = Supabase.instance.client.auth.currentUser;
        await _supabaseService.createNews(
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
          imageUrl: imageUrl,
          author: widget.authorName,
          authorId: user?.id ?? '',
          category: _selectedCategory,
          status: 'pending',
        );

        await _supabaseService.saveNotification(
          title: "BERITA BARU DIHANTAR",
          message: "Menunggu kelulusan Admin: ${_titleController.text.trim()}",
          type: 'news_pending',
          userId: user?.id,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.newsToEdit != null 
              ? 'Kemaskini berjaya dihantar untuk kelulusan!' 
              : 'Berita berjaya dihantar untuk kelulusan!'), 
            backgroundColor: Colors.green
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.newsToEdit != null ? 'Edit Berita & Blog' : 'Tulis Berita & Blog'),
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: _isSubmitting 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Kategori Berita', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCategory = val);
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text('Tajuk Berita', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      hintText: 'Masukkan tajuk yang menarik...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => v == null || v.isEmpty ? 'Tajuk diperlukan' : null,
                  ),
                  const SizedBox(height: 20),
                  const Text('Gambar Berita', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      height: 180,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      ),
                      child: _selectedImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_selectedImage!, fit: BoxFit.cover),
                          )
                        : (_existingImageUrl != null 
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(_existingImageUrl!, fit: BoxFit.cover),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo_rounded, size: 40, color: Colors.grey),
                                  SizedBox(height: 8),
                                  Text('Tekan untuk pilih gambar', style: TextStyle(color: Colors.grey)),
                                ],
                              )),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '* Pastikan gambar anda dalam format landskap (nisbah 16:9) untuk paparan yang terbaik di tab Berita.',
                    style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 20),
                  const Text('Kandungan Berita', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _contentController,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText: 'Tulis isi berita atau blog di sini...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => v == null || v.isEmpty ? 'Kandungan diperlukan' : null,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _submitNews,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryRed,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        widget.newsToEdit != null ? 'Simpan Perubahan' : 'Terbitkan Sekarang', 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}
