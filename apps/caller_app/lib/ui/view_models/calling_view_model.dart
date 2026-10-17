import 'package:flutter/foundation.dart';
import '../../core/config/app_config.dart';
import '../../data/models/dial_attempt_model.dart';
import '../../data/models/lead_model.dart';
import '../../data/models/reason_model.dart';
import '../../data/repositories/calling_repository.dart';
import '../../data/repositories/lead_repository.dart';
import '../../data/repositories/reason_repository.dart';
import '../../data/services/call_launcher_service.dart';

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

  CallingViewModel(
    this._callingRepository,
    this._leadRepository,
    this._reasonRepository,
    this._callLauncherService,
  );

  bool _isCallLocked = false;
  DialAttemptModel? _activeAttempt;
  LeadModel? _activeLead;
  bool _isLoading = false;
  String? _errorMessage;

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

      // Reset dialog form fields
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

  /// Submits the mandatory post-call dialog and unlocks the queue
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

    try {
      final dbOutcome = _outcomeToString(_outcome);

      await _callingRepository.submitCallDialog(
        dialAttemptId: _activeAttempt!.id,
        numberE164: _activeLead!.phoneE164,
        startedAt: _activeAttempt!.dialedAt,
        durationSecs: _callDurationSecs,
        callerClaimedConnected: isConnected,
        outcome: dbOutcome,
        reasonIds: _selectedReasonIds,
        otherReasonText:
            _otherReasonText.trim().isNotEmpty ? _otherReasonText.trim() : null,
        note: _notes.trim().isNotEmpty ? _notes.trim() : null,
        followUpDueAt: _followUpDateTime,
        followUpType: _followUpDateTime != null ? _followUpType : null,
      );

      // Release Call Lock
      _isCallLocked = false;
      _activeAttempt = null;
      _activeLead = null;
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

  String _outcomeToString(PostCallOutcome outcome) {
    switch (outcome) {
      case PostCallOutcome.interested:
        return 'interested';
      case PostCallOutcome.notInterested:
        return 'not_interested';
      case PostCallOutcome.callback:
        return 'interested'; // follow-up handles callback
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
