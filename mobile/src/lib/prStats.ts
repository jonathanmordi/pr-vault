// PR detection, season points, trend windows and rivals.
//
// Everything here is computed from scraped rows (meet_appearances,
// track_prs, school_records) and is plain TypeScript, so it can be unit
// tested without a Supabase backend.

/** A row as PostgREST returns it. */
export type Row = Record<string, any>;

export const kFieldEvents = [
  'High Jump', 'Long Jump', 'Triple Jump', 'Pole Vault',
  'Shot Put', 'Discus', 'Hammer', 'Javelin', 'Weight Throw',
  'Decathlon', 'Heptathlon', 'Pentathlon',
];

export const isFieldEvent = (event: string) => kFieldEvents.includes(event);

/** Field marks are better when higher, track times when lower. */
export const isBetterMark = (event: string, a: number, b: number) =>
  isFieldEvent(event) ? a > b : a < b;

/** Parses a `YYYY-MM-DD` meet date into a local date, or null. */
export function parseMeetDate(raw: unknown): Date | null {
  if (typeof raw !== 'string' || raw.length < 10) return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(raw);
  if (!m) return null;
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return isNaN(d.getTime()) ? null : d;
}

/** A local date, e.g. for tests: `day(2026, 3, 1)` is March 1. */
export const day = (year: number, month: number, date: number) => new Date(year, month - 1, date);

/** The local calendar day of [d], with the time dropped. */
export const dateOnly = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());

/** `2026-03-01`. */
export function isoDay(d: Date) {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** Orders strings by code unit, so case matters (localeCompare ignores it). */
export const compareStrings = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

/** Whole days from [a] to [b], ignoring daylight saving shifts. */
export const daysBetween = (a: Date, b: Date) =>
  Math.round((Date.UTC(b.getFullYear(), b.getMonth(), b.getDate()) -
    Date.UTC(a.getFullYear(), a.getMonth(), a.getDate())) / 86_400_000);

// ─── Seasons ──────────────────────────────────────────────────────────────────

/**
 * Every result and PR belongs to one season: 'indoor', 'outdoor' or 'xc'
 * (cross country). Track seasons never mix: an indoor 200 and an outdoor
 * 200 are separate events with separate PRs.
 */
export const kSeasons = ['indoor', 'outdoor', 'xc'];

export function seasonLabel(season: string) {
  switch (season) {
    case 'indoor': return 'Indoor';
    case 'outdoor': return 'Outdoor';
    case 'xc': return 'XC';
    default: return season;
  }
}

/** Cross country races are named by distance: 8k, 6k, 5k. */
export const isXcEvent = (event: string) => /^\d+(\.\d+)?k$/i.test(event);

const indoorOnly = new Set([
  '55 Meters', '60 Meters', '55 Hurdles', '60 Hurdles', '300 Meters',
  '500 Meters', '600 Meters', '1000 Meters', 'Weight Throw', 'Pentathlon',
]);
const outdoorOnly = new Set([
  '100 Meters', '100 Hurdles', '110 Hurdles', '400 Hurdles', '10,000 Meters',
  '3000 Steeplechase', 'Hammer', 'Discus', 'Javelin', 'Decathlon',
  '4 x 100 Relay',
]);

/**
 * The season of a result saved without one. The same rules as the
 * database's guess_track_season(): event, meet name, then the date (indoor
 * runs from November to mid-March).
 */
export function guessSeason(event: string, meetName: string | null | undefined, date: Date | null): string {
  if (isXcEvent(event)) return 'xc';
  const meet = meetName?.toLowerCase() ?? '';
  if (meet.includes('indoor')) return 'indoor';
  if (meet.includes('outdoor')) return 'outdoor';
  if (indoorOnly.has(event)) return 'indoor';
  if (outdoorOnly.has(event)) return 'outdoor';
  if (date) {
    const month = date.getMonth() + 1;
    if ([11, 12, 1, 2].includes(month) || (month === 3 && date.getDate() <= 15)) return 'indoor';
  }
  return 'outdoor';
}

/** A meet_appearances or track_prs row's season, guessed for rows from before results had one. */
export function seasonOf(row: Row): string {
  const s = row.season;
  if (typeof s === 'string' && s.length > 0) return s;
  return guessSeason(
    row.event ?? '',
    row.meet_name ?? row.set_at_meet,
    parseMeetDate(row.meet_date ?? row.set_on),
  );
}

/** Identifies an event within a season, e.g. for keying rivals. */
export const eventKey = (event: string, season: string) => `${event}|${season}`;

/** The seasons among [rows], in [kSeasons] order. */
export function seasonsIn(rows: Iterable<Row>): string[] {
  const present = new Set<string>();
  for (const r of rows) present.add(seasonOf(r));
  return kSeasons.filter((s) => present.has(s));
}

/**
 * The track season of the most recent result in [rows]: what to show
 * first. Cross country only when there's no track result at all.
 */
export function latestSeasonOf(rows: Iterable<Row>): string {
  let latest: Date | null = null;
  let season: string | null = null;
  let xc = false;
  for (const r of rows) {
    const s = seasonOf(r);
    if (s === 'xc') {
      xc = true;
      continue;
    }
    const d = parseMeetDate(r.meet_date ?? r.set_on);
    if (d && (!latest || d > latest)) {
      latest = d;
      season = s;
    }
  }
  return season ?? (xc ? 'xc' : 'outdoor');
}

/** 'SR-4' → 'Senior'. TFRRS shows class years as FR-1, SO-2, JR-3, SR-4. */
export function classYearLabel(raw: string | null | undefined): string | null {
  const code = raw?.trim().split('-')[0].toUpperCase() ?? '';
  switch (code) {
    case '': return null;
    case 'FR': return 'Freshman';
    case 'SO': return 'Sophomore';
    case 'JR': return 'Junior';
    case 'SR': return 'Senior';
    case 'GR': return 'Grad student';
    default: return raw!.trim();
  }
}

/**
 * Academic seasons run Aug 1 – Jul 31, covering one indoor and one outdoor
 * season. Returns the year the season starts in.
 */
export const academicYearOf = (d: Date) => (d.getMonth() + 1 >= 8 ? d.getFullYear() : d.getFullYear() - 1);

export const kMultiEvents = ['Decathlon', 'Heptathlon', 'Pentathlon'];

/** Field events marked in meters. Multi-events are scored in points. */
export const isMeasuredInMeters = (event: string) => isFieldEvent(event) && !kMultiEvents.includes(event);

const trimInches = (inches: number) => inches.toFixed(2).replace(/0+$/, '').replace(/\.$/, '');

/**
 * 6.22 → `20' 4.75"`. Rounds down to the quarter inch, as NCAA conversions
 * do, so a mark never reads longer than it was.
 */
export function feetInches(meters: number) {
  const quarters = Math.floor(meters / 0.0254 * 4 + 1e-6);
  return `${Math.floor(quarters / 48)}' ${trimInches((quarters % 48) / 4)}"`;
}

/** The scraped display, or feet and inches when [imperial] and the event is marked in meters. */
export function markDisplay(event: string, display: string, meters: number | null | undefined, imperial: boolean) {
  if (!imperial || meters == null || meters <= 0) return display;
  return isMeasuredInMeters(event) ? feetInches(meters) : display;
}

export function formatGap(event: string, gap: number, imperial = false) {
  if (isFieldEvent(event)) {
    if (!isMeasuredInMeters(event)) return `${Math.round(gap)} pts`;
    if (!imperial) return `${gap.toFixed(2)}m`;
    const quarters = Math.round(gap / 0.0254 * 4);
    const inches = trimInches((quarters % 48) / 4);
    return quarters >= 48 ? `${Math.floor(quarters / 48)}' ${inches}"` : `${inches}"`;
  }
  if (gap >= 60) {
    const m = Math.floor(gap / 60);
    const s = (gap - m * 60).toFixed(2).padStart(5, '0');
    return `${m}:${s}s`;
  }
  return `${gap.toFixed(2)}s`;
}

function markOf(row: Row, event: string, timeKey: string, markKey: string): number | null {
  const raw = isFieldEvent(event) ? row[markKey] : row[timeKey];
  const v = typeof raw === 'number' ? raw : raw == null ? null : Number(raw);
  return v != null && !isNaN(v) && v > 0 ? v : null;
}

// ─── PR detection ─────────────────────────────────────────────────────────────

/** A meet where an athlete beat their previous best in an event. */
export class PrEvent {
  readonly athleteId: string;
  readonly event: string;
  readonly season: string;
  readonly date: Date;
  readonly display: string;
  readonly meetName: string;
  readonly value: number;
  readonly previousValue: number;
  readonly schoolRecord: boolean;

  constructor(p: {
    athleteId: string;
    event: string;
    season?: string;
    date: Date;
    display: string;
    meetName: string;
    value: number;
    previousValue: number;
    schoolRecord?: boolean;
  }) {
    this.athleteId = p.athleteId;
    this.event = p.event;
    this.season = p.season ?? 'outdoor';
    this.date = p.date;
    this.display = p.display;
    this.meetName = p.meetName;
    this.value = p.value;
    this.previousValue = p.previousValue;
    this.schoolRecord = p.schoolRecord ?? false;
  }

  /** How much better than the previous best, in percent (always positive). */
  get improvementPct() {
    return isFieldEvent(this.event)
      ? (this.value - this.previousValue) / this.previousValue * 100
      : (this.previousValue - this.value) / this.previousValue * 100;
  }

  /** Absolute improvement in the event's unit (seconds or meters). */
  get gap() {
    return Math.abs(this.value - this.previousValue);
  }

  /** 10 for the PR, +5 per 1% improved, +100 for a school record. */
  get points() {
    return 10 + Math.round(this.improvementPct * 5) + (this.schoolRecord ? 100 : 0);
  }

  /** Stable identity, used to remember which alerts were already seen. */
  get key() {
    return `${this.athleteId}|${this.event}|${isoDay(this.date)}|${this.display}`;
  }
}

/**
 * Walks each athlete's results in date order and returns every meet where
 * they beat their previous best in that event and season, newest first.
 *
 * Only the best mark of each day counts, so a prelim and a final on the
 * same day are one PR. A debut mark has nothing to beat and isn't a PR.
 */
export function detectPrs(
  appearances: Iterable<Row>,
  { records = [], genderByAthlete = {} }: { records?: Row[]; genderByAthlete?: Record<string, string> } = {},
): PrEvent[] {
  const byAthleteEvent = new Map<string, Map<string, { value: number; row: Row; date: Date }>>();
  for (const a of appearances) {
    const athleteId = a.athlete_id as string | undefined;
    const event = a.event as string | undefined;
    const date = parseMeetDate(a.meet_date);
    if (!athleteId || !event || !date) continue;
    const v = markOf(a, event, 'time_seconds', 'mark_meters');
    if (v == null) continue;
    const key = `${athleteId}\u0000${event}\u0000${seasonOf(a)}`;
    let days = byAthleteEvent.get(key);
    if (!days) byAthleteEvent.set(key, (days = new Map()));
    const k = isoDay(date);
    const cur = days.get(k);
    if (!cur || isBetterMark(event, v, cur.value)) days.set(k, { value: v, row: a, date });
  }

  const prs: PrEvent[] = [];
  for (const [key, days] of byAthleteEvent) {
    const [athleteId, event, season] = key.split('\u0000');
    const ordered = [...days.values()].sort((a, b) => a.date.getTime() - b.date.getTime());
    let best: number | null = null;
    for (const d of ordered) {
      if (best != null && isBetterMark(event, d.value, best)) {
        prs.push(new PrEvent({
          athleteId,
          event,
          season,
          date: d.date,
          display: d.row.display_value ?? '',
          meetName: d.row.meet_name ?? '',
          value: d.value,
          previousValue: best,
          schoolRecord: holdsSchoolRecord(records, event, season, genderByAthlete[athleteId], d.value),
        }));
      }
      if (best == null || isBetterMark(event, d.value, best)) best = d.value;
    }
  }

  prs.sort((a, b) => {
    const byDate = b.date.getTime() - a.date.getTime();
    if (byDate !== 0) return byDate;
    const byAthlete = compareStrings(a.athleteId, b.athleteId);
    return byAthlete !== 0 ? byAthlete : compareStrings(a.event, b.event);
  });
  return prs;
}

/**
 * school_records only stores the current record, so a PR counts as a school
 * record when it matches (or beats) the record for its season.
 */
function holdsSchoolRecord(records: Row[], event: string, season: string, gender: string | undefined, value: number) {
  if (gender == null) return false;
  for (const r of records) {
    if (r.event !== event || r.gender !== gender) continue;
    const rs = r.season as string | undefined;
    if (rs && rs !== season) continue;
    const rec = markOf(r, event, 'record_mark_seconds', 'record_mark_meters');
    if (rec == null) continue;
    if (Math.abs(value - rec) < 1e-6 || isBetterMark(event, value, rec)) return true;
  }
  return false;
}

// ─── Trending ─────────────────────────────────────────────────────────────────

/** A date range the trending list and season points are computed over. */
export class TrendWindow {
  private constructor(
    readonly id: string,
    readonly label: string,
    readonly shortLabel: string,
    readonly start: Date | null, // inclusive
    readonly end: Date | null, // exclusive
  ) {}

  static lastDays(days: number, now: Date) {
    const today = dateOnly(now);
    const start = new Date(today.getFullYear(), today.getMonth(), today.getDate() - days);
    return new TrendWindow(`last${days}`, `Last ${days} days`, `${days}d`, start, null);
  }

  static season(startYear: number) {
    const yy = (y: number) => String(y % 100).padStart(2, '0');
    const end = yy(startYear + 1);
    return new TrendWindow(`season${startYear}`, `${startYear}–${end}`, `${yy(startYear)}–${end}`,
      new Date(startYear, 7, 1), new Date(startYear + 1, 7, 1));
  }

  static readonly allTime = new TrendWindow('all', 'All time', 'All-time', null, null);

  get isSeason() {
    return this.id.startsWith('season');
  }

  contains(d: Date) {
    return (!this.start || d >= this.start) && (!this.end || d < this.end);
  }
}

/** The last 30 days, the (up to three) most recent seasons that have PRs, and all time. */
export function trendWindows(prs: Iterable<PrEvent>, now: Date): TrendWindow[] {
  const years = [...new Set([...prs].map((p) => academicYearOf(p.date)))].sort((a, b) => b - a);
  return [TrendWindow.lastDays(30, now), ...years.slice(0, 3).map(TrendWindow.season), TrendWindow.allTime];
}

/**
 * The most recent season with PRs, so the list isn't empty in the
 * offseason. Falls back to all time when there's no data at all.
 */
export const defaultTrendWindow = (windows: TrendWindow[]) =>
  windows.find((w) => w.isSeason) ?? TrendWindow.allTime;

export class AthleteTrend {
  /** [prs] newest first. */
  constructor(readonly athleteId: string, readonly prs: PrEvent[]) {}

  get prCount() {
    return this.prs.length;
  }

  get points() {
    return this.prs.reduce((sum, p) => sum + p.points, 0);
  }

  get lastPr() {
    return this.prs[0].date;
  }

  /** Distinct events, in order of most recent PR. */
  get events() {
    return [...new Set(this.prs.map((p) => p.event))];
  }
}

/**
 * Groups PRs by athlete and ranks them by PR count (or by points), with the
 * other metric and then the most recent PR as tie-breakers.
 */
export function trendingAthletes(prs: Iterable<PrEvent>, byPoints = false): AthleteTrend[] {
  const grouped = new Map<string, PrEvent[]>();
  for (const p of prs) {
    const list = grouped.get(p.athleteId);
    if (list) list.push(p);
    else grouped.set(p.athleteId, [p]);
  }
  const rows = [...grouped].map(
    ([id, list]) => new AthleteTrend(id, list.sort((a, b) => b.date.getTime() - a.date.getTime())),
  );
  rows.sort((a, b) => {
    const primary = byPoints ? b.points - a.points : b.prCount - a.prCount;
    if (primary !== 0) return primary;
    const secondary = byPoints ? b.prCount - a.prCount : b.points - a.points;
    if (secondary !== 0) return secondary;
    return b.lastPr.getTime() - a.lastPr.getTime();
  });
  return rows;
}

// ─── Rivals ───────────────────────────────────────────────────────────────────

/** The teammate whose PR in an event is closest to an athlete's own. */
export class Rival {
  readonly athleteId: string;
  readonly event: string;
  readonly season: string;
  readonly myValue: number;
  readonly theirValue: number;
  readonly theirDisplay: string;

  constructor(p: {
    athleteId: string;
    event: string;
    season?: string;
    myValue: number;
    theirValue: number;
    theirDisplay: string;
  }) {
    this.athleteId = p.athleteId;
    this.event = p.event;
    this.season = p.season ?? 'outdoor';
    this.myValue = p.myValue;
    this.theirValue = p.theirValue;
    this.theirDisplay = p.theirDisplay;
  }

  get isAhead() {
    return isBetterMark(this.event, this.theirValue, this.myValue);
  }

  get gap() {
    return Math.abs(this.theirValue - this.myValue);
  }

  get gapPct() {
    return this.gap / this.myValue * 100;
  }
}

/**
 * Finds the same-gender teammate with the closest PR in [event] and
 * [season]. Ties go to the teammate who's ahead, since that's the one worth
 * chasing.
 */
export function findRival(p: {
  athleteId: string;
  event: string;
  season?: string;
  myValue: number;
  gender: string | null | undefined;
  teamPrs: Iterable<Row>;
}): Rival | null {
  const season = p.season ?? 'outdoor';
  let best: Rival | null = null;
  for (const row of p.teamPrs) {
    const otherId = row.athlete_id as string | undefined;
    if (!otherId || otherId === p.athleteId || row.event !== p.event || seasonOf(row) !== season) continue;
    const otherGender = row.profiles?.gender ?? 'M';
    if (p.gender != null && otherGender !== p.gender) continue;
    const v = markOf(row, p.event, 'best_time_seconds', 'best_mark_meters');
    if (v == null) continue;
    const candidate = new Rival({
      athleteId: otherId,
      event: p.event,
      season,
      myValue: p.myValue,
      theirValue: v,
      theirDisplay: row.best_display ?? '',
    });
    if (
      !best ||
      candidate.gap < best.gap - 1e-9 ||
      (Math.abs(candidate.gap - best.gap) < 1e-9 && candidate.isAhead && !best.isAhead)
    ) {
      best = candidate;
    }
  }
  return best;
}

/** Rivals for each event and season [athleteId] has a PR in, keyed by [eventKey]. */
export function rivalsFor(athleteId: string, gender: string | null | undefined, teamPrs: Row[]): Map<string, Rival> {
  const rivals = new Map<string, Rival>();
  for (const p of teamPrs) {
    if (p.athlete_id !== athleteId) continue;
    const event = p.event as string | undefined;
    if (!event) continue;
    const mine = markOf(p, event, 'best_time_seconds', 'best_mark_meters');
    if (mine == null) continue;
    const season = seasonOf(p);
    const rival = findRival({ athleteId, event, season, myValue: mine, gender, teamPrs });
    if (rival) rivals.set(eventKey(event, season), rival);
  }
  return rivals;
}

// ─── Performance-list ranks ───────────────────────────────────────────────────

/** How a national rank compares with the projected championship field. */
export type NationalsStatus = {
  inside: boolean;
  /** Distance from the cut in the event's unit, or null when there's no cut mark yet. */
  gap: number | null;
};

/**
 * An athlete's place on a TFRRS national or conference performance list.
 * Lists rank season bests, so every rank belongs to a season.
 */
export class ListRank {
  constructor(
    readonly event: string,
    readonly scope: string, // 'national' or 'conference'
    readonly label: string, // e.g. 'D3', 'MAC'
    readonly season: string, // 'indoor' or 'outdoor'
    readonly seasonYear: number,
    readonly rank: number,
    readonly listSize: number,
    /** The athlete's mark on the list, as TFRRS shows it. */
    readonly markDisplay: string | null = null,
    /** Size of the projected championship field, on national lists. */
    readonly cutRank: number | null = null,
    /** Mark of the athlete at [cutRank], or null while the list is shorter. */
    readonly cutMark: string | null = null,
  ) {}

  /** Parses a list_ranks row, or returns null if it's incomplete. */
  static tryParse(row: Row): ListRank | null {
    const { event, scope, season } = row;
    const year = row.season_year;
    const rank = row.rank;
    if (event == null || scope == null || season == null || year == null || rank == null) return null;
    return new ListRank(
      event,
      scope,
      row.label ?? (scope === 'national' ? 'National' : 'Conf.'),
      season,
      Math.trunc(year),
      Math.trunc(rank),
      row.list_size == null ? 0 : Math.trunc(row.list_size),
      row.mark_display ?? null,
      row.cut_rank == null ? null : Math.trunc(row.cut_rank),
      row.cut_mark ?? null,
    );
  }

  /**
   * Where this rank sits against the projected national championship field,
   * or null for conference lists and lists without a cut.
   */
  get nationals(): NationalsStatus | null {
    const cut = this.cutRank;
    if (this.scope !== 'national' || cut == null) return null;
    const mine = parseMarkValue(this.markDisplay);
    const line = parseMarkValue(this.cutMark);
    return { inside: this.rank <= cut, gap: mine == null || line == null ? null : Math.abs(mine - line) };
  }

  /** Later seasons sort higher; outdoor follows indoor within a year. */
  get recency() {
    return this.seasonYear * 2 + (this.season === 'outdoor' ? 1 : 0);
  }

  get seasonLabel() {
    return `${this.season === 'outdoor' ? 'Outdoor' : 'Indoor'} ${this.seasonYear}`;
  }
}

/**
 * For each event, the ranks from the most recent season the athlete was
 * ranked in, national first. National and conference ranks are never mixed
 * across seasons, so one season label describes them both.
 */
export function latestRanksByEvent(rows: Iterable<Row>): Map<string, ListRank[]> {
  const byEvent = new Map<string, ListRank[]>();
  for (const row of rows) {
    const r = ListRank.tryParse(row);
    if (!r) continue;
    const list = byEvent.get(r.event);
    if (list) list.push(r);
    else byEvent.set(r.event, [r]);
  }
  const out = new Map<string, ListRank[]>();
  for (const [event, ranks] of byEvent) {
    const latest = Math.max(...ranks.map((r) => r.recency));
    const scopeOrder = (r: ListRank) => (r.scope === 'national' ? 0 : 1);
    out.set(event, ranks.filter((r) => r.recency === latest).sort((a, b) => scopeOrder(a) - scopeOrder(b)));
  }
  return out;
}

/**
 * A TFRRS mark as a number: '10.22' → 10.22, '1:59.23' → 119.23,
 * '6.95m' → 6.95, '4520' → 4520. Null for anything else (DNF, FOUL).
 */
export function parseMarkValue(raw: string | null | undefined): number | null {
  const m = /^\d+(?::\d+){0,2}(?:\.\d+)?/.exec(raw?.trim() ?? '');
  if (!m) return null;
  return m[0].split(':').reduce((total, part) => total * 60 + parseFloat(part), 0);
}
