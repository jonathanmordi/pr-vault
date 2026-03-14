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

    final filtered = _entries
        .where((e) => e['event'] == _selectedEvent)
        .toList();

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

  Color _heatColor(double delta) {
    if (delta >= 2.0) return const Color(0xFFFF4500);
    if (delta >= 1.0) return const Color(0xFFFF8C00);
    if (delta >= 0.5) return const Color(0xFFFFA500);
    if (delta > 0.0) return const Color(0xFF1DB954);
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PR Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLeaderboard,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
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
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SizedBox(
                  height: 50,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _events.length,
                    itemBuilder: (context, i) {
                      final event = _events[i];
                      final selected = event == _selectedEvent;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8, top: 8),
                        child: FilterChip(
                          label: Text(event),
                          selected: selected,
                          onSelected: (_) =>
                              setState(() => _selectedEvent = event),
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final entry = _filtered[index];
                      final name =
                          entry['profiles']?['full_name'] ?? 'Unknown';
                      final delta =
                          (entry['improvement_delta_pct'] ?? 0.0) as num;
                      final color = _heatColor(delta.toDouble());

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(name),
                        subtitle: Text(
                          _selectedEvent == 'All'
                              ? 'Best: ${entry['event']} — ${entry['best_display']}'
                              : '${entry['event']} — ${entry['best_display']}',
                        ),
                        trailing: _isHeatMap
                            ? (delta > 0
                                ? Text(
                                    '+${delta.toStringAsFixed(2)}%',
                                    style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : const Text('—'))
                            : Text(
                                entry['best_display'] ?? '—',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
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