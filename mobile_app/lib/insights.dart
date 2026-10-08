// Insights for one athlete, worked out from their results so every number is
// exact. The profile shows the strongest few as cards. Pure Dart: the caller
// passes formatters for marks and gaps so units follow the user's settings.

import 'pr_stats.dart';

enum InsightKind { schoolRecord, freshPr, trend, nationals, seasonPace, rival, drought }

class Insight {
  final InsightKind kind;
  final String event;
  final String title;
  final String detail;

  /// Higher shows first.
  final double score;

  const Insight({
    required this.kind,
    required this.event,
    required this.title,
    required this.detail,
    required this.score,
  });

  @override
  String toString() => '$kind($event): $title — $detail';
}

/// A school record to measure an event against.
class RecordRef {
  /// Seconds for track events, meters for field events.
  final double value;
  final String display;
  final String holder;
  final int? year;

  const RecordRef({required this.value, required this.display, required this.holder, this.year});
}

class _Result {
  final DateTime date;
  final double value;
  final String display;
  final String meet;
  const _Result(this.date, this.value, this.display, this.meet);
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _day(DateTime d) => '${_months[d.month - 1]} ${d.day}';

/// How many results count as recent form.
const _formWindow = 5;

/// Results older than this don't make an event "current" for trends,
/// droughts or fresh PRs.
const _recentDays = 180;

/// Within this share of the cut mark counts as close to qualifying.
const _closeToCut = 0.05;

/// Within this share of a school record counts as close to it.
const _closeToRecord = 0.03;

/// The strongest insights for an athlete, at most [limit] and at most two
/// per event.
///
/// [appearances] are the athlete's meet_appearances rows; [ranks] the latest
/// list ranks per event; [rivals] their rival per event; [records] the school
/// record per event; [nameOf] turns an athlete id into a display name.
List<Insight> athleteInsights({
  required Iterable<Map<String, dynamic>> appearances,
  Map<String, List<ListRank>> ranks = const {},
  Map<String, Rival> rivals = const {},
  Map<String, RecordRef> records = const {},
  String Function(String athleteId)? nameOf,
  required String Function(String event, String display, double value) formatMark,
  required String Function(String event, double gap) formatGap,
  required DateTime now,
  int limit = 4,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final byEvent = _resultsByEvent(appearances);
  final insights = <Insight>[];

  for (final MapEntry(key: event, value: results) in byEvent.entries) {
    final last = results.last;
    final daysSinceLast = today.difference(last.date).inDays;
    final recent = daysSinceLast <= _recentDays;
    final name = _eventName(event);

    // Index of each PR: results that beat everything before them.
    final prIndexes = <int>[];
    for (var i = 0; i < results.length; i++) {
      if (prIndexes.isEmpty || isBetterMark(event, results[i].value, results[prIndexes.last].value)) {
        prIndexes.add(i);
      }
    }

    // A PR at the latest meet, set in the last 30 days.
    if (prIndexes.last == results.length - 1 && results.length > 1 && daysSinceLast <= 30) {
      final previous = results[prIndexes[prIndexes.length - 2]];
      final gain = (last.value - previous.value).abs();
      insights.add(Insight(
        kind: InsightKind.freshPr,
        event: event,
        title: 'New PR in the $name',
        detail: '${formatMark(event, last.display, last.value)} on ${_day(last.date)}, '
            '${formatGap(event, gain)} better',
        score: 100 - daysSinceLast.toDouble(),
      ));
    }

    // Recent form: how many of the last few results beat the one before.
    if (recent && results.length >= 4) {
      final form = results.sublist(results.length - (results.length < _formWindow ? results.length : _formWindow));
      var better = 0;
      for (var i = 1; i < form.length; i++) {
        if (isBetterMark(event, form[i].value, form[i - 1].value)) better++;
      }
      final comparisons = form.length - 1;
      if (better >= 3 && better / comparisons >= 0.75) {
        insights.add(Insight(
          kind: InsightKind.trend,
          event: event,
          title: '${_capitalize(name)} is trending up',
          detail: 'Better in $better of your last ${form.length} meets',
          score: 70 + better.toDouble(),
        ));
      }
    }

    // A drought: several meets since the last PR.
    final sincePr = results.length - 1 - prIndexes.last;
    if (recent && sincePr >= 4) {
      final pr = results[prIndexes.last];
      insights.add(Insight(
        kind: InsightKind.drought,
        event: event,
        title: '$sincePr meets since a ${name.toLowerCase()} PR',
        detail: 'Your best is ${formatMark(event, pr.display, pr.value)} from ${_day(pr.date)}',
        score: 30 + sincePr.toDouble(),
      ));
    }

    // This season against the same point last season.
    final pace = _seasonPace(event, results, today);
    if (pace != null && pace > 0) {
      insights.add(Insight(
        kind: InsightKind.seasonPace,
        event: event,
        title: 'Ahead of last season',
        detail: '${_capitalize(name)} is ${formatGap(event, pace)} better than this point last year',
        score: 60,
      ));
    }
  }

  // School records: holding one, or close to it.
  for (final MapEntry(key: event, value: record) in records.entries) {
    final results = byEvent[event];
    if (results == null || results.isEmpty || record.value <= 0) continue;
    var best = results.first;
    for (final r in results) {
      if (isBetterMark(event, r.value, best.value)) best = r;
    }
    final name = _eventName(event);
    if (!isBetterMark(event, record.value, best.value)) {
      insights.add(Insight(
        kind: InsightKind.schoolRecord,
        event: event,
        title: 'School record holder',
        detail: '${_capitalize(name)}, ${formatMark(event, best.display, best.value)} on ${_day(best.date)}, ${best.date.year}',
        score: 95,
      ));
      continue;
    }
    final gap = (record.value - best.value).abs();
    if (gap / record.value <= _closeToRecord) {
      final year = record.year == null ? '' : " '${(record.year! % 100).toString().padLeft(2, '0')}";
      insights.add(Insight(
        kind: InsightKind.schoolRecord,
        event: event,
        title: '${formatGap(event, gap)} from the school record',
        detail: '${_capitalize(name)} record: ${record.display}, ${_displayName(record.holder)}$year',
        score: 85 - gap / record.value * 100,
      ));
    }
  }

  // Nationals: inside the projected field, or close to it.
  for (final MapEntry(key: event, value: eventRanks) in ranks.entries) {
    for (final r in eventRanks) {
      final status = r.nationals;
      if (status == null) continue;
      final name = _eventName(event);
      final season = r.seasonLabel.toLowerCase();
      if (status.inside) {
        insights.add(Insight(
          kind: InsightKind.nationals,
          event: event,
          title: 'Inside the ${r.label} nationals cut',
          detail: '#${r.rank} in the $name, $season',
          score: 90,
        ));
      } else {
        final cut = parseMarkValue(r.cutMark);
        final gap = status.gap;
        if (cut != null && cut > 0 && gap != null && gap / cut <= _closeToCut) {
          insights.add(Insight(
            kind: InsightKind.nationals,
            event: event,
            title: '${formatGap(event, gap)} from the ${r.label} cut',
            detail: '${_capitalize(name)}, #${r.rank} on the $season list',
            score: 80 - gap / cut * 100,
          ));
        }
      }
    }
  }

  // The closest rival, when it's close.
  final closest = rivals.values.toList()..sort((a, b) => a.gapPct.compareTo(b.gapPct));
  if (closest.isNotEmpty && nameOf != null && closest.first.gapPct <= 3) {
    final rival = closest.first;
    final who = _displayName(nameOf(rival.athleteId));
    final gap = formatGap(rival.event, rival.gap);
    final name = _eventName(rival.event);
    insights.add(Insight(
      kind: InsightKind.rival,
      event: rival.event,
      title: rival.isAhead ? '$gap behind $who' : '$gap ahead of $who',
      detail: rival.isAhead ? 'Closest teammate in the $name' : 'Holding off your closest teammate in the $name',
      score: 50 - rival.gapPct,
    ));
  }

  insights.sort((a, b) => b.score.compareTo(a.score));
  final perEvent = <String, int>{};
  final picked = <Insight>[];
  for (final insight in insights) {
    if (picked.length == limit) break;
    if ((perEvent[insight.event] ?? 0) >= 2) continue;
    perEvent[insight.event] = (perEvent[insight.event] ?? 0) + 1;
    picked.add(insight);
  }
  return picked;
}

/// Each event's results, oldest first, one per day (the best that day).
Map<String, List<_Result>> _resultsByEvent(Iterable<Map<String, dynamic>> appearances) {
  final byDay = <String, Map<DateTime, _Result>>{};
  for (final a in appearances) {
    final event = a['event'] as String?;
    final date = parseMeetDate(a['meet_date']);
    if (event == null || date == null) continue;
    final field = isFieldEvent(event);
    final v = ((field ? a['mark_meters'] : a['time_seconds']) as num?)?.toDouble();
    if (v == null || v <= 0) continue;
    final result = _Result(date, v, a['display_value'] as String? ?? '', a['meet_name'] as String? ?? '');
    final days = byDay.putIfAbsent(event, () => {});
    final existing = days[date];
    if (existing == null || isBetterMark(event, v, existing.value)) days[date] = result;
  }
  return {
    for (final MapEntry(key: event, value: days) in byDay.entries)
      event: days.values.toList()..sort((a, b) => a.date.compareTo(b.date)),
  };
}

/// How much better this season's best is than last season's best at the
/// same point (days since Aug 1), or null without results in both.
double? _seasonPace(String event, List<_Result> results, DateTime today) {
  final season = academicYearOf(today);
  final dayOfSeason = today.difference(DateTime(season, 8, 1)).inDays;
  final cutoffLastYear = DateTime(season - 1, 8, 1).add(Duration(days: dayOfSeason));

  double? best(Iterable<_Result> rs) {
    double? b;
    for (final r in rs) {
      if (b == null || isBetterMark(event, r.value, b)) b = r.value;
    }
    return b;
  }

  final now = best(results.where((r) => academicYearOf(r.date) == season));
  final then = best(results.where(
      (r) => academicYearOf(r.date) == season - 1 && !r.date.isAfter(cutoffLastYear)));
  if (now == null || then == null) return null;
  return isBetterMark(event, now, then) ? (now - then).abs() : -(now - then).abs();
}

/// '400 Meters' → '400m', 'Long Jump' → 'long jump'.
String _eventName(String event) {
  final m = RegExp(r'^(\d+) Meters?$').firstMatch(event);
  if (m != null) return '${m.group(1)}m';
  return event.toLowerCase();
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// 'Mordi, Jonathan' → 'Jonathan Mordi' (same as design_system's formatName,
/// kept here so this file stays free of Flutter).
String _displayName(String raw) {
  if (!raw.contains(',')) return raw;
  final parts = raw.split(',');
  return '${parts[1].trim()} ${parts[0].trim()}';
}
