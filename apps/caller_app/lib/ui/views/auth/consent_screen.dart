import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../view_models/auth_view_model.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _checkLeadsOnly = false;
  bool _checkDurationOnly = false;
  bool _checkNoPersonalData = false;

  bool get _canProceed =>
      _checkLeadsOnly && _checkDurationOnly && _checkNoPersonalData;

  Future<void> _handleAccept() async {
    final authVm = context.read<AuthViewModel>();
    await authVm.acceptPrivacyConsent();
    if (mounted) {
      context.go('/queue');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Privacy & Verification Notice'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Security shield icon
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.successLight,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.success.withOpacity(0.3)),
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    color: AppTheme.success,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Personal SIM Call Verification',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Orvyqmedia uses Android call-log verification so employees can use their personal SIM without paying for expensive telephony bridges. Your privacy is strictly protected by architectural rules.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // Guaranteed Privacy Safeguards
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'What is Protected (On-Device Filtering & Privacy)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildRuleRow(
                      Icons.shield_outlined,
                      'Assigned Leads Matching Only',
                      'Recent outgoing logs are queried on-device to match your assigned lead. Only matching work calls are retained and uploaded.',
                    ),
                    const SizedBox(height: 10),
                    _buildRuleRow(
                      Icons.phone_disabled_outlined,
                      'Zero Retention of Personal Calls',
                      'Personal and unrelated calls scanned in temporary memory are immediately discarded on-device and are NEVER saved or uploaded.',
                    ),
                    const SizedBox(height: 10),
                    _buildRuleRow(
                      Icons.mic_off_outlined,
                      'No Audio Recording',
                      'The app does not record, transmit, or store any call audio.',
                    ),
                    const SizedBox(height: 10),
                    _buildRuleRow(
                      Icons.block_outlined,
                      'No Contacts or Messages',
                      'Contacts, SMS, and WhatsApp messages are completely inaccessible to this app.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'Please acknowledge each condition below to proceed:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMain,
                ),
              ),
              const SizedBox(height: 12),

              // Checkbox 1
              CheckboxListTile(
                value: _checkLeadsOnly,
                onChanged: (val) => setState(() => _checkLeadsOnly = val ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'I understand that outgoing call logs are queried on-device to match calls made to my assigned leads.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMain),
                ),
              ),

              // Checkbox 2
              CheckboxListTile(
                value: _checkDurationOnly,
                onChanged: (val) =>
                    setState(() => _checkDurationOnly = val ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'I consent to uploading the call timestamp, duration (≥10s connected threshold), and verification source for assigned leads only.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMain),
                ),
              ),

              // Checkbox 3
              CheckboxListTile(
                value: _checkNoPersonalData,
                onChanged: (val) =>
                    setState(() => _checkNoPersonalData = val ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'I understand that personal calls, contacts, and messages are never stored on disk or uploaded to any server.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMain),
                ),
              ),
              const SizedBox(height: 28),

              // Accept Button
              ElevatedButton(
                onPressed: _canProceed ? _handleAccept : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  disabledBackgroundColor: AppTheme.border,
                ),
                child: const Text('Accept & Enter Queue'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  context.read<AuthViewModel>().signOut();
                  context.go('/login');
                },
                child: const Text('Decline & Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRuleRow(IconData icon, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMain,
                ),
              ),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
