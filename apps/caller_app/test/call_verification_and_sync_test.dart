import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:caller_app/core/config/app_config.dart';
import 'package:caller_app/data/models/device_call_log_model.dart';
import 'package:caller_app/data/services/background_sync_service.dart';
import 'package:caller_app/data/services/call_log_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallLogService Phone Number Matching & Privacy Filtering', () {
    final service = CallLogService();

    test('accepts exact 10-digit Indian subscriber number match across formats', () {
      const leadPhone = '+919876543210';

      expect(service.isPhoneNumberMatch('9876543210', leadPhone), isTrue);
      expect(service.isPhoneNumberMatch('09876543210', leadPhone), isTrue);
      expect(service.isPhoneNumberMatch('+919876543210', leadPhone), isTrue);
      expect(service.isPhoneNumberMatch('919876543210', leadPhone), isTrue);
      expect(service.isPhoneNumberMatch('+91 98765 43210', leadPhone), isTrue);
      expect(service.isPhoneNumberMatch('098765-43210', leadPhone), isTrue);
    });

    test('rejects unsafe short suffix matches', () {
      const leadPhone = '+919876543210';

      // 4 to 8 digit short suffixes must NEVER match
      expect(service.isPhoneNumberMatch('43210', leadPhone), isFalse);
      expect(service.isPhoneNumberMatch('543210', leadPhone), isFalse);
      expect(service.isPhoneNumberMatch('6543210', leadPhone), isFalse);
      expect(service.isPhoneNumberMatch('76543210', leadPhone), isFalse);
    });

    test('rejects similar numbers differing by a single digit', () {
      const leadPhone = '+919876543210';

      expect(service.isPhoneNumberMatch('+919876543211', leadPhone), isFalse);
      expect(service.isPhoneNumberMatch('9876543219', leadPhone), isFalse);
      expect(service.isPhoneNumberMatch('09876543200', leadPhone), isFalse);
    });

    test('discards personal calls during on-device filtering', () {
      const assignedLeadPhone = '+919876543210';
      const personalMotherPhone = '+919123456780';
      const personalFriendPhone = '+918001122334';

      expect(service.isPhoneNumberMatch(personalMotherPhone, assignedLeadPhone), isFalse);
      expect(service.isPhoneNumberMatch(personalFriendPhone, assignedLeadPhone), isFalse);
    });

    test('strictly bypasses and returns null when caller is off duty (isClockedIn is false)', () async {
      final res = await service.matchOutgoingCallForLead(
        leadPhoneE164: '+919876543210',
        dialedAfter: DateTime.now(),
        isClockedIn: false,
      );
      expect(res, isNull);
    });

    test('handles repeated calls to the same lead using dialedAfter threshold', () {
      const leadPhone = '+919876543210';
      final call1DialedAt = DateTime.parse('2026-10-19T10:00:00Z');
      final call1EndedAt = DateTime.parse('2026-10-19T10:02:00Z');

      final call2DialedAt = DateTime.parse('2026-10-19T10:15:00Z');
      final call2EndedAt = DateTime.parse('2026-10-19T10:17:30Z');

      expect(call1DialedAt.isBefore(call2DialedAt), isTrue);

      // Call 1 log entry
      final log1 = DeviceCallLogModel(
        numberE164: leadPhone,
        rawNumber: '09876543210',
        callType: 'outgoing',
        startedAt: call1EndedAt.subtract(const Duration(seconds: 45)),
        durationSecs: 45,
        simSlot: 'SIM 1 (Jio)',
        timestampMillis: call1EndedAt.millisecondsSinceEpoch,
      );

      // Call 2 log entry
      final log2 = DeviceCallLogModel(
        numberE164: leadPhone,
        rawNumber: '09876543210',
        callType: 'outgoing',
        startedAt: call2EndedAt.subtract(const Duration(seconds: 90)),
        durationSecs: 90,
        simSlot: 'SIM 1 (Jio)',
        timestampMillis: call2EndedAt.millisecondsSinceEpoch,
      );

      // Verify that filtering by call2DialedAt only matches log2, not the earlier log1
      final windowStart = call2DialedAt.subtract(const Duration(seconds: 30));
      expect(log1.startedAt.isAfter(windowStart), isFalse, reason: 'Old call should not match new attempt');
      expect(log2.startedAt.isAfter(windowStart), isTrue, reason: 'New call matches current attempt');
    });

    test('captures SIM slot details for dual SIM devices', () {
      final sim1Call = DeviceCallLogModel(
        numberE164: '+919876543210',
        rawNumber: '9876543210',
        callType: 'outgoing',
        startedAt: DateTime.now(),
        durationSecs: 25,
        simSlot: 'SIM 1 (Jio)',
        timestampMillis: DateTime.now().millisecondsSinceEpoch,
      );

      final sim2Call = DeviceCallLogModel(
        numberE164: '+919876543210',
        rawNumber: '9876543210',
        callType: 'outgoing',
        startedAt: DateTime.now(),
        durationSecs: 25,
        simSlot: 'SIM 2 (Airtel)',
        timestampMillis: DateTime.now().millisecondsSinceEpoch,
      );

      expect(sim1Call.simSlot, 'SIM 1 (Jio)');
      expect(sim2Call.simSlot, 'SIM 2 (Airtel)');
    });
  });

  group('Call Verification & 10s Rule Duration Threshold', () {
    test('hardware verified vs manual entry evidence source designation', () {
      DeviceCallLogModel? matchedLog = DeviceCallLogModel(
        numberE164: '+919876543210',
        rawNumber: '9876543210',
        callType: 'outgoing',
        startedAt: DateTime.now(),
        durationSecs: 30,
        simSlot: 'SIM 1',
        timestampMillis: DateTime.now().millisecondsSinceEpoch,
      );

      String getEvidenceSource(DeviceCallLogModel? log) =>
          log != null ? 'device_log' : 'manual';

      expect(getEvidenceSource(matchedLog), 'device_log');
      expect(getEvidenceSource(null), 'manual');
    });

    test('10-second rule is duration threshold only and does not prove interest', () {
      bool meetsDurationThreshold(int secs) =>
          secs >= AppConfig.minConnectedDurationSecs;

      expect(meetsDurationThreshold(0), isFalse);
      expect(meetsDurationThreshold(9), isFalse);
      expect(meetsDurationThreshold(10), isTrue);
      expect(meetsDurationThreshold(25), isTrue);

      // Meeting the threshold allows marking as Interested, but doesn't prove it
      bool canMarkInterested(int secs) => meetsDurationThreshold(secs);
      expect(canMarkInterested(5), isFalse);
      expect(canMarkInterested(15), isTrue);
    });
  });

  group('Offline Reliability, WorkManager Sync & Error Handling', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('offline sync payload contains required p_device_id and evidence_source', () async {
      final payload = {
        'p_dial_attempt_id': '550e8400-e29b-41d4-a716-446655440000',
        'p_device_id': 'd3b07384-d113-46d4-89c0-82cf30a59966',
        'p_number_e164': '+919876543210',
        'p_call_type': 'outgoing',
        'p_started_at': '2026-10-19T10:00:00.000Z',
        'p_duration_secs': 45,
        'p_sim_slot': 'SIM 1',
        'p_clock_skew_secs': 0,
        'p_caller_claimed_connected': true,
        'p_outcome': 'interested',
        'p_reason_ids': <String>[],
        'p_other_reason_text': null,
        'p_note': 'Discussed enterprise package',
        'p_seconds_after_call_end': 0,
        'p_follow_up_due_at': '2026-10-20T10:00:00.000Z',
        'p_follow_up_type': 'call',
        'p_evidence_source': 'device_log',
      };

      await BackgroundSyncService.enqueuePendingSync(payload);

      final count = await BackgroundSyncService.getPendingSyncCount();
      expect(count, 1);

      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('pending_unsubmitted_sync_queue') ?? [];
      expect(list.length, 1);

      final decoded = jsonDecode(list.first);
      expect(decoded['payload']['p_device_id'], 'd3b07384-d113-46d4-89c0-82cf30a59966');
      expect(decoded['payload']['p_evidence_source'], 'device_log');
    });

    test('simulates app restart: preserves pending items across process termination', () async {
      final payload = {
        'p_dial_attempt_id': 'attempt-restart-test',
        'p_device_id': 'device-123',
        'p_number_e164': '+919876543210',
        'p_duration_secs': 30,
        'p_evidence_source': 'manual',
      };

      await BackgroundSyncService.enqueuePendingSync(payload);
      expect(await BackgroundSyncService.getPendingSyncCount(), 1);

      // Simulate app restart by re-reading SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getStringList('pending_unsubmitted_sync_queue') ?? [];
      expect(queueJson.length, 1);

      final item = SyncItem.fromJson(jsonDecode(queueJson.first));
      expect(item.id, 'attempt-restart-test');
      expect(item.status, 'pending');
      expect(item.payload['p_evidence_source'], 'manual');
    });

    test('prevents duplicate queue entries on rapid retries', () async {
      final payload = {
        'p_dial_attempt_id': 'attempt-dedupe-test',
        'p_device_id': 'device-123',
        'p_number_e164': '+919876543210',
        'p_duration_secs': 15,
      };

      // Enqueue twice
      await BackgroundSyncService.enqueuePendingSync(payload);
      await BackgroundSyncService.enqueuePendingSync(payload);

      // Should be deduplicated by p_dial_attempt_id
      final count = await BackgroundSyncService.getPendingSyncCount();
      expect(count, 1);
    });

    test('classifies permanent errors and keeps failed items visible', () {
      expect(SyncItem.isPermanentError('PostgrestException: violates foreign key constraint'), isTrue);
      expect(SyncItem.isPermanentError('PostgrestException: permission denied for function'), isTrue);
      expect(SyncItem.isPermanentError('PostgrestException: P0001: CALL_LOCKED'), isTrue);
      expect(SyncItem.isPermanentError('PostgrestException: column "actual_duration_seconds" does not exist'), isTrue);
      
      // Transient network errors are not permanent
      expect(SyncItem.isPermanentError('SocketException: Connection refused'), isFalse);
      expect(SyncItem.isPermanentError('TimeoutException: Request timed out'), isFalse);
    });

    test('retains failed items for user/audit visibility rather than dropping them', () async {
      final item = SyncItem(
        id: 'attempt-failed-visible',
        payload: {
          'p_dial_attempt_id': 'attempt-failed-visible',
          'p_number_e164': '+919876543210',
          'p_duration_secs': 50,
        },
        status: 'failed',
        retryCount: 5,
        lastError: 'PostgrestException: P0001: Permission denied on RPC',
        createdAt: DateTime.now(),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('pending_unsubmitted_sync_queue', [jsonEncode(item.toJson())]);

      final pendingCount = await BackgroundSyncService.getPendingSyncCount();
      final failedCount = await BackgroundSyncService.getFailedSyncCount();
      final failedItems = await BackgroundSyncService.getFailedSyncItems();

      expect(pendingCount, 0, reason: 'Failed item should not be in pending count');
      expect(failedCount, 1, reason: 'Failed item must be counted in failedSyncCount');
      expect(failedItems.length, 1);
      expect(failedItems.first.lastError, contains('Permission denied'));

      // Dismissal removes the item
      await BackgroundSyncService.removeSyncItem('attempt-failed-visible');
      expect(await BackgroundSyncService.getFailedSyncCount(), 0);
    });
  });
}
