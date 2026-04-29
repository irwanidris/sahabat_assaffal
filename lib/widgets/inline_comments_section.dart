import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/community_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class InlineCommentsSection extends StatefulWidget {
  final String reportId;
  final CommunityService communityService;
  final bool isDarkMode;

  const InlineCommentsSection({
    super.key,
    required this.reportId,
    required this.communityService,
    required this.isDarkMode,
  });

  @override
  State<InlineCommentsSection> createState() => _InlineCommentsSectionState();
}

class _InlineCommentsSectionState extends State<InlineCommentsSection> {
  final TextEditingController _commentController = TextEditingController();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  bool _isExpanded = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    try {
      final comments = await widget.communityService.getComments(widget.reportId);
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendComment() async {
    if (_commentController.text.trim().isEmpty) return;
    setState(() => _isSending = true);
    try {
      final success = await widget.communityService.addComment(widget.reportId, _commentController.text.trim());
      if (success && mounted) {
        _commentController.clear();
        await _loadComments();
      }
    } catch (e) {
      debugPrint('Failed to send comment: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _deleteComment(int commentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Padam Komen'),
        content: const Text('Adakah anda pasti ingin memadam komen ini?'),
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
      final success = await widget.communityService.deleteComment(commentId);
      if (success) {
        _loadComments();
      }
    }
  }

  Future<void> _editComment(Map<String, dynamic> comment) async {
    final controller = TextEditingController(text: comment['content']);
    final newContent = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Komen'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Masukkan komen baru...'),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (newContent != null && newContent.trim().isNotEmpty && newContent != comment['content']) {
      final success = await widget.communityService.updateComment(comment['id'], newContent.trim());
      if (success) {
        _loadComments();
      }
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: (widget.isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.comment_outlined, size: 20, color: widget.isDarkMode ? Colors.white70 : Colors.black54),
                const SizedBox(width: 10),
                const Text('Komen', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1976D2).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_comments.length}',
                    style: const TextStyle(
                      fontSize: 12, 
                      fontWeight: FontWeight.bold, 
                      color: Color(0xFF1976D2),
                    ),
                  ),
                ),
                const Spacer(),
                Icon(_isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded),
              ],
            ),
          ),
        ),
        if (_isExpanded) ...[
          const SizedBox(height: 12),
          if (_isLoading) 
            const Center(child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ))
          else if (_comments.isEmpty) 
            const Center(child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Belum ada komen', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ))
          else 
            ..._comments.map((c) {
              final createdAt = DateTime.tryParse(c['created_at'] ?? '')?.toLocal();
              final timeStr = createdAt != null ? DateFormat('dd/MM HH:mm').format(createdAt) : '';
              final avatarUrl = c['avatar_url'] as String?;
              final isOwner = _authService.currentUser?.id == c['user_id'];
              final isAdmin = widget.communityService.isAdmin();

              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                  backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) 
                      ? NetworkImage(avatarUrl) 
                      : null,
                  child: (avatarUrl == null || avatarUrl.isEmpty)
                      ? Text(
                          (c['user_name'] ?? 'S')[0].toUpperCase(),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                        )
                      : null,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c['user_name'] ?? 'Sahabat',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    if (timeStr.isNotEmpty)
                      Text(
                        timeStr,
                        style: TextStyle(fontSize: 10, color: widget.isDarkMode ? Colors.white54 : Colors.black54),
                      ),
                  ],
                ),
                subtitle: Text(
                  c['content'] ?? '',
                  style: TextStyle(fontSize: 13, color: widget.isDarkMode ? Colors.white70 : Colors.black87),
                ),
                trailing: (isOwner || isAdmin) 
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isOwner)
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.blue),
                              onPressed: () => _editComment(c),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
                            onPressed: () => _deleteComment(c['id']),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                          ),
                        ],
                      )
                    : null,
              );
            }),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _authService.currentUser == null
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryRed.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 18, color: AppTheme.primaryRed),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Log masuk untuk memberi komen',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.primaryRed,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            try {
                              await _authService.signInWithGoogle();
                              if (mounted) setState(() {});
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Gagal Log Masuk: $e'))
                                );
                              }
                            }
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'LOG MASUK',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          style: TextStyle(color: widget.isDarkMode ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            hintText: 'Tambah komen...',
                            hintStyle: TextStyle(color: widget.isDarkMode ? Colors.white54 : Colors.black54),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            filled: true,
                            fillColor: (widget.isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
                            border: OutlineInputBorder(
                              borderRadius: const BorderRadius.all(Radius.circular(12)),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: const BorderRadius.all(Radius.circular(12)),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: const BorderRadius.all(Radius.circular(12)),
                              borderSide: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.5)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: _isSending
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send_rounded, color: AppTheme.primaryBlue),
                        onPressed: _isSending ? null : _sendComment,
                      ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}
