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
  /// Only outgoing entries matching [leadPhoneE164] are ever processed.
  /// All personal calls and non-matching entries are immediately discarded on-device.
  Future<DeviceCallLogModel?> matchOutgoingCallForLead({
    required String leadPhoneE164,
    required DateTime dialedAfter,
    Duration timeout = const Duration(seconds: 15),
    Duration interval = const Duration(milliseconds: 1500),
    void Function(int secondsRemaining)? onProgress,
  }) async {
    final targetDigits = _extractSignificantDigits(leadPhoneE164);
    final startTime = DateTime.now();
    // Query entries starting 2 minutes prior to dial tap to tolerate clock skew (§7)
    final fromEpoch =
        dialedAfter.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch;

    while (DateTime.now().difference(startTime) < timeout) {
      final elapsed = DateTime.now().difference(startTime);
      final remaining = (timeout - elapsed).inSeconds;
      onProgress?.call(remaining > 0 ? remaining : 0);

      try {
        final Iterable<CallLogEntry> entries = await CallLog.query(
          dateFrom: fromEpoch,
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
          final entryDigits = _extractSignificantDigits(entryNumber);

          // 2. Strict Lead Matching (§6 Privacy Guard)
          if (entryDigits.isNotEmpty &&
              targetDigits.isNotEmpty &&
              (entryDigits == targetDigits ||
                  entryDigits.endsWith(targetDigits) ||
                  targetDigits.endsWith(entryDigits))) {
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

  /// Extracts the last 10 digits for Indian standard numbers to ensure robust matching
  /// against local dial patterns (e.g. 08971027214, +918971027214, 8971027214).
  static String _extractSignificantDigits(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }
}
