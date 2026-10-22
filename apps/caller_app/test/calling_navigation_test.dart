import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:caller_app/ui/view_models/calling_view_model.dart';
import 'package:caller_app/data/models/lead_model.dart';
import 'package:caller_app/data/models/reason_model.dart';
import 'package:caller_app/data/repositories/calling_repository.dart';
import 'package:caller_app/data/repositories/lead_repository.dart';
import 'package:caller_app/data/repositories/reason_repository.dart';
import 'package:caller_app/data/services/call_launcher_service.dart';
import 'package:caller_app/data/services/call_log_service.dart';
import 'package:caller_app/data/models/device_call_log_model.dart';
import 'package:caller_app/data/services/storage_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Mock implementations for unit test isolation
class MockCallingRepository extends CallingRepository {
  MockCallingRepository(StorageService storageService)
      : super(SupabaseClient('https://mock.supabase.co', 'anon-key'), storageService);

  @override
  String get deviceId => 'test-device-uuid';

  @override
  Future<Map<String, dynamic>> startDialAttempt({required String leadId}) async {
    return {
      'success': true,
      'dial_attempt_id': 'mock-attempt-123',
    };
  }

  @override
  Future<Map<String, dynamic>> submitCallDialog({
    required String dialAttemptId,
    required String numberE164,
    required DateTime startedAt,
    required int durationSecs,
    String? simSlot,
    required bool callerClaimedConnected,
    required String outcome,
    required List<String> reasonIds,
    String? otherReasonText,
    String? note,
    int? secondsAfterCallEnd,
    DateTime? followUpDueAt,
    String? followUpType,
    String evidenceSource = 'device_log',
  }) async {
    return {
      'success': true,
      'call_id': 'mock-call-id',
      'disposition_id': 'mock-disp-id',
      'evidence_source': evidenceSource,
    };
  }

  bool isClockedInMock = false;

  @override
  Future<Map<String, dynamic>> clockIn() async {
    isClockedInMock = true;
    return {
      'success': true,
      'session_id': 'mock-session-123',
    };
  }

  @override
  Future<Map<String, dynamic>> clockOut({String? sessionId}) async {
    isClockedInMock = false;
    return {
      'success': true,
      'duration_seconds': 120,
    };
  }

  @override
  Future<Map<String, dynamic>> getCallerWorkStatus() async {
    return {
      'is_clocked_in': isClockedInMock,
      'current_session_id': isClockedInMock ? 'mock-session-123' : null,
      'active_seconds_today': isClockedInMock ? 120 : 0,
      'quota_target_seconds': 7200,
      'quota_met': false,
    };
  }
}

class MockLeadRepository extends LeadRepository {
  MockLeadRepository() : super(SupabaseClient('https://mock.supabase.co', 'anon-key'));

  @override
  Future<LeadModel?> getLeadById(String id) async => null;
}

class MockReasonRepository extends ReasonRepository {
  MockReasonRepository() : super(SupabaseClient('https://mock.supabase.co', 'anon-key'));

  @override
  Future<List<ReasonModel>> fetchActiveReasons() async => [];
}

class MockCallLauncherService extends CallLauncherService {
  @override
  Future<bool> launchDialer(String numberE164) async => true;
}

class MockCallLogService extends CallLogService {
  int matchCallCount = 0;

  @override
  Future<DeviceCallLogModel?> matchOutgoingCallForLead({
    required String leadPhoneE164,
    required DateTime dialedAfter,
    bool isClockedIn = true,
    Duration timeout = const Duration(seconds: 15),
    Duration interval = const Duration(milliseconds: 1500),
    void Function(int secondsRemaining)? onProgress,
  }) async {
    if (!isClockedIn) return null;
    matchCallCount++;
    return DeviceCallLogModel(
      numberE164: leadPhoneE164,
      rawNumber: leadPhoneE164,
      callType: 'outgoing',
      startedAt: dialedAfter,
      durationSecs: 42,
      simSlot: 'SIM 1',
      timestampMillis: dialedAfter.millisecondsSinceEpoch,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallingViewModel Navigation & Cancellation Tests', () {
    late CallingViewModel callingVm;
    late MockCallLogService mockCallLogService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'device_local_id': 'test-device-uuid'});
      final prefs = await SharedPreferences.getInstance();
      final storageService = StorageService(prefs);
      mockCallLogService = MockCallLogService();

      callingVm = CallingViewModel(
        MockCallingRepository(storageService),
        MockLeadRepository(),
        MockReasonRepository(),
        MockCallLauncherService(),
        mockCallLogService,
      );
    });

    test('initiateCall blocks call and prompts Work Login Required when off-duty', () async {
      final lead = LeadModel(
        id: 'lead-123',
        name: 'John Doe',
        phoneE164: '+919876543210',
        status: 'assigned',
        createdAt: DateTime.now(),
      );

      expect(callingVm.isClockedIn, false);
      final success = await callingVm.initiateCall(lead);
      expect(success, false);
      expect(callingVm.isCallLocked, false);
      expect(callingVm.errorMessage, contains('Work Login Required'));
    });

    test('clockIn and clockOut properly transition duty status and allow/disallow calls', () async {
      final lead = LeadModel(
        id: 'lead-123',
        name: 'John Doe',
        phoneE164: '+919876543210',
        status: 'assigned',
        createdAt: DateTime.now(),
      );

      // 1. Clock in
      final clockInSuccess = await callingVm.clockIn();
      expect(clockInSuccess, true);
      expect(callingVm.isClockedIn, true);

      // 2. Call succeeds now
      final callSuccess = await callingVm.initiateCall(lead);
      expect(callSuccess, true);
      expect(callingVm.isCallLocked, true);

      callingVm.cancelOrDiscardAttempt();

      // 3. Clock out
      final clockOutSuccess = await callingVm.clockOut();
      expect(clockOutSuccess, true);
      expect(callingVm.isClockedIn, false);

      // 4. Calls blocked again
      final call2Success = await callingVm.initiateCall(lead);
      expect(call2Success, false);
      expect(callingVm.errorMessage, contains('Work Login Required'));
    });

    test('detectCallLog strictly avoids calling CallLogService when caller is off-duty', () async {
      expect(callingVm.isClockedIn, false);
      final detected = await callingVm.detectCallLog();
      expect(detected, false);
      expect(mockCallLogService.matchCallCount, 0, reason: 'CallLog must never be queried when off-duty');
    });

    test('detectCallLog queries and matches call log when caller is clocked in', () async {
      await callingVm.clockIn();
      expect(callingVm.isClockedIn, true);

      final lead = LeadModel(
        id: 'lead-123',
        name: 'John Doe',
        phoneE164: '+919876543210',
        status: 'assigned',
        createdAt: DateTime.now(),
      );
      await callingVm.initiateCall(lead);

      final detected = await callingVm.detectCallLog();
      expect(detected, true);
      expect(mockCallLogService.matchCallCount, 1, reason: 'CallLog queried when clocked in');
      expect(callingVm.matchedCallLog?.durationSecs, 42);
      expect(callingVm.callDurationSecs, 42);
    });

    test('cancelOrDiscardAttempt cleanly unlocks the call lock and resets active state', () async {
      callingVm.setClockedInForTesting(true);

      // 1. Manually initiate call simulation
      final lead = LeadModel(
        id: 'lead-123',
        name: 'John Doe',
        phoneE164: '+919876543210',
        status: 'assigned',
        createdAt: DateTime.now(),
      );

      final success = await callingVm.initiateCall(lead);
      expect(success, true);
      expect(callingVm.isCallLocked, true);
      expect(callingVm.activeLead?.name, 'John Doe');
      expect(callingVm.activeAttempt?.id, 'mock-attempt-123');

      // 2. User presses Back or Discard & Exit from /dialog or /calling
      callingVm.cancelOrDiscardAttempt();

      // 3. Verify state is completely unlocked
      expect(callingVm.isCallLocked, false);
      expect(callingVm.activeAttempt, isNull);
      expect(callingVm.activeLead, isNull);
      expect(callingVm.matchedCallLog, isNull);
      expect(callingVm.errorMessage, isNull);
    });

    test('Mark Call Not Placed sets duration to 0 and outcome to notPlaced', () {
      callingVm.setDurationSecs(45);
      callingVm.setOutcome(PostCallOutcome.interested);

      expect(callingVm.callDurationSecs, 45);
      expect(callingVm.outcome, PostCallOutcome.interested);

      // Caller clicks "Mark Call Not Placed"
      callingVm.setDurationSecs(0);
      callingVm.setOutcome(PostCallOutcome.notPlaced);

      expect(callingVm.callDurationSecs, 0);
      expect(callingVm.outcome, PostCallOutcome.notPlaced);
      expect(callingVm.isConnected, false);
    });

    test('Gracefully prevents submitDialog when activeAttempt or activeLead is null', () async {
      // Calling submit without any active attempt
      final result = await callingVm.submitDialog();
      expect(result, false);
      expect(callingVm.errorMessage, contains('No active dial attempt'));
    });
  });
}
