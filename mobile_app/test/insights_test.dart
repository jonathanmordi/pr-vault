import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/insights.dart';
import 'package:mobile_app/pr_stats.dart';

Map<String, dynamic> jump(String date, double m, {String event = 'Long Jump', String meet = 'Meet'}) => {
      'event': event,
      'meet_date': date,
      'mark_meters': m,
      'time_seconds': null,
      'display_value': '${m.toStringAsFixed(2)}m',
      'meet_name': meet,
    };

Map<String, dynamic> run(String date, double s, {String event = '400 Meters'}) => {
      'event': event,
      'meet_date': date,
      'mark_meters': null,
      'time_seconds': s,
      'display_value': s.toStringAsFixed(2),
      'meet_name': 'Meet',
    };

List<Insight> insightsFor(
  List<Map<String, dynamic>> appearances, {
  String today = '2026-03-01',
  Map<String, List<ListRank>> ranks = const {},
  Map<String, Rival> rivals = const {},
  Map<String, RecordRef> records = const {},
  int limit = 10,
}) =>
    athleteInsights(
      appearances: appearances,
      ranks: ranks,
      rivals: rivals,
      records: records,
      nameOf: (id) => {'okafor': 'Okafor, Daniel'}[id] ?? id,
      formatMark: (event, display, value) => display,
      formatGap: formatGap,
      now: DateTime.parse(today),
      limit: limit,
    );

Iterable<InsightKind> kinds(List<Insight> xs) => xs.map((i) => i.kind);

void main() {
  test('a PR at the latest meet in the last month is news', () {
    final xs = insightsFor([jump('2026-01-10', 6.50), jump('2026-02-20', 6.62)]);
    final pr = xs.firstWhere((i) => i.kind == InsightKind.freshPr);
    expect(pr.title, 'New PR in the long jump');
    expect(pr.detail, '6.62m on Feb 20, 0.12m better');
  });

  test('an old PR is not news', () {
    final xs = insightsFor([jump('2025-01-10', 6.50), jump('2025-02-20', 6.62)]);
    expect(kinds(xs), isNot(contains(InsightKind.freshPr)));
  });

  test('improving in most recent meets is a trend; times improve by going down', () {
    final xs = insightsFor([
      run('2026-01-10', 52.0), run('2026-01-24', 51.6), run('2026-02-07', 51.9),
      run('2026-02-14', 51.2), run('2026-02-21', 50.8),
    ]);
    final trend = xs.firstWhere((i) => i.kind == InsightKind.trend);
    expect(trend.title, '400m is trending up');
    expect(trend.detail, 'Better in 3 of your last 5 meets');
  });

  test('a mixed run of results is not a trend', () {
    final xs = insightsFor([
      jump('2026-01-10', 6.5), jump('2026-01-24', 6.4), jump('2026-02-07', 6.6), jump('2026-02-14', 6.3),
    ]);
    expect(kinds(xs), isNot(contains(InsightKind.trend)));
  });

  test('several meets without a PR is a drought', () {
    final xs = insightsFor([
      jump('2026-01-10', 6.90), jump('2026-01-24', 6.70), jump('2026-02-07', 6.75),
      jump('2026-02-14', 6.80), jump('2026-02-21', 6.72),
    ]);
    final d = xs.firstWhere((i) => i.kind == InsightKind.drought);
    expect(d.title, '4 meets since a long jump PR');
    expect(d.detail, 'Your best is 6.90m from Jan 10');
  });

  test('two results on one day count once, the better one', () {
    final xs = insightsFor([
      jump('2026-01-10', 6.50), jump('2026-02-20', 6.40), jump('2026-02-20', 6.62),
    ]);
    expect(xs.firstWhere((i) => i.kind == InsightKind.freshPr).detail, startsWith('6.62m on Feb 20'));
  });

  test('ahead of the same point last season', () {
    final xs = insightsFor([
      jump('2025-01-20', 6.40), jump('2025-02-10', 6.45), jump('2025-04-20', 6.80), // last season
      jump('2026-01-24', 6.60), // this season, by Mar 1
    ]);
    final pace = xs.firstWhere((i) => i.kind == InsightKind.seasonPace);
    expect(pace.detail, 'Long jump is 0.15m better than this point last year');
  });

  group('nationals', () {
    ListRank d3(int rank, String mark, String cut) => ListRank.tryParse({
          'event': 'Long Jump', 'scope': 'national', 'label': 'D3', 'season': 'indoor',
          'season_year': 2026, 'rank': rank, 'list_size': 500, 'mark_display': mark,
          'cut_rank': 20, 'cut_mark': cut,
        })!;

    test('inside the cut', () {
      final xs = insightsFor([], ranks: {'Long Jump': [d3(12, '7.10m', '7.00m')]});
      expect(xs.single.title, 'Inside the D3 nationals cut');
      expect(xs.single.detail, '#12 in the long jump, indoor 2026');
    });

    test('close to the cut', () {
      final xs = insightsFor([], ranks: {'Long Jump': [d3(31, '6.80m', '7.00m')]});
      expect(xs.single.title, '0.20m from the D3 cut');
    });

    test('far from the cut says nothing', () {
      expect(insightsFor([], ranks: {'Long Jump': [d3(140, '6.00m', '7.00m')]}), isEmpty);
    });
  });

  test('a close rival, by name', () {
    const rival = Rival(athleteId: 'okafor', event: 'Triple Jump', myValue: 14.0, theirValue: 14.12, theirDisplay: '14.12m');
    final xs = insightsFor([], rivals: {'Triple Jump': rival});
    expect(xs.single.title, '0.12m behind Daniel Okafor');
    expect(xs.single.detail, 'Closest teammate in the triple jump');
  });

  test('strongest first, capped, at most two per event', () {
    final xs = insightsFor([
      jump('2026-01-10', 6.50), jump('2026-01-24', 6.55), jump('2026-02-07', 6.58),
      jump('2026-02-14', 6.60), jump('2026-02-21', 6.66),
    ], limit: 4);
    expect(xs.length, lessThanOrEqualTo(4));
    expect(xs.where((i) => i.event == 'Long Jump').length, lessThanOrEqualTo(2));
    expect(xs.first.kind, InsightKind.freshPr);
  });

  group('school records', () {
    const record = RecordRef(value: 6.96, display: '6.96m', holder: 'Lowe, Nicholas', year: 2011);

    test('close to the record', () {
      final xs = insightsFor([jump('2026-01-10', 6.80), jump('2026-02-20', 6.91)],
          records: {'Long Jump': record}, today: '2026-10-07');
      final r = xs.single;
      expect(r.kind, InsightKind.schoolRecord);
      expect(r.title, '0.05m from the school record');
      expect(r.detail, "Long jump record: 6.96m, Nicholas Lowe '11");
    });

    test('holding the record', () {
      final xs = insightsFor([jump('2026-02-20', 7.01)], records: {'Long Jump': record}, today: '2026-10-07');
      expect(xs.single.title, 'School record holder');
      expect(xs.single.detail, 'Long jump, 7.01m on Feb 20, 2026');
    });

    test('far from the record says nothing', () {
      expect(insightsFor([jump('2026-02-20', 6.20)], records: {'Long Jump': record}, today: '2026-10-07'), isEmpty);
    });

    test('times: faster than the record holds it', () {
      const r400 = RecordRef(value: 48.10, display: '48.10', holder: 'Smith, A');
      expect(insightsFor([run('2026-02-20', 48.05)], records: {'400 Meters': r400}, today: '2026-10-07')
          .single.detail, startsWith('400m, 48.05'));
      expect(insightsFor([run('2026-02-20', 49.0)], records: {'400 Meters': r400}, today: '2026-10-07')
          .single.title, '0.90s from the school record');
    });
  });
}
