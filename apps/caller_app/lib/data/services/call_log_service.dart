import 'dart:async';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/device_call_log_model.dart';

class CallLogService {
  /// Checks whether READ_CALL_LOG and PHONE permissions are granted
  Future<bool> hasCallLogPermission() async {
    final phoneStatus = await Permission.phone.isGranted;
    // On Android, READ_CALL_LOG is bundled under Permission.phone or requestable
    return phoneStatus;
  }

  /// Requests the necessary phone and call-log permissions
  Future<bool> requestCallLogPermission() async {
    final status = await Permission.phone.request();
    return status.isGranted;
  }

  /// Polls the native Android CallLog for the newest outgoing call matching the lead.
  /// Retries up to [timeout] duration because OEMs write the log asynchronously (§5.3).
  ///
  /// CRITICAL PRIVACY RULE (§6):
  /// Call logs are ONLY queried and matched when [isClockedIn] is true.
  /// If [isClockedIn] is false (off duty / work logout), call log access is COMPLETELY BYPASSED.
  /// Only outgoing entries matching [leadPhoneE164] are ever processed.
  /// All personal calls and non-matching entries are immediately discarded on-device.
  Future<DeviceCallLogModel?> matchOutgoingCallForLead({
    required String leadPhoneE164,
    required DateTime dialedAfter,
    bool isClockedIn = true,
    Duration timeout = const Duration(seconds: 15),
    Duration interval = const Duration(milliseconds: 1500),
    void Function(int secondsRemaining)? onProgress,
  }) async {
    // STRICT PRIVACY GUARANTEE: Never query CallLog if off duty
    if (!isClockedIn) {
      return null;
    }

    final startTime = DateTime.now();
    // Query entries starting 2 minutes prior to dial tap to tolerate clock skew (§7)
    final fromEpoch =
        dialedAfter.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch;

    while (DateTime.now().difference(startTime) < timeout) {
      final elapsed = DateTime.now().difference(startTime);
      final remaining = (timeout - elapsed).inSeconds;
      onProgress?.call(remaining > 0 ? remaining : 0);

      try {
        final toEpoch = DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch;

        final Iterable<CallLogEntry> entries = await CallLog.query(
          dateFrom: fromEpoch,
          dateTo: toEpoch,
          type: CallType.outgoing,
        );

        // Sort descending by timestamp (newest first)
        final sorted = entries.toList()
          ..sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));

        for (final entry in sorted) {
          // 1. Must be OUTGOING (§5.3)
          if (entry.callType != CallType.outgoing) {
            continue;
          }

          final entryNumber = entry.number ?? '';

          // 2. Strict Lead Matching (Safe 10-digit subscriber match, no short suffixes)
          if (isPhoneNumberMatch(entryNumber, leadPhoneE164)) {
            // Matched!
            final callStartedAt = DateTime.fromMillisecondsSinceEpoch(
              entry.timestamp ?? dialedAfter.millisecondsSinceEpoch,
              isUtc: true,
            );

            return DeviceCallLogModel(
              numberE164: leadPhoneE164,
              rawNumber: entryNumber,
              callType: 'outgoing',
              startedAt: callStartedAt,
              durationSecs: entry.duration ?? 0,
              simSlot: entry.simDisplayName ?? entry.phoneAccountId,
              timestampMillis: entry.timestamp ?? 0,
            );
          }
        }
      } catch (_) {
        // Query error or log locked by telephony provider; retry on next tick
      }

      await Future.delayed(interval);
    }

    // No matching call log found within the polling window
    return null;
  }

  /// Safely checks if a raw call log number matches the assigned lead phone number.
  /// Enforces a minimum 10-digit subscriber number match and prohibits dangerous
  /// short-suffix matching (which could erroneously match personal or extension calls).
  bool isPhoneNumberMatch(String rawEntryNumber, String leadPhoneE164) =>
      isNumberMatch(rawEntryNumber, leadPhoneE164);

  static bool isNumberMatch(String rawEntryNumber, String leadPhoneE164) {
    final entryDigits = rawEntryNumber.replaceAll(RegExp(r'\D'), '');
    final targetDigits = leadPhoneE164.replaceAll(RegExp(r'\D'), '');

    // Discard any entry numbers that lack full 10-digit national subscriber length
    if (entryDigits.length < 10 || targetDigits.length < 10) {
      return false;
    }

    // Extract exact 10-digit national subscriber number
    final entry10 = entryDigits.substring(entryDigits.length - 10);
    final target10 = targetDigits.substring(targetDigits.length - 10);

    if (entry10 != target10) {
      return false;
    }

    // Verify any remaining prefix is only a valid dialing prefix (trunk 0 or country code 91)
    final entryPrefix = entryDigits.substring(0, entryDigits.length - 10);
    if (entryPrefix.isNotEmpty && entryPrefix != '0' && entryPrefix != '91') {
      return false;
    }

    final targetPrefix = targetDigits.substring(0, targetDigits.length - 10);
    if (targetPrefix.isNotEmpty && targetPrefix != '0' && targetPrefix != '91') {
      return false;
    }

    return true;
  }
}
