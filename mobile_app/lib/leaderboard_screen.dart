import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _grouped = [];
  bool _loading = true;
  String _selectedEvent = 'All';
  List<String> _events = ['All'];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadLeaderboard();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLeaderboard() async {
    setState(() => _loading = true);

    final response = await supabase
        .from('track_prs')
        .select(
            'event, best_display, best_mark_meters, best_time_seconds, improvement_delta_pct, athlete_id, profiles(full_name)')
        .order('improvement_delta_pct', ascending: false);

    final data = List<Map<String, dynamic>>.from(response);
    final events = ['All', ...{...data.map((e) => e['event'] as String)}];

    final Map<String, Map<String, dynamic>> best = {};
    for (final entry in data) {
      final athleteId = entry['athlete_id'] as String;
      final delta = (entry['improvement_delta_pct'] ?? 0.0) as num;
      if (!best.containsKey(athleteId) ||
          delta > (best[athleteId]!['improvement_delta_pct'] as num)) {
        best[athleteId] = entry;
      }
    }

    final grouped = best.values.toList()
      ..sort((a, b) => (b['improvement_delta_pct'] as num)
          .compareTo(a['improvement_delta_pct'] as num));

    setState(() {
      _entries = data;
      _events = events;
      _loading = false;
      _grouped = grouped;
    });
  }

  bool get _isField => ['HJ', 'LJ', 'TJ', 'PV', 'SP', 'DT', 'HT', 'JT']
      .contains(_selectedEvent.toUpperCase());

  bool get _isHeatMap => _tabController.index == 0;

  List<Map<String, dynamic>> get _filtered {
    if (_selectedEvent == 'All') return _grouped;

    final filtered =
        _entries.where((e) => e['event'] == _selectedEvent).toList();

    if (_isHeatMap) {
      filtered.sort((a, b) => (b['improvement_delta_pct'] as num? ?? 0)
          .compareTo(a['improvement_delta_pct'] as num? ?? 0));
    } else {
      if (_isField) {
        filtered.sort((a, b) => (b['best_mark_meters'] as num? ?? 0)
            .compareTo(a['best_mark_meters'] as num? ?? 0));
      } else {
        filtered.sort((a, b) =>
            (a['best_time_seconds'] as num? ?? 9999)
                .compareTo(b['best_time_seconds'] as num? ?? 9999));
      }
    }
    return filtered;
  }

  Widget _rankCircle(int index, num delta, bool isDark) {
    final isTop = index == 0 && delta > 0;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isTop
            ? const Color(0xFFB80C09)
            : isDark
                ? const Color(0x14FFFFFF)
                : const Color(0xFFF0EDEA),
        border: isTop
            ? null
            : Border.all(
                color: isDark
                    ? const Color(0x18FFFFFF)
                    : const Color(0xFFE0DEDB),
                width: 1,
              ),
      ),
      child: Center(
        child: Text(
          '${index + 1}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isTop
                ? Colors.white
                : isDark
                    ? const Color(0xFF888888)
                    : const Color(0xFF444444),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor =
        isDark ? const Color(0x0FFFFFFF) : const Color(0xFFEEECEA);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PR Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loadLeaderboard,
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Heat Map'),
            Tab(text: 'PR Rankings'),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFB80C09),
              ),
            )
          : Column(
              children: [
                Container(
                  height: 48,
                  color: isDark
                      ? const Color(0xFF141301)
                      : const Color(0xFFFFFFFF),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: _events.length,
                    itemBuilder: (context, i) {
                      final event = _events[i];
                      final selected = event == _selectedEvent;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(event),
                          selected: selected,
                          showCheckmark: false,
                          onSelected: (_) =>
                              setState(() => _selectedEvent = event),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      );
                    },
                  ),
                ),
                Divider(height: 1, color: dividerColor),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No results for $_selectedEvent',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFF555555)
                                  : const Color(0xFF999999),
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: dividerColor),
                          itemBuilder: (context, index) {
                            final entry = _filtered[index];
                            final name =
                                entry['profiles']?['full_name'] ?? 'Unknown';
                            final delta =
                                (entry['improvement_delta_pct'] ?? 0.0)
                                    as num;

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  _rankCircle(index, delta, isDark),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: isDark
                                                ? const Color(0xFFE5E7E6)
                                                : const Color(0xFF141301),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _selectedEvent == 'All'
                                              ? 'Best: ${entry['event']} — ${entry['best_display']}'
                                              : '${entry['event']} — ${entry['best_display']}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF888888),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (_isHeatMap)
                                    delta > 0
                                        ? Text(
                                            '+${delta.toStringAsFixed(2)}%',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFFB80C09),
                                            ),
                                          )
                                        : Text(
                                            '—',
                                            style: TextStyle(
                                              color: isDark
                                                  ? const Color(0xFF444444)
                                                  : const Color(0xFFBBBBBB),
                                            ),
                                          )
                                  else if (_selectedEvent != 'All')
                                    Text(
                                      entry['best_display'] ?? '—',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFB80C09),
                                      ),
                                    )
                                  else
                                    Text(
                                      entry['event'] ?? '—',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF888888),
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
}