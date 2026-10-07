// Unit tests for PR detection, season points, trend windows and rivals.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/pr_stats.dart';

Map<String, dynamic> run(String athlete, String date, double seconds,
        {String event = '400 Meters', String meet = 'Meet'}) =>
    {
      'athlete_id': athlete,
      'event': event,
      'time_seconds': seconds,
      'mark_meters': null,
      'display_value': seconds.toStringAsFixed(2),
      'meet_name': meet,
      'meet_date': date,
    };

Map<String, dynamic> jump(String athlete, String date, double meters,
        {String event = 'Long Jump'}) =>
    {
      'athlete_id': athlete,
      'event': event,
      'time_seconds': null,
      'mark_meters': meters,
      'display_value': '${meters.toStringAsFixed(2)}m',
      'meet_name': 'Meet',
      'meet_date': date,
    };

Map<String, dynamic> pr(String athlete, String event, double value,
        {String gender = 'M'}) =>
    {
      'athlete_id': athlete,
      'event': event,
      'best_time_seconds': isFieldEvent(event) ? null : value,
      'best_mark_meters': isFieldEvent(event) ? value : null,
      'best_display': '$value',
      'profiles': {'full_name': athlete, 'gender': gender},
    };

void main() {
  group('detectPrs', () {
    test('a debut mark is not a PR; beating it is', () {
      final prs = detectPrs([
        run('a', '2026-01-10', 50.0),
        run('a', '2026-01-17', 49.5),
      ]);
      expect(prs, hasLength(1));
      expect(prs.single.value, 49.5);
      expect(prs.single.previousValue, 50.0);
      expect(prs.single.improvementPct, closeTo(1.0, 1e-9));
    });

    test('a slower track time is not a PR', () {
      final prs = detectPrs([
        run('a', '2026-01-10', 50.0),
        run('a', '2026-01-17', 50.4),
        run('a', '2026-01-24', 50.1),
      ]);
      expect(prs, isEmpty);
    });

    test('field events are better when longer', () {
      final prs = detectPrs([
        jump('a', '2026-01-10', 6.00),
        jump('a', '2026-01-17', 5.90),
        jump('a', '2026-01-24', 6.30),
      ]);
      expect(prs, hasLength(1));
      expect(prs.single.value, 6.30);
      expect(prs.single.previousValue, 6.00);
      expect(prs.single.improvementPct, closeTo(5.0, 1e-9));
    });

    test('a prelim and final on the same day count as one PR', () {
      final prs = detectPrs([
        run('a', '2026-01-10', 50.0),
        run('a', '2026-01-17', 49.8, meet: 'Prelim'),
        run('a', '2026-01-17', 49.5, meet: 'Final'),
      ]);
      expect(prs, hasLength(1));
      expect(prs.single.value, 49.5);
      expect(prs.single.previousValue, 50.0);
    });

    test('results are input-order independent', () {
      final prs = detectPrs([
        run('a', '2026-02-01', 49.0),
        run('a', '2026-01-01', 50.0),
        run('a', '2026-01-15', 49.5),
      ]);
      expect(prs.map((p) => p.value), [49.0, 49.5]);
    });

    test('skips rows without a date or a usable mark', () {
      final prs = detectPrs([
        run('a', '2026-01-10', 50.0),
        {...run('a', '2026-01-17', 49.0), 'meet_date': null},
        {...run('a', '2026-01-24', 48.0), 'time_seconds': 0},
        {...run('a', '2026-01-31', 48.0), 'time_seconds': null},
      ]);
      expect(prs, isEmpty);
    });

    test('keeps events and athletes separate, newest first', () {
      final prs = detectPrs([
        run('a', '2026-01-10', 50.0),
        run('a', '2026-03-10', 49.0),
        run('a', '2026-01-10', 23.0, event: '200 Meters'),
        run('a', '2026-02-10', 22.5, event: '200 Meters'),
        run('b', '2026-01-10', 52.0),
        run('b', '2026-04-10', 51.0),
      ]);
      expect(prs.map((p) => '${p.athleteId} ${p.event}'), [
        'b 400 Meters',
        'a 400 Meters',
        'a 200 Meters',
      ]);
    });

    test('flags a PR that matches the school record for its season', () {
      final records = [
        {
          'event': '400 Meters',
          'gender': 'M',
          'season': 'indoor',
          'record_mark_seconds': 49.5,
        },
      ];
      final prs = detectPrs(
        [
          run('a', '2026-01-10', 50.0),
          run('a', '2026-02-10', 49.5),
        ],
        records: records,
        genderByAthlete: {'a': 'M'},
      );
      expect(prs.single.schoolRecord, isTrue);
    });

    test('ignores records from another season or gender', () {
      final appearances = [
        run('a', '2026-01-10', 50.0),
        run('a', '2026-02-10', 49.5),
      ];
      final outdoor = [
        {
          'event': '400 Meters',
          'gender': 'M',
          'season': 'outdoor',
          'record_mark_seconds': 49.5,
        },
      ];
      expect(
        detectPrs(appearances,
                records: outdoor, genderByAthlete: {'a': 'M'})
            .single
            .schoolRecord,
        isFalse,
      );
      final women = [
        {...outdoor.single, 'season': 'indoor', 'gender': 'F'},
      ];
      expect(
        detectPrs(appearances, records: women, genderByAthlete: {'a': 'M'})
            .single
            .schoolRecord,
        isFalse,
      );
    });
  });

  group('PrEvent.points', () {
    PrEvent make(double prev, double value, {bool record = false}) => PrEvent(
          athleteId: 'a',
          event: '400 Meters',
          date: DateTime(2026, 1, 1),
          display: '',
          meetName: '',
          value: value,
          previousValue: prev,
          schoolRecord: record,
        );

    test('10 for the PR plus 5 per percent improved', () {
      expect(make(50.0, 49.0).points, 10 + 10); // 2% → 10
      expect(make(50.0, 49.9).points, 10 + 1); // 0.2% → 1
    });

    test('school records add 100', () {
      expect(make(50.0, 49.0, record: true).points, 120);
    });
  });

  group('TrendWindow', () {
    test('seasons run Aug 1 to Jul 31', () {
      final s = TrendWindow.season(2025);
      expect(s.label, '2025–26');
      expect(s.shortLabel, '25–26');
      expect(s.contains(DateTime(2025, 7, 31)), isFalse);
      expect(s.contains(DateTime(2025, 8, 1)), isTrue);
      expect(s.contains(DateTime(2026, 7, 31)), isTrue);
      expect(s.contains(DateTime(2026, 8, 1)), isFalse);
    });

    test('pads two-digit years', () {
      expect(TrendWindow.season(2009).label, '2009–10');
      expect(TrendWindow.season(2099).shortLabel, '99–00');
    });

    test('lists last 30 days, up to three seasons with PRs, then all time',
        () {
      PrEvent at(DateTime d) => PrEvent(
            athleteId: 'a',
            event: '400 Meters',
            date: d,
            display: '',
            meetName: '',
            value: 49,
            previousValue: 50,
          );
      final windows = trendWindows([
        at(DateTime(2026, 5, 1)),
        at(DateTime(2025, 2, 1)),
        at(DateTime(2023, 9, 1)),
        at(DateTime(2022, 3, 1)),
      ], DateTime(2026, 10, 4));
      expect(windows.map((w) => w.id), [
        'last30',
        'season2025',
        'season2024',
        'season2023',
        'all',
      ]);
      // In the offseason the default is the latest season with data.
      expect(defaultTrendWindow(windows).id, 'season2025');
    });

    test('defaults to all time when there are no PRs', () {
      final windows = trendWindows(const [], DateTime(2026, 10, 4));
      expect(defaultTrendWindow(windows), TrendWindow.allTime);
    });
  });

  group('trendingAthletes', () {
    final prs = detectPrs([
      // a: two small PRs
      run('a', '2026-01-01', 50.0),
      run('a', '2026-01-08', 49.9),
      run('a', '2026-01-15', 49.8),
      // b: one big PR
      run('b', '2026-01-01', 55.0),
      run('b', '2026-01-08', 50.0),
    ]);

    test('ranks by PR count, then points', () {
      final rows = trendingAthletes(prs);
      expect(rows.map((r) => r.athleteId), ['a', 'b']);
      expect(rows.first.prCount, 2);
    });

    test('can rank by points instead', () {
      final rows = trendingAthletes(prs, byPoints: true);
      expect(rows.map((r) => r.athleteId), ['b', 'a']);
      expect(rows.first.points, greaterThan(rows.last.points));
    });

    test('lists distinct events, most recent first', () {
      final rows = trendingAthletes(detectPrs([
        run('a', '2026-01-01', 23.0, event: '200 Meters'),
        run('a', '2026-01-08', 22.9, event: '200 Meters'),
        run('a', '2026-01-01', 50.0),
        run('a', '2026-02-01', 49.0),
        run('a', '2026-03-01', 48.5),
      ]));
      expect(rows.single.events, ['400 Meters', '200 Meters']);
    });
  });

  group('rivals', () {
    final team = [
      pr('me', '400 Meters', 50.0),
      pr('fast', '400 Meters', 49.8),
      pr('slow', '400 Meters', 50.5),
      pr('woman', '400 Meters', 50.01, gender: 'F'),
      pr('other', '200 Meters', 22.0),
    ];

    test('picks the closest same-gender teammate in the event', () {
      final r = findRival(
        athleteId: 'me',
        event: '400 Meters',
        myValue: 50.0,
        gender: 'M',
        teamPrs: team,
      )!;
      expect(r.athleteId, 'fast');
      expect(r.isAhead, isTrue);
      expect(r.gap, closeTo(0.2, 1e-9));
    });

    test('a tie goes to the teammate who is ahead', () {
      final r = findRival(
        athleteId: 'me',
        event: '400 Meters',
        myValue: 50.0,
        gender: 'M',
        teamPrs: [
          pr('behind', '400 Meters', 50.2),
          pr('ahead', '400 Meters', 49.8),
        ],
      )!;
      expect(r.athleteId, 'ahead');
    });

    test('in field events, ahead means a longer mark', () {
      final r = findRival(
        athleteId: 'me',
        event: 'Long Jump',
        myValue: 6.00,
        gender: 'M',
        teamPrs: [pr('x', 'Long Jump', 6.10)],
      )!;
      expect(r.isAhead, isTrue);
    });

    test('no teammates in the event means no rival', () {
      expect(
        findRival(
          athleteId: 'other',
          event: '200 Meters',
          myValue: 22.0,
          gender: 'M',
          teamPrs: team,
        ),
        isNull,
      );
    });

    test('rivalsFor covers every event the athlete has a PR in', () {
      final rivals = rivalsFor('me', 'M', [
        ...team,
        pr('me', '200 Meters', 22.4),
      ]);
      expect(rivals.keys, unorderedEquals(['400 Meters', '200 Meters']));
      expect(rivals['200 Meters']!.athleteId, 'other');
    });
  });

  group('formatGap', () {
    test('formats track gaps in seconds', () {
      expect(formatGap('400 Meters', 0.2), '0.20s');
      expect(formatGap('Mile', 75.5), '1:15.50s');
    });

    test('formats field gaps in meters', () {
      expect(formatGap('Long Jump', 0.12), '0.12m');
    });

    test('formats field gaps in inches, then feet, when imperial', () {
      expect(formatGap('Long Jump', 0.12, imperial: true), '4.75"');
      expect(formatGap('Shot Put', 0.4, imperial: true), "1' 3.75\"");
    });

    test('formats multi-event gaps in points', () {
      expect(formatGap('Pentathlon', 120), '120 pts');
      expect(formatGap('Pentathlon', 120, imperial: true), '120 pts');
    });
  });

  group('markDisplay', () {
    test('converts meters to feet and inches, rounding down to 1/4"', () {
      expect(feetInches(6.22), "20' 4.75\"");
      expect(feetInches(1.76), "5' 9.25\"");
      expect(feetInches(1.8288), "6' 0\"");
      expect(feetInches(11.22), "36' 9.5\"");
    });

    test('leaves metric, track times and multi-events as scraped', () {
      expect(markDisplay('Long Jump', '6.22m', 6.22, imperial: false), '6.22m');
      expect(markDisplay('60 Meters', '7.12', 7.12, imperial: true), '7.12');
      expect(markDisplay('Pentathlon', '2980', 2980, imperial: true), '2980');
      expect(markDisplay('Long Jump', 'FOUL', null, imperial: true), 'FOUL');
    });

    test('converts field marks when imperial', () {
      expect(markDisplay('Long Jump', '6.22m', 6.22, imperial: true),
          "20' 4.75\"");
    });
  });

  group('latestRanksByEvent', () {
    Map<String, dynamic> rank(String event, String scope, String season,
            int year, int place) =>
        {
          'event': event,
          'scope': scope,
          'label': scope == 'national' ? 'D3' : 'MAC',
          'season': season,
          'season_year': year,
          'rank': place,
          'list_size': 500,
        };

    test('uses the most recent season, national first', () {
      final ranks = latestRanksByEvent([
        rank('Long Jump', 'conference', 'indoor', 2026, 4),
        rank('Long Jump', 'conference', 'outdoor', 2026, 2),
        rank('Long Jump', 'national', 'outdoor', 2026, 66),
        rank('Long Jump', 'national', 'outdoor', 2025, 90),
      ])['Long Jump']!;
      expect(ranks.map((r) => '${r.label} #${r.rank}'), ['D3 #66', 'MAC #2']);
      expect(ranks.first.seasonLabel, 'Outdoor 2026');
    });

    test('never mixes seasons between national and conference', () {
      // Nationally ranked indoors only; the outdoor conference rank is newer.
      final ranks = latestRanksByEvent([
        rank('High Jump', 'national', 'indoor', 2026, 19),
        rank('High Jump', 'conference', 'outdoor', 2026, 1),
      ])['High Jump']!;
      expect(ranks.map((r) => r.scope), ['conference']);
    });

    test('keeps events separate and skips incomplete rows', () {
      final ranks = latestRanksByEvent([
        rank('60 Meters', 'conference', 'indoor', 2026, 6),
        rank('100 Meters', 'conference', 'outdoor', 2026, 15),
        {'event': '200 Meters', 'scope': 'national'},
      ]);
      expect(ranks.keys, unorderedEquals(['60 Meters', '100 Meters']));
    });
  });
}
