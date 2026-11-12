// A small fake team for tests: realistic TFRRS-style names, a long name and
// meet names to stress layouts, and results across indoor and outdoor
// seasons, with one PR per event per season as in the database.

import { Row, guessSeason, isFieldEvent, parseMeetDate } from '@/lib/prStats';
import { TeamSnapshot } from '@/lib/teamData';

export const sampleUserId = 'me';

type Series = [athleteId: string, name: string, gender: string, event: string, results: [string, number][]];

const series: Series[] = [
  ['me', 'Mordi, Jonathan', 'M', 'Triple Jump', [
    ['2025-01-18', 13.41], ['2025-02-22', 13.62], ['2025-12-06', 13.55],
    ['2026-01-24', 13.88], ['2026-02-28', 14.02], ['2026-04-04', 13.95],
    ['2026-04-18', 14.1],
  ]],
  ['me', 'Mordi, Jonathan', 'M', 'Long Jump', [
    ['2025-12-06', 6.71], ['2026-02-07', 6.88], ['2026-04-11', 6.85], ['2026-05-02', 6.93],
  ]],
  ['okafor', 'Okafor, Daniel', 'M', 'Triple Jump', [['2025-12-06', 13.8], ['2026-01-24', 14.05], ['2026-03-28', 14.22]]],
  ['okafor', 'Okafor, Daniel', 'M', 'Long Jump', [['2025-12-06', 6.8], ['2026-02-07', 6.95]]],
  ['bv', 'Bartholomew-Vanderbilt, Alexander Maximilian', 'M', '400 Meters', [
    ['2025-12-13', 51.2], ['2026-01-31', 50.42], ['2026-02-21', 49.87], ['2026-04-25', 49.31],
  ]],
  ['smith', 'Smith, Marcus', 'M', '60 Meters', [['2025-12-13', 7.12], ['2026-01-31', 7.01], ['2026-02-21', 6.98]]],
  ['chen', 'Chen, Lily', 'F', '400 Meters', [['2025-12-13', 59.8], ['2026-02-21', 58.4], ['2026-04-25', 57.95]]],
  ['chen', 'Chen, Lily', 'F', '200 Meters', [['2026-03-28', 26.1], ['2026-04-25', 25.62]]],
  ['rivera', 'Rivera, Sofia', 'F', 'Long Jump', [['2025-12-06', 5.4], ['2026-02-07', 5.62], ['2026-05-02', 5.71]]],
  ['nguyen', 'Nguyen, Ava', 'F', 'Mile', [['2025-12-13', 312.4], ['2026-02-21', 305.9]]],
];

const meets: Record<string, string[]> = {
  indoor: ['Fastrack National Invitational at the Ocean Breeze Athletic Complex', 'MAC Indoor Championships'],
  outdoor: ['Stevens Duck Classic', 'MAC Outdoor Championships'],
};

function display(event: string, v: number) {
  if (isFieldEvent(event)) return `${v.toFixed(2)}m`;
  if (v >= 60) {
    const m = Math.floor(v / 60);
    return `${m}:${(v - m * 60).toFixed(2).padStart(5, '0')}`;
  }
  return v.toFixed(2);
}

/** [alumni] lists athlete ids that have left the roster. */
export function sampleTeam(alumni: Set<string> = new Set()): TeamSnapshot {
  const appearances: Row[] = [];
  const prs: Row[] = [];
  for (const [athleteId, name, gender, event, results] of series) {
    const field = isFieldEvent(event);
    const bySeason = new Map<string, [string, number][]>();
    let i = 0;
    for (const [date, v] of results) {
      const season = guessSeason(event, null, parseMeetDate(date));
      bySeason.set(season, [...(bySeason.get(season) ?? []), [date, v]]);
      const names = meets[season];
      appearances.push({
        athlete_id: athleteId,
        event,
        season,
        time_seconds: field ? null : v,
        mark_meters: field ? v : null,
        display_value: display(event, v),
        meet_name: names[i++ % names.length],
        meet_date: date,
      });
    }
    // One PR per season: the best, and how much it beat the best before.
    for (const [season, rs] of bySeason) {
      const better = (a: number, b: number) => (field ? a > b : a < b);
      let best = rs[0];
      for (const r of rs) if (better(r[1], best[1])) best = r;
      const before = rs.filter((r) => r[0] < best[0]).map((r) => r[1]);
      const prev = before.length === 0 ? null : before.reduce((a, b) => (better(a, b) ? a : b));
      prs.push({
        athlete_id: athleteId,
        event,
        season,
        best_time_seconds: field ? null : best[1],
        best_mark_meters: field ? best[1] : null,
        best_display: display(event, best[1]),
        improvement_delta_pct: prev == null ? 0 : Math.abs(best[1] - prev) / prev * 100,
        set_on: best[0],
        set_at_meet: meets[season][0],
        profiles: { full_name: name, gender, on_roster: !alumni.has(athleteId), class_year: 'JR-3' },
      });
    }
  }
  appearances.sort((a, b) => (a.meet_date < b.meet_date ? -1 : a.meet_date > b.meet_date ? 1 : 0));
  return new TeamSnapshot({
    userId: sampleUserId,
    prs,
    appearances,
    records: [{ event: '400 Meters', gender: 'M', season: 'outdoor', record_mark_seconds: 49.31, record_mark_meters: null }],
  });
}
