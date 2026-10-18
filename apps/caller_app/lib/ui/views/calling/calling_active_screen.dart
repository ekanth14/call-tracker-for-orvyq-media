import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/phone_formatter.dart';
import '../../view_models/calling_view_model.dart';
import 'widgets/pitch_cheat_sheet.dart';

class CallingActiveScreen extends StatefulWidget {
  const CallingActiveScreen({super.key});

  @override
  State<CallingActiveScreen> createState() => _CallingActiveScreenState();
}

class _CallingActiveScreenState extends State<CallingActiveScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _secondsElapsed = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When caller finishes the phone call in native dialer and returns to app (§5.3)
    if (state == AppLifecycleState.resumed && mounted) {
      _startVerificationFlow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _startVerificationFlow() async {
    final callingVm = context.read<CallingViewModel>();
    if (callingVm.isDetectingCallLog) return;

    // Start native call-log detection
    await callingVm.detectCallLog();

    if (mounted) {
      context.go('/dialog');
    }
  }

  @override
  Widget build(BuildContext context) {
    final callingVm = context.watch<CallingViewModel>();
    final lead = callingVm.activeLead;

    return PopScope(
      canPop: false, // Call Lock prevents bypassing (§5)
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),

                // Pulsing calling avatar or detecting spinner
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: callingVm.isDetectingCallLog
                              ? AppTheme.primary.withOpacity(0.15)
                              : AppTheme.success.withOpacity(0.15),
                        ),
                      ),
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: callingVm.isDetectingCallLog
                              ? AppTheme.primary
                              : AppTheme.success,
                        ),
                        child: Icon(
                          callingVm.isDetectingCallLog
                              ? Icons.sync_rounded
                              : Icons.phone_in_talk_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Lead info
                Text(
                  lead?.name ?? 'Lead',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  PhoneFormatter.formatE164(lead?.phoneE164),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
                if (lead?.company != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    lead!.company!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // Timer badge
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined,
                            size: 16, color: AppTheme.textMuted),
                        const SizedBox(width: 6),
                        Text(
                          'Elapsed: ${DateFormatter.formatDuration(_secondsElapsed)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Corporate In-App Sales Pitch & Objections Cheat-Sheet
                Center(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.psychology_outlined, size: 18),
                    label: const Text('Sales Pitch & Objections Cheat-Sheet'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: () {
                      PitchCheatSheet.show(
                        context,
                        leadName: callingVm.activeLead?.name ?? '',
                        company: callingVm.activeLead?.company,
                      );
                    },
                  ),
                ),

                const Spacer(),

                // Detecting or Instruction Card
                if (callingVm.isDetectingCallLog) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.infoLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.info.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reading SIM Call Log Proof...',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textMain,
                                ),
                              ),
                              Text(
                                'Matching outgoing call (${callingVm.detectionSecondsRemaining}s window)',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.infoLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.info.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: AppTheme.info, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Place the call in your SIM phone dialer. Once finished, tap below to verify call log and submit mandatory notes.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMain,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Button to proceed to detection and dialog
                  ElevatedButton.icon(
                    onPressed: _startVerificationFlow,
                    icon: const Icon(Icons.verified_outlined, size: 20),
                    label: const Text('Call Finished → Verify Log'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
