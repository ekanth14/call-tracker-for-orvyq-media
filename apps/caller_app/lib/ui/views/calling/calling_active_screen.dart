import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/phone_formatter.dart';
import '../../view_models/calling_view_model.dart';

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
      final callingVm = context.read<CallingViewModel>();
      callingVm.setDurationSecs(_secondsElapsed);
      context.go('/dialog');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _proceedToDialog() {
    final callingVm = context.read<CallingViewModel>();
    callingVm.setDurationSecs(_secondsElapsed);
    context.go('/dialog');
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

                // Pulsing calling avatar
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.success.withOpacity(0.15),
                        ),
                      ),
                      Container(
                        width: 88,
                        height: 88,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.success,
                        ),
                        child: const Icon(
                          Icons.phone_in_talk_rounded,
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

                const Spacer(),

                // Instruction Card
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
                          'Place the call in your SIM phone dialer. Once finished, return here to complete mandatory disposition notes.',
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

                // Button to proceed to dialog
                ElevatedButton.icon(
                  onPressed: _proceedToDialog,
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text('Call Finished → Enter Notes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
