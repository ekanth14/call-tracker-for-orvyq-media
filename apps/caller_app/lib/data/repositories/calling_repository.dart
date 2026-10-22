import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dial_attempt_model.dart';
import '../models/stats_model.dart';
import '../services/storage_service.dart';

class CallingRepository {
  final SupabaseClient _supabase;
  final StorageService _storageService;

  CallingRepository(this._supabase, this._storageService);

  /// Checks if the current caller has an open dial attempt with no submitted dialog.
  /// Enforces client-side Call Lock (§5 & §8).
  Future<DialAttemptModel?> checkActiveCallLock() async {
    final callerId = _supabase.auth.currentUser?.id;
    if (callerId == null) return null;

    final response = await _supabase
        .from('dial_attempts')
        .select('*')
        .eq('caller_id', callerId)
        .eq('status', 'open')
        .order('dialed_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return DialAttemptModel.fromJson(response);
  }

  /// Initiates a dial attempt on the server, enforcing server-side call lock and lead ownership.
  Future<Map<String, dynamic>> startDialAttempt({
    required String leadId,
  }) async {
    final deviceId = _storageService.getOrCreateDeviceId();

    try {
      final res = await _supabase.rpc(
        'start_dial_attempt',
        params: {
          'p_lead_id': leadId,
          'p_device_id': deviceId,
        },
      );

      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      final message = e.toString();
      if (message.contains('CALL_LOCKED')) {
        throw Exception(
          'Call Locked: You have a pending call attempt that requires post-call notes before making another call.',
        );
      }
      rethrow;
    }
  }

  /// Authoritative device ID generated or retrieved locally
  String get deviceId => _storageService.getOrCreateDeviceId();

  /// Submits the mandatory post-call dialog and matched call-log facts to the server.
  /// Releases Call Lock and persists immutable disposition.
  Future<Map<String, dynamic>> submitCallDialog({
    required String dialAttemptId,
    required String numberE164,
    required DateTime startedAt,
    required int durationSecs,
    String? simSlot,
    required bool callerClaimedConnected,
    required String outcome, // 'interested', 'not_interested', 'callback', etc.
    required List<String> reasonIds,
    String? otherReasonText,
    String? note,
    int? secondsAfterCallEnd,
    DateTime? followUpDueAt,
    String? followUpType, // 'call', 'whatsapp', 'email', 'meeting'
    String evidenceSource = 'device_log', // 'device_log' or 'manual'
  }) async {
    final devId = deviceId;
    final clientTime = DateTime.now().toUtc();
    final clockSkewSecs = (DateTime.now().toUtc().millisecondsSinceEpoch -
            clientTime.millisecondsSinceEpoch) ~/
        1000;

    final baseParams = <String, dynamic>{
      'p_dial_attempt_id': dialAttemptId,
      'p_device_id': devId,
      'p_number_e164': numberE164,
      'p_call_type': 'outgoing',
      'p_started_at': startedAt.toUtc().toIso8601String(),
      'p_duration_secs': durationSecs,
      'p_sim_slot': simSlot,
      'p_clock_skew_secs': clockSkewSecs,
      'p_caller_claimed_connected': callerClaimedConnected,
      'p_outcome': outcome,
      'p_reason_ids': reasonIds,
      'p_other_reason_text': otherReasonText,
      'p_note': note,
      'p_seconds_after_call_end': secondsAfterCallEnd ?? 0,
      'p_follow_up_due_at': followUpDueAt?.toUtc().toIso8601String(),
      'p_follow_up_type': followUpType,
    };

    try {
      final res = await _supabase.rpc(
        'submit_call_dialog',
        params: {
          ...baseParams,
          'p_evidence_source': evidenceSource,
        },
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('p_evidence_source') ||
          errStr.contains('PGRST202') ||
          errStr.contains('schema cache')) {
        final res = await _supabase.rpc(
          'submit_call_dialog',
          params: baseParams,
        );
        return Map<String, dynamic>.from(res as Map);
      }
      rethrow;
    }
  }

  /// Retrieves today's calling metrics for the authenticated caller
  Future<StatsModel> getTodayStats() async {
    final callerId = _supabase.auth.currentUser?.id;
    if (callerId == null) return StatsModel();

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toUtc();

    try {
      final callsRes = await _supabase
          .from('calls')
          .select('id, talk_secs, dispositions(outcome)')
          .eq('caller_id', callerId)
          .gte('initiated_at', startOfDay.toIso8601String());

      final List<dynamic> calls = callsRes as List<dynamic>;
      final totalCalls = calls.length;
      int connectedCalls = 0;
      int interestedCount = 0;

      for (final call in calls) {
        final talkSecs = (call['talk_secs'] as num?)?.toInt() ?? 0;
        if (talkSecs >= 10) {
          connectedCalls++;
        }
        final disp = call['dispositions'];
        if (disp != null) {
          if (disp is List && disp.isNotEmpty) {
            if (disp[0]['outcome'] == 'interested') interestedCount++;
          } else if (disp is Map && disp['outcome'] == 'interested') {
            interestedCount++;
          }
        }
      }

      final followUpsRes = await _supabase
          .from('follow_ups')
          .select('id')
          .eq('assigned_to', callerId)
          .eq('status', 'open')
          .lte(
            'due_at',
            DateTime(now.year, now.month, now.day, 23, 59, 59)
                .toUtc()
                .toIso8601String(),
          );

      final followUpsCount = (followUpsRes as List<dynamic>).length;

      return StatsModel(
        totalCallsToday: totalCalls,
        connectedCallsToday: connectedCalls,
        interestedToday: interestedCount,
        pendingCallbacksToday: followUpsCount,
      );
    } catch (_) {
      return StatsModel();
    }
  }

  /// Clocks in the authenticated caller, establishing an active work session.
  Future<Map<String, dynamic>> clockIn() async {
    final res = await _supabase.rpc('clock_in');
    return Map<String, dynamic>.from(res as Map);
  }

  /// Clocks out the caller, closing their active work session.
  Future<Map<String, dynamic>> clockOut({String? sessionId}) async {
    final callerId = _supabase.auth.currentUser?.id;
    var targetSessionId = sessionId;

    // If no session ID passed, resolve the active session directly
    if (targetSessionId == null && callerId != null) {
      try {
        final activeRow = await _supabase
            .from('caller_work_sessions')
            .select('id')
            .eq('caller_id', callerId)
            .eq('is_active', true)
            .order('started_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (activeRow != null) {
          targetSessionId = activeRow['id'] as String?;
        }
      } catch (_) {}
    }

    final res = await _supabase.rpc(
      'clock_out',
      params: targetSessionId != null ? {'p_session_id': targetSessionId} : {},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  /// Retrieves the authoritative live work session status for the caller.
  Future<Map<String, dynamic>> getCallerWorkStatus() async {
    final userId = _supabase.auth.currentUser?.id;

    // 1. Try authoritative get_caller_work_status RPC
    try {
      final res = await _supabase.rpc('get_caller_work_status');
      if (res != null) {
        final map = Map<String, dynamic>.from(res as Map);
        if (map.containsKey('is_clocked_in')) {
          return map;
        }
      }
    } catch (_) {}

    // 2. Try get_daily_caller_quota RPC
    if (userId != null) {
      try {
        final quotaRes = await _supabase.rpc('get_daily_caller_quota', params: {
          'p_caller_id': userId,
        });
        if (quotaRes != null) {
          final q = Map<String, dynamic>.from(quotaRes as Map);
          if (q.containsKey('is_clocked_in')) {
            return {
              'is_clocked_in': q['is_clocked_in'] == true,
              'current_session_id': q['current_session_id'],
              'active_seconds_today': (q['active_seconds'] as num?)?.toInt() ?? 0,
              'quota_target_seconds': (q['quota_target_seconds'] as num?)?.toInt() ?? 7200,
              'quota_met': q['quota_met'] == true,
            };
          }
        }
      } catch (_) {}
    }

    // 3. Resilient Direct Table Fallback: query caller_work_sessions table directly!
    // Ensures status is accurate even before remote RPC migrations are applied.
    if (userId != null) {
      try {
        final now = DateTime.now().toUtc();
        final startOfDay = DateTime.utc(now.year, now.month, now.day);

        final activeSession = await _supabase
            .from('caller_work_sessions')
            .select('*')
            .eq('caller_id', userId)
            .eq('is_active', true)
            .order('started_at', ascending: false)
            .limit(1)
            .maybeSingle();

        final todaySessions = await _supabase
            .from('caller_work_sessions')
            .select('started_at, ended_at, duration_seconds, is_active')
            .eq('caller_id', userId)
            .gte('started_at', startOfDay.toIso8601String());

        int totalTodaySeconds = 0;
        if (todaySessions is List) {
          for (final s in todaySessions) {
            final isAct = s['is_active'] == true;
            if (isAct) {
              final startedAt = DateTime.tryParse(s['started_at']?.toString() ?? '') ?? now;
              totalTodaySeconds += now.difference(startedAt).inSeconds.clamp(0, 86400);
            } else {
              totalTodaySeconds += (s['duration_seconds'] as num?)?.toInt() ?? 0;
            }
          }
        }

        return {
          'is_clocked_in': activeSession != null,
          'current_session_id': activeSession?['id'] as String?,
          'active_seconds_today': totalTodaySeconds,
          'quota_target_seconds': 7200,
          'quota_met': totalTodaySeconds >= 7200,
        };
      } catch (_) {}
    }

    return {
      'is_clocked_in': false,
      'current_session_id': null,
      'active_seconds_today': 0,
      'quota_target_seconds': 7200,
      'quota_met': false,
    };
  }
}

