import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/phone_formatter.dart';
import '../../../../core/utils/whatsapp_helper.dart';
import '../../../../data/models/lead_model.dart';

class LeadCard extends StatelessWidget {
  final LeadModel lead;
  final bool isCallLocked;
  final VoidCallback onCall;

  const LeadCard({
    super.key,
    required this.lead,
    required this.isCallLocked,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Name & Status badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lead.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    ),
                    if (lead.company != null && lead.company!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.business_outlined,
                              size: 14, color: AppTheme.textMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              lead.company!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              _buildStatusBadge(lead.status),
            ],
          ),
          const SizedBox(height: 12),

          // Details row: Phone & City
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phone_outlined,
                        size: 14, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      PhoneFormatter.formatE164(lead.phoneE164),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMain,
                      ),
                    ),
                  ],
                ),
              ),
              if (lead.city != null && lead.city!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: AppTheme.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        lead.city!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          // Follow-up reminder if present
          if (lead.nextFollowUpAt != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.warningLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.alarm, size: 14, color: AppTheme.warning),
                  const SizedBox(width: 6),
                  Text(
                    'Follow-up due: ${DateFormatter.formatFull(lead.nextFollowUpAt)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Divider(height: 24, thickness: 1, color: AppTheme.border),

          // Bottom row: Attempt count / Last call & Call button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lead.attemptCount == 0
                        ? 'Not dialed yet'
                        : 'Attempts: ${lead.attemptCount}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  if (lead.lastCallAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Last: ${DateFormatter.formatRelative(lead.lastCallAt)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ],
              ),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // One-Tap WhatsApp Follow-Up
                  IconButton(
                    tooltip: 'Send WhatsApp Follow-Up',
                    icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF25D366), size: 19),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.1),
                      padding: const EdgeInsets.all(10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      WhatsAppHelper.openFollowUpChat(
                        phoneE164: lead.phoneE164,
                        leadName: lead.name,
                        callerName: 'Orvyq Media',
                      );
                    },
                  ),
                  const SizedBox(width: 8),

                  // Big Call Button
                  ElevatedButton.icon(
                    onPressed: isCallLocked ? null : onCall,
                    icon: const Icon(Icons.phone_rounded, size: 18),
                    label: const Text('Call Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.border,
                      minimumSize: const Size(110, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case 'new':
      case 'assigned':
        bg = AppTheme.infoLight;
        fg = AppTheme.info;
        label = 'Pending';
        break;
      case 'in_progress':
        bg = AppTheme.warningLight;
        fg = AppTheme.warning;
        label = 'In Progress';
        break;
      case 'follow_up':
        bg = AppTheme.warningLight;
        fg = AppTheme.warning;
        label = 'Follow Up';
        break;
      case 'interested':
        bg = AppTheme.successLight;
        fg = AppTheme.success;
        label = 'Interested';
        break;
      case 'not_interested':
        bg = AppTheme.dangerLight;
        fg = AppTheme.danger;
        label = 'Not Interested';
        break;
      default:
        bg = AppTheme.background;
        fg = AppTheme.textMuted;
        label = status.replaceAll('_', ' ');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
