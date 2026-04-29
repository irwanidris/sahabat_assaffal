import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';

class AdminChatScreen extends StatefulWidget {
  const AdminChatScreen({super.key});

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  RealtimeChannel? _channel;
  List<String> _typingUsers = [];
  Timer? _typingTimer;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _setupRealtime();
  }

  void _setupRealtime() {
    final user = _authService.currentUser;
    final String userName = user?.userMetadata?['full_name'] ?? 'Admin';

    _channel = Supabase.instance.client.channel('public:admin_chats');

    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'admin_chats',
          callback: (payload) {
            _loadMessages();
          },
        )
        .onPresenceSync((payload) {
          final dynamic newState = _channel!.presenceState();
          final List<String> typing = [];

          try {
            if (newState is Map) {
              newState.forEach((key, value) {
                final List presences = value as List;
                for (final p in presences) {
                  final dynamic presence = p;
                  if (presence.payload['is_typing'] == true && presence.payload['user_id'] != user?.id) {
                    typing.add(presence.payload['user_name'] as String);
                  }
                }
              });
            } else if (newState is Iterable) {
              for (final dynamic p in newState) {
                final dynamic presence = p;
                if (presence.payload['is_typing'] == true && presence.payload['user_id'] != user?.id) {
                  typing.add(presence.payload['user_name'] as String);
                }
              }
            }
          } catch (e) {
            debugPrint('Error parsing presence: $e');
          }

          if (mounted) {
            setState(() {
              _typingUsers = typing.toSet().toList();
            });
          }
        })
        .subscribe((status, [error]) async {
          debugPrint('Sembang Realtime Status: $status');
          if (error != null) debugPrint('Sembang Realtime Error: $error');

          if (status == RealtimeSubscribeStatus.subscribed) {
            await _channel!.track({
              'user_id': user?.id,
              'user_name': userName,
              'is_typing': false,
            });
          }
        });
  }

  void _onTyping(String text) {
    if (!_isTyping && text.isNotEmpty) {
      _setTypingStatus(true);
    } else if (_isTyping && text.isEmpty) {
      _setTypingStatus(false);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_isTyping) _setTypingStatus(false);
    });
  }

  Future<void> _setTypingStatus(bool typing) async {
    final user = _authService.currentUser;
    final String userName = user?.userMetadata?['full_name'] ?? 'Admin';

    _isTyping = typing;
    if (_channel != null) {
      await _channel!.track({
        'user_id': user?.id,
        'user_name': userName,
        'is_typing': typing,
      });
    }
  }

  Future<void> _loadMessages() async {
    try {
      final data = await Supabase.instance.client
          .from('admin_chats')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      
      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading messages: $e');
    }
  }

  Future<void> _pickAndUploadImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (image == null) return;

    setState(() => _isSending = true);

    try {
      final String imageUrl = await _supabaseService.uploadImage(File(image.path));
      await _sendMessage(imageUrl: imageUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat naik gambar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendMessage({String? imageUrl}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty && imageUrl == null) return;

    if (imageUrl == null) {
      _messageController.clear();
      _setTypingStatus(false);
    }
    
    final user = _authService.currentUser;
    if (user == null) return;

    String role = 'User';
    if (user.userMetadata?['is_yb'] == true) role = 'Penaung';
    else if (user.userMetadata?['is_admin'] == true) role = 'Admin';
    else if (user.userMetadata?['is_moderator'] == true) role = 'Moderator';

    try {
      await Supabase.instance.client.from('admin_chats').insert({
        'message': text,
        'sender_name': user.userMetadata?['full_name'] ?? 'Admin',
        'sender_role': role,
        'user_id': user.id,
        'image_url': imageUrl,
      });

      // Muat semula mesej serta-merta untuk kelancaran UI
      _loadMessages();

      // Hantar notifikasi kepada Admin/Moderator lain
      await _supabaseService.sendChatNotification(
        senderName: user.userMetadata?['full_name'] ?? 'Seseorang',
        message: imageUrl != null ? '📷 Menghantar gambar' : text,
        senderUserId: user.id,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghantar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> msg) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Padam ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Tidak')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ya', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _deleteMessage(msg);
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> msg) async {
    try {
      final currentUser = _authService.currentUser;
      final bool isSuperAdmin = currentUser?.userMetadata?['is_admin'] == true;
      final bool isMe = msg['user_id'] == currentUser?.id;

      String deleteNote;
      if (isSuperAdmin && !isMe) {
        deleteNote = 'Admin telah memadam mesej.';
      } else {
        final String nickname = msg['sender_name'] ?? 'Sahabat';
        deleteNote = '$nickname telah memadam mesej.';
      }

      await Supabase.instance.client
          .from('admin_chats')
          .update({
            'message': deleteNote,
            'image_url': null,
            'is_deleted': true,
          })
          .eq('id', msg['id']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memadam mesej: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final currentUser = _authService.currentUser;

    return Scaffold(
      backgroundColor: isDarkMode ? AppTheme.darkBackground : const Color(0xFFFFF9C4), // Kuning lembut (Lemon Chiffon/Light Yellow)
      body: SafeArea(
        child: Column(
          children: [
            _buildGlassHeader(isDarkMode),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      children: [
                        _messages.isEmpty
                            ? const Center(child: Text('Tiada mesej lagi. Mula bersembang!'))
                            : ListView.builder(
                                controller: _scrollController,
                                reverse: true,
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  final msg = _messages[index];
                                  final bool isMe = msg['user_id'] == currentUser?.id;
                                  
                                  // Logik Paparan Tarikh
                                  bool showDateHeader = false;
                                  if (index == _messages.length - 1) {
                                    showDateHeader = true;
                                  } else {
                                    final DateTime currentDate = DateTime.parse(msg['created_at']).toLocal();
                                    final DateTime nextDate = DateTime.parse(_messages[index + 1]['created_at']).toLocal();
                                    if (currentDate.day != nextDate.day || 
                                        currentDate.month != nextDate.month || 
                                        currentDate.year != nextDate.year) {
                                      showDateHeader = true;
                                    }
                                  }

                                  return Column(
                                    children: [
                                      if (showDateHeader) _buildDateHeader(msg['created_at'], isDarkMode),
                                      _buildChatBubble(msg, isMe, isDarkMode),
                                    ],
                                  );
                                },
                              ),
                        if (_typingUsers.isNotEmpty)
                          Positioned(
                            bottom: 8,
                            left: 20,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDarkMode ? Colors.black54 : Colors.white70,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryRed.withOpacity(0.5)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "${_typingUsers.join(', ')} sedang menaip...",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontStyle: FontStyle.italic,
                                      color: isDarkMode ? Colors.white70 : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            _buildMessageInput(isDarkMode),
          ],
        ),
      ),
    );
  }

  String _getFormattedDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr).toUtc().add(const Duration(hours: 8));
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final msgDate = DateTime(date.year, date.month, date.day);

      if (msgDate == today) {
        return 'HARI INI';
      } else if (msgDate == yesterday) {
        return 'SEMALAM';
      } else {
        return DateFormat('dd MMMM yyyy').format(date).toUpperCase();
      }
    } catch (e) {
      return '';
    }
  }

  Widget _buildDateHeader(String dateStr, bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _getFormattedDate(dateStr),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: isDarkMode ? Colors.white54 : Colors.black54,
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
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.report_problem),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'ChatRoom',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'For Admin & Moderator Only',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatBubble(Map<String, dynamic> msg, bool isMe, bool isDarkMode) {
    final bool isDeleted = msg['is_deleted'] == true;
    final user = _authService.currentUser;
    final bool isSuperAdmin = user?.userMetadata?['is_admin'] == true;
    
    // Super Admin boleh padam mana-mana mesej, user biasa hanya boleh padam mesej sendiri
    final bool canDelete = (isMe || isSuperAdmin) && !isDeleted;

    final Color roleColor = msg['sender_role'] == 'Penaung' 
        ? const Color(0xFFD4AF37) 
        : (msg['sender_role'] == 'Admin' ? Colors.blue : Colors.orange);

    final String? imageUrl = msg['image_url'];

    return GestureDetector(
      onLongPress: canDelete ? () => _confirmDelete(msg) : null,
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDeleted 
                ? (isDarkMode ? Colors.grey.withOpacity(0.1) : Colors.grey.shade200)
                : (isMe 
                    ? AppTheme.primaryRed 
                    : (isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white)),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 0),
              bottomRight: Radius.circular(isMe ? 0 : 16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: isDeleted 
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.remove_circle_outline, size: 14, color: isDarkMode ? Colors.white54 : Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    msg['message'] ?? 'Mesej telah dipadam',
                    style: TextStyle(
                      color: isDarkMode ? Colors.white54 : Colors.grey,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          msg['sender_name'] ?? 'Unknown',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: roleColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            msg['sender_role'] ?? 'User',
                            style: TextStyle(color: roleColor, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (imageUrl != null && imageUrl.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        placeholder: (context, url) => const SizedBox(
                          height: 200,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, url, error) => const Icon(Icons.error),
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (msg['message'] != null && msg['message'].toString().isNotEmpty)
                    Text(
                      msg['message'] ?? '',
                      style: TextStyle(
                        color: isMe ? Colors.white : (isDarkMode ? Colors.white : Colors.black87),
                        fontSize: 14,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      DateFormat('HH:mm').format(DateTime.parse(msg['created_at']).toUtc().add(const Duration(hours: 8))),
                      style: TextStyle(
                        color: isMe ? Colors.white70 : Colors.grey,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }

  Widget _buildMessageInput(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? AppTheme.darkSurface : const Color(0xFFFFF9C4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          )
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.add_photo_alternate_rounded, 
              color: isDarkMode ? Colors.white70 : Colors.grey.shade600),
            onPressed: _isSending ? null : _pickAndUploadImage,
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              enabled: !_isSending,
              onChanged: _onTyping,
              decoration: InputDecoration(
                hintText: _isSending ? 'Menghantar gambar...' : 'Tulis mesej...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          _isSending 
            ? const SizedBox(width: 40, height: 40, child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2)))
            : CircleAvatar(
                backgroundColor: AppTheme.primaryRed,
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  onPressed: () => _sendMessage(),
                ),
              ),
        ],
      ),
    );
  }
}
