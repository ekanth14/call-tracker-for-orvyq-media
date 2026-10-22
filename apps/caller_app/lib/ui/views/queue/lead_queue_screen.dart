import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../view_models/auth_view_model.dart';
import '../../view_models/calling_view_model.dart';
import '../../view_models/queue_view_model.dart';
import '../../view_models/stats_view_model.dart';
import 'widgets/call_lock_banner.dart';
import 'widgets/daily_quota_card.dart';
import 'widgets/lead_card.dart';
import 'widgets/stats_header.dart';

class LeadQueueScreen extends StatefulWidget {
  const LeadQueueScreen({super.key});

  @override
  State<LeadQueueScreen> createState() => _LeadQueueScreenState();
}

class _LeadQueueScreenState extends State<LeadQueueScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final queueVm = context.read<QueueViewModel>();
    final callingVm = context.read<CallingViewModel>();
    final statsVm = context.read<StatsViewModel>();

    await Future.wait([
      queueVm.loadLeads(),
      callingVm.checkCallLock(),
      callingVm.fetchWorkStatus(),
      statsVm.loadTodayStats(),
    ]);

    // If call lock is active on open, prompt caller
    if (callingVm.isCallLocked && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Call in progress: Please complete notes for your previous call.',
          ),
          backgroundColor: AppTheme.warning,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _onCallLead(dynamic lead) async {
    final callingVm = context.read<CallingViewModel>();

    if (callingVm.isCallLocked) {
      context.push('/dialog');
      return;
    }

    // Work Login Check: Callers must clock in before initiating lead calls (§1 & §2)
    if (!callingVm.isClockedIn) {
      final shouldClockIn = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.access_time_rounded, color: AppTheme.primary),
              SizedBox(width: 8),
              Text('Start Shift to Call'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You are currently Off Duty. You must clock in (Start Shift) to begin your work period before placing calls to leads.',
                style: TextStyle(fontSize: 14, color: AppTheme.textMain),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 18, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Privacy Guarantee: Call tracking is active ONLY during work periods for assigned leads. Personal calls while off duty are never monitored or tracked.',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              icon: const Icon(Icons.login_rounded, size: 16),
              label: const Text('Clock In & Call'),
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      );

      if (shouldClockIn != true) return;

      final clockedIn = await callingVm.clockIn();
      if (!clockedIn) {
        if (mounted && callingVm.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(callingVm.errorMessage!),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
        return;
      }
    }

    final success = await callingVm.initiateCall(lead);
    if (success && mounted) {
      // Navigate to the active calling / waiting screen
      context.push('/calling');
    } else if (!success && mounted && callingVm.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(callingVm.errorMessage!),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authVm = context.watch<AuthViewModel>();
    final queueVm = context.watch<QueueViewModel>();
    final callingVm = context.watch<CallingViewModel>();
    final statsVm = context.watch<StatsViewModel>();

    final callerName = authVm.profile?.fullName ?? 'Caller';
    final callerSim = authVm.profile?.mobileE164 ?? 'Personal SIM';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              callerName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMain,
              ),
            ),
            Text(
              'SIM: $callerSim',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Team Community Chat',
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => context.push('/chat'),
          ),
          IconButton(
            tooltip: 'My Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push('/profile'),
          ),
          IconButton(
            tooltip: 'System Health Check',
            icon: const Icon(Icons.health_and_safety_outlined),
            onPressed: () => context.push('/health'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppTheme.primary,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Call Lock Alert Banner if active
            if (callingVm.isCallLocked)
              CallLockBanner(
                activeLead: callingVm.activeLead,
                onTapCompleteDialog: () => context.push('/dialog'),
              ),

            // Daily Stats Header
            StatsHeader(
              stats: statsVm.stats,
              onRefresh: () => statsVm.loadTodayStats(),
            ),
            const SizedBox(height: 12),

            // Work Shift & Off-Duty Privacy Banner
            _buildWorkStatusBanner(context, callingVm),
            const SizedBox(height: 12),

            // Mandatory 2-Hour Daily Work Quota Card (Interpretation A)
            const DailyQuotaCard(),
            const SizedBox(height: 16),

            // Search Bar
            TextField(
              controller: _searchController,
              onChanged: queueVm.setSearchQuery,
              decoration: InputDecoration(
                hintText: 'Search by lead name, phone, or company...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          queueVm.setSearchQuery('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 12),

            // Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All Leads', QueueFilter.all, queueVm),
                  const SizedBox(width: 8),
                  _buildFilterChip('Pending', QueueFilter.pending, queueVm),
                  const SizedBox(width: 8),
                  _buildFilterChip('Follow-ups', QueueFilter.followUp, queueVm),
                  const SizedBox(width: 8),
                  _buildFilterChip('Completed', QueueFilter.completed, queueVm),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Leads List Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Assigned Leads (${queueVm.filteredLeads.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
                if (queueVm.isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Leads List or Empty State
            if (queueVm.filteredLeads.isEmpty && !queueVm.isLoading) ...[
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: [
                    Icon(Icons.assignment_outlined,
                        size: 48, color: AppTheme.textMuted.withOpacity(0.5)),
                    const SizedBox(height: 12),
                    const Text(
                      'No leads found',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Any new leads assigned by the owner will appear here automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ] else ...[
              ...queueVm.filteredLeads.map((lead) {
                return LeadCard(
                  lead: lead,
                  isCallLocked: callingVm.isCallLocked,
                  onCall: () => _onCallLead(lead),
                );
              }),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
      String label, QueueFilter filter, QueueViewModel queueVm) {
    final isSelected = queueVm.currentFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => queueVm.setFilter(filter),
      selectedColor: AppTheme.primary,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: isSelected ? Colors.white : AppTheme.textMain,
      ),
      side: BorderSide(
        color: isSelected ? AppTheme.primary : AppTheme.border,
      ),
    );
  }

  Widget _buildWorkStatusBanner(BuildContext context, CallingViewModel callingVm) {
    final isClockedIn = callingVm.isClockedIn;
    final isLoading = callingVm.isWorkStatusLoading;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isClockedIn ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isClockedIn ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isClockedIn ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isClockedIn ? Icons.work_history_rounded : Icons.work_off_outlined,
              size: 20,
              color: isClockedIn ? const Color(0xFF047857) : const Color(0xFFB45309),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isClockedIn ? const Color(0xFF10B981) : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isClockedIn ? 'ON DUTY (Active Shift)' : 'OFF DUTY (Logged Out)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isClockedIn ? const Color(0xFF065F46) : const Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isClockedIn
                      ? 'Call tracking active for leads • Personal calls excluded'
                      : 'Call tracking paused • Personal calls strictly private',
                  style: TextStyle(
                    fontSize: 11,
                    color: isClockedIn ? const Color(0xFF047857) : const Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isClockedIn ? Colors.red.shade600 : AppTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: isLoading
                ? null
                : () async {
                    if (isClockedIn) {
                      final success = await callingVm.clockOut();
                      if (!success && context.mounted && callingVm.errorMessage != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(callingVm.errorMessage!),
                            backgroundColor: AppTheme.danger,
                          ),
                        );
                      }
                    } else {
                      final success = await callingVm.clockIn();
                      if (!success && context.mounted && callingVm.errorMessage != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(callingVm.errorMessage!),
                            backgroundColor: AppTheme.danger,
                          ),
                        );
                      }
                    }
                  },
            child: isLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    isClockedIn ? 'Clock Out' : 'Clock In',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }
}
