import { PostgrestError } from '@supabase/supabase-js';

import {
  PrEvent,
  Rival,
  Row,
  TrendWindow,
  compareStrings,
  defaultTrendWindow,
  detectPrs,
  latestSeasonOf,
  rivalsFor,
  seasonsIn,
  trendWindows,
} from './prStats';
import { DeviceTeamCacheStore, TeamCacheStore } from './teamCache';

/**
 * One load of the team's scraped results. The leaderboard, trending list,
 * activity feed and rival cards all read from the same snapshot, so moving
 * between them doesn't refetch.
 */
export class TeamSnapshot {
  readonly userId: string | null;
  /** track_prs rows joined with profiles(full_name, gender, on_roster, class_year). */
  readonly prs: Row[];
  /** Every meet_appearances row for the team, oldest first. */
  readonly appearances: Row[];
  readonly records: Row[];

  private readonly names = new Map<string, string>();
  private readonly genders = new Map<string, string>();
  private readonly current = new Map<string, boolean>();
  private readonly classYears = new Map<string, string | null>();

  constructor(p: { userId: string | null; prs: Row[]; appearances: Row[]; records: Row[] }) {
    this.userId = p.userId;
    this.prs = p.prs;
    this.appearances = p.appearances;
    this.records = p.records;
    for (const pr of this.prs) {
      const id = pr.athlete_id as string;
      this.names.set(id, pr.profiles?.full_name ?? 'Unknown');
      this.genders.set(id, pr.profiles?.gender ?? 'M');
      this.current.set(id, pr.profiles?.on_roster ?? true);
      this.classYears.set(id, pr.profiles?.class_year ?? null);
    }
  }

  /** Bumped whenever the rows' shape changes, so an old saved copy is dropped instead of misread. */
  static readonly cacheVersion = 1;

  toCache() {
    return {
      v: TeamSnapshot.cacheVersion,
      user: this.userId,
      prs: this.prs,
      appearances: this.appearances,
      records: this.records,
    };
  }

  /** A saved copy for [userId], or null if it's someone else's or from an older version of the app. */
  static fromCache(data: Record<string, any>, userId: string): TeamSnapshot | null {
    if (data.v !== TeamSnapshot.cacheVersion || data.user !== userId) return null;
    const rows = (list: unknown) => (Array.isArray(list) ? (list as Row[]) : []);
    return new TeamSnapshot({
      userId,
      prs: rows(data.prs),
      appearances: rows(data.appearances),
      records: rows(data.records),
    });
  }

  /** One athlete's PRs, sorted by event, as a profile shows them. */
  prsOf(athleteId: string) {
    return this.prs
      .filter((p) => p.athlete_id === athleteId)
      .sort((a, b) => compareStrings(a.event ?? '', b.event ?? ''));
  }

  /** One athlete's results, oldest first. */
  appearancesOf(athleteId: string) {
    return this.appearances.filter((a) => a.athlete_id === athleteId);
  }

  /** False for alumni: athletes no longer on the current TFRRS roster. */
  isCurrent(athleteId: string) {
    return this.current.get(athleteId) ?? true;
  }

  get hasAlumni() {
    return [...this.current.values()].includes(false);
  }

  /** As TFRRS shows it, e.g. 'SR-4'; see classYearLabel. */
  classYearOf(athleteId: string) {
    return this.classYears.get(athleteId) ?? null;
  }

  nameOf = (athleteId: string) => this.names.get(athleteId) ?? 'Unknown';
  genderOf = (athleteId: string) => this.genders.get(athleteId) ?? 'M';

  private _seasons?: string[];
  /** Seasons the team has PRs in, indoor first. */
  get seasons() {
    return (this._seasons ??= seasonsIn(this.prs));
  }

  private _latestSeason?: string;
  /** The season to show first: that of the team's latest track result. */
  get latestSeason() {
    return (this._latestSeason ??= latestSeasonOf(this.appearances));
  }

  private _prEvents?: PrEvent[];
  /** Every PR the team has set, newest first. */
  get prEvents() {
    return (this._prEvents ??= detectPrs(this.appearances, {
      records: this.records,
      genderByAthlete: Object.fromEntries(this.genders),
    }));
  }

  private _windows?: TrendWindow[];
  get windows() {
    return (this._windows ??= trendWindows(this.prEvents, new Date()));
  }

  /** The season that points are reported for by default. */
  get currentSeason() {
    return defaultTrendWindow(this.windows);
  }

  pointsFor(athleteId: string, window: TrendWindow) {
    return this.prEvents
      .filter((p) => p.athleteId === athleteId && window.contains(p.date))
      .reduce((sum, p) => sum + p.points, 0);
  }

  private rivalCache = new Map<string, Map<string, Rival>>();
  /** Rivals come from the current roster only; alumni aren't chasing anyone. */
  rivalsOf(athleteId: string) {
    let rivals = this.rivalCache.get(athleteId);
    if (!rivals) {
      rivals = rivalsFor(
        athleteId,
        this.genders.get(athleteId),
        this.prs.filter((p) => p.athlete_id === athleteId || this.isCurrent(p.athlete_id)),
      );
      this.rivalCache.set(athleteId, rivals);
    }
    return rivals;
  }
}

/** Where team data comes from: Supabase in the app, a fake in tests. */
export interface TeamSource {
  prs(seasons: boolean): Promise<Row[]>;
  appearances(seasons: boolean): Promise<Row[]>;
  records(): Promise<Row[]>;
}

const prColumns =
  'event, best_display, best_mark_meters, best_time_seconds, improvement_delta_pct, set_on, set_at_meet, athlete_id';
const appearanceColumns = 'athlete_id, event, time_seconds, mark_meters, display_value, meet_name, meet_date';

/**
 * PostgREST caps each response (1000 rows by default), so page through until
 * a request comes back empty.
 */
async function fetchAll(page: (from: number, to: number) => PromiseLike<{ data: Row[] | null }>) {
  const pageSize = 1000;
  const rows: Row[] = [];
  for (;;) {
    const { data } = await page(rows.length, rows.length + pageSize - 1);
    if (!data || data.length === 0) return rows;
    rows.push(...data);
  }
}

export function supabaseTeamSource(): TeamSource {
  // Required lazily so tests can run without a Supabase client.
  const { supabase } = require('./supabase') as typeof import('./supabase');
  return {
    // Ordered by the table's unique key so pages never overlap or skip.
    // Without seasons (before the indoor_outdoor migration) rows have no
    // season and seasonOf() guesses it.
    prs: (seasons) =>
      fetchAll((from, to) => {
        let q = supabase
          .from('track_prs')
          .select(`${seasons ? 'season, ' : ''}${prColumns}, profiles(full_name, gender, on_roster, class_year)`)
          .order('athlete_id')
          .order('event');
        if (seasons) q = q.order('season');
        return q.range(from, to).throwOnError() as any;
      }),
    appearances: (seasons) =>
      fetchAll((from, to) =>
        supabase
          .from('meet_appearances')
          .select(`${seasons ? 'season, ' : ''}${appearanceColumns}`)
          .order('meet_date')
          .order('athlete_id')
          .order('event')
          .order('meet_name')
          .order('display_value')
          .range(from, to)
          .throwOnError() as any,
      ),
    records: async () => (await supabase.from('school_records').select().throwOnError()).data ?? [],
  };
}

/**
 * Caches the latest [TeamSnapshot] for the signed-in user, in memory and on
 * the phone. At launch [restore] returns last time's copy right away, while
 * [load] fetches the latest.
 */
export class TeamData {
  static readonly instance = new TeamData();

  private snapshot: TeamSnapshot | null = null;
  private inFlight: Promise<TeamSnapshot> | null = null;

  /** Whether [snapshot] came from the server this session, rather than from the copy saved on the phone. */
  private fresh = false;

  /** Where the copy is saved. Replaceable for tests. */
  store: TeamCacheStore = new DeviceTeamCacheStore();

  /** Where data comes from. Replaceable so tests can run without Supabase. */
  source: () => TeamSource = supabaseTeamSource;

  /** The signed-in user's id. Replaceable so tests can run without Supabase. */
  currentUserId: () => string | null = () => {
    const { currentUserId } = require('./session') as typeof import('./session');
    return currentUserId();
  };

  /** Forgets this session's data but not the saved copy, like the app being closed and opened again. For tests. */
  newSession() {
    this.snapshot = null;
    this.fresh = false;
    this.inFlight = null;
  }

  /** Replaces the cache, for tests. */
  seed(snapshot: TeamSnapshot) {
    this.snapshot = snapshot;
    this.fresh = true;
  }

  /** The cached snapshot, unless it belongs to a different (signed-out) user. */
  get cached(): TeamSnapshot | null {
    const s = this.snapshot;
    return s && s.userId === this.currentUserId() ? s : null;
  }

  /**
   * The copy saved on the phone last time, or the one in memory, so a screen
   * can show data at once while [load] gets the latest. Null when there's
   * none.
   */
  async restore(): Promise<TeamSnapshot | null> {
    const c = this.cached;
    if (c) return c;
    const uid = this.currentUserId();
    if (!uid) return null;
    try {
      const data = await this.store.read(uid);
      const snap = data ? TeamSnapshot.fromCache(data, uid) : null;
      // Unless the latest arrived meanwhile, or someone else signed in.
      if (snap && !this.cached && this.currentUserId() === uid) {
        this.snapshot = snap;
        this.fresh = false;
      }
    } catch {
      // A missing or unreadable copy just means downloading as before.
    }
    return this.cached;
  }

  /**
   * Returns this session's snapshot from the server, or fetches it.
   * Concurrent callers share a single request. [force] always refetches.
   */
  load({ force = false } = {}): Promise<TeamSnapshot> {
    const c = this.cached;
    if (!force && c && this.fresh) return Promise.resolve(c);
    return (this.inFlight ??= this.fetch().finally(() => {
      this.inFlight = null;
    }));
  }

  /** Forgets the team's data, in memory and on the phone: on sign-out. */
  async clear() {
    this.snapshot = null;
    this.fresh = false;
    try {
      await this.store.clear();
    } catch {}
  }

  private async fetch(): Promise<TeamSnapshot> {
    const userId = this.currentUserId();
    const source = this.source();
    const orWithoutSeasons = (get: (seasons: boolean) => Promise<Row[]>) =>
      get(true).catch((e) => {
        if (e instanceof PostgrestError) return get(false);
        throw e;
      });
    const [prs, appearances, records] = await Promise.all([
      orWithoutSeasons(source.prs),
      orWithoutSeasons(source.appearances),
      source.records(),
    ]);
    const snapshot = new TeamSnapshot({ userId, prs, appearances, records });
    this.snapshot = snapshot;
    this.fresh = true;
    if (userId) this.store.write(userId, snapshot.toCache()).catch(() => {});
    return snapshot;
  }
}
