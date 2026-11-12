// Insights for one athlete, worked out from their results so every number is
// exact. The profile shows the strongest few as cards. Plain TypeScript: the
// caller passes formatters for marks and gaps so units follow the user's
// settings.

import {
  ListRank,
  Rival,
  Row,
  academicYearOf,
  dateOnly,
  daysBetween,
  eventKey,
  isBetterMark,
  isFieldEvent,
  parseMarkValue,
  parseMeetDate,
  seasonOf,
} from './prStats';

export type InsightKind = 'schoolRecord' | 'freshPr' | 'trend' | 'nationals' | 'seasonPace' | 'rival' | 'drought';

export type Insight = {
  kind: InsightKind;
  event: string;
  /** 'indoor', 'outdoor' or 'xc'; insights never mix seasons. */
  season: string;
  title: string;
  detail: string;
  /** Higher shows first. */
  score: number;
};

/** A school record to measure an event against. */
export type RecordRef = {
  /** Seconds for track events, meters for field events. */
  value: number;
  display: string;
  holder: string;
  year?: number | null;
};

type Result = { date: Date; value: number; display: string; meet: string };

const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const dayLabel = (d: Date) => `${months[d.getMonth()]} ${d.getDate()}`;

/** How many results count as recent form. */
const formWindow = 5;

/** Results older than this don't make an event "current" for trends, droughts or fresh PRs. */
const recentDays = 180;

/** Within this share of the cut mark counts as close to qualifying. */
const closeToCut = 0.05;

/** Within this share of a school record counts as close to it. */
const closeToRecord = 0.03;

/**
 * The strongest insights for an athlete, at most [limit] and at most two per
 * event and season.
 *
 * [appearances] are the athlete's meet_appearances rows; [ranks] the latest
 * list ranks per event; [rivals] their rivals; [records] the school record
 * per event and season, keyed by [eventKey]; [nameOf] turns an athlete id
 * into a display name.
 */
export function athleteInsights(p: {
  appearances: Iterable<Row>;
  ranks?: Map<string, ListRank[]>;
  rivals?: Map<string, Rival>;
  records?: Map<string, RecordRef>;
  nameOf?: (athleteId: string) => string;
  formatMark: (event: string, display: string, value: number) => string;
  formatGap: (event: string, gap: number) => string;
  now: Date;
  limit?: number;
}): Insight[] {
  const { formatMark, formatGap, nameOf } = p;
  const ranks = p.ranks ?? new Map();
  const rivals = p.rivals ?? new Map();
  const records = p.records ?? new Map();
  const limit = p.limit ?? 4;
  const today = dateOnly(p.now);
  const byEvent = resultsByEvent(p.appearances);
  const insights: Insight[] = [];

  for (const { event, season, results } of byEvent) {
    const last = results[results.length - 1];
    const daysSinceLast = daysBetween(last.date, today);
    const recent = daysSinceLast <= recentDays;
    const name = eventName(event, season);

    // Index of each PR: results that beat everything before them.
    const prIndexes: number[] = [];
    for (let i = 0; i < results.length; i++) {
      if (prIndexes.length === 0 || isBetterMark(event, results[i].value, results[prIndexes[prIndexes.length - 1]].value)) {
        prIndexes.push(i);
      }
    }
    const lastPr = prIndexes[prIndexes.length - 1];

    // A PR at the latest meet, set in the last 30 days.
    if (lastPr === results.length - 1 && results.length > 1 && daysSinceLast <= 30) {
      const previous = results[prIndexes[prIndexes.length - 2]];
      const gain = Math.abs(last.value - previous.value);
      insights.push({
        kind: 'freshPr',
        event,
        season,
        title: `New PR in the ${name}`,
        detail: `${formatMark(event, last.display, last.value)} on ${dayLabel(last.date)}, ${formatGap(event, gain)} better`,
        score: 100 - daysSinceLast,
      });
    }

    // Recent form: how many of the last few results beat the one before.
    if (recent && results.length >= 4) {
      const form = results.slice(results.length - Math.min(results.length, formWindow));
      let better = 0;
      for (let i = 1; i < form.length; i++) {
        if (isBetterMark(event, form[i].value, form[i - 1].value)) better++;
      }
      const comparisons = form.length - 1;
      if (better >= 3 && better / comparisons >= 0.75) {
        insights.push({
          kind: 'trend',
          event,
          season,
          title: `${capitalize(name)} is trending up`,
          detail: `Better in ${better} of your last ${form.length} meets`,
          score: 70 + better,
        });
      }
    }

    // A drought: several meets since the last PR.
    const sincePr = results.length - 1 - lastPr;
    if (recent && sincePr >= 4) {
      const pr = results[lastPr];
      insights.push({
        kind: 'drought',
        event,
        season,
        title: `${sincePr} meets since an ${name} PR`,
        detail: `Your best is ${formatMark(event, pr.display, pr.value)} from ${dayLabel(pr.date)}`,
        score: 30 + sincePr,
      });
    }

    // This season against the same point last season.
    const pace = seasonPace(event, results, today);
    if (pace != null && pace > 0) {
      insights.push({
        kind: 'seasonPace',
        event,
        season,
        title: 'Ahead of last season',
        detail: `${capitalize(name)} is ${formatGap(event, pace)} better than this point last year`,
        score: 60,
      });
    }
  }

  // School records: holding one, or close to it.
  for (const { event, season, results } of byEvent) {
    const record = records.get(eventKey(event, season));
    if (!record || results.length === 0 || record.value <= 0) continue;
    let best = results[0];
    for (const r of results) {
      if (isBetterMark(event, r.value, best.value)) best = r;
    }
    const name = eventName(event, season);
    if (!isBetterMark(event, record.value, best.value)) {
      insights.push({
        kind: 'schoolRecord',
        event,
        season,
        title: 'School record holder',
        detail: `${capitalize(name)}, ${formatMark(event, best.display, best.value)} on ${dayLabel(best.date)}, ${best.date.getFullYear()}`,
        score: 95,
      });
      continue;
    }
    const gap = Math.abs(record.value - best.value);
    if (gap / record.value <= closeToRecord) {
      const year = record.year == null ? '' : ` '${String(record.year % 100).padStart(2, '0')}`;
      insights.push({
        kind: 'schoolRecord',
        event,
        season,
        title: `${formatGap(event, gap)} from the school record`,
        detail: `${capitalize(name)} record: ${record.display}, ${displayName(record.holder)}${year}`,
        score: 85 - gap / record.value * 100,
      });
    }
  }

  // Nationals: inside the projected field, or close to it.
  for (const [event, eventRanks] of ranks) {
    for (const r of eventRanks) {
      const status = r.nationals;
      if (!status) continue;
      const name = eventName(event);
      const seasonText = r.seasonLabel.toLowerCase();
      if (status.inside) {
        insights.push({
          kind: 'nationals',
          event,
          season: r.season,
          title: `Inside the ${r.label} nationals cut`,
          detail: `#${r.rank} in the ${name}, ${seasonText}`,
          score: 90,
        });
      } else {
        const cut = parseMarkValue(r.cutMark);
        const gap = status.gap;
        if (cut != null && cut > 0 && gap != null && gap / cut <= closeToCut) {
          insights.push({
            kind: 'nationals',
            event,
            season: r.season,
            title: `${formatGap(event, gap)} from the ${r.label} cut`,
            detail: `${capitalize(name)}, #${r.rank} on the ${seasonText} list`,
            score: 80 - gap / cut * 100,
          });
        }
      }
    }
  }

  // The closest rival, when it's close.
  const closest = [...rivals.values()].sort((a, b) => a.gapPct - b.gapPct);
  if (closest.length > 0 && nameOf && closest[0].gapPct <= 3) {
    const rival = closest[0];
    const who = displayName(nameOf(rival.athleteId));
    const gap = formatGap(rival.event, rival.gap);
    const name = eventName(rival.event, rival.season);
    insights.push({
      kind: 'rival',
      event: rival.event,
      season: rival.season,
      title: rival.isAhead ? `${gap} behind ${who}` : `${gap} ahead of ${who}`,
      detail: rival.isAhead ? `Closest teammate in the ${name}` : `Holding off your closest teammate in the ${name}`,
      score: 50 - rival.gapPct,
    });
  }

  insights.sort((a, b) => b.score - a.score);
  const perEvent = new Map<string, number>();
  const picked: Insight[] = [];
  for (const insight of insights) {
    if (picked.length === limit) break;
    const key = eventKey(insight.event, insight.season);
    const n = perEvent.get(key) ?? 0;
    if (n >= 2) continue;
    perEvent.set(key, n + 1);
    picked.push(insight);
  }
  return picked;
}

/** Each event and season's results, oldest first, one per day (the best that day). */
function resultsByEvent(appearances: Iterable<Row>) {
  const byDay = new Map<string, { event: string; season: string; days: Map<number, Result> }>();
  for (const a of appearances) {
    const event = a.event as string | undefined;
    const date = parseMeetDate(a.meet_date);
    if (!event || !date) continue;
    const v = isFieldEvent(event) ? a.mark_meters : a.time_seconds;
    if (v == null || v <= 0) continue;
    const result: Result = { date, value: v, display: a.display_value ?? '', meet: a.meet_name ?? '' };
    const season = seasonOf(a);
    const key = eventKey(event, season);
    let group = byDay.get(key);
    if (!group) byDay.set(key, (group = { event, season, days: new Map() }));
    const existing = group.days.get(date.getTime());
    if (!existing || isBetterMark(event, v, existing.value)) group.days.set(date.getTime(), result);
  }
  return [...byDay.values()].map(({ event, season, days }) => ({
    event,
    season,
    results: [...days.values()].sort((a, b) => a.date.getTime() - b.date.getTime()),
  }));
}

/**
 * How much better this season's best is than last season's best at the
 * same point (days since Aug 1), or null without results in both.
 */
function seasonPace(event: string, results: Result[], today: Date): number | null {
  const season = academicYearOf(today);
  const dayOfSeason = daysBetween(new Date(season, 7, 1), today);
  const cutoffLastYear = new Date(season - 1, 7, 1 + dayOfSeason);

  const best = (rs: Result[]) => {
    let b: number | null = null;
    for (const r of rs) {
      if (b == null || isBetterMark(event, r.value, b)) b = r.value;
    }
    return b;
  };

  const now = best(results.filter((r) => academicYearOf(r.date) === season));
  const then = best(results.filter((r) => academicYearOf(r.date) === season - 1 && r.date <= cutoffLastYear));
  if (now == null || then == null) return null;
  return isBetterMark(event, now, then) ? Math.abs(now - then) : -Math.abs(now - then);
}

/**
 * '400 Meters' → '400m', 'Long Jump' → 'long jump'. With a [season],
 * 'outdoor 400m', 'indoor long jump', 'XC 8k'.
 */
function eventName(event: string, season?: string) {
  const m = /^(\d+) Meters?$/.exec(event);
  const name = m ? `${m[1]}m` : event.toLowerCase();
  if (season == null) return name;
  return season === 'xc' ? `XC ${name}` : `${season} ${name}`;
}

const capitalize = (s: string) => (s.length === 0 ? s : s[0].toUpperCase() + s.slice(1));

/** 'Mordi, Jonathan' → 'Jonathan Mordi'. */
function displayName(raw: string) {
  if (!raw.includes(',')) return raw;
  const parts = raw.split(',');
  return `${parts[1].trim()} ${parts[0].trim()}`;
}
