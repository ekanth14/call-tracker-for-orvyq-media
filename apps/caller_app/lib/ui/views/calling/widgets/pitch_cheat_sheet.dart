import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';

class ScriptItem {
  final String title;
  final String category; // 'pitch', 'objection', 'closing'
  final String content;

  const ScriptItem({
    required this.title,
    required this.category,
    required this.content,
  });
}

class PitchCheatSheet extends StatefulWidget {
  final String leadName;
  final String? company;

  const PitchCheatSheet({
    super.key,
    required this.leadName,
    this.company,
  });

  static void show(BuildContext context, {required String leadName, String? company}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PitchCheatSheet(leadName: leadName, company: company),
    );
  }

  @override
  State<PitchCheatSheet> createState() => _PitchCheatSheetState();
}

class _PitchCheatSheetState extends State<PitchCheatSheet> {
  String _selectedCategory = 'all';

  final List<ScriptItem> _scripts = const [
    ScriptItem(
      title: 'Opening Elevator Pitch',
      category: 'pitch',
      content:
          "Hi {name}, this is {caller} from Orvyq Media. I'm reaching out because we help growing companies increase qualified sales pipeline by 3x without burning ad spend. Do you have 60 seconds for a quick intro?",
    ),
    ScriptItem(
      title: 'Objection: "Not Interested Right Now"',
      category: 'objection',
      content:
          "I completely understand, {name}. Most of our best partners said the exact same thing before seeing our 5-minute case study. Would you be open to just reviewing how we solved lead quality for peers in your space, with zero commitment?",
    ),
    ScriptItem(
      title: 'Objection: "Send Me an Email / Brochure"',
      category: 'objection',
      content:
          "I'd be glad to send that over! So I don't clutter your inbox with irrelevant slides, what is the single biggest priority your team is focused on solving this quarter?",
    ),
    ScriptItem(
      title: 'Objection: "Already Have an Agency / Team"',
      category: 'objection',
      content:
          "That's great! We actually work alongside in-house teams as performance accelerators. When is your next strategy review with them? I'd love to share an audit of untapped revenue channels they might have missed.",
    ),
    ScriptItem(
      title: 'Closing: 10-Minute Discovery Call',
      category: 'closing',
      content:
          "It sounds like there is strong synergy here. I'd love to connect you with our senior growth strategist for a focused 10-minute discovery call. Does Tuesday at 3:00 PM or Wednesday at 11:30 AM suit your calendar?",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _selectedCategory == 'all'
        ? _scripts
        : _scripts.where((s) => s.category == _selectedCategory).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.psychology_outlined, color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sales Scripts & Objections',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMain,
                        ),
                      ),
                      Text(
                        'Corporate rebuttals & closing frameworks',
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Category Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _buildFilterChip('All', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('🎤 Opening Pitches', 'pitch'),
                const SizedBox(width: 8),
                _buildFilterChip('🛡️ Objection Handlers', 'objection'),
                const SizedBox(width: 8),
                _buildFilterChip('🎯 Closings', 'closing'),
              ],
            ),
          ),

          const Divider(height: 24),

          // Scripts List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (ctx, idx) {
                final item = filtered[idx];
                final formattedContent = item.content
                    .replaceAll('{name}', widget.leadName.isNotEmpty ? widget.leadName : 'Sir/Ma\'am')
                    .replaceAll('{caller}', 'our representative');

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textMain,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: formattedContent));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Script copied to clipboard'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.copy_rounded, size: 16, color: Colors.grey.shade600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formattedContent,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: AppTheme.textMain,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedCategory == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? Colors.white : AppTheme.textMain,
        ),
      ),
      selected: isSelected,
      selectedColor: AppTheme.primary,
      backgroundColor: AppTheme.background,
      side: BorderSide(color: isSelected ? AppTheme.primary : AppTheme.border),
      onSelected: (_) => setState(() => _selectedCategory = value),
    );
  }
}
