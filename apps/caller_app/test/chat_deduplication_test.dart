import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> deduplicateChatMessages(List<Map<String, dynamic>> raw) {
  final uniqueMap = <String, Map<String, dynamic>>{};
  for (final msg in raw) {
    final id = msg['id']?.toString() ?? '';
    if (id.isNotEmpty) {
      uniqueMap[id] = msg;
    }
  }
  return uniqueMap.values.toList()
    ..sort((a, b) {
      final aTime = a['created_at']?.toString() ?? '';
      final bTime = b['created_at']?.toString() ?? '';
      return aTime.compareTo(bTime);
    });
}

void main() {
  group('Chat Deduplication & Moderation Verification', () {
    final msg1 = {
      'id': 'msg-001',
      'sender_id': 'caller-uuid-1',
      'sender_name': 'ekanth',
      'sender_role': 'caller',
      'content': 'Hey what are you guys doing?',
      'is_announcement': false,
      'is_edited': false,
      'created_at': '2026-10-18T15:19:36.826Z',
    };

    final msg2 = {
      'id': 'msg-002',
      'sender_id': 'caller-uuid-2',
      'sender_name': 'nishchal',
      'sender_role': 'caller',
      'content': 'Hii',
      'is_announcement': false,
      'is_edited': false,
      'created_at': '2026-10-19T19:58:10.194Z',
    };

    final msg3Announcement = {
      'id': 'msg-003',
      'sender_id': 'owner-uuid-1',
      'sender_name': 'Owner Admin',
      'sender_role': 'owner',
      'content': 'Important team announcement',
      'is_announcement': true,
      'is_edited': true,
      'created_at': '2026-10-19T20:00:17.302Z',
    };

    test('deduplicates duplicate messages emitted by Realtime Stream', () {
      // Simulate the bug where employee message was emitted twice by Realtime / initial fetch
      final streamWithDuplicates = [
        msg1,
        msg2,
        Map<String, dynamic>.from(msg2), // duplicate
        Map<String, dynamic>.from(msg2), // second duplicate
        msg3Announcement,
      ];

      expect(streamWithDuplicates.length, 5);

      final deduped = deduplicateChatMessages(streamWithDuplicates);

      // Exactly 3 unique messages must be returned
      expect(deduped.length, 3);
      expect(deduped[0]['id'], 'msg-001');
      expect(deduped[1]['id'], 'msg-002');
      expect(deduped[2]['id'], 'msg-003');
    });

    test('retains is_edited flag when message is updated by admin', () {
      final updatedMsg = {
        ...msg2,
        'content': 'Hii (moderated)',
        'is_edited': true,
      };

      final streamWithUpdate = [
        msg1,
        updatedMsg,
        msg3Announcement,
      ];

      final deduped = deduplicateChatMessages(streamWithUpdate);
      expect(deduped[1]['is_edited'], true);
      expect(deduped[1]['content'], 'Hii (moderated)');
    });

    test('correctly preserves chronological ordering by created_at', () {
      final outOfOrder = [
        msg3Announcement,
        msg1,
        msg2,
      ];

      final sorted = deduplicateChatMessages(outOfOrder);
      expect(sorted[0]['id'], 'msg-001');
      expect(sorted[1]['id'], 'msg-002');
      expect(sorted[2]['id'], 'msg-003');
    });
  });
}
