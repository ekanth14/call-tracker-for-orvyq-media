import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;
  String? _currentUserId;
  String _currentUserName = 'Caller';
  String _currentUserRole = 'caller';

  // Persistent stream initialized once in initState to avoid duplicate channel connections
  late final Stream<List<Map<String, dynamic>>> _messagesStream;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _messagesStream = Supabase.instance.client
        .from('team_messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _currentUserId = user.id;

    try {
      final profile = await supabase
          .from('profiles')
          .select('full_name, role')
          .eq('id', user.id)
          .single();

      if (mounted) {
        setState(() {
          _currentUserName = profile['full_name'] ?? 'Caller';
          _currentUserRole = profile['role'] ?? 'caller';
        });
      }
    } catch (_) {}
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending || _currentUserId == null) return;

    // Synchronously lock sending state to prevent double-tap re-entrancy
    _isSending = true;
    setState(() {});
    _messageController.clear();

    final supabase = Supabase.instance.client;

    try {
      await supabase.from('team_messages').insert({
        'sender_id': _currentUserId,
        'sender_name': _currentUserName,
        'sender_role': _currentUserRole,
        'content': content,
        'is_announcement': false,
      });

      Future.delayed(const Duration(milliseconds: 150), _scrollToBottom);
    } catch (e) {
      if (mounted) {
        _messageController.text = content;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.forum_outlined, size: 20),
            SizedBox(width: 8),
            Text('Team Community Chat'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Stream of Messages with Primary Key Deduplication
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading chat: ${snapshot.error}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.danger),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Explicit primary-key deduplication: guarantees no duplicate bubbles occur
                final rawMessages = snapshot.data!;
                final uniqueMap = <String, Map<String, dynamic>>{};
                for (final msg in rawMessages) {
                  final id = msg['id']?.toString() ?? '';
                  if (id.isNotEmpty) {
                    uniqueMap[id] = msg;
                  }
                }

                final messages = uniqueMap.values.toList()
                  ..sort((a, b) {
                    final aTime = a['created_at']?.toString() ?? '';
                    final bTime = b['created_at']?.toString() ?? '';
                    return aTime.compareTo(bTime);
                  });

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mark_chat_unread_outlined,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No messages yet',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Say hello to the team or share a quick update!',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  );
                }

                if (messages.length != _lastMessageCount) {
                  _lastMessageCount = messages.length;
                  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['sender_id'] == _currentUserId;
                    final isAnnouncement = msg['is_announcement'] == true;
                    final isEdited = msg['is_edited'] == true;
                    final senderName = msg['sender_name'] ?? 'Unknown';
                    final senderRole = msg['sender_role'] ?? 'caller';
                    final content = msg['content'] ?? '';
                    final createdAt = msg['created_at'] != null
                        ? DateTime.tryParse(msg['created_at'])?.toLocal()
                        : null;
                    final timeStr = createdAt != null
                        ? DateFormat('h:mm a').format(createdAt)
                        : '';

                    if (isAnnouncement) {
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.campaign_rounded, color: Colors.amber, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Announcement • $senderName',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber.shade900,
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isEdited)
                                            Padding(
                                              padding: const EdgeInsets.only(right: 4),
                                              child: Text(
                                                '(edited)',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontStyle: FontStyle.italic,
                                                  color: Colors.amber.shade700,
                                                ),
                                              ),
                                            ),
                                          Text(
                                            timeStr,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.amber.shade800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    content,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.brown.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Employees/callers are strictly restricted from editing and deleting.
                    // Plain message bubble with no delete or edit action triggers.
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment:
                            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        children: [
                          Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.76,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe ? AppTheme.primary : Colors.white,
                              borderRadius: BorderRadius.circular(16).copyWith(
                                bottomRight: isMe ? const Radius.circular(2) : null,
                                bottomLeft: !isMe ? const Radius.circular(2) : null,
                              ),
                              border: isMe ? null : Border.all(color: AppTheme.border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                if (!isMe)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          senderName,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textMain,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: senderRole == 'owner'
                                                ? AppTheme.primary.withValues(alpha: 0.1)
                                                : Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            senderRole.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                              color: senderRole == 'owner'
                                                  ? AppTheme.primary
                                                  : Colors.green.shade800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Text(
                                  content,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isMe ? Colors.white : AppTheme.textMain,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isEdited)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 3),
                                        child: Text(
                                          '(edited)',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontStyle: FontStyle.italic,
                                            color: isMe ? Colors.white70 : AppTheme.textMuted,
                                          ),
                                        ),
                                      ),
                                    Text(
                                      timeStr,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: isMe ? Colors.white70 : AppTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Message Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: TextField(
                        controller: _messageController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Type a message to the team...',
                          hintStyle: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _sendMessage,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
