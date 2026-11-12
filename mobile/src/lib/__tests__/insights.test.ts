import { Insight, InsightKind, RecordRef, athleteInsights } from '../insights';
import { ListRank, Rival, Row, formatGap, parseMeetDate } from '../prStats';

const jump = (date: string, m: number, { event = 'Long Jump', meet = 'Meet' } = {}): Row => ({
  event,
  meet_date: date,
  mark_meters: m,
  time_seconds: null,
  display_value: `${m.toFixed(2)}m`,
  meet_name: meet,
});

const run = (date: string, s: number, { event = '400 Meters' } = {}): Row => ({
  event,
  meet_date: date,
  mark_meters: null,
  time_seconds: s,
  display_value: s.toFixed(2),
  meet_name: 'Meet',
});

function insightsFor(
  appearances: Row[],
  {
    today = '2026-03-01',
    ranks = new Map<string, ListRank[]>(),
    rivals = new Map<string, Rival>(),
    records = new Map<string, RecordRef>(),
    limit = 10,
  } = {},
): Insight[] {
  return athleteInsights({
    appearances,
    ranks,
    rivals,
    records,
    nameOf: (id) => ({ okafor: 'Okafor, Daniel' } as Record<string, string>)[id] ?? id,
    formatMark: (_event, display) => display,
    formatGap: (event, gap) => formatGap(event, gap),
    now: parseMeetDate(today)!,
    limit,
  });
}

const kinds = (xs: Insight[]): InsightKind[] => xs.map((i) => i.kind);
const find = (xs: Insight[], kind: InsightKind) => xs.find((i) => i.kind === kind)!;

test('a PR at the latest meet in the last month is news', () => {
  const pr = find(insightsFor([jump('2026-01-10', 6.5), jump('2026-02-20', 6.62)]), 'freshPr');
  expect(pr.title).toBe('New PR in the indoor long jump');
  expect(pr.detail).toBe('6.62m on Feb 20, 0.12m better');
});

test('an old PR is not news', () => {
  expect(kinds(insightsFor([jump('2025-01-10', 6.5), jump('2025-02-20', 6.62)]))).not.toContain('freshPr');
});

test('improving in most recent meets is a trend; times improve by going down', () => {
  const trend = find(
    insightsFor([
      run('2026-01-10', 52.0), run('2026-01-24', 51.6), run('2026-02-07', 51.9),
      run('2026-02-14', 51.2), run('2026-02-21', 50.8),
    ]),
    'trend',
  );
  expect(trend.title).toBe('Indoor 400m is trending up');
  expect(trend.detail).toBe('Better in 3 of your last 5 meets');
});

test('indoor and outdoor are separate: an outdoor PR only beats outdoor marks', () => {
  const pr = find(
    insightsFor(
      [
        jump('2026-02-14', 6.95, { meet: 'MAC Indoor Championships' }),
        jump('2026-04-11', 6.7, { meet: 'Invite' }),
        jump('2026-04-25', 6.78, { meet: 'Invite' }),
      ],
      { today: '2026-05-01' },
    ),
    'freshPr',
  );
  expect(pr.title).toBe('New PR in the outdoor long jump');
  expect(pr.season).toBe('outdoor');
  expect(pr.detail).toBe('6.78m on Apr 25, 0.08m better');
});

test('results with a season use it over the guess', () => {
  const lj = (date: string, m: number, season: string) => ({ ...jump(date, m), season });
  const xs = insightsFor([lj('2026-04-04', 6.5, 'indoor'), lj('2026-04-18', 6.62, 'indoor')], { today: '2026-04-20' });
  expect(find(xs, 'freshPr').title).toBe('New PR in the indoor long jump');
});

test('a mixed run of results is not a trend', () => {
  const xs = insightsFor([jump('2026-01-10', 6.5), jump('2026-01-24', 6.4), jump('2026-02-07', 6.6), jump('2026-02-14', 6.3)]);
  expect(kinds(xs)).not.toContain('trend');
});

test('several meets without a PR is a drought', () => {
  const d = find(
    insightsFor([
      jump('2026-01-10', 6.9), jump('2026-01-24', 6.7), jump('2026-02-07', 6.75),
      jump('2026-02-14', 6.8), jump('2026-02-21', 6.72),
    ]),
    'drought',
  );
  expect(d.title).toBe('4 meets since an indoor long jump PR');
  expect(d.detail).toBe('Your best is 6.90m from Jan 10');
});

test('two results on one day count once, the better one', () => {
  const xs = insightsFor([jump('2026-01-10', 6.5), jump('2026-02-20', 6.4), jump('2026-02-20', 6.62)]);
  expect(find(xs, 'freshPr').detail.startsWith('6.62m on Feb 20')).toBe(true);
});

test('ahead of the same point last season', () => {
  const xs = insightsFor([
    jump('2025-01-20', 6.4), jump('2025-02-10', 6.45), jump('2025-04-20', 6.8), // last season
    jump('2026-01-24', 6.6), // this season, by Mar 1
  ]);
  expect(find(xs, 'seasonPace').detail).toBe('Indoor long jump is 0.15m better than this point last year');
});

describe('nationals', () => {
  const d3 = (rank: number, mark: string, cut: string) =>
    ListRank.tryParse({
      event: 'Long Jump', scope: 'national', label: 'D3', season: 'indoor',
      season_year: 2026, rank, list_size: 500, mark_display: mark,
      cut_rank: 20, cut_mark: cut,
    })!;

  test('inside the cut', () => {
    const xs = insightsFor([], { ranks: new Map([['Long Jump', [d3(12, '7.10m', '7.00m')]]]) });
    expect(xs).toHaveLength(1);
    expect(xs[0].title).toBe('Inside the D3 nationals cut');
    expect(xs[0].detail).toBe('#12 in the long jump, indoor 2026');
  });

  test('close to the cut', () => {
    const xs = insightsFor([], { ranks: new Map([['Long Jump', [d3(31, '6.80m', '7.00m')]]]) });
    expect(xs[0].title).toBe('0.20m from the D3 cut');
  });

  test('far from the cut says nothing', () => {
    expect(insightsFor([], { ranks: new Map([['Long Jump', [d3(140, '6.00m', '7.00m')]]]) })).toEqual([]);
  });
});

test('a close rival, by name', () => {
  const rival = new Rival({ athleteId: 'okafor', event: 'Triple Jump', myValue: 14.0, theirValue: 14.12, theirDisplay: '14.12m' });
  const xs = insightsFor([], { rivals: new Map([['Triple Jump', rival]]) });
  expect(xs).toHaveLength(1);
  expect(xs[0].title).toBe('0.12m behind Daniel Okafor');
  expect(xs[0].detail).toBe('Closest teammate in the outdoor triple jump');
});

test('strongest first, capped, at most two per event', () => {
  const xs = insightsFor(
    [jump('2026-01-10', 6.5), jump('2026-01-24', 6.55), jump('2026-02-07', 6.58), jump('2026-02-14', 6.6), jump('2026-02-21', 6.66)],
    { limit: 4 },
  );
  expect(xs.length).toBeLessThanOrEqual(4);
  expect(xs.filter((i) => i.event === 'Long Jump').length).toBeLessThanOrEqual(2);
  expect(xs[0].kind).toBe('freshPr');
});

describe('school records', () => {
  const record: RecordRef = { value: 6.96, display: '6.96m', holder: 'Lowe, Nicholas', year: 2011 };
  const records = new Map([['Long Jump|indoor', record]]);

  test('close to the record', () => {
    const xs = insightsFor([jump('2026-01-10', 6.8), jump('2026-02-20', 6.91)], { records, today: '2026-10-07' });
    expect(xs).toHaveLength(1);
    expect(xs[0].kind).toBe('schoolRecord');
    expect(xs[0].title).toBe('0.05m from the school record');
    expect(xs[0].detail).toBe("Indoor long jump record: 6.96m, Nicholas Lowe '11");
  });

  test('holding the record', () => {
    const xs = insightsFor([jump('2026-02-20', 7.01)], { records, today: '2026-10-07' });
    expect(xs[0].title).toBe('School record holder');
    expect(xs[0].detail).toBe('Indoor long jump, 7.01m on Feb 20, 2026');
  });

  test('far from the record says nothing', () => {
    expect(insightsFor([jump('2026-02-20', 6.2)], { records, today: '2026-10-07' })).toEqual([]);
  });

  test('times: faster than the record holds it', () => {
    const r400 = new Map([['400 Meters|indoor', { value: 48.1, display: '48.10', holder: 'Smith, A' }]]);
    expect(insightsFor([run('2026-02-20', 48.05)], { records: r400, today: '2026-10-07' })[0].detail.startsWith('Indoor 400m, 48.05')).toBe(true);
    expect(insightsFor([run('2026-02-20', 49.0)], { records: r400, today: '2026-10-07' })[0].title).toBe('0.90s from the school record');
  });
});
