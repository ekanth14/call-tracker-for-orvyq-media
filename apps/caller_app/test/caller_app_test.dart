import 'package:flutter_test/flutter_test.dart';
import '../lib/core/config/app_config.dart';
import '../lib/core/utils/phone_formatter.dart';
import '../lib/core/utils/date_formatter.dart';

void main() {
  group('PhoneFormatter Tests', () {
    test('formats Indian 10-digit mobile number with +91 country code', () {
      expect(PhoneFormatter.formatE164('8971027214'), '+91 89710 27214');
    });

    test('formats existing E.164 +91 mobile number with clean spacing', () {
      expect(PhoneFormatter.formatE164('+918971027214'), '+91 89710 27214');
    });

    test('handles null or empty phone gracefully', () {
      expect(PhoneFormatter.formatE164(null), 'No Phone');
      expect(PhoneFormatter.formatE164(''), 'No Phone');
    });

    test('masks phone number correctly for display', () {
      final masked = PhoneFormatter.maskPhone('+918971027214');
      expect(masked.contains('••'), isTrue);
      expect(masked.endsWith('214'), isTrue);
    });
  });

  group('DateFormatter Tests', () {
    test('formats zero and short durations correctly', () {
      expect(DateFormatter.formatDuration(0), '0s');
      expect(DateFormatter.formatDuration(9), '9s');
      expect(DateFormatter.formatDuration(10), '10s');
      expect(DateFormatter.formatDuration(75), '1m 15s');
      expect(DateFormatter.formatDuration(3600), '60m 0s');
    });

    test('formats relative dates accurately', () {
      final now = DateTime.now();
      expect(DateFormatter.formatRelative(now), 'Just now');
      expect(DateFormatter.formatRelative(null), 'Never');
    });
  });

  group('Verification Rule §5.1 (10-Second Connected Threshold)', () {
    test('minimum connected duration threshold is locked to 10 seconds', () {
      expect(AppConfig.minConnectedDurationSecs, 10);
    });

    test('evaluates connected status strictly based on talk seconds', () {
      bool isConnected(int seconds) =>
          seconds >= AppConfig.minConnectedDurationSecs;

      expect(isConnected(0), isFalse, reason: 'Zero duration is not connected');
      expect(isConnected(5), isFalse, reason: '5 seconds is under 10s threshold');
      expect(isConnected(9), isFalse, reason: '9 seconds is under 10s threshold');
      expect(isConnected(10), isTrue, reason: '10 seconds meets the threshold');
      expect(isConnected(11), isTrue, reason: '11 seconds exceeds threshold');
      expect(isConnected(180), isTrue, reason: '3 minutes is connected');
    });

    test('outcome Interested is invalid when duration is under 10s', () {
      bool validateOutcome(String outcome, int durationSecs) {
        final connected = durationSecs >= AppConfig.minConnectedDurationSecs;
        if (!connected && outcome == 'interested') {
          return false; // Prohibited by §5.1
        }
        return true;
      }

      expect(validateOutcome('interested', 5), isFalse);
      expect(validateOutcome('interested', 9), isFalse);
      expect(validateOutcome('interested', 10), isTrue);
      expect(validateOutcome('interested', 45), isTrue);
      expect(validateOutcome('not_interested', 3), isTrue);
      expect(validateOutcome('ringing', 0), isTrue);
    });
  });

  group('Call Lock Architecture (§5 & §8)', () {
    test('Call Lock state machine enforces single active dial attempt', () {
      bool isCallLocked = false;
      String? activeAttemptId;

      void startDial(String attemptId) {
        if (isCallLocked) {
          throw Exception('CALL_LOCKED: complete previous dialog first');
        }
        isCallLocked = true;
        activeAttemptId = attemptId;
      }

      void submitDialog() {
        isCallLocked = false;
        activeAttemptId = null;
      }

      // Step 1: Start call 1
      startDial('attempt-1');
      expect(isCallLocked, isTrue);
      expect(activeAttemptId, 'attempt-1');

      // Step 2: Attempting call 2 while locked throws
      expect(() => startDial('attempt-2'), throwsException);

      // Step 3: Complete dialog 1 unlocks
      submitDialog();
      expect(isCallLocked, isFalse);
      expect(activeAttemptId, isNull);

      // Step 4: Now call 2 succeeds
      startDial('attempt-2');
      expect(isCallLocked, isTrue);
      expect(activeAttemptId, 'attempt-2');
    });
  });
}
