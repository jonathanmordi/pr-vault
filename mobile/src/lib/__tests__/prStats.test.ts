// Unit tests for PR detection, season points, trend windows and rivals.
import {
  ListRank,
  PrEvent,
  Row,
  TrendWindow,
  day,
  defaultTrendWindow,
  detectPrs,
  feetInches,
  findRival,
  formatGap,
  guessSeason,
  isFieldEvent,
  latestRanksByEvent,
  latestSeasonOf,
  markDisplay,
  parseMarkValue,
  rivalsFor,
  seasonOf,
  seasonsIn,
  trendWindows,
  trendingAthletes,
} from '../prStats';

const run = (athlete: string, date: string, seconds: number, { event = '400 Meters', meet = 'Meet' } = {}): Row => ({
  athlete_id: athlete,
  event,
  time_seconds: seconds,
  mark_meters: null,
  display_value: seconds.toFixed(2),
  meet_name: meet,
  meet_date: date,
});

const jump = (athlete: string, date: string, meters: number, { event = 'Long Jump' } = {}): Row => ({
  athlete_id: athlete,
  event,
  time_seconds: null,
  mark_meters: meters,
  display_value: `${meters.toFixed(2)}m`,
  meet_name: 'Meet',
  meet_date: date,
});

const pr = (athlete: string, event: string, value: number, { gender = 'M' } = {}): Row => ({
  athlete_id: athlete,
  event,
  best_time_seconds: isFieldEvent(event) ? null : value,
  best_mark_meters: isFieldEvent(event) ? value : null,
  best_display: `${value}`,
  profiles: { full_name: athlete, gender },
});

describe('seasons', () => {
  test("a row's own season wins over the guess", () => {
    expect(seasonOf({ event: 'Long Jump', meet_date: '2026-04-04', season: 'indoor' })).toBe('indoor');
    expect(seasonOf({ event: 'Long Jump', meet_date: '2026-04-04' })).toBe('outdoor');
    expect(seasonOf({ event: 'Long Jump', set_on: '2026-02-04' })).toBe('indoor');
  });

  test('guesses like the database does', () => {
    expect(guessSeason('8k', 'Fall Classic', day(2025, 10, 4))).toBe('xc');
    expect(guessSeason('Long Jump', 'AARTFC Indoor Championships', day(2026, 3, 7))).toBe('indoor');
    expect(guessSeason('Long Jump', 'Invite', day(2026, 3, 15))).toBe('indoor');
    expect(guessSeason('Long Jump', 'Invite', day(2026, 3, 16))).toBe('outdoor');
    expect(guessSeason('60 Meters', 'Invite', day(2026, 4, 1))).toBe('indoor');
    expect(guessSeason('Hammer', 'Invite', day(2026, 2, 1))).toBe('outdoor');
  });

  test('opens on the latest track season, XC only when there is no track', () => {
    expect(latestSeasonOf([
      { event: 'Long Jump', meet_date: '2026-02-01' },
      { event: 'Long Jump', meet_date: '2026-05-01' },
      { event: '8k', meet_date: '2026-10-01' },
    ])).toBe('outdoor');
    expect(latestSeasonOf([{ event: '8k', meet_date: '2026-10-01' }])).toBe('xc');
    expect(latestSeasonOf([])).toBe('outdoor');
  });

  test('seasons in order', () => {
    expect(seasonsIn([
      { event: '8k', meet_date: '2026-10-01' },
      { event: 'Mile', season: 'outdoor' },
      { event: 'Mile', season: 'indoor' },
    ])).toEqual(['indoor', 'outdoor', 'xc']);
  });

  test('an outdoor mark is not a PR over an indoor one', () => {
    const prs = detectPrs([
      { ...run('a', '2026-02-10', 23.0, { event: '200 Meters' }), season: 'indoor' },
      { ...run('a', '2026-04-10', 22.8, { event: '200 Meters' }), season: 'outdoor' },
      { ...run('a', '2026-04-24', 22.6, { event: '200 Meters' }), season: 'outdoor' },
    ]);
    expect(prs).toHaveLength(1);
    expect(prs[0].season).toBe('outdoor');
    expect(prs[0].previousValue).toBe(22.8);
  });

  test('a PR is checked against the school record for its own season', () => {
    const records = [
      { event: '400 Meters', gender: 'M', season: 'indoor', record_mark_seconds: 49.5 },
      { event: '400 Meters', gender: 'M', season: 'outdoor', record_mark_seconds: 47.0 },
    ];
    // An indoor championship in late March: indoor, so the indoor record.
    const prs = detectPrs(
      [
        { ...run('a', '2026-03-01', 50.0), season: 'indoor' },
        { ...run('a', '2026-03-20', 49.4), season: 'indoor' },
      ],
      { records, genderByAthlete: { a: 'M' } },
    );
    expect(prs[0].schoolRecord).toBe(true);
  });

  test('rivals are from the same season', () => {
    const rivals = rivalsFor('me', 'M', [
      { ...pr('me', '400 Meters', 50.0), season: 'indoor' },
      { ...pr('them', '400 Meters', 50.1), season: 'outdoor' },
      { ...pr('other', '400 Meters', 51.0), season: 'indoor' },
    ]);
    expect([...rivals.keys()]).toEqual(['400 Meters|indoor']);
    expect(rivals.get('400 Meters|indoor')!.athleteId).toBe('other');
  });
});

describe('detectPrs', () => {
  test('a debut mark is not a PR; beating it is', () => {
    const prs = detectPrs([run('a', '2026-01-10', 50.0), run('a', '2026-01-17', 49.5)]);
    expect(prs).toHaveLength(1);
    expect(prs[0].value).toBe(49.5);
    expect(prs[0].previousValue).toBe(50.0);
    expect(prs[0].improvementPct).toBeCloseTo(1.0, 9);
  });

  test('a slower track time is not a PR', () => {
    const prs = detectPrs([run('a', '2026-01-10', 50.0), run('a', '2026-01-17', 50.4), run('a', '2026-01-24', 50.1)]);
    expect(prs).toEqual([]);
  });

  test('field events are better when longer', () => {
    const prs = detectPrs([jump('a', '2026-01-10', 6.0), jump('a', '2026-01-17', 5.9), jump('a', '2026-01-24', 6.3)]);
    expect(prs).toHaveLength(1);
    expect(prs[0].value).toBe(6.3);
    expect(prs[0].previousValue).toBe(6.0);
    expect(prs[0].improvementPct).toBeCloseTo(5.0, 9);
  });

  test('a prelim and final on the same day count as one PR', () => {
    const prs = detectPrs([
      run('a', '2026-01-10', 50.0),
      run('a', '2026-01-17', 49.8, { meet: 'Prelim' }),
      run('a', '2026-01-17', 49.5, { meet: 'Final' }),
    ]);
    expect(prs).toHaveLength(1);
    expect(prs[0].value).toBe(49.5);
    expect(prs[0].previousValue).toBe(50.0);
  });

  test('results are input-order independent', () => {
    const prs = detectPrs([run('a', '2026-02-01', 49.0), run('a', '2026-01-01', 50.0), run('a', '2026-01-15', 49.5)]);
    expect(prs.map((p) => p.value)).toEqual([49.0, 49.5]);
  });

  test('skips rows without a date or a usable mark', () => {
    const prs = detectPrs([
      run('a', '2026-01-10', 50.0),
      { ...run('a', '2026-01-17', 49.0), meet_date: null },
      { ...run('a', '2026-01-24', 48.0), time_seconds: 0 },
      { ...run('a', '2026-01-31', 48.0), time_seconds: null },
    ]);
    expect(prs).toEqual([]);
  });

  test('keeps events and athletes separate, newest first', () => {
    const prs = detectPrs([
      run('a', '2026-01-10', 50.0),
      run('a', '2026-03-10', 49.0),
      run('a', '2026-01-10', 23.0, { event: '200 Meters' }),
      run('a', '2026-02-10', 22.5, { event: '200 Meters' }),
      run('b', '2026-01-10', 52.0),
      run('b', '2026-03-12', 51.0),
    ]);
    expect(prs.map((p) => `${p.athleteId} ${p.event}`)).toEqual(['b 400 Meters', 'a 400 Meters', 'a 200 Meters']);
  });

  test('flags a PR that matches the school record for its season', () => {
    const records = [{ event: '400 Meters', gender: 'M', season: 'indoor', record_mark_seconds: 49.5 }];
    const prs = detectPrs([run('a', '2026-01-10', 50.0), run('a', '2026-02-10', 49.5)], {
      records,
      genderByAthlete: { a: 'M' },
    });
    expect(prs[0].schoolRecord).toBe(true);
  });

  test('ignores records from another season or gender', () => {
    const appearances = [run('a', '2026-01-10', 50.0), run('a', '2026-02-10', 49.5)];
    const outdoor = [{ event: '400 Meters', gender: 'M', season: 'outdoor', record_mark_seconds: 49.5 }];
    expect(detectPrs(appearances, { records: outdoor, genderByAthlete: { a: 'M' } })[0].schoolRecord).toBe(false);
    const women = [{ ...outdoor[0], season: 'indoor', gender: 'F' }];
    expect(detectPrs(appearances, { records: women, genderByAthlete: { a: 'M' } })[0].schoolRecord).toBe(false);
  });
});

describe('PrEvent.points', () => {
  const make = (prev: number, value: number, record = false) =>
    new PrEvent({
      athleteId: 'a',
      event: '400 Meters',
      date: day(2026, 1, 1),
      display: '',
      meetName: '',
      value,
      previousValue: prev,
      schoolRecord: record,
    });

  test('10 for the PR plus 5 per percent improved', () => {
    expect(make(50.0, 49.0).points).toBe(10 + 10); // 2% → 10
    expect(make(50.0, 49.9).points).toBe(10 + 1); // 0.2% → 1
  });

  test('school records add 100', () => {
    expect(make(50.0, 49.0, true).points).toBe(120);
  });
});

describe('TrendWindow', () => {
  test('seasons run Aug 1 to Jul 31', () => {
    const s = TrendWindow.season(2025);
    expect(s.label).toBe('2025–26');
    expect(s.shortLabel).toBe('25–26');
    expect(s.contains(day(2025, 7, 31))).toBe(false);
    expect(s.contains(day(2025, 8, 1))).toBe(true);
    expect(s.contains(day(2026, 7, 31))).toBe(true);
    expect(s.contains(day(2026, 8, 1))).toBe(false);
  });

  test('pads two-digit years', () => {
    expect(TrendWindow.season(2009).label).toBe('2009–10');
    expect(TrendWindow.season(2099).shortLabel).toBe('99–00');
  });

  test('lists last 30 days, up to three seasons with PRs, then all time', () => {
    const at = (d: Date) =>
      new PrEvent({ athleteId: 'a', event: '400 Meters', date: d, display: '', meetName: '', value: 49, previousValue: 50 });
    const windows = trendWindows(
      [at(day(2026, 5, 1)), at(day(2025, 2, 1)), at(day(2023, 9, 1)), at(day(2022, 3, 1))],
      day(2026, 10, 4),
    );
    expect(windows.map((w) => w.id)).toEqual(['last30', 'season2025', 'season2024', 'season2023', 'all']);
    // In the offseason the default is the latest season with data.
    expect(defaultTrendWindow(windows).id).toBe('season2025');
  });

  test('defaults to all time when there are no PRs', () => {
    const windows = trendWindows([], day(2026, 10, 4));
    expect(defaultTrendWindow(windows)).toBe(TrendWindow.allTime);
  });
});

describe('trendingAthletes', () => {
  const prs = detectPrs([
    // a: two small PRs
    run('a', '2026-01-01', 50.0),
    run('a', '2026-01-08', 49.9),
    run('a', '2026-01-15', 49.8),
    // b: one big PR
    run('b', '2026-01-01', 55.0),
    run('b', '2026-01-08', 50.0),
  ]);

  test('ranks by PR count, then points', () => {
    const rows = trendingAthletes(prs);
    expect(rows.map((r) => r.athleteId)).toEqual(['a', 'b']);
    expect(rows[0].prCount).toBe(2);
  });

  test('can rank by points instead', () => {
    const rows = trendingAthletes(prs, true);
    expect(rows.map((r) => r.athleteId)).toEqual(['b', 'a']);
    expect(rows[0].points).toBeGreaterThan(rows[1].points);
  });

  test('lists distinct events, most recent first', () => {
    const rows = trendingAthletes(
      detectPrs([
        run('a', '2026-01-01', 23.0, { event: '200 Meters' }),
        run('a', '2026-01-08', 22.9, { event: '200 Meters' }),
        run('a', '2026-01-01', 50.0),
        run('a', '2026-02-01', 49.0),
        run('a', '2026-03-01', 48.5),
      ]),
    );
    expect(rows[0].events).toEqual(['400 Meters', '200 Meters']);
  });
});

describe('rivals', () => {
  const team = [
    pr('me', '400 Meters', 50.0),
    pr('fast', '400 Meters', 49.8),
    pr('slow', '400 Meters', 50.5),
    pr('woman', '400 Meters', 50.01, { gender: 'F' }),
    pr('other', '200 Meters', 22.0),
  ];

  test('picks the closest same-gender teammate in the event', () => {
    const r = findRival({ athleteId: 'me', event: '400 Meters', myValue: 50.0, gender: 'M', teamPrs: team })!;
    expect(r.athleteId).toBe('fast');
    expect(r.isAhead).toBe(true);
    expect(r.gap).toBeCloseTo(0.2, 9);
  });

  test('a tie goes to the teammate who is ahead', () => {
    const r = findRival({
      athleteId: 'me',
      event: '400 Meters',
      myValue: 50.0,
      gender: 'M',
      teamPrs: [pr('behind', '400 Meters', 50.2), pr('ahead', '400 Meters', 49.8)],
    })!;
    expect(r.athleteId).toBe('ahead');
  });

  test('in field events, ahead means a longer mark', () => {
    const r = findRival({ athleteId: 'me', event: 'Long Jump', myValue: 6.0, gender: 'M', teamPrs: [pr('x', 'Long Jump', 6.1)] })!;
    expect(r.isAhead).toBe(true);
  });

  test('no teammates in the event means no rival', () => {
    expect(findRival({ athleteId: 'other', event: '200 Meters', myValue: 22.0, gender: 'M', teamPrs: team })).toBeNull();
  });

  test('rivalsFor covers every event the athlete has a PR in', () => {
    const rivals = rivalsFor('me', 'M', [...team, pr('me', '200 Meters', 22.4)]);
    expect([...rivals.values()].map((r) => r.event).sort()).toEqual(['200 Meters', '400 Meters']);
    expect([...rivals.keys()].sort()).toEqual(['200 Meters|outdoor', '400 Meters|outdoor']);
    expect([...rivals.values()].find((r) => r.event === '200 Meters')!.athleteId).toBe('other');
  });
});

describe('formatGap', () => {
  test('formats track gaps in seconds', () => {
    expect(formatGap('400 Meters', 0.2)).toBe('0.20s');
    expect(formatGap('Mile', 75.5)).toBe('1:15.50s');
  });

  test('formats field gaps in meters', () => {
    expect(formatGap('Long Jump', 0.12)).toBe('0.12m');
  });

  test('formats field gaps in inches, then feet, when imperial', () => {
    expect(formatGap('Long Jump', 0.12, true)).toBe('4.75"');
    expect(formatGap('Shot Put', 0.4, true)).toBe(`1' 3.75"`);
  });

  test('formats multi-event gaps in points', () => {
    expect(formatGap('Pentathlon', 120)).toBe('120 pts');
    expect(formatGap('Pentathlon', 120, true)).toBe('120 pts');
  });
});

describe('markDisplay', () => {
  test('converts meters to feet and inches, rounding down to 1/4"', () => {
    expect(feetInches(6.22)).toBe(`20' 4.75"`);
    expect(feetInches(1.76)).toBe(`5' 9.25"`);
    expect(feetInches(1.8288)).toBe(`6' 0"`);
    expect(feetInches(11.22)).toBe(`36' 9.5"`);
  });

  test('leaves metric, track times and multi-events as scraped', () => {
    expect(markDisplay('Long Jump', '6.22m', 6.22, false)).toBe('6.22m');
    expect(markDisplay('60 Meters', '7.12', 7.12, true)).toBe('7.12');
    expect(markDisplay('Pentathlon', '2980', 2980, true)).toBe('2980');
    expect(markDisplay('Long Jump', 'FOUL', null, true)).toBe('FOUL');
  });

  test('converts field marks when imperial', () => {
    expect(markDisplay('Long Jump', '6.22m', 6.22, true)).toBe(`20' 4.75"`);
  });
});

describe('latestRanksByEvent', () => {
  const rank = (event: string, scope: string, season: string, year: number, place: number): Row => ({
    event,
    scope,
    label: scope === 'national' ? 'D3' : 'MAC',
    season,
    season_year: year,
    rank: place,
    list_size: 500,
  });

  test('uses the most recent season, national first', () => {
    const ranks = latestRanksByEvent([
      rank('Long Jump', 'conference', 'indoor', 2026, 4),
      rank('Long Jump', 'conference', 'outdoor', 2026, 2),
      rank('Long Jump', 'national', 'outdoor', 2026, 66),
      rank('Long Jump', 'national', 'outdoor', 2025, 90),
    ]).get('Long Jump')!;
    expect(ranks.map((r) => `${r.label} #${r.rank}`)).toEqual(['D3 #66', 'MAC #2']);
    expect(ranks[0].seasonLabel).toBe('Outdoor 2026');
  });

  test('never mixes seasons between national and conference', () => {
    // Nationally ranked indoors only; the outdoor conference rank is newer.
    const ranks = latestRanksByEvent([
      rank('High Jump', 'national', 'indoor', 2026, 19),
      rank('High Jump', 'conference', 'outdoor', 2026, 1),
    ]).get('High Jump')!;
    expect(ranks.map((r) => r.scope)).toEqual(['conference']);
  });

  test('keeps events separate and skips incomplete rows', () => {
    const ranks = latestRanksByEvent([
      rank('60 Meters', 'conference', 'indoor', 2026, 6),
      rank('100 Meters', 'conference', 'outdoor', 2026, 15),
      { event: '200 Meters', scope: 'national' },
    ]);
    expect([...ranks.keys()].sort()).toEqual(['100 Meters', '60 Meters']);
  });
});

describe('parseMarkValue', () => {
  test('reads times, field marks and points', () => {
    expect(parseMarkValue('10.22')).toBe(10.22);
    expect(parseMarkValue('1:59.23')).toBeCloseTo(119.23, 9);
    expect(parseMarkValue('1:02:03.5')).toBeCloseTo(3723.5, 9);
    expect(parseMarkValue('6.95m')).toBe(6.95);
    expect(parseMarkValue(' 4520 ')).toBe(4520);
  });

  test('returns null for non-marks', () => {
    expect(parseMarkValue('DNF')).toBeNull();
    expect(parseMarkValue('')).toBeNull();
    expect(parseMarkValue(null)).toBeNull();
  });
});

describe('ListRank.nationals', () => {
  const national = (rank: number, mark: string, { cut, cutRank = 22 }: { cut?: string; cutRank?: number | null } = {}) =>
    ListRank.tryParse({
      event: '100 Meters',
      scope: 'national',
      label: 'D3',
      season: 'outdoor',
      season_year: 2026,
      rank,
      list_size: 500,
      mark_display: mark,
      cut_rank: cutRank,
      cut_mark: cut ?? null,
    })!;

  test('inside the cut, with the margin', () => {
    const s = national(19, '10.62', { cut: '10.70' }).nationals!;
    expect(s.inside).toBe(true);
    expect(s.gap).toBeCloseTo(0.08, 9);
  });

  test('outside the cut, with how far', () => {
    const s = national(31, '10.81', { cut: '10.70' }).nationals!;
    expect(s.inside).toBe(false);
    expect(s.gap).toBeCloseTo(0.11, 9);
  });

  test('a list shorter than the cut has everyone in, with no margin', () => {
    const s = national(3, '10.81').nationals!;
    expect(s.inside).toBe(true);
    expect(s.gap).toBeNull();
  });

  test('nothing for conference lists or before cuts were scraped', () => {
    expect(national(1, '10.5', { cutRank: null }).nationals).toBeNull();
    const conf = ListRank.tryParse({
      event: '100 Meters',
      scope: 'conference',
      label: 'MAC',
      season: 'outdoor',
      season_year: 2026,
      rank: 1,
      cut_rank: 22,
    })!;
    expect(conf.nationals).toBeNull();
  });
});
