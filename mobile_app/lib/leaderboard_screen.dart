import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';

final supabase = Supabase.instance.client;

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String _selectedEvent = 'All';
  List<String> _events = ['All'];

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    setState(() => _loading = true);

    final response = await supabase
        .from('track_prs')
        .select('event, best_display, improvement_delta_pct, profiles(full_name)')
        .order('improvement_delta_pct', ascending: false);

    final data = List<Map<String, dynamic>>.from(response);

    // build event filter list
    final events = ['All', ...{...data.map((e) => e['event'] as String)}];

    setState(() {
      _entries = data;
      _events = events;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    if (_selectedEvent == 'All') return _entries;
    return _entries.where((e) => e['event'] == _selectedEvent).toList();
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
        title: const Text('Heat Map'),
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Event filter chips
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
                // Leaderboard list
                Expanded(
                  child: ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final entry = _filtered[index];
                      final name = entry['profiles']?['full_name'] ?? 'Unknown';
                      final event = entry['event'] ?? '';
                      final display = entry['best_display'] ?? '';
                      final delta = (entry['improvement_delta_pct'] ?? 0.0) as num;
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
                        subtitle: Text('$event — $display'),
                        trailing: delta > 0
                            ? Text(
                                '+${delta.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : const Text('—'),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}