import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/stats_model.dart';

class StatsHeader extends StatelessWidget {
  final StatsModel stats;
  final VoidCallback onRefresh;

  const StatsHeader({
    super.key,
    required this.stats,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Today's Progress",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMain,
                ),
              ),
              InkWell(
                onTap: onRefresh,
                child: const Row(
                  children: [
                    Icon(Icons.refresh, size: 16, color: AppTheme.primary),
                    SizedBox(width: 4),
                    Text(
                      'Refresh',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildStatBox(
                label: 'Total Calls',
                value: '${stats.totalCallsToday}',
                color: AppTheme.textMain,
                bgColor: AppTheme.background,
              ),
              const SizedBox(width: 10),
              _buildStatBox(
                label: 'Connected (≥10s)',
                value: '${stats.connectedCallsToday}',
                color: AppTheme.success,
                bgColor: AppTheme.successLight,
              ),
              const SizedBox(width: 10),
              _buildStatBox(
                label: 'Interested',
                value: '${stats.interestedToday}',
                color: AppTheme.primary,
                bgColor: AppTheme.infoLight,
              ),
              const SizedBox(width: 10),
              _buildStatBox(
                label: 'Callbacks',
                value: '${stats.pendingCallbacksToday}',
                color: AppTheme.warning,
                bgColor: AppTheme.warningLight,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox({
    required String label,
    required String value,
    required Color color,
    required Color bgColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
