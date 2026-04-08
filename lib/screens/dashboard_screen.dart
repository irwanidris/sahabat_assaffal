import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../cubit/reports_cubit.dart';
import '../cubit/theme_cubit.dart';
import '../models/pothole_report.dart';
import '../theme/app_theme.dart';
import '../services/share_service.dart';
import '../services/community_service.dart';
import '../services/device_service.dart';
import '../services/auth_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ShareService _shareService = ShareService();
  final CommunityService _communityService = CommunityService();
  final DeviceService _deviceService = DeviceService();
  final AuthService _authService = AuthService();
  
  final Set<String> _upvotedReports = {};

  @override
  void initState() {
    super.initState();
    context.read<ReportsCubit>().loadReports();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildGlassHeader(isDarkMode),
            _buildStatsBar(isDarkMode),
            Expanded(
              child: BlocBuilder<ReportsCubit, ReportsState>(
                builder: (context, state) {
                  if (state is ReportsLoading) return const Center(child: CircularProgressIndicator());
                  if (state is ReportsError) return _buildErrorState(isDarkMode);
                  if (state is ReportsLoaded) {
                    if (state.reports.isEmpty) return _buildEmptyState(isDarkMode);
                    return RefreshIndicator(
                      onRefresh: () => context.read<ReportsCubit>().refreshReports(),
                      color: AppTheme.primaryRed,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                        itemCount: state.reports.length,
                        itemBuilder: (context, index) => _buildReportCard(state.reports[index], isDarkMode, index),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassHeader(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppTheme.primaryRed, AppTheme.primaryBlue]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.dashboard_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87)),
                    Text('Sayangi Tungku, Selamatkan Tungku', style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600)),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => context.read<ThemeCubit>().toggleTheme(),
                  icon: Icon(isDarkMode ? Icons.wb_sunny_rounded : Icons.nightlight_round, color: isDarkMode ? Colors.amber : Colors.indigo),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsBar(bool isDarkMode) {
    return BlocBuilder<ReportsCubit, ReportsState>(
      builder: (context, state) {
        int total = 0, pending = 0, resolved = 0;
        if (state is ReportsLoaded) {
          total = state.reports.length;
          pending = state.reports.where((r) => r.status != 'resolved').length;
          resolved = state.reports.where((r) => r.status == 'resolved').length;
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTheme.primaryRed, AppTheme.primaryBlue]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Jumlah', total.toString(), Icons.flag_rounded),
                _buildStatItem('Proses', pending.toString(), Icons.pending_actions_rounded),
                _buildStatItem('Selesai', resolved.toString(), Icons.check_circle_rounded),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Row(children: [Icon(icon, size: 18, color: Colors.white70), const SizedBox(width: 6), Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white))]),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70)),
      ],
    );
  }

  Widget _buildReportCard(PotholeReport report, bool isDarkMode, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: CachedNetworkImage(imageUrl: report.imageUrl, height: 180, width: double.infinity, fit: BoxFit.cover),
                ),
                Positioned(top: 14, right: 14, child: _buildStatusBadge(report.status)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(report.areaName ?? 'Kawasan Tidak Diketahui', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87)),
                  const SizedBox(height: 8),
                  Row(children: [Icon(Icons.place_rounded, size: 14, color: Colors.grey), const SizedBox(width: 6), Expanded(child: Text(report.address ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis))]),
                  const Divider(height: 30),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(_formatDate(report.createdAt), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      const Spacer(),
                      _buildActionRow(report, isDarkMode),
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

  Widget _buildActionRow(PotholeReport report, bool isDarkMode) {
    return Row(
      children: [
        IconButton(icon: const Icon(Icons.thumb_up_outlined, size: 18), onPressed: () => _communityService.toggleUpvote(report.id)),
        Text('${report.upvoteCount}', style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 10),
        IconButton(icon: const Icon(Icons.chat_bubble_outline, size: 18), onPressed: () => _showCommentsSheet(report, isDarkMode)),
        Text('${report.commentCount}', style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 10),
        IconButton(icon: const Icon(Icons.share_outlined, size: 18), onPressed: () => _shareService.shareReport(report)),
      ],
    );
  }

  void _showCommentsSheet(PotholeReport report, bool isDarkMode) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CommentsSheet(report: report, isDarkMode: isDarkMode),
    );
    if (mounted) {
      context.read<ReportsCubit>().refreshReports();
    }
  }

  Widget _buildStatusBadge(String status) {
    final isResolved = status == 'resolved';
    String label = isResolved ? 'SELESAI' : 'PROSES';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: (isResolved ? Colors.green : Colors.orange).withOpacity(0.9), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }

  Widget _buildErrorState(bool isDarkMode) => const Center(child: Text('Gagal memuat laporan'));
  Widget _buildEmptyState(bool isDarkMode) => const Center(child: Text('Tiada laporan'));

  String _formatDate(DateTime date) {
    // Memastikan waktu dipaparkan mengikut waktu tempatan Malaysia
    return DateFormat('d MMM yyyy, h:mm a').format(date.toLocal());
  }
}

class _CommentsSheet extends StatefulWidget {
  final PotholeReport report;
  final bool isDarkMode;
  const _CommentsSheet({required this.report, required this.isDarkMode});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final TextEditingController _commentController = TextEditingController();
  final CommunityService _communityService = CommunityService();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    final data = await _communityService.getComments(widget.report.id);
    if (mounted) setState(() { _comments = data; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _authService.currentUser;
    final isAdmin = _communityService.isAdmin();

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: widget.isDarkMode ? const Color(0xFF1a1a2e) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Komen (${_comments.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const Divider(),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator()) 
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _comments.length,
                  itemBuilder: (context, i) {
                    final c = _comments[i];
                    final isOwner = c['user_id'] == currentUser?.id;
                    final canManage = isOwner || isAdmin;
                    
                    DateTime commentDate = DateTime.parse(c['created_at']).toLocal();
                    return ListTile(
                      title: Text(c['user_name'] ?? 'Pengguna', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(c['content'] ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(DateFormat('d/M H:mm').format(commentDate), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          if (canManage)
                            _buildCommentOptions(c, isOwner),
                        ],
                      ),
                    );
                  },
                ),
          ),
          if (currentUser != null)
            _buildInputArea()
          else
            _buildLoginPrompt(),
        ],
      ),
    );
  }

  Widget _buildCommentOptions(Map<String, dynamic> comment, bool isOwner) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 16, color: Colors.grey),
      padding: EdgeInsets.zero,
      onSelected: (value) {
        if (value == 'edit') {
          _showEditDialog(comment);
        } else if (value == 'delete') {
          _confirmDelete(comment['id']);
        }
      },
      itemBuilder: (context) => [
        if (isOwner)
          const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])),
        const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Padam', style: TextStyle(color: Colors.red))])),
      ],
    );
  }

  void _showEditDialog(Map<String, dynamic> comment) {
    final editController = TextEditingController(text: comment['content']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Komen', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: editController,
          maxLines: 3,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Tulis komen baru...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final newContent = editController.text.trim();
              if (newContent.isNotEmpty) {
                final success = await _communityService.updateComment(comment['id'], newContent);
                if (success && mounted) {
                  Navigator.pop(context);
                  _loadComments();
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(int commentId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Padam Komen?'),
        content: const Text('Adakah anda pasti mahu memadam komen ini? Tindakan ini tidak boleh dibatalkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          TextButton(
            onPressed: () async {
              final success = await _communityService.deleteComment(commentId);
              if (success && mounted) {
                Navigator.pop(context);
                _loadComments();
              }
            },
            child: const Text('Padam', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16, left: 16, right: 16, top: 10),
      child: Row(
        children: [
          Expanded(child: TextField(controller: _commentController, decoration: const InputDecoration(hintText: 'Tambah komen...', border: InputBorder.none))),
          IconButton(icon: const Icon(Icons.send, color: AppTheme.primaryRed), onPressed: _submitComment),
        ],
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: Colors.grey.withOpacity(0.1),
      child: const Text('Sila log masuk untuk memberi komen.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
    );
  }

  Future<void> _submitComment() async {
    if (_commentController.text.trim().isEmpty) return;
    final success = await _communityService.addComment(widget.report.id, _commentController.text);
    if (success) {
      _commentController.clear();
      _loadComments();
    }
  }
}
