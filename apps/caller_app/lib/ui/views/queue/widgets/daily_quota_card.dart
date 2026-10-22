import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../view_models/calling_view_model.dart';

class DailyQuotaCard extends StatefulWidget {
  const DailyQuotaCard({super.key});

  @override
  State<DailyQuotaCard> createState() => _DailyQuotaCardState();
}

class _DailyQuotaCardState extends State<DailyQuotaCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final callingVm = context.read<CallingViewModel>();
      callingVm.fetchWorkStatus();
    });
  }

  Future<void> _toggleClockIn(CallingViewModel callingVm) async {
    if (callingVm.isClockedIn) {
      final success = await callingVm.clockOut();
      if (!success && mounted && callingVm.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(callingVm.errorMessage!),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } else {
      final success = await callingVm.clockIn();
      if (!success && mounted && callingVm.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(callingVm.errorMessage!),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final callingVm = context.watch<CallingViewModel>();

    if (callingVm.isWorkStatusLoading && callingVm.activeWorkSeconds == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final isClockedIn = callingVm.isClockedIn;
    final totalActive = callingVm.activeWorkSeconds;
    final targetSeconds = callingVm.quotaTargetSeconds > 0 ? callingVm.quotaTargetSeconds : 7200;
    final progressPct = (totalActive / targetSeconds).clamp(0.0, 1.0);
    final isQuotaMet = callingVm.isQuotaMet;
    final hours = totalActive ~/ 3600;
    final mins = (totalActive % 3600) ~/ 60;
    final remainingSecs = (targetSeconds - totalActive).clamp(0, targetSeconds);
    final remHours = remainingSecs ~/ 3600;
    final remMins = (remainingSecs % 3600) ~/ 60;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isQuotaMet ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isQuotaMet ? Colors.green.shade200 : AppTheme.border,
          width: isQuotaMet ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: isQuotaMet
                          ? Colors.green.shade100
                          : isClockedIn
                              ? Colors.amber.shade100
                              : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.timer_outlined,
                      size: 18,
                      color: isQuotaMet
                          ? Colors.green.shade700
                          : isClockedIn
                              ? Colors.amber.shade800
                              : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Daily Work Target (2h)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMain,
                        ),
                      ),
                      Text(
                        isQuotaMet
                            ? 'Mandatory 2h Completed! 🎉'
                            : isClockedIn
                                ? 'Shift Active • Live Ticking'
                                : 'Clock in to log active work',
                        style: TextStyle(
                          fontSize: 11,
                          color: isQuotaMet
                              ? Colors.green.shade700
                              : isClockedIn
                                  ? Colors.amber.shade900
                                  : AppTheme.textMuted,
                          fontWeight: isQuotaMet || isClockedIn
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Clock-In / Out Button
              InkWell(
                onTap: () => _toggleClockIn(callingVm),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isClockedIn
                        ? Colors.red.shade50
                        : AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isClockedIn
                          ? Colors.red.shade200
                          : AppTheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isClockedIn ? Colors.red : AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isClockedIn ? 'Clock Out' : 'Clock In',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isClockedIn ? Colors.red.shade700 : AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progressPct,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                isQuotaMet ? Colors.green.shade600 : AppTheme.primary,
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Footer metrics
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${hours}h ${mins}m / 2h 00m (${(progressPct * 100).toInt()}%)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMain,
                ),
              ),
              Text(
                isQuotaMet
                    ? 'Quota Fulfilled'
                    : '${remHours > 0 ? '$remHours h ' : ''}${remMins}m remaining',
                style: TextStyle(
                  fontSize: 11,
                  color: isQuotaMet ? Colors.green.shade700 : AppTheme.textMuted,
                  fontWeight: isQuotaMet ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
