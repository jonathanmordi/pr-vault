// PR detection, season points, trend windows and rivals.
//
// Everything here is computed from scraped rows (meet_appearances,
// track_prs, school_records) and is pure Dart, so it can be unit tested
// without a Supabase backend.

const kFieldEvents = [
  'High Jump', 'Long Jump', 'Triple Jump', 'Pole Vault',
  'Shot Put', 'Discus', 'Hammer', 'Javelin', 'Weight Throw',
  'Decathlon', 'Heptathlon', 'Pentathlon',
];

bool isFieldEvent(String event) => kFieldEvents.contains(event);

/// Field marks are better when higher, track times when lower.
bool isBetterMark(String event, double a, double b) =>
    isFieldEvent(event) ? a > b : a < b;

/// Parses a `YYYY-MM-DD` meet date into a local date, or null.
DateTime? parseMeetDate(Object? raw) {
  if (raw is! String || raw.length < 10) return null;
  final d = DateTime.tryParse(raw.substring(0, 10));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// Matches the scraper: March–August marks count toward outdoor records.
String trackSeasonOf(DateTime d) =>
    d.month >= 3 && d.month <= 8 ? 'outdoor' : 'indoor';

/// Academic seasons run Aug 1 – Jul 31, covering one indoor and one
/// outdoor season. Returns the year the season starts in.
int academicYearOf(DateTime d) => d.month >= 8 ? d.year : d.year - 1;

String formatGap(String event, double gap) {
  if (isFieldEvent(event)) return '${gap.toStringAsFixed(2)}m';
  if (gap >= 60) {
    final m = gap ~/ 60;
    final s = (gap - m * 60).toStringAsFixed(2).padLeft(5, '0');
    return '$m:${s}s';
  }
  return '${gap.toStringAsFixed(2)}s';
}

double? _markOf(Map<String, dynamic> row, String event, String timeKey,
    String markKey) {
  final v = isFieldEvent(event)
      ? (row[markKey] as num?)?.toDouble()
      : (row[timeKey] as num?)?.toDouble();
  return v != null && v > 0 ? v : null;
}

// ─── PR detection ─────────────────────────────────────────────────────────────

/// A meet where an athlete beat their previous best in an event.
class PrEvent {
  final String athleteId;
  final String event;
  final DateTime date;
  final String display;
  final String meetName;
  final double value;
  final double previousValue;
  final bool schoolRecord;

  const PrEvent({
    required this.athleteId,
    required this.event,
    required this.date,
    required this.display,
    required this.meetName,
    required this.value,
    required this.previousValue,
    this.schoolRecord = false,
  });

  /// How much better than the previous best, in percent (always positive).
  double get improvementPct => isFieldEvent(event)
      ? (value - previousValue) / previousValue * 100
      : (previousValue - value) / previousValue * 100;

  /// Absolute improvement in the event's unit (seconds or meters).
  double get gap => (value - previousValue).abs();

  /// 10 for the PR, +5 per 1% improved, +100 for a school record.
  int get points =>
      10 + (improvementPct * 5).round() + (schoolRecord ? 100 : 0);

  /// Stable identity, used to remember which alerts were already seen.
  String get key =>
      '$athleteId|$event|${date.toIso8601String().substring(0, 10)}|$display';
}

class _DayBest {
  final double value;
  final Map<String, dynamic> row;
  const _DayBest(this.value, this.row);
}

/// Walks each athlete's results in date order and returns every meet where
/// they beat their previous best, newest first.
///
/// Only the best mark of each day counts, so a prelim and a final on the
/// same day are one PR. A debut mark has nothing to beat and isn't a PR.
List<PrEvent> detectPrs(
  Iterable<Map<String, dynamic>> appearances, {
  Iterable<Map<String, dynamic>> records = const [],
  Map<String, String> genderByAthlete = const {},
}) {
  final byAthleteEvent = <String, Map<DateTime, _DayBest>>{};
  for (final a in appearances) {
    final athleteId = a['athlete_id'] as String?;
    final event = a['event'] as String?;
    final date = parseMeetDate(a['meet_date']);
    if (athleteId == null || event == null || date == null) continue;
    final v = _markOf(a, event, 'time_seconds', 'mark_meters');
    if (v == null) continue;
    final days = byAthleteEvent.putIfAbsent('$athleteId\u0000$event', () => {});
    final cur = days[date];
    if (cur == null || isBetterMark(event, v, cur.value)) {
      days[date] = _DayBest(v, a);
    }
  }

  final prs = <PrEvent>[];
  byAthleteEvent.forEach((key, days) {
    final sep = key.indexOf('\u0000');
    final athleteId = key.substring(0, sep);
    final event = key.substring(sep + 1);
    final dates = days.keys.toList()..sort();
    double? best;
    for (final date in dates) {
      final day = days[date]!;
      if (best != null && isBetterMark(event, day.value, best)) {
        prs.add(PrEvent(
          athleteId: athleteId,
          event: event,
          date: date,
          display: day.row['display_value'] as String? ?? '',
          meetName: day.row['meet_name'] as String? ?? '',
          value: day.value,
          previousValue: best,
          schoolRecord: _holdsSchoolRecord(
            records, event, genderByAthlete[athleteId], date, day.value),
        ));
      }
      if (best == null || isBetterMark(event, day.value, best)) {
        best = day.value;
      }
    }
  });

  prs.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    final byAthlete = a.athleteId.compareTo(b.athleteId);
    return byAthlete != 0 ? byAthlete : a.event.compareTo(b.event);
  });
  return prs;
}

/// school_records only stores the current record, so a PR counts as a
/// school record when it matches (or beats) the record for its season.
bool _holdsSchoolRecord(Iterable<Map<String, dynamic>> records, String event,
    String? gender, DateTime date, double value) {
  if (gender == null) return false;
  final season = trackSeasonOf(date);
  for (final r in records) {
    if (r['event'] != event || r['gender'] != gender) continue;
    final rs = r['season'] as String?;
    if (rs != null && rs.isNotEmpty && rs != season) continue;
    final rec = _markOf(r, event, 'record_mark_seconds', 'record_mark_meters');
    if (rec == null) continue;
    if ((value - rec).abs() < 1e-6 || isBetterMark(event, value, rec)) {
      return true;
    }
  }
  return false;
}

// ─── Trending ─────────────────────────────────────────────────────────────────

/// A date range the trending list and season points are computed over.
class TrendWindow {
  final String id;
  final String label;
  final String shortLabel;
  final DateTime? start; // inclusive
  final DateTime? end; // exclusive

  const TrendWindow._(this.id, this.label, this.shortLabel, this.start,
      this.end);

  factory TrendWindow.lastDays(int days, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return TrendWindow._('last$days', 'Last $days days', '${days}d',
        today.subtract(Duration(days: days)), null);
  }

  factory TrendWindow.season(int startYear) {
    String yy(int y) => '${y % 100}'.padLeft(2, '0');
    final end = yy(startYear + 1);
    return TrendWindow._('season$startYear', '$startYear–$end',
        '${yy(startYear)}–$end', DateTime(startYear, 8, 1),
        DateTime(startYear + 1, 8, 1));
  }

  static const allTime = TrendWindow._('all', 'All time', 'All-time', null, null);

  bool get isSeason => id.startsWith('season');

  bool contains(DateTime d) =>
      (start == null || !d.isBefore(start!)) &&
      (end == null || d.isBefore(end!));

  @override
  bool operator ==(Object other) => other is TrendWindow && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The last 30 days, the (up to three) most recent seasons that have PRs,
/// and all time.
List<TrendWindow> trendWindows(Iterable<PrEvent> prs, DateTime now) {
  final years = prs.map((p) => academicYearOf(p.date)).toSet().toList()
    ..sort((a, b) => b.compareTo(a));
  return [
    TrendWindow.lastDays(30, now),
    for (final y in years.take(3)) TrendWindow.season(y),
    TrendWindow.allTime,
  ];
}

/// The most recent season with PRs, so the list isn't empty in the
/// offseason. Falls back to all time when there's no data at all.
TrendWindow defaultTrendWindow(List<TrendWindow> windows) =>
    windows.firstWhere((w) => w.isSeason, orElse: () => TrendWindow.allTime);

class AthleteTrend {
  final String athleteId;

  /// Newest first.
  final List<PrEvent> prs;

  const AthleteTrend(this.athleteId, this.prs);

  int get prCount => prs.length;
  int get points => prs.fold(0, (sum, p) => sum + p.points);
  DateTime get lastPr => prs.first.date;

  /// Distinct events, in order of most recent PR.
  List<String> get events {
    final seen = <String>{};
    return [for (final p in prs) if (seen.add(p.event)) p.event];
  }
}

/// Groups PRs by athlete and ranks them by PR count (or by points), with the
/// other metric and then the most recent PR as tie-breakers.
List<AthleteTrend> trendingAthletes(Iterable<PrEvent> prs,
    {bool byPoints = false}) {
  final grouped = <String, List<PrEvent>>{};
  for (final p in prs) {
    grouped.putIfAbsent(p.athleteId, () => []).add(p);
  }
  final rows = [
    for (final e in grouped.entries)
      AthleteTrend(e.key, e.value..sort((a, b) => b.date.compareTo(a.date))),
  ];
  rows.sort((a, b) {
    final primary = byPoints
        ? b.points.compareTo(a.points)
        : b.prCount.compareTo(a.prCount);
    if (primary != 0) return primary;
    final secondary = byPoints
        ? b.prCount.compareTo(a.prCount)
        : b.points.compareTo(a.points);
    if (secondary != 0) return secondary;
    return b.lastPr.compareTo(a.lastPr);
  });
  return rows;
}

// ─── Rivals ───────────────────────────────────────────────────────────────────

/// The teammate whose PR in an event is closest to an athlete's own.
class Rival {
  final String athleteId;
  final String event;
  final double myValue;
  final double theirValue;
  final String theirDisplay;

  const Rival({
    required this.athleteId,
    required this.event,
    required this.myValue,
    required this.theirValue,
    required this.theirDisplay,
  });

  bool get isAhead => isBetterMark(event, theirValue, myValue);
  double get gap => (theirValue - myValue).abs();
  double get gapPct => gap / myValue * 100;
}

/// Finds the same-gender teammate with the closest PR in [event]. Ties go
/// to the teammate who's ahead, since that's the one worth chasing.
Rival? findRival({
  required String athleteId,
  required String event,
  required double myValue,
  required String? gender,
  required Iterable<Map<String, dynamic>> teamPrs,
}) {
  Rival? best;
  for (final p in teamPrs) {
    final otherId = p['athlete_id'] as String?;
    if (otherId == null || otherId == athleteId || p['event'] != event) {
      continue;
    }
    final otherGender = (p['profiles'] as Map?)?['gender'] as String? ?? 'M';
    if (gender != null && otherGender != gender) continue;
    final v = _markOf(p, event, 'best_time_seconds', 'best_mark_meters');
    if (v == null) continue;
    final candidate = Rival(
      athleteId: otherId,
      event: event,
      myValue: myValue,
      theirValue: v,
      theirDisplay: p['best_display'] as String? ?? '',
    );
    if (best == null ||
        candidate.gap < best.gap - 1e-9 ||
        ((candidate.gap - best.gap).abs() < 1e-9 &&
            candidate.isAhead &&
            !best.isAhead)) {
      best = candidate;
    }
  }
  return best;
}

/// Rivals for each event [athleteId] has a PR in, keyed by event.
Map<String, Rival> rivalsFor(String athleteId, String? gender,
    Iterable<Map<String, dynamic>> teamPrs) {
  final rivals = <String, Rival>{};
  for (final p in teamPrs) {
    if (p['athlete_id'] != athleteId) continue;
    final event = p['event'] as String?;
    if (event == null) continue;
    final mine = _markOf(p, event, 'best_time_seconds', 'best_mark_meters');
    if (mine == null) continue;
    final rival = findRival(
      athleteId: athleteId,
      event: event,
      myValue: mine,
      gender: gender,
      teamPrs: teamPrs,
    );
    if (rival != null) rivals[event] = rival;
  }
  return rivals;
}
