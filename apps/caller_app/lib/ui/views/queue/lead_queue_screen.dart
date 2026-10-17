import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../view_models/auth_view_model.dart';
import '../../view_models/calling_view_model.dart';
import '../../view_models/queue_view_model.dart';
import '../../view_models/stats_view_model.dart';
import 'widgets/call_lock_banner.dart';
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

    final success = await callingVm.initiateCall(lead);
    if (success && mounted) {
      // Navigate to the active calling / waiting screen
      context.push('/calling');
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
            tooltip: 'System Health Check',
            icon: const Icon(Icons.health_and_safety_outlined),
            onPressed: () => context.push('/health'),
          ),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await authVm.signOut();
              if (mounted) context.go('/login');
            },
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
}
