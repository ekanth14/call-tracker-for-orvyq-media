import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';

class DailyQuotaCard extends StatefulWidget {
  const DailyQuotaCard({super.key});

  @override
  State<DailyQuotaCard> createState() => _DailyQuotaCardState();
}

class _DailyQuotaCardState extends State<DailyQuotaCard> {
  bool _isLoading = true;
  bool _isClockedIn = false;
  String? _currentSessionId;
  int _activeSeconds = 0;
  final int _targetSeconds = 7200; // 2 Hours = 7200s
  Timer? _liveTicker;

  @override
  void initState() {
    super.initState();
    _fetchDailyQuota();
  }

  @override
  void dispose() {
    _liveTicker?.cancel();
    super.dispose();
  }

  void _startLiveTicker() {
    _liveTicker?.cancel();
    _liveTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isClockedIn) {
        setState(() {
          _activeSeconds += 1;
        });
      }
    });
  }

  Future<void> _fetchDailyQuota() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final res = await supabase.rpc('get_daily_caller_quota', params: {
        'p_caller_id': userId,
      });

      if (res != null && mounted) {
        final data = res as Map<String, dynamic>;
        setState(() {
          _activeSeconds = (data['active_seconds'] as num?)?.toInt() ?? 0;
          _isClockedIn = data['is_clocked_in'] == true;
          _currentSessionId = data['current_session_id'] as String?;
          _isLoading = false;
        });

        if (_isClockedIn) {
          _startLiveTicker();
        } else {
          _liveTicker?.cancel();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleClockIn() async {
    setState(() => _isLoading = true);
    final supabase = Supabase.instance.client;

    try {
      if (_isClockedIn && _currentSessionId != null) {
        // Clock Out
        await supabase.rpc('clock_out', params: {
          'p_session_id': _currentSessionId,
        });
      } else {
        // Clock In
        await supabase.rpc('clock_in');
      }
      await _fetchDailyQuota();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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

    final totalActive = _activeSeconds;
    final progressPct = (totalActive / _targetSeconds).clamp(0.0, 1.0);
    final isQuotaMet = totalActive >= _targetSeconds;
    final hours = totalActive ~/ 3600;
    final mins = (totalActive % 3600) ~/ 60;
    final remainingSecs = (_targetSeconds - totalActive).clamp(0, _targetSeconds);
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
                          : _isClockedIn
                              ? Colors.amber.shade100
                              : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.timer_outlined,
                      size: 18,
                      color: isQuotaMet
                          ? Colors.green.shade700
                          : _isClockedIn
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
                            : _isClockedIn
                                ? 'Shift Active • Live Ticking'
                                : 'Clock in to log active work',
                        style: TextStyle(
                          fontSize: 11,
                          color: isQuotaMet
                              ? Colors.green.shade700
                              : _isClockedIn
                                  ? Colors.amber.shade900
                                  : AppTheme.textMuted,
                          fontWeight: isQuotaMet || _isClockedIn
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
                onTap: _toggleClockIn,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isClockedIn
                        ? Colors.red.shade50
                        : AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isClockedIn
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
                          color: _isClockedIn ? Colors.red : AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isClockedIn ? 'Clock Out' : 'Clock In',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _isClockedIn ? Colors.red.shade700 : AppTheme.primary,
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
