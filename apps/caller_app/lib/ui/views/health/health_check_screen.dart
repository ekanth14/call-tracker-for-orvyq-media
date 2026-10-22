import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/background_sync_service.dart';
import '../../../data/services/permission_service.dart';

class HealthCheckScreen extends StatefulWidget {
  const HealthCheckScreen({super.key});

  @override
  State<HealthCheckScreen> createState() => _HealthCheckScreenState();
}

class _HealthCheckScreenState extends State<HealthCheckScreen> {
  final _permissionService = PermissionService();
  PermissionStatusReport? _report;
  int _pendingSyncCount = 0;
  int _failedSyncCount = 0;
  List<SyncItem> _failedItems = [];
  bool _isLoading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() => _isLoading = true);
    final report = await _permissionService.checkPermissions();
    final count = await BackgroundSyncService.getPendingSyncCount();
    final failedCount = await BackgroundSyncService.getFailedSyncCount();
    final failedItems = await BackgroundSyncService.getFailedSyncItems();
    if (mounted) {
      setState(() {
        _report = report;
        _pendingSyncCount = count;
        _failedSyncCount = failedCount;
        _failedItems = failedItems;
        _isLoading = false;
      });
    }
  }

  Future<void> _triggerManualSync() async {
    setState(() => _isSyncing = true);
    await BackgroundSyncService.processSyncQueue();
    await _checkStatus();
    if (mounted) {
      setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Device Health & Permissions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkStatus,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Health Overview Banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _report?.allEssentialGranted == true
                          ? AppTheme.successLight
                          : AppTheme.warningLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _report?.allEssentialGranted == true
                            ? AppTheme.success.withOpacity(0.3)
                            : AppTheme.warning.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _report?.allEssentialGranted == true
                              ? Icons.check_circle_rounded
                              : Icons.warning_amber_rounded,
                          color: _report?.allEssentialGranted == true
                              ? AppTheme.success
                              : AppTheme.warning,
                          size: 28,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _report?.allEssentialGranted == true
                                    ? 'System Ready for Calling'
                                    : 'Action Needed for Verification',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _report?.allEssentialGranted == true
                                      ? AppTheme.success
                                      : const Color(0xFF92400E),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _report?.allEssentialGranted == true
                                    ? 'All essential permissions and device settings are active.'
                                    : 'Some permissions or battery settings need configuration.',
                                style: const TextStyle(
                                  fontSize: 12,
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

                  // Background Sync Status Card (§5.2)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _failedSyncCount > 0
                            ? AppTheme.danger.withOpacity(0.4)
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
                              'Background Sync & Offline Proofs',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textMain,
                              ),
                            ),
                            if (_isSyncing)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else if (_pendingSyncCount > 0 || _failedSyncCount > 0)
                              TextButton.icon(
                                onPressed: _triggerManualSync,
                                icon: const Icon(Icons.sync, size: 16),
                                label: const Text('Sync Now', style: TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              _failedSyncCount > 0
                                  ? Icons.error_outline_rounded
                                  : _pendingSyncCount == 0
                                      ? Icons.cloud_done_rounded
                                      : Icons.cloud_upload_outlined,
                              color: _failedSyncCount > 0
                                  ? AppTheme.danger
                                  : _pendingSyncCount == 0
                                      ? AppTheme.success
                                      : AppTheme.warning,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _failedSyncCount > 0
                                    ? '$_failedSyncCount offline item(s) failed sync.'
                                    : _pendingSyncCount == 0
                                        ? 'All call proofs synchronized with server.'
                                        : '$_pendingSyncCount offline call proof(s) pending sync.',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _failedSyncCount > 0
                                      ? AppTheme.danger
                                      : _pendingSyncCount == 0
                                          ? AppTheme.textMain
                                          : const Color(0xFF92400E),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_failedItems.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          const Text(
                            'Failed Uploads (Visible For Audit):',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.danger,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ..._failedItems.map((item) {
                            final phone = item.payload['p_number_e164'] ?? 'Unknown';
                            final duration = item.payload['p_duration_secs'] ?? 0;
                            final err = item.lastError ?? 'Unknown submission error';
                            return Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '$phone (${duration}s)',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.textMain,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              minimumSize: const Size(40, 24),
                                            ),
                                            onPressed: () async {
                                              await BackgroundSyncService.retryFailedItem(item.id);
                                              _checkStatus();
                                            },
                                            child: const Text('Retry', style: TextStyle(fontSize: 11)),
                                          ),
                                          const SizedBox(width: 8),
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              minimumSize: const Size(40, 24),
                                              foregroundColor: AppTheme.danger,
                                            ),
                                            onPressed: () async {
                                              await BackgroundSyncService.removeSyncItem(item.id);
                                              _checkStatus();
                                            },
                                            child: const Text('Dismiss', style: TextStyle(fontSize: 11)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    err,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF991B1B),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    'Permissions Status',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Phone / Call Log permission
                  _buildPermissionTile(
                    title: 'Phone & Call Log Permission',
                    description:
                        'Allows reading outgoing duration and timestamp for assigned leads only (§6).',
                    isGranted: _report?.phoneGranted ?? false,
                    onRequest: () async {
                      await _permissionService.requestPhonePermission();
                      _checkStatus();
                    },
                  ),

                  // Battery Exemption
                  _buildPermissionTile(
                    title: 'Battery Optimization Exemption',
                    description:
                        'Prevents phone manufacturers from killing the app in the background (§5.2).',
                    isGranted: _report?.batteryOptimizationIgnored ?? false,
                    onRequest: () async {
                      await _permissionService.requestBatteryExemption();
                      _checkStatus();
                    },
                  ),

                  // Notification Permission
                  _buildPermissionTile(
                    title: 'Notification Alerts',
                    description:
                        'Notifies you of scheduled follow-ups and unsubmitted call notes.',
                    isGranted: _report?.notificationsGranted ?? false,
                    onRequest: () async {
                      await _permissionService.requestNotificationPermission();
                      _checkStatus();
                    },
                  ),

                  const SizedBox(height: 24),

                  // OEM Device Background Guidance (§5.2)
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
                          'Phone Settings Guide (Xiaomi, Samsung, Realme)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Certain Android devices aggressively kill background apps. If you experience missed syncs:\n\n'
                          '1. Xiaomi/MIUI: Enable "Autostart" and set Battery Saver to "No restrictions".\n'
                          '2. Samsung: Add Orvyqmedia Caller to "Never sleeping apps".\n'
                          '3. Realme/Oppo: Turn on "Allow background activity" in App info.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton(
                          onPressed: () =>
                              _permissionService.openAppSettingsPage(),
                          child: const Text('Open App Settings in Android'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback onRequest,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(
            isGranted ? Icons.check_circle : Icons.cancel_outlined,
            color: isGranted ? AppTheme.success : AppTheme.danger,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (!isGranted) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRequest,
              child: const Text('Enable', style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}
