import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pr_stats.dart';
import 'team_cache.dart';

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

  /// Bumped whenever the rows' shape changes, so an old saved copy is
  /// dropped instead of misread.
  static const cacheVersion = 1;

  Map<String, dynamic> toCache() => {
        'v': cacheVersion,
        'user': userId,
        'prs': prs,
        'appearances': appearances,
        'records': records,
      };

  /// A saved copy for [userId], or null if it's someone else's or from an
  /// older version of the app.
  static TeamSnapshot? fromCache(Map<String, dynamic> data, String userId) {
    if (data['v'] != cacheVersion || data['user'] != userId) return null;
    List<Map<String, dynamic>> rows(Object? list) => [
          for (final r in (list as List? ?? const []))
            Map<String, dynamic>.from(r as Map),
        ];
    return TeamSnapshot(
      userId: userId,
      prs: rows(data['prs']),
      appearances: rows(data['appearances']),
      records: rows(data['records']),
    );
  }

  /// One athlete's PRs (sorted by event) and results (oldest first), as a
  /// profile shows them.
  List<Map<String, dynamic>> prsOf(String athleteId) =>
      prs.where((p) => p['athlete_id'] == athleteId).toList()
        ..sort((a, b) => (a['event'] as String? ?? '').compareTo(b['event'] as String? ?? ''));

  List<Map<String, dynamic>> appearancesOf(String athleteId) =>
      appearances.where((a) => a['athlete_id'] == athleteId).toList();

  late final Map<String, String> _names = {
    for (final p in prs)
      p['athlete_id'] as String:
          (p['profiles']?['full_name'] as String?) ?? 'Unknown',
  };

  late final Map<String, String> _genders = {
    for (final p in prs)
      p['athlete_id'] as String: (p['profiles']?['gender'] as String?) ?? 'M',
  };

  late final Map<String, bool> _current = {
    for (final p in prs)
      p['athlete_id'] as String: (p['profiles']?['on_roster'] as bool?) ?? true,
  };

  late final Map<String, String?> _classYears = {
    for (final p in prs)
      p['athlete_id'] as String: p['profiles']?['class_year'] as String?,
  };

  /// False for alumni: athletes no longer on the current TFRRS roster.
  bool isCurrent(String athleteId) => _current[athleteId] ?? true;

  bool get hasAlumni => _current.containsValue(false);

  /// As TFRRS shows it, e.g. 'SR-4'; see classYearLabel.
  String? classYearOf(String athleteId) => _classYears[athleteId];

  String nameOf(String athleteId) => _names[athleteId] ?? 'Unknown';
  String genderOf(String athleteId) => _genders[athleteId] ?? 'M';

  /// Seasons the team has PRs in, indoor first.
  late final List<String> seasons = seasonsIn(prs);

  /// The season to show first: that of the team's latest track result.
  late final String latestSeason = latestSeasonOf(appearances);

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

  /// Rivals come from the current roster only; alumni aren't chasing anyone.
  Map<String, Rival> rivalsOf(String athleteId) => rivalsFor(
      athleteId,
      _genders[athleteId],
      prs.where((p) => p['athlete_id'] == athleteId || isCurrent(p['athlete_id'] as String)));
}

/// Caches the latest [TeamSnapshot] for the signed-in user, in memory and
/// on the phone. At launch [restore] returns last time's copy right away,
/// while [load] fetches the latest.
class TeamData {
  TeamData._();
  static final instance = TeamData._();

  TeamSnapshot? _snapshot;
  Future<TeamSnapshot>? _inFlight;

  /// Whether [_snapshot] came from the server this session, rather than
  /// from the copy saved on the phone.
  bool _fresh = false;

  /// Where the copy is saved. Replaceable for tests.
  TeamCacheStore store = TeamCacheStore.device();

  /// The signed-in user's id. Replaceable so tests can run without Supabase.
  String? Function() currentUserId = () => _supabase.auth.currentUser?.id;

  /// Forgets this session's data but not the saved copy, like the app
  /// being closed and opened again. For tests.
  @visibleForTesting
  void newSession() {
    _snapshot = null;
    _fresh = false;
    _inFlight = null;
  }

  /// Replaces the cache, for tests.
  @visibleForTesting
  void seed(TeamSnapshot snapshot) {
    _snapshot = snapshot;
    _fresh = true;
  }

  /// The cached snapshot, unless it belongs to a different (signed-out) user.
  TeamSnapshot? get cached {
    final s = _snapshot;
    return s != null && s.userId == currentUserId() ? s : null;
  }

  /// The copy saved on the phone last time, or the one in memory, so a
  /// screen can show data at once while [load] gets the latest. Null when
  /// there's none.
  Future<TeamSnapshot?> restore() async {
    final c = cached;
    if (c != null) return c;
    final uid = currentUserId();
    if (uid == null) return null;
    try {
      final data = await store.read(uid);
      final snap = data == null ? null : TeamSnapshot.fromCache(data, uid);
      // Unless the latest arrived meanwhile, or someone else signed in.
      if (snap != null && cached == null && currentUserId() == uid) {
        _snapshot = snap;
        _fresh = false;
      }
    } catch (_) {
      // A missing or unreadable copy just means downloading as before.
    }
    return cached;
  }

  /// Returns this session's snapshot from the server, or fetches it.
  /// Concurrent callers share a single request. [force] always refetches.
  Future<TeamSnapshot> load({bool force = false}) {
    final c = cached;
    if (!force && c != null && _fresh) return Future.value(c);
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  /// Forgets the team's data, in memory and on the phone: on sign-out.
  Future<void> clear() async {
    _snapshot = null;
    _fresh = false;
    try {
      await store.clear();
    } catch (_) {}
  }

  static const _prColumns =
      'event, best_display, best_mark_meters, best_time_seconds, improvement_delta_pct, set_on, set_at_meet, athlete_id';
  static const _appearanceColumns =
      'athlete_id, event, time_seconds, mark_meters, display_value, meet_name, meet_date';

  /// Ordered by the table's unique key so pages never overlap or skip.
  /// Without [seasons] (before the indoor_outdoor migration) rows have no
  /// season and seasonOf() guesses it.
  Future<List<Map<String, dynamic>>> _fetchPrs({bool seasons = true}) =>
      _fetchAll((from, to) {
        final q = _supabase
            .from('track_prs')
            .select(
                '${seasons ? 'season, ' : ''}$_prColumns, profiles(full_name, gender, on_roster, class_year)')
            .order('athlete_id')
            .order('event');
        return (seasons ? q.order('season') : q).range(from, to);
      });

  Future<List<Map<String, dynamic>>> _fetchAppearances({bool seasons = true}) =>
      _fetchAll((from, to) => _supabase
          .from('meet_appearances')
          .select('${seasons ? 'season, ' : ''}$_appearanceColumns')
          .order('meet_date')
          .order('athlete_id')
          .order('event')
          .order('meet_name')
          .order('display_value')
          .range(from, to));

  Future<TeamSnapshot> _fetch() async {
    final userId = currentUserId();
    final results = await Future.wait([
      _fetchPrs().catchError((_) => _fetchPrs(seasons: false),
          test: (e) => e is PostgrestException),
      _fetchAppearances().catchError(
          (_) => _fetchAppearances(seasons: false),
          test: (e) => e is PostgrestException),
      _supabase.from('school_records').select(),
    ]);
    final snapshot = TeamSnapshot(
      userId: userId,
      prs: results[0],
      appearances: results[1],
      records: List<Map<String, dynamic>>.from(results[2]),
    );
    _snapshot = snapshot;
    _fresh = true;
    if (userId != null) {
      store.write(userId, snapshot.toCache()).catchError((_) {});
    }
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
