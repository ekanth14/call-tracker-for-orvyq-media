import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/config/app_config.dart';
import '../../data/models/device_call_log_model.dart';
import '../../data/models/dial_attempt_model.dart';
import '../../data/models/lead_model.dart';
import '../../data/models/reason_model.dart';
import '../../data/repositories/calling_repository.dart';
import '../../data/repositories/lead_repository.dart';
import '../../data/repositories/reason_repository.dart';
import '../../data/services/background_sync_service.dart';
import '../../data/services/call_launcher_service.dart';
import '../../data/services/call_log_service.dart';

enum PostCallOutcome {
  interested,
  notInterested,
  callback,
  wrongNumber,
  ringing,
  busy,
  switchedOff,
  notPlaced,
}

class CallingViewModel extends ChangeNotifier {
  final CallingRepository _callingRepository;
  final LeadRepository _leadRepository;
  final ReasonRepository _reasonRepository;
  final CallLauncherService _callLauncherService;
  final CallLogService _callLogService;

  CallingViewModel(
    this._callingRepository,
    this._leadRepository,
    this._reasonRepository,
    this._callLauncherService,
    this._callLogService,
  );

  bool _isCallLocked = false;
  DialAttemptModel? _activeAttempt;
  LeadModel? _activeLead;
  bool _isLoading = false;
  String? _errorMessage;

  // Work Session & Duty Status (§1 & §2)
  bool _isClockedIn = false;
  String? _currentSessionId;
  int _activeWorkSeconds = 0;
  int _quotaTargetSeconds = 7200; // 2 Hours = 7200s
  bool _isWorkStatusLoading = false;
  Timer? _liveWorkTicker;

  // Call-Log Detection State (§5.3 & §6)
  DeviceCallLogModel? _matchedCallLog;
  bool _isDetectingCallLog = false;
  bool _detectionTimedOut = false;
  int _detectionSecondsRemaining = 15;

  // Dialog form state
  int _callDurationSecs = 0;
  PostCallOutcome _outcome = PostCallOutcome.ringing;
  final List<String> _selectedReasonIds = [];
  String _otherReasonText = '';
  String _notes = '';
  DateTime? _followUpDateTime;
  String _followUpType = 'call';

  List<ReasonModel> _availableReasons = [];

  bool get isCallLocked => _isCallLocked;
  DialAttemptModel? get activeAttempt => _activeAttempt;
  LeadModel? get activeLead => _activeLead;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Work Session Getters
  bool get isClockedIn => _isClockedIn;
  String? get currentSessionId => _currentSessionId;
  int get activeWorkSeconds => _activeWorkSeconds;
  int get quotaTargetSeconds => _quotaTargetSeconds;
  bool get isQuotaMet => _activeWorkSeconds >= _quotaTargetSeconds;
  bool get isWorkStatusLoading => _isWorkStatusLoading;

  DeviceCallLogModel? get matchedCallLog => _matchedCallLog;
  bool get isDetectingCallLog => _isDetectingCallLog;
  bool get detectionTimedOut => _detectionTimedOut;
  int get detectionSecondsRemaining => _detectionSecondsRemaining;

  int get callDurationSecs => _callDurationSecs;
  PostCallOutcome get outcome => _outcome;
  List<String> get selectedReasonIds => _selectedReasonIds;
  String get otherReasonText => _otherReasonText;
  String get notes => _notes;
  DateTime? get followUpDateTime => _followUpDateTime;
  String get followUpType => _followUpType;
  List<ReasonModel> get availableReasons => _availableReasons;

  /// True if duration >= minConnectedDurationSecs (10s)
  bool get isConnected =>
      _callDurationSecs >= AppConfig.minConnectedDurationSecs;

  @override
  void dispose() {
    _liveWorkTicker?.cancel();
    super.dispose();
  }

  void _startWorkTicker() {
    _liveWorkTicker?.cancel();
    _liveWorkTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isClockedIn) {
        _activeWorkSeconds += 1;
        notifyListeners();
      }
    });
  }

  /// Authoritatively fetches the caller's live work status and quota from database.
  Future<void> fetchWorkStatus() async {
    _isWorkStatusLoading = true;
    notifyListeners();

    try {
      final status = await _callingRepository.getCallerWorkStatus();
      _isClockedIn = status['is_clocked_in'] == true;
      _currentSessionId = status['current_session_id'] as String?;
      _activeWorkSeconds = (status['active_seconds_today'] as num?)?.toInt() ?? 0;
      _quotaTargetSeconds = (status['quota_target_seconds'] as num?)?.toInt() ?? 7200;

      if (_isClockedIn) {
        _startWorkTicker();
      } else {
        _liveWorkTicker?.cancel();
      }
    } catch (_) {
      // Keep previous state if network error
    } finally {
      _isWorkStatusLoading = false;
      notifyListeners();
    }
  }

  /// Clocks into active work shift, allowing lead calling and daily quota logging.
  Future<bool> clockIn() async {
    _isWorkStatusLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _callingRepository.clockIn();
      _isClockedIn = true;
      _currentSessionId = res['session_id'] as String?;
      _startWorkTicker();
      notifyListeners();

      // Refresh background stats without wiping out active clocked-in state
      try {
        final status = await _callingRepository.getCallerWorkStatus();
        if (status['is_clocked_in'] == true) {
          _isClockedIn = true;
          _currentSessionId = status['current_session_id'] as String?;
        }
        _activeWorkSeconds = (status['active_seconds_today'] as num?)?.toInt() ?? _activeWorkSeconds;
        _quotaTargetSeconds = (status['quota_target_seconds'] as num?)?.toInt() ?? 7200;
      } catch (_) {}

      _isWorkStatusLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to clock in: ${e.toString().replaceAll('Exception:', '').trim()}';
      _isWorkStatusLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Clocks out of active work shift, pausing call tracking and ensuring off-duty privacy.
  Future<bool> clockOut() async {
    _isWorkStatusLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _callingRepository.clockOut(sessionId: _currentSessionId);
      _isClockedIn = false;
      _currentSessionId = null;
      _liveWorkTicker?.cancel();
      notifyListeners();

      // Refresh background stats
      try {
        final status = await _callingRepository.getCallerWorkStatus();
        _isClockedIn = status['is_clocked_in'] == true;
        _currentSessionId = status['current_session_id'] as String?;
        _activeWorkSeconds = (status['active_seconds_today'] as num?)?.toInt() ?? _activeWorkSeconds;
        _quotaTargetSeconds = (status['quota_target_seconds'] as num?)?.toInt() ?? 7200;
      } catch (_) {}

      _isWorkStatusLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to clock out: ${e.toString().replaceAll('Exception:', '').trim()}';
      _isWorkStatusLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Test isolation helper to set clocked-in state
  @visibleForTesting
  void setClockedInForTesting(bool clockedIn, {String? sessionId, int activeSeconds = 0}) {
    _isClockedIn = clockedIn;
    _currentSessionId = sessionId;
    _activeWorkSeconds = activeSeconds;
    notifyListeners();
  }

  /// Check active call lock on app start or resume
  Future<void> checkCallLock() async {
    try {
      final openAttempt = await _callingRepository.checkActiveCallLock();
      if (openAttempt != null) {
        _isCallLocked = true;
        _activeAttempt = openAttempt;
        _activeLead = await _leadRepository.getLeadById(openAttempt.leadId);
        await _loadReasons();
        notifyListeners();
      } else {
        _isCallLocked = false;
        _activeAttempt = null;
        _activeLead = null;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _loadReasons() async {
    try {
      _availableReasons = await _reasonRepository.fetchActiveReasons();
    } catch (_) {}
  }

  /// Initiates a call to an assigned lead, enforcing Call Lock & launching phone dialer
  Future<bool> initiateCall(LeadModel lead) async {
    if (!_isClockedIn) {
      _errorMessage =
          'Work Login Required: You are currently off duty. Please clock in before initiating calls to leads.';
      notifyListeners();
      return false;
    }

    if (_isCallLocked) {
      _errorMessage =
          'Call Locked: You must complete notes for your previous call before placing a new one.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Record dial attempt on server
      final res =
          await _callingRepository.startDialAttempt(leadId: lead.id);
      final attemptId = res['dial_attempt_id'] as String;

      _activeAttempt = DialAttemptModel(
        id: attemptId,
        leadId: lead.id,
        callerId: '',
        dialedAt: DateTime.now(),
        status: 'open',
      );
      _activeLead = lead;
      _isCallLocked = true;

      // Reset state & call-log proof
      _matchedCallLog = null;
      _isDetectingCallLog = false;
      _detectionTimedOut = false;
      _callDurationSecs = 0;
      _outcome = PostCallOutcome.ringing;
      _selectedReasonIds.clear();
      _otherReasonText = '';
      _notes = '';
      _followUpDateTime = null;
      _followUpType = 'call';

      await _loadReasons();

      // 2. Launch phone dialer with number
      final launched =
          await _callLauncherService.launchDialer(lead.phoneE164);
      if (!launched) {
        _errorMessage =
            'Could not open dialer. Please dial ${lead.phoneE164} manually.';
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Reads native Android CallLog to detect and match the newest outgoing call (§5.3)
  /// Polls asynchronously to accommodate slow OEM log writing.
  /// Strictly requires active work shift; if off-duty, bypasses call log completely.
  Future<bool> detectCallLog({Duration timeout = const Duration(seconds: 15)}) async {
    if (!_isClockedIn || _activeLead == null || _activeAttempt == null) return false;

    _isDetectingCallLog = true;
    _detectionTimedOut = false;
    _detectionSecondsRemaining = timeout.inSeconds;
    notifyListeners();

    try {
      final matched = await _callLogService.matchOutgoingCallForLead(
        leadPhoneE164: _activeLead!.phoneE164,
        dialedAfter: _activeAttempt!.dialedAt,
        isClockedIn: _isClockedIn,
        timeout: timeout,
        onProgress: (remaining) {
          _detectionSecondsRemaining = remaining;
          notifyListeners();
        },
      );

      _isDetectingCallLog = false;

      if (matched != null) {
        _matchedCallLog = matched;
        _callDurationSecs = matched.durationSecs;

        // Auto-configure initial outcome based on 10s rule (§5.1)
        if (matched.isConnected) {
          _outcome = PostCallOutcome.interested;
        } else {
          _outcome = PostCallOutcome.ringing;
        }

        notifyListeners();
        return true;
      } else {
        _matchedCallLog = null;
        _detectionTimedOut = true;
        _outcome = PostCallOutcome.notPlaced;
        notifyListeners();
        return false;
      }
    } catch (_) {
      _isDetectingCallLog = false;
      _detectionTimedOut = true;
      notifyListeners();
      return false;
    }
  }

  // Setters for Post-Call Dialog
  void setDurationSecs(int secs) {
    _callDurationSecs = secs;
    // Enforce 10s rule: If duration < 10s, cannot be interested
    if (_callDurationSecs < AppConfig.minConnectedDurationSecs &&
        _outcome == PostCallOutcome.interested) {
      _outcome = PostCallOutcome.ringing;
    }
    notifyListeners();
  }

  void setOutcome(PostCallOutcome val) {
    if (val == PostCallOutcome.interested && !isConnected) {
      _errorMessage =
          'Cannot mark Interested: Connected duration must be at least ${AppConfig.minConnectedDurationSecs} seconds.';
      notifyListeners();
      return;
    }
    _outcome = val;
    _errorMessage = null;
    notifyListeners();
  }

  void toggleReason(String reasonId) {
    if (_selectedReasonIds.contains(reasonId)) {
      _selectedReasonIds.remove(reasonId);
    } else {
      _selectedReasonIds.add(reasonId);
    }
    notifyListeners();
  }

  void setOtherReasonText(String text) {
    _otherReasonText = text;
  }

  void setNotes(String text) {
    _notes = text;
  }

  void setFollowUp(DateTime? dt, String type) {
    _followUpDateTime = dt;
    _followUpType = type;
    notifyListeners();
  }

  /// Cancels or discards active dial attempt locally, unlocking the queue.
  void cancelOrDiscardAttempt() {
    _isCallLocked = false;
    _activeAttempt = null;
    _activeLead = null;
    _matchedCallLog = null;
    _isDetectingCallLog = false;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Submits the mandatory post-call dialog and unlocks the queue
  /// If offline or network fails, queues to WorkManager for background sync (§5.2)
  Future<bool> submitDialog() async {
    if (_activeAttempt == null || _activeLead == null) {
      _errorMessage = 'No active dial attempt found to submit.';
      notifyListeners();
      return false;
    }

    // Validation
    if (_outcome == PostCallOutcome.interested && !isConnected) {
      _errorMessage =
          'Duration is under ${AppConfig.minConnectedDurationSecs}s. Must be connected to mark Interested.';
      notifyListeners();
      return false;
    }

    if (_outcome == PostCallOutcome.notInterested &&
        _selectedReasonIds.isEmpty &&
        _otherReasonText.trim().isEmpty) {
      _errorMessage =
          'Please select at least one reason why the lead was not interested.';
      notifyListeners();
      return false;
    }

    if ((_outcome == PostCallOutcome.callback ||
            _outcome == PostCallOutcome.interested) &&
        _followUpDateTime != null &&
        _followUpDateTime!.isBefore(DateTime.now())) {
      _errorMessage = 'Follow-up time must be in the future.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final dbOutcome = _outcomeToString(_outcome);
    final callStartedAt =
        _matchedCallLog?.startedAt ?? _activeAttempt!.dialedAt;
    final simSlot = _matchedCallLog?.simSlot;
    final evidenceSource = _matchedCallLog != null ? 'device_log' : 'manual';

    try {
      await _callingRepository.submitCallDialog(
        dialAttemptId: _activeAttempt!.id,
        numberE164: _activeLead!.phoneE164,
        startedAt: callStartedAt,
        durationSecs: _callDurationSecs,
        simSlot: simSlot,
        callerClaimedConnected: isConnected,
        outcome: dbOutcome,
        reasonIds: _selectedReasonIds,
        otherReasonText:
            _otherReasonText.trim().isNotEmpty ? _otherReasonText.trim() : null,
        note: _notes.trim().isNotEmpty ? _notes.trim() : null,
        followUpDueAt: _followUpDateTime,
        followUpType: _followUpDateTime != null ? _followUpType : null,
        evidenceSource: evidenceSource,
      );

      // Release Call Lock
      _isCallLocked = false;
      _activeAttempt = null;
      _activeLead = null;
      _matchedCallLog = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      // Offline fallback: Queue for WorkManager background sync (§5.2)
      final payload = {
        'p_dial_attempt_id': _activeAttempt!.id,
        'p_device_id': _callingRepository.deviceId,
        'p_number_e164': _activeLead!.phoneE164,
        'p_call_type': 'outgoing',
        'p_started_at': callStartedAt.toUtc().toIso8601String(),
        'p_duration_secs': _callDurationSecs,
        'p_sim_slot': simSlot,
        'p_clock_skew_secs': 0,
        'p_caller_claimed_connected': isConnected,
        'p_outcome': dbOutcome,
        'p_reason_ids': _selectedReasonIds,
        'p_other_reason_text': _otherReasonText,
        'p_note': _notes,
        'p_seconds_after_call_end': 0,
        'p_follow_up_due_at': _followUpDateTime?.toUtc().toIso8601String(),
        'p_follow_up_type': _followUpDateTime != null ? _followUpType : null,
        'p_evidence_source': evidenceSource,
      };

      await BackgroundSyncService.enqueuePendingSync(payload);

      // Release Call Lock locally so caller is not blocked when offline
      _isCallLocked = false;
      _activeAttempt = null;
      _activeLead = null;
      _matchedCallLog = null;
      _isLoading = false;
      notifyListeners();
      return true;
    }
  }

  String _outcomeToString(PostCallOutcome outcome) {
    switch (outcome) {
      case PostCallOutcome.interested:
        return 'interested';
      case PostCallOutcome.notInterested:
        return 'not_interested';
      case PostCallOutcome.callback:
        return 'interested';
      case PostCallOutcome.wrongNumber:
        return 'wrong_number';
      case PostCallOutcome.ringing:
      case PostCallOutcome.busy:
      case PostCallOutcome.switchedOff:
      case PostCallOutcome.notPlaced:
        return 'unreachable';
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
