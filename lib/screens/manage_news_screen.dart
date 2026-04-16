import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';

class ManageNewsScreen extends StatefulWidget {
  const ManageNewsScreen({super.key});

  @override
  State<ManageNewsScreen> createState() => _ManageNewsScreenState();
}

class _ManageNewsScreenState extends State<ManageNewsScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _allNews = [];

  @override
  void initState() {
    super.initState();
    _fetchAllNews();
  }

  Future<void> _fetchAllNews() async {
    setState(() => _isLoading = true);
    final news = await _supabaseService.fetchNews(approvedOnly: false);
    setState(() {
      _allNews = news;
      _isLoading = false;
    });
  }

  Future<void> _handleStatusUpdate(dynamic id, String status) async {
    try {
      final String stringId = id.toString();
      debugPrint('UI: Update status for $stringId to $status');
      await _supabaseService.updateNewsStatus(stringId, status);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'approved' ? 'Berita telah diluluskan!' : 'Berita telah ditolak.'),
            backgroundColor: status == 'approved' ? Colors.green : Colors.orange,
          ),
        );
        _fetchAllNews();
      }
    } catch (e) {
      debugPrint('UI Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleDelete(dynamic id) async {
    final TextEditingController deleteController = TextEditingController();
    bool canDelete = false;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Padam Berita?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tindakan ini tidak boleh diundur. Sila tulis \'Padam\' untuk pengesahan:'),
                const SizedBox(height: 12),
                TextField(
                  controller: deleteController,
                  decoration: const InputDecoration(
                    hintText: 'Taip Padam di sini',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      canDelete = value.trim().toLowerCase() == 'padam';
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              IconButton(
                onPressed: canDelete ? () => Navigator.pop(context, true) : null,
                icon: Icon(
                  Icons.check_circle,
                  color: canDelete ? Colors.red : Colors.grey,
                  size: 32,
                ),
              ),
            ],
          );
        }
      ),
    );

    if (confirm == true) {
      try {
        final String stringId = id.toString();
        await _supabaseService.deleteNews(stringId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Berita telah dipadam sepenuhnya.'), backgroundColor: Colors.black),
          );
          _fetchAllNews();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memadam: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Filter news based on status
    final pendingNews = _allNews.where((n) => n['status'] == 'pending').toList();
    final approvedNews = _allNews.where((n) => n['status'] == 'approved').toList();
    final rejectedNews = _allNews.where((n) => n['status'] == 'rejected').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Urus Kelulusan Berita'),
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchAllNews,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pendingNews.isNotEmpty) ...[
                      _buildSectionHeader('Menunggu Kelulusan', Colors.red, Icons.pending_actions),
                      const SizedBox(height: 12),
                      ...pendingNews.map((news) => _buildNewsCard(news, isDarkMode)),
                      const SizedBox(height: 24),
                    ],
                    if (approvedNews.isNotEmpty) ...[
                      _buildSectionHeader('Telah Diluluskan', Colors.blue, Icons.check_circle_outline),
                      const SizedBox(height: 12),
                      ...approvedNews.map((news) => _buildNewsCard(news, isDarkMode)),
                      const SizedBox(height: 24),
                    ],
                    if (rejectedNews.isNotEmpty) ...[
                      _buildSectionHeader('Perlu Kemaskini (Ditolak)', Colors.orange, Icons.edit_note),
                      const SizedBox(height: 12),
                      ...rejectedNews.map((news) => _buildNewsCard(news, isDarkMode)),
                      const SizedBox(height: 24),
                    ],
                    if (_allNews.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: 100),
                          child: Text('Tiada rekod berita ditemui.'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, Color color, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildNewsCard(Map<String, dynamic> news, bool isDarkMode) {
    final status = news['status'] as String;
    final bool isPending = status == 'pending';
    final bool isApproved = status == 'approved';
    final bool isRejected = status == 'rejected';

    Color baseColor;
    if (isPending) {
      baseColor = Colors.red;
    } else if (isApproved) {
      baseColor = Colors.blue;
    } else {
      baseColor = Colors.orange;
    }

    final DateTime date = DateTime.parse(news['created_at']);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: baseColor.withOpacity(isDarkMode ? 0.15 : 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: baseColor.withOpacity(0.3), width: 2),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: baseColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPending ? Icons.warning_amber_rounded : (isApproved ? Icons.check_circle_rounded : Icons.edit_note_rounded),
              color: baseColor,
              size: 24,
            ),
          ),
          title: Text(
            news['title'] ?? 'Tiada Tajuk',
            style: TextStyle(
              fontWeight: FontWeight.bold, 
              fontSize: 16,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          subtitle: Text(
            'Oleh: ${news['author']} • ${DateFormat('dd MMM, HH:mm').format(date)}',
            style: TextStyle(
              fontSize: 12,
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.black26 : Colors.white70,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (news['image_url'] != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        news['image_url'],
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 100,
                          width: double.infinity,
                          color: Colors.grey.withOpacity(0.2),
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text(
                    'Kandungan Berita:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    news['content'] ?? '',
                    style: const TextStyle(fontSize: 14, height: 1.6),
                  ),
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Butang Hapus (Simbol sahaja)
                      IconButton(
                        onPressed: () => _handleDelete(news['id']),
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                        tooltip: 'Hapus',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red.withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const Spacer(),
                      // Butang Luluskan (Simbol sahaja)
                      if (isPending || isRejected) ...[
                        IconButton(
                          onPressed: () => _handleStatusUpdate(news['id'], 'approved'),
                          icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
                          tooltip: 'Luluskan',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      // Butang Tolak (Simbol sahaja)
                      if (isPending)
                        IconButton(
                          onPressed: () => _handleStatusUpdate(news['id'], 'rejected'),
                          icon: const Icon(Icons.cancel_rounded, color: Colors.white),
                          tooltip: 'Tolak',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.orange.shade700,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
