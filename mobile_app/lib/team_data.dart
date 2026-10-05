import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pr_stats.dart';

final _supabase = Supabase.instance.client;

/// One load of the team's scraped results. The leaderboard, trending list,
/// activity feed and rival cards all read from the same snapshot, so moving
/// between them doesn't refetch.
class TeamSnapshot {
  final String? userId;

  /// track_prs rows joined with profiles(full_name, gender).
  final List<Map<String, dynamic>> prs;

  /// Every meet_appearances row for the team, oldest first.
  final List<Map<String, dynamic>> appearances;

  final List<Map<String, dynamic>> records;

  TeamSnapshot({
    required this.userId,
    required this.prs,
    required this.appearances,
    required this.records,
  });

  late final Map<String, String> _names = {
    for (final p in prs)
      p['athlete_id'] as String:
          (p['profiles']?['full_name'] as String?) ?? 'Unknown',
  };

  late final Map<String, String> _genders = {
    for (final p in prs)
      p['athlete_id'] as String: (p['profiles']?['gender'] as String?) ?? 'M',
  };

  String nameOf(String athleteId) => _names[athleteId] ?? 'Unknown';
  String genderOf(String athleteId) => _genders[athleteId] ?? 'M';

  /// Every PR the team has set, newest first.
  late final List<PrEvent> prEvents =
      detectPrs(appearances, records: records, genderByAthlete: _genders);

  late final List<TrendWindow> windows =
      trendWindows(prEvents, DateTime.now());

  /// The season that points are reported for by default.
  late final TrendWindow currentSeason = defaultTrendWindow(windows);

  int pointsFor(String athleteId, TrendWindow window) => prEvents
      .where((p) => p.athleteId == athleteId && window.contains(p.date))
      .fold(0, (sum, p) => sum + p.points);

  Map<String, Rival> rivalsOf(String athleteId) =>
      rivalsFor(athleteId, _genders[athleteId], prs);
}

/// Caches the latest [TeamSnapshot] for the signed-in user.
class TeamData {
  TeamData._();
  static final instance = TeamData._();

  TeamSnapshot? _snapshot;
  Future<TeamSnapshot>? _inFlight;

  /// The signed-in user's id. Replaceable so tests can run without Supabase.
  String? Function() currentUserId = () => _supabase.auth.currentUser?.id;

  /// Replaces the cache, for tests.
  @visibleForTesting
  void seed(TeamSnapshot snapshot) => _snapshot = snapshot;

  /// The cached snapshot, unless it belongs to a different (signed-out) user.
  TeamSnapshot? get cached {
    final s = _snapshot;
    return s != null && s.userId == currentUserId() ? s : null;
  }

  /// Returns the cached snapshot, or fetches one. Concurrent callers share a
  /// single request. [force] always refetches.
  Future<TeamSnapshot> load({bool force = false}) {
    final c = cached;
    if (!force && c != null) return Future.value(c);
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<TeamSnapshot> _fetch() async {
    final userId = currentUserId();
    final results = await Future.wait([
      _fetchAll((from, to) => _supabase
          .from('track_prs')
          .select(
              'event, best_display, best_mark_meters, best_time_seconds, improvement_delta_pct, set_on, set_at_meet, athlete_id, profiles(full_name, gender)')
          .order('athlete_id')
          .order('event')
          .range(from, to)),
      // Ordered by the table's unique key so pages never overlap or skip.
      _fetchAll((from, to) => _supabase
          .from('meet_appearances')
          .select(
              'athlete_id, event, time_seconds, mark_meters, display_value, meet_name, meet_date')
          .order('meet_date')
          .order('athlete_id')
          .order('event')
          .order('meet_name')
          .order('display_value')
          .range(from, to)),
      _supabase.from('school_records').select(),
    ]);
    final snapshot = TeamSnapshot(
      userId: userId,
      prs: results[0],
      appearances: results[1],
      records: List<Map<String, dynamic>>.from(results[2]),
    );
    _snapshot = snapshot;
    return snapshot;
  }

  /// PostgREST caps each response (1000 rows by default), so page through
  /// until a request comes back empty.
  static Future<List<Map<String, dynamic>>> _fetchAll(
      PostgrestTransformBuilder<PostgrestList> Function(int from, int to)
          page) async {
    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    while (true) {
      final batch = await page(rows.length, rows.length + pageSize - 1);
      if (batch.isEmpty) return rows;
      rows.addAll(batch);
    }
  }
}
