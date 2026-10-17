import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/phone_formatter.dart';
import '../../view_models/calling_view_model.dart';
import '../../view_models/queue_view_model.dart';
import '../../view_models/stats_view_model.dart';

class PostCallDialogScreen extends StatefulWidget {
  const PostCallDialogScreen({super.key});

  @override
  State<PostCallDialogScreen> createState() => _PostCallDialogScreenState();
}

class _PostCallDialogScreenState extends State<PostCallDialogScreen> {
  final _notesController = TextEditingController();
  final _otherReasonController = TextEditingController();
  final _durationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final callingVm = context.read<CallingViewModel>();
    _durationController.text = callingVm.callDurationSecs.toString();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _otherReasonController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _pickFollowUpDateTime() async {
    final callingVm = context.read<CallingViewModel>();
    final now = DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );

    if (pickedDate != null && mounted) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 11, minute: 0),
      );

      if (pickedTime != null) {
        final fullDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        callingVm.setFollowUp(fullDateTime, callingVm.followUpType);
      }
    }
  }

  Future<void> _handleSubmit() async {
    final callingVm = context.read<CallingViewModel>();
    final queueVm = context.read<QueueViewModel>();
    final statsVm = context.read<StatsViewModel>();

    callingVm.setNotes(_notesController.text);
    callingVm.setOtherReasonText(_otherReasonController.text);

    final success = await callingVm.submitDialog();
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Call recorded & verified successfully! Queue unlocked.'),
          backgroundColor: AppTheme.success,
        ),
      );

      // Refresh queue and metrics
      await Future.wait([
        queueVm.loadLeads(silent: true),
        statsVm.loadTodayStats(),
      ]);

      if (mounted) {
        context.go('/queue');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final callingVm = context.watch<CallingViewModel>();
    final lead = callingVm.activeLead;

    return PopScope(
      canPop: false, // Mandatory: Call Lock enforces completion (§5 & §8)
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Mandatory Call Disposition'),
          automaticallyImplyLeading: false, // Cannot dismiss
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Call Lock Warning Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.warningLight,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppTheme.warning.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_rounded,
                          size: 16, color: AppTheme.warning),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Call Lock Active: Submitting unlocks your next lead.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Lead Info Summary Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lead?.name ?? 'Lead Contact',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            PhoneFormatter.formatE164(lead?.phoneE164),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                          if (lead?.company != null) ...[
                            const SizedBox(width: 8),
                            const Text('•',
                                style: TextStyle(color: AppTheme.textMuted)),
                            const SizedBox(width: 8),
                            Text(
                              lead!.company!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Duration & 10-Second Connected Rule (§5.1)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: callingVm.isConnected
                          ? AppTheme.success.withOpacity(0.5)
                          : AppTheme.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Call Duration (Seconds)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textMain,
                            ),
                          ),
                          _buildConnectionBadge(callingVm.isConnected),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _durationController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: 'Duration in seconds',
                                suffixText: 'secs',
                              ),
                              onChanged: (val) {
                                final secs = int.tryParse(val) ?? 0;
                                callingVm.setDurationSecs(secs);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Wrap(
                            spacing: 6,
                            children: [0, 15, 30, 60].map((s) {
                              return ActionChip(
                                label: Text('${s}s'),
                                onPressed: () {
                                  _durationController.text = s.toString();
                                  callingVm.setDurationSecs(s);
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        callingVm.isConnected
                            ? '✅ Verified connected: Meets the ≥${AppConfig.minConnectedDurationSecs}s connected threshold.'
                            : '⚠️ Under ${AppConfig.minConnectedDurationSecs}s minimum: System will record call as not connected.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: callingVm.isConnected
                              ? AppTheme.success
                              : const Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Call Outcome Selector
                const Text(
                  'Call Outcome *',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 10),

                // Connected Outcomes (Interested, Not Interested, Callback)
                const Text(
                  'CONNECTED (Talk time ≥10s)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildOutcomeButton(
                      label: 'Interested',
                      icon: Icons.thumb_up_alt_rounded,
                      outcome: PostCallOutcome.interested,
                      callingVm: callingVm,
                      color: AppTheme.success,
                      enabled: callingVm.isConnected, // Enforce 10s rule!
                    ),
                    _buildOutcomeButton(
                      label: 'Not Interested',
                      icon: Icons.thumb_down_alt_rounded,
                      outcome: PostCallOutcome.notInterested,
                      callingVm: callingVm,
                      color: AppTheme.danger,
                    ),
                    _buildOutcomeButton(
                      label: 'Callback Requested',
                      icon: Icons.event_repeat_rounded,
                      outcome: PostCallOutcome.callback,
                      callingVm: callingVm,
                      color: AppTheme.primary,
                    ),
                    _buildOutcomeButton(
                      label: 'Wrong Number',
                      icon: Icons.wrong_location_rounded,
                      outcome: PostCallOutcome.wrongNumber,
                      callingVm: callingVm,
                      color: AppTheme.textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Not Connected Outcomes (Ringing, Busy, Off, Not placed)
                const Text(
                  'NOT CONNECTED / UNREACHABLE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildOutcomeButton(
                      label: 'No Answer / Ringing',
                      icon: Icons.ring_volume_rounded,
                      outcome: PostCallOutcome.ringing,
                      callingVm: callingVm,
                      color: AppTheme.warning,
                    ),
                    _buildOutcomeButton(
                      label: 'Busy / Declined',
                      icon: Icons.phone_busy_rounded,
                      outcome: PostCallOutcome.busy,
                      callingVm: callingVm,
                      color: AppTheme.warning,
                    ),
                    _buildOutcomeButton(
                      label: 'Switched Off',
                      icon: Icons.power_off_rounded,
                      outcome: PostCallOutcome.switchedOff,
                      callingVm: callingVm,
                      color: AppTheme.textMuted,
                    ),
                    _buildOutcomeButton(
                      label: 'Call Not Placed',
                      icon: Icons.cancel_outlined,
                      outcome: PostCallOutcome.notPlaced,
                      callingVm: callingVm,
                      color: AppTheme.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // If NOT INTERESTED: Seed Reasons (§10.2)
                if (callingVm.outcome == PostCallOutcome.notInterested) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Why were they not interested? *',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: callingVm.availableReasons.map((reason) {
                            final isSelected = callingVm.selectedReasonIds
                                .contains(reason.id);
                            return FilterChip(
                              label: Text(reason.label),
                              selected: isSelected,
                              onSelected: (_) =>
                                  callingVm.toggleReason(reason.id),
                              selectedColor: AppTheme.dangerLight,
                              checkmarkColor: AppTheme.danger,
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isSelected
                                    ? AppTheme.danger
                                    : AppTheme.textMain,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _otherReasonController,
                          decoration: const InputDecoration(
                            labelText: 'Other reason (optional)',
                            hintText: 'e.g. Needs approval from senior management',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // If INTERESTED or CALLBACK: Follow-up Scheduler
                if (callingVm.outcome == PostCallOutcome.interested ||
                    callingVm.outcome == PostCallOutcome.callback) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Schedule Next Follow-Up',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _pickFollowUpDateTime,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.background,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_month,
                                    size: 20, color: AppTheme.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    callingVm.followUpDateTime != null
                                        ? DateFormat('EEE, dd MMM yyyy • hh:mm a')
                                            .format(callingVm.followUpDateTime!)
                                        : 'Select follow-up date and time',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: callingVm.followUpDateTime != null
                                          ? AppTheme.textMain
                                          : AppTheme.textMuted,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down,
                                    color: AppTheme.textMuted),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Follow-up Channel:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: ['call', 'whatsapp', 'email', 'meeting']
                              .map((type) {
                            final isSel = callingVm.followUpType == type;
                            return ChoiceChip(
                              label: Text(type.toUpperCase()),
                              selected: isSel,
                              onSelected: (_) =>
                                  callingVm.setFollowUp(callingVm.followUpDateTime, type),
                              selectedColor: AppTheme.primary,
                              labelStyle: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isSel ? Colors.white : AppTheme.textMain,
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Notes Field
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Call Notes',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _notesController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText:
                              'Summary of conversation, objections, or next steps...',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Error Message Banner if validation failed
                if (callingVm.errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppTheme.danger, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            callingVm.errorMessage!,
                            style: const TextStyle(
                              color: AppTheme.danger,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Submit Button
                ElevatedButton(
                  onPressed: callingVm.isLoading ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: callingVm.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit Disposition & Unlock Queue',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionBadge(bool isConnected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isConnected ? AppTheme.successLight : AppTheme.warningLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isConnected
              ? AppTheme.success.withOpacity(0.3)
              : AppTheme.warning.withOpacity(0.3),
        ),
      ),
      child: Text(
        isConnected ? 'Connected (≥10s)' : 'Not Connected (<10s)',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isConnected ? AppTheme.success : const Color(0xFFB45309),
        ),
      ),
    );
  }

  Widget _buildOutcomeButton({
    required String label,
    required IconData icon,
    required PostCallOutcome outcome,
    required CallingViewModel callingVm,
    required Color color,
    bool enabled = true,
  }) {
    final isSelected = callingVm.outcome == outcome;

    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: OutlinedButton.icon(
        onPressed: enabled ? () => callingVm.setOutcome(outcome) : null,
        icon: Icon(icon, size: 16, color: isSelected ? Colors.white : color),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          backgroundColor: isSelected ? color : Colors.white,
          foregroundColor: isSelected ? Colors.white : AppTheme.textMain,
          side: BorderSide(
            color: isSelected ? color : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
