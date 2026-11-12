import { router } from 'expo-router';
import { ReactNode, useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, Pressable, ScrollView, Text, View, useWindowDimensions } from 'react-native';
import Animated, {
  SharedValue,
  interpolate,
  interpolateColor,
  useAnimatedScrollHandler,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Bob, FadeSlideIn, PressScale, SkeletonPulse, kSpring } from '@/components/motion';
import { SegmentToggle } from '@/components/SegmentToggle';
import { ChartPoint, TrendChart } from '@/components/TrendChart';
import {
  AppChip,
  BackCircle,
  EmptyState,
  GlassCard,
  GradientAvatar,
  Icon,
  IconName,
  InitialsAvatar,
  SkeletonBox,
  WashHeader,
  sectionTitleStyle,
  SectionTitle,
} from '@/components/ui';
import { formatName } from '@/lib/format';
import { haptic } from '@/lib/haptics';
import { Insight, InsightKind, RecordRef, athleteInsights } from '@/lib/insights';
import { Prefs, usePrefs } from '@/lib/prefs';
import {
  ListRank,
  Rival,
  Row,
  academicYearOf,
  classYearLabel,
  eventKey,
  isFieldEvent,
  kSeasons,
  latestRanksByEvent,
  latestSeasonOf,
  parseMeetDate,
  seasonLabel,
  seasonOf,
  seasonsIn,
} from '@/lib/prStats';
import { supabase } from '@/lib/supabase';
import { TeamData, TeamSnapshot } from '@/lib/teamData';
import { C, alpha, cardStyle, useDark, washTop } from '@/theme/colors';

/** A leaderboard result to lead the profile sheet with, so the peek has something to show before the profile loads. */
export type ProfileFocus = {
  event: string;
  display?: string | null;
  meters?: number | null;
  improvementPct: number;
};

/** Connects a profile to the draggable sheet hosting it. */
export type ProfileSheet = {
  /** 0 at the peek height, 1 at full screen. */
  progress: SharedValue<number>;
  /** Animates the sheet up to full screen. */
  expand: () => void;
};

const barHeight = 48;

export function AthleteProfile({
  athleteId,
  athleteName,
  gender,
  showBackButton = true,
  focus,
  season: askedSeason,
  sheet,
  scrollY: sheetScrollY,
  renderScroll,
}: {
  athleteId: string;
  athleteName: string;
  gender: string;
  showBackButton?: boolean;
  focus?: ProfileFocus;
  /** The season to open on, e.g. the leaderboard's. Otherwise the season of the athlete's latest results. */
  season?: string;
  /** Set when shown inside the profile sheet instead of as a page. */
  sheet?: ProfileSheet;
  scrollY?: SharedValue<number>;
  renderScroll?: (content: ReactNode) => ReactNode;
}) {
  const dark = useDark();
  const prefs = usePrefs();
  const insets = useSafeAreaInsets();
  const name = formatName(athleteName);
  const isFemale = gender === 'F';
  const page = sheet ? C.sheet(dark) : C.bg(dark);

  const [prs, setPrs] = useState<Row[]>([]);
  const [appearances, setAppearances] = useState<Row[]>([]);
  const [records, setRecords] = useState<Row[]>([]);
  const [maxes, setMaxes] = useState<Row[]>([]);
  const [rankRows, setRankRows] = useState<Row[]>([]);
  const [team, setTeam] = useState<TeamSnapshot | null>(TeamData.instance.cached);
  const [pickedSeason, setPickedSeason] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedEvent, setSelectedEvent] = useState<string | null>(null);
  const loadingRef = useRef(true);
  loadingRef.current = loading;
  const mounted = useRef(true);
  useEffect(
    () => () => {
      mounted.current = false;
    },
    [],
  );

  const ownScrollY = useSharedValue(0);
  const scrollY = sheetScrollY ?? ownScrollY;
  const onScroll = useAnimatedScrollHandler((e) => {
    ownScrollY.value = e.contentOffset.y;
  });

  /** Seasons this athlete has PRs in, indoor first. */
  const seasons = useMemo(() => seasonsIn(prs), [prs]);

  /** The season shown: the one picked, else the one asked for, else that of their latest results, as long as they have PRs in it. */
  const seasonNow = useMemo(() => {
    for (const s of [pickedSeason, askedSeason, latestSeasonOf(appearances)]) {
      if (s && seasons.includes(s)) return s;
    }
    return seasons[0] ?? 'outdoor';
  }, [pickedSeason, askedSeason, appearances, seasons]);

  const seasonPrs = useMemo(() => prs.filter((p) => seasonOf(p) === seasonNow), [prs, seasonNow]);
  const seasonRanks = useMemo(() => latestRanksByEvent(rankRows.filter((r) => r.season === seasonNow)), [rankRows, seasonNow]);
  const ranks = useMemo(() => latestRanksByEvent(rankRows), [rankRows]);

  // The event charted: the one picked if this season has it, else the
  // leaderboard's, else the first.
  const charted = useMemo(() => {
    if (selectedEvent && seasonPrs.some((p) => p.event === selectedEvent)) return selectedEvent;
    if (focus && seasonPrs.some((p) => p.event === focus.event)) return focus.event;
    return seasonPrs[0]?.event ?? null;
  }, [selectedEvent, seasonPrs, focus]);

  /**
   * Shows the athlete from the team's data at once, before their own rows
   * arrive. Rankings and lifts aren't in it; they appear when the rest loads.
   */
  const showFrom = (t: TeamSnapshot) => {
    const p = t.prsOf(athleteId);
    const a = t.appearancesOf(athleteId);
    if (p.length === 0 && a.length === 0) return;
    setPrs(p);
    setAppearances(a);
    setRecords(t.records.filter((r) => r.gender === gender));
    setLoading(false);
    loadingRef.current = false;
  };

  const load = async () => {
    // Team data (for rivals and points) is usually cached already; it never
    // holds up the rest of the profile.
    TeamData.instance
      .load()
      .then((t) => mounted.current && setTeam(t))
      .catch(() => {});

    // Ranks are optional: before the list_ranks migration is applied this
    // query fails, and the profile should still load. Before the cut columns
    // exist, fall back to ranks without the nationals projection.
    const rankColumns = 'event, scope, label, season, season_year, rank, list_size';
    const ranksOf = async (columns: string) =>
      (await supabase.from('list_ranks').select(columns).eq('athlete_id', athleteId).throwOnError()).data as unknown as Row[];
    const ranksFuture = ranksOf(`${rankColumns}, mark_display, cut_rank, cut_mark`)
      .catch(() => ranksOf(rankColumns))
      .catch(() => [] as Row[]);

    try {
      // Independent queries, so fetch them in parallel.
      const [p, a, r, m] = await Promise.all([
        supabase.from('track_prs').select().eq('athlete_id', athleteId).order('event').throwOnError(),
        supabase.from('meet_appearances').select().eq('athlete_id', athleteId).order('meet_date', { ascending: true }).throwOnError(),
        supabase.from('school_records').select().eq('gender', gender).throwOnError(),
        supabase.from('lifting_maxes').select('lift_type, weight_lbs').eq('athlete_id', athleteId).order('lift_type').throwOnError(),
      ]);
      const rr = await ranksFuture;
      if (!mounted.current) return;
      setPrs(p.data ?? []);
      setAppearances(a.data ?? []);
      setRecords(r.data ?? []);
      setMaxes(m.data ?? []);
      setRankRows(rr ?? []);
      setLoading(false);
      setError(null);
    } catch {
      if (!mounted.current) return;
      // Already showing the team's copy: keep it rather than an error.
      if (!loadingRef.current) return;
      setLoading(false);
      setError("Couldn't load this profile.");
    }
  };

  useEffect(() => {
    const cached = TeamData.instance.cached;
    if (cached) showFrom(cached);
    else {
      TeamData.instance.restore().then((t) => {
        if (!t || !mounted.current) return;
        setTeam((cur) => cur ?? t);
        if (loadingRef.current) showFrom(t);
      });
    }
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [athleteId]);

  const retry = () => {
    setLoading(true);
    setError(null);
    load();
  };

  const openAthlete = (id: string) => {
    if (!team) return;
    router.push({ pathname: '/athlete/[id]', params: { id, name: team.nameOf(id), gender: team.genderOf(id) } });
  };

  /** 'Senior' for someone on the current roster, "Alum '26" for someone who has left it, or null if unknown. */
  const standing = (() => {
    if (!team) return null;
    if (team.isCurrent(athleteId)) return classYearLabel(team.classYearOf(athleteId));
    const dates = appearances.map((a) => parseMeetDate(a.meet_date)).filter((d): d is Date => d != null);
    if (dates.length === 0) return 'Alum';
    const last = dates.reduce((a, b) => (a > b ? a : b));
    return `Alum '${String((academicYearOf(last) + 1) % 100).padStart(2, '0')}`;
  })();

  const bestImprovement = prs.reduce((m, p) => Math.max(m, Number(p.improvement_delta_pct ?? 0)), 0);

  /** The school record for the PR's event and season. Indoor and outdoor records are separate, and cross country has none. */
  const recordFor = (pr: Row) => records.find((r) => r.event === pr.event && (r.season ?? 'indoor') === seasonOf(pr)) ?? null;

  /** Closest teammates this season, nearest first. */
  const rivals: Rival[] = team
    ? [...team.rivalsOf(athleteId).values()].filter((r) => r.season === seasonNow).sort((a, b) => a.gapPct - b.gapPct)
    : [];

  const chartPoints = (event: string): ChartPoint[] =>
    appearances
      .filter((a) => a.event === event && a.meet_date != null && seasonOf(a) === seasonNow)
      .flatMap((a) => {
        const v = isFieldEvent(event) ? a.mark_meters : a.time_seconds;
        return v != null && v > 0
          ? [{ value: v, display: prefs.mark(event, a.display_value, a.mark_meters), meetName: a.meet_name ?? 'Unknown', date: a.meet_date ?? '' }]
          : [];
      });

  const insights = athleteInsights({
    appearances,
    ranks,
    rivals: team?.rivalsOf(athleteId),
    records: new Map(
      prs.flatMap((pr): [string, RecordRef][] => {
        const r = recordFor(pr);
        const value = r && (isFieldEvent(pr.event ?? '') ? r.record_mark_meters : r.record_mark_seconds);
        if (!r || value == null) return [];
        return [[eventKey(pr.event, seasonOf(pr)), { value: Number(value), display: r.record_display ?? '', holder: r.holder_name ?? '', year: r.year_set ?? null }]];
      }),
    ),
    nameOf: team?.nameOf,
    formatMark: (event, display, value) => prefs.mark(event, display, value),
    formatGap: (event, gap) => prefs.gap(event, gap),
    now: new Date(),
  });

  const setSeason = (label: string) => setPickedSeason(kSeasons.find((s) => seasonLabel(s) === label) ?? null);

  const content = (
    <View style={{ paddingTop: sheet ? barHeight : insets.top + 44, paddingBottom: 120 }}>
      <Hero
        dark={dark}
        name={name}
        rawName={athleteName}
        female={isFemale}
        details={[standing, isFemale ? 'Women' : 'Men'].filter(Boolean).join(' · ')}
        base={page}
        stats={
          loading ? (
            <StatsSkeleton dark={dark} />
          ) : error ? null : (
            <FadeSlideIn style={{ flexDirection: 'row' }}>
              <Stat dark={dark} value={`${prs.length}`} label="PRs" />
              <Stat dark={dark} value={bestImprovement > 0 ? `+${bestImprovement.toFixed(1)}%` : '—'} label="Best gain" />
              <Stat dark={dark} value={`${new Set(appearances.map((a) => a.meet_name)).size}`} label="Meets" />
              <Stat
                dark={dark}
                value={team ? `${team.pointsFor(athleteId, team.currentSeason)}` : '—'}
                label={team ? `${team.currentSeason.shortLabel} points` : 'Points'}
              />
            </FadeSlideIn>
          )
        }
      />
      <View style={{ paddingHorizontal: 20 }}>
        {sheet && (
          <>
            {focus && <FocusRow dark={dark} focus={focus} prefs={prefs} />}
            <SheetHint dark={dark} sheet={sheet} />
          </>
        )}

        {loading ? (
          <ProfileSkeleton dark={dark} />
        ) : error ? (
          <View style={{ paddingTop: 40 }}>
            <EmptyState icon="cloud-off" title={error} actionLabel="Try again" onAction={retry} dark={dark} />
          </View>
        ) : (
          <>
            {insights.length > 0 && <InsightsRail insights={insights} dark={dark} />}

            {/* Indoor and outdoor PRs are separate; one season at a time from here down to Rivals. */}
            {seasons.length > 1 && (
              <FadeSlideIn delay={100} style={{ marginBottom: 24 }}>
                <SegmentToggle
                  testID="profile-season"
                  options={seasons.map(seasonLabel)}
                  value={seasonLabel(seasonNow)}
                  dark={dark}
                  height={40}
                  fontSize={14}
                  fill
                  onChange={setSeason}
                />
              </FadeSlideIn>
            )}

            {seasonPrs.length > 0 && (
              <FadeSlideIn delay={120} style={{ marginBottom: 28 }}>
                <SectionTitle text="Progression" dark={dark} />
                <View style={{ height: 36, marginTop: 12, marginHorizontal: -20 }}>
                  <FlatList
                    horizontal
                    showsHorizontalScrollIndicator={false}
                    data={seasonPrs}
                    keyExtractor={(p) => p.event}
                    contentContainerStyle={{ paddingHorizontal: 20, gap: 8, alignItems: 'center' }}
                    renderItem={({ item }) => (
                      <AppChip label={item.event} selected={item.event === charted} dark={dark} small onPress={() => setSelectedEvent(item.event)} />
                    )}
                  />
                </View>
                {charted && (
                  <GlassCard dark={dark} style={{ padding: 20, marginTop: 16 }}>
                    <TrendChart key={`${seasonNow}|${charted}`} points={chartPoints(charted)} isField={isFieldEvent(charted)} dark={dark} />
                  </GlassCard>
                )}
              </FadeSlideIn>
            )}

            <FadeSlideIn delay={180} style={{ marginBottom: 28 }}>
              <FoldableSection
                title="Personal Records"
                subtitle={seasons.length > 1 ? undefined : `${seasonLabel(seasonNow)} bests`}
                dark={dark}
              >
                <GlassCard dark={dark} testID="personal-records">
                  {seasonPrs.map((pr, i) => (
                    <PrRow
                      key={pr.event}
                      pr={pr}
                      isLast={i === seasonPrs.length - 1}
                      dark={dark}
                      prefs={prefs}
                      record={recordFor(pr)}
                      ranks={seasonRanks.get(pr.event) ?? []}
                    />
                  ))}
                </GlassCard>
              </FoldableSection>
            </FadeSlideIn>

            {rivals.length > 0 && team && (
              <FadeSlideIn delay={195} style={{ marginBottom: 28 }}>
                <FoldableSection title="Rivals" subtitle="Closest teammate PR in each event" dark={dark}>
                  <GlassCard dark={dark}>
                    {rivals.map((r, i) => (
                      <RivalRow
                        key={eventKey(r.event, r.season)}
                        rival={r}
                        name={team.nameOf(r.athleteId)}
                        gender={team.genderOf(r.athleteId)}
                        isLast={i === rivals.length - 1}
                        dark={dark}
                        prefs={prefs}
                        onPress={() => openAthlete(r.athleteId)}
                      />
                    ))}
                  </GlassCard>
                </FoldableSection>
              </FadeSlideIn>
            )}

            {maxes.length > 0 && (
              <FadeSlideIn delay={210} style={{ marginBottom: 28 }}>
                <SectionTitle text="Lifting Maxes" dark={dark} />
                <GlassCard dark={dark} style={{ marginTop: 12 }}>
                  {maxes.map((m, i) => (
                    <View key={m.lift_type} style={[rowStyle(dark, i === maxes.length - 1), { flexDirection: 'row', alignItems: 'center' }]}>
                      <Text style={{ flex: 1, fontSize: 14, fontWeight: '600', color: C.text1(dark) }}>{m.lift_type}</Text>
                      <Text style={{ fontSize: 16, fontWeight: '700', color: C.accentOf(dark), letterSpacing: -0.5 }}>
                        {prefs.weight(m.weight_lbs ?? 0)}
                      </Text>
                    </View>
                  ))}
                </GlassCard>
              </FadeSlideIn>
            )}

            <FadeSlideIn delay={240}>
              <FoldableSection title="Meet History" dark={dark}>
                <MeetHistory appearances={appearances} dark={dark} prefs={prefs} />
              </FoldableSection>
            </FadeSlideIn>
          </>
        )}
      </View>
    </View>
  );

  return (
    <View style={{ flex: 1, backgroundColor: page }}>
      {renderScroll ? (
        renderScroll(content)
      ) : (
        <Animated.ScrollView onScroll={onScroll} scrollEventThrottle={16} showsVerticalScrollIndicator={false}>
          {content}
        </Animated.ScrollView>
      )}
      <TopBar
        dark={dark}
        name={name}
        page={page}
        scrollY={scrollY}
        sheet={!!sheet}
        topInset={sheet ? 0 : insets.top}
        onBack={showBackButton ? () => router.back() : undefined}
      />
    </View>
  );
}

/**
 * The bar over the profile: a grab handle in the sheet, a back button on a
 * page. Its color starts as the wash's top color and fades to the page color
 * as the hero scrolls away, so there's no seam; the name fades in once the
 * hero's name has scrolled away.
 */
function TopBar({
  dark,
  name,
  page,
  scrollY,
  sheet,
  topInset,
  onBack,
}: {
  dark: boolean;
  name: string;
  page: string;
  scrollY: SharedValue<number>;
  sheet: boolean;
  topInset: number;
  onBack?: () => void;
}) {
  const top = washTop(dark, page);
  const bar = useAnimatedStyle(() => ({
    backgroundColor: interpolateColor(Math.min(1, Math.max(0, scrollY.value / 120)), [0, 1], [top, page]),
  }));
  const title = useAnimatedStyle(() => ({ opacity: interpolate(scrollY.value, [90, 130], [0, 1], 'clamp') }));
  return (
    <Animated.View
      pointerEvents="box-none"
      style={[{ position: 'absolute', left: 0, right: 0, top: 0, paddingTop: topInset, height: topInset + (sheet ? barHeight : 44) }, bar]}
    >
      {sheet && (
        <View style={{ alignItems: 'center', paddingTop: 8 }}>
          <View style={{ width: 36, height: 5, borderRadius: 3, backgroundColor: alpha(C.text3(dark), 0.5) }} />
        </View>
      )}
      <View style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: sheet ? 36 : 44, alignItems: 'center', justifyContent: 'center' }} pointerEvents="box-none">
        <Animated.Text numberOfLines={1} style={[{ fontSize: 16, fontWeight: '600', color: C.text1(dark), maxWidth: '70%' }, title]}>
          {name}
        </Animated.Text>
        {onBack && (
          <View style={{ position: 'absolute', left: 12 }}>
            <BackCircle onPress={onBack} dark={dark} size={34} />
          </View>
        )}
      </View>
    </Animated.View>
  );
}

/** Avatar, name and details over a soft wash of the team color, then the stat strip. */
function Hero({
  dark,
  name,
  rawName,
  female,
  details,
  base,
  stats,
}: {
  dark: boolean;
  name: string;
  rawName: string;
  female: boolean;
  details: string;
  base: string;
  stats: ReactNode;
}) {
  return (
    <WashHeader dark={dark} base={base} style={{ paddingHorizontal: 20, paddingTop: 12, paddingBottom: 20 }}>
      <FadeSlideIn>
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <GradientAvatar name={rawName} female={female} dark={dark} size={64} />
          <View style={{ flex: 1, marginLeft: 14 }}>
            <Text numberOfLines={2} style={{ fontSize: 26, fontWeight: '800', letterSpacing: -0.8, lineHeight: 29, color: C.text1(dark) }}>
              {name}
            </Text>
            <Text style={{ marginTop: 4, fontSize: 13, fontWeight: '500', color: C.text2(dark) }}>{details}</Text>
          </View>
        </View>
        <View style={{ height: 18 }} />
        {stats}
      </FadeSlideIn>
    </WashHeader>
  );
}

function Stat({ dark, value, label }: { dark: boolean; value: string; label: string }) {
  return (
    <View style={{ flex: 1 }}>
      <Text style={{ fontSize: 20, fontWeight: '800', letterSpacing: -0.5, color: C.text1(dark) }}>{value}</Text>
      <Text style={{ marginTop: 2, fontSize: 11, fontWeight: '500', color: C.text3(dark) }}>{label}</Text>
    </View>
  );
}

function StatsSkeleton({ dark }: { dark: boolean }) {
  return (
    <SkeletonPulse>
      <View style={{ flexDirection: 'row' }}>
        {[0, 1, 2, 3].map((i) => (
          <View key={i} style={{ flex: 1, gap: 6 }}>
            <SkeletonBox dark={dark} width={36} height={20} />
            <SkeletonBox dark={dark} width={52} height={10} />
          </View>
        ))}
      </View>
    </SkeletonPulse>
  );
}

function ProfileSkeleton({ dark }: { dark: boolean }) {
  return (
    <SkeletonPulse>
      <SkeletonBox dark={dark} width={110} height={12} />
      <View style={{ height: 12 }} />
      <SkeletonBox dark={dark} height={280} radius={16} />
      <View style={{ height: 28 }} />
      <SkeletonBox dark={dark} width={150} height={12} />
      <View style={{ height: 12 }} />
      <SkeletonBox dark={dark} height={200} radius={16} />
    </SkeletonPulse>
  );
}

/** "Swipe up" affordance under the peek. Fades out as the sheet rises and opens the full profile when tapped. */
function SheetHint({ dark, sheet }: { dark: boolean; sheet: ProfileSheet }) {
  const style = useAnimatedStyle(() => ({ opacity: Math.max(0, Math.min(1, 1 - sheet.progress.value * 3)) }));
  return (
    <Animated.View style={style}>
      <Pressable onPress={sheet.expand} style={{ paddingVertical: 12, flexDirection: 'row', justifyContent: 'center', alignItems: 'center' }}>
        {/* Bobs gently to show the card can be dragged up. */}
        <Bob>
          <Icon name="keyboard-arrow-up" size={18} color={C.text3(dark)} />
        </Bob>
        <Text style={{ marginLeft: 4, fontSize: 12, fontWeight: '500', color: C.text3(dark) }}>Swipe up for full profile</Text>
      </Pressable>
    </Animated.View>
  );
}

function FocusRow({ dark, focus, prefs }: { dark: boolean; focus: ProfileFocus; prefs: Prefs }) {
  const improved = focus.improvementPct > 0;
  return (
    <View style={{ flexDirection: 'row', gap: 10 }}>
      <FocusStat dark={dark} label="Personal Best" value={prefs.mark(focus.event, focus.display, focus.meters)} accent />
      <FocusStat dark={dark} label="Event" value={focus.event} />
      <FocusStat dark={dark} label="Improvement" value={improved ? `+${focus.improvementPct.toFixed(2)}%` : '—'} accent={improved} />
    </View>
  );
}

function FocusStat({ dark, label, value, accent = false }: { dark: boolean; label: string; value: string; accent?: boolean }) {
  return (
    <GlassCard dark={dark} style={{ flex: 1, paddingHorizontal: 12, paddingVertical: 16, alignItems: 'center' }}>
      <Text style={{ fontSize: 10, fontWeight: '500', letterSpacing: 0.5, color: C.text3(dark), textAlign: 'center' }}>{label.toUpperCase()}</Text>
      {/* Long event names and imperial marks shrink rather than wrap. */}
      <Text
        numberOfLines={1}
        adjustsFontSizeToFit
        minimumFontScale={0.5}
        style={{ marginTop: 8, fontSize: 18, fontWeight: '700', letterSpacing: -0.5, color: accent ? C.accentOf(dark) : C.text1(dark) }}
      >
        {value}
      </Text>
    </GlassCard>
  );
}

const insightIcons: Record<InsightKind, IconName> = {
  schoolRecord: 'military-tech',
  freshPr: 'emoji-events',
  trend: 'trending-up',
  nationals: 'flag',
  seasonPace: 'speed',
  rival: 'compare-arrows',
  drought: 'hourglass-bottom',
};

/** The strongest insights as a swipeable row of cards, edge to edge. */
function InsightsRail({ insights, dark }: { insights: Insight[]; dark: boolean }) {
  return (
    <FadeSlideIn delay={60} style={{ marginBottom: 28 }}>
      <SectionTitle text="Insights" dark={dark} />
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        style={{ marginTop: 12, marginHorizontal: -20 }}
        contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 8, gap: 10 }}
      >
        {insights.map((insight) => (
          <View key={`${insight.kind}${insight.event}${insight.season}`} style={[cardStyle(dark), { width: 236, minHeight: 128, padding: 16 }]}>
            <View
              style={{ width: 32, height: 32, borderRadius: 16, backgroundColor: C.accentSoft(dark), alignItems: 'center', justifyContent: 'center' }}
            >
              <Icon name={insightIcons[insight.kind]} size={17} color={C.accentOf(dark)} />
            </View>
            <View style={{ flex: 1, minHeight: 12 }} />
            <Text numberOfLines={1} style={{ fontSize: 15, fontWeight: '700', letterSpacing: -0.2, color: C.text1(dark) }}>
              {insight.title}
            </Text>
            <Text numberOfLines={2} style={{ marginTop: 3, fontSize: 12.5, lineHeight: 16, color: C.text2(dark) }}>
              {insight.detail}
            </Text>
          </View>
        ))}
      </ScrollView>
    </FadeSlideIn>
  );
}

/** A profile section whose header folds its content away. Starts open. */
function FoldableSection({ title, subtitle, dark, children }: { title: string; subtitle?: string; dark: boolean; children: ReactNode }) {
  const [open, setOpen] = useState(true);
  const [height, setHeight] = useState(0);
  const reveal = useSharedValue(1);
  const toggle = () => {
    haptic.selection();
    setOpen(!open);
    reveal.value = withTiming(open ? 0 : 1, { duration: 280, easing: kSpring });
  };
  const body = useAnimatedStyle(() => ({
    height: height === 0 ? undefined : height * reveal.value,
    opacity: reveal.value,
    overflow: 'hidden',
  }));
  const chevron = useAnimatedStyle(() => ({ transform: [{ rotate: `${(reveal.value - 1) * 90}deg` }] }));
  return (
    <View>
      <Pressable onPress={toggle} accessibilityRole="button" accessibilityState={{ expanded: open }}>
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <Text style={[sectionTitleStyle(dark), { flex: 1 }]}>{title}</Text>
          <Animated.View style={chevron}>
            <Icon name="keyboard-arrow-down" size={20} color={C.text3(dark)} />
          </Animated.View>
        </View>
        {subtitle ? <Text style={{ marginTop: 4, fontSize: 12, color: C.text3(dark) }}>{subtitle}</Text> : null}
      </Pressable>
      <Animated.View style={body}>
        <View onLayout={(e) => setHeight(e.nativeEvent.layout.height)} style={{ paddingTop: 12, position: height === 0 ? 'relative' : 'absolute', left: 0, right: 0 }}>
          {children}
        </View>
      </Animated.View>
    </View>
  );
}

const rowStyle = (dark: boolean, isLast: boolean) => ({
  paddingHorizontal: 18,
  paddingVertical: 14,
  borderBottomWidth: isLast ? 0 : 0.5,
  borderBottomColor: C.border(dark),
});

function PrRow({
  pr,
  isLast,
  dark,
  prefs,
  record,
  ranks,
}: {
  pr: Row;
  isLast: boolean;
  dark: boolean;
  prefs: Prefs;
  record: Row | null;
  /** National then conference rank from the latest ranked season. */
  ranks: ListRank[];
}) {
  const delta = Number(pr.improvement_delta_pct ?? 0);
  const gapText = record ? recordGapText(pr, record, prefs) : null;
  const pct = record ? recordPercentage(pr, record) : null;
  const isNewRecord = gapText?.includes('NEW SCHOOL RECORD') ?? false;
  return (
    <View style={rowStyle(dark, isLast)}>
      <View style={{ flexDirection: 'row', alignItems: 'center' }}>
        <View style={{ flex: 1 }}>
          <Text style={{ fontSize: 14, fontWeight: '600', color: C.text1(dark) }}>{pr.event ?? ''}</Text>
          <Text style={{ fontSize: 11, color: C.text3(dark) }}>{pr.set_at_meet ?? 'Season best'}</Text>
        </View>
        <View style={{ alignItems: 'flex-end' }}>
          <Text style={{ fontSize: 16, fontWeight: '700', color: C.accentOf(dark), letterSpacing: -0.5 }}>
            {prefs.mark(pr.event ?? '', pr.best_display, pr.best_mark_meters)}
          </Text>
          {delta > 0 && <Text style={{ fontSize: 11, color: C.text3(dark) }}>+{delta.toFixed(1)}%</Text>}
        </View>
      </View>
      {ranks.length > 0 && (
        // Wraps on narrow phones once the nationals margin is in the pill.
        <View style={{ marginTop: 8, flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 6 }}>
          {ranks.map((r) => (
            <RankPill key={r.scope} rank={r} dark={dark} prefs={prefs} />
          ))}
          <Text style={{ fontSize: 10, color: C.text3(dark) }}>{ranks[0].seasonLabel.toLowerCase()}</Text>
        </View>
      )}
      {gapText ? (
        <View style={{ marginTop: 8 }}>
          {pct != null && !isNewRecord && (
            <View style={{ height: 3, borderRadius: 2, backgroundColor: C.surface3(dark), overflow: 'hidden' }}>
              <View style={{ width: `${pct * 100}%`, height: 3, backgroundColor: pct > 0.95 ? C.accentOf(dark) : C.text3(dark) }} />
            </View>
          )}
          <Text
            style={{
              marginTop: 4,
              fontSize: 10,
              color: isNewRecord ? C.accentOf(dark) : C.text3(dark),
              fontWeight: isNewRecord ? '700' : '400',
              textAlign: isNewRecord ? 'center' : 'left',
            }}
          >
            {gapText}
          </Text>
        </View>
      ) : null}
    </View>
  );
}

function recordGapText(pr: Row, record: Row, prefs: Prefs) {
  const event = pr.event ?? '';
  const year = `'${(record.year_set ?? 0) % 100}`;
  if (isFieldEvent(event)) {
    const prMark = Number(pr.best_mark_meters ?? 0);
    const recMark = Number(record.record_mark_meters ?? 0);
    if (prMark <= 0 || recMark <= 0) return '';
    const gap = recMark - prMark;
    if (gap <= 0) return '🏆 NEW SCHOOL RECORD';
    return `${prefs.gap(event, gap)} from record (${prefs.mark(event, record.record_display, recMark)}, ${record.holder_name} ${year})`;
  }
  const prTime = Number(pr.best_time_seconds ?? 0);
  const recTime = Number(record.record_mark_seconds ?? 9999);
  if (prTime <= 0 || recTime >= 9999) return '';
  const gap = prTime - recTime;
  if (gap <= 0) return '🏆 NEW SCHOOL RECORD';
  if (gap >= 60) {
    const m = Math.floor(gap / 60);
    const s = (gap % 60).toFixed(2).padStart(5, '0');
    return `${m}:${s} off record (${record.record_display}, ${record.holder_name} ${year})`;
  }
  return `${gap.toFixed(2)}s off record (${record.record_display}, ${record.holder_name} ${year})`;
}

function recordPercentage(pr: Row, record: Row) {
  const clamp = (v: number) => Math.max(0, Math.min(1, v));
  if (isFieldEvent(pr.event ?? '')) {
    const prMark = Number(pr.best_mark_meters ?? 0);
    const recMark = Number(record.record_mark_meters ?? 1);
    return recMark <= 0 ? 0 : clamp(prMark / recMark);
  }
  const prTime = Number(pr.best_time_seconds ?? 9999);
  const recTime = Number(record.record_mark_seconds ?? 1);
  return recTime <= 0 ? 0 : clamp(recTime / prTime);
}

/** '#19 D3 · in by 0.08m': the rank, plus where it sits against the projected nationals field on national lists. */
function RankPill({ rank: r, dark, prefs }: { rank: ListRank; dark: boolean; prefs: Prefs }) {
  const nationals = r.nationals;
  const top = nationals?.inside ?? r.rank <= 10;
  const gap = nationals?.gap ?? null;
  const gapText = gap == null ? null : prefs.gap(r.event, gap);
  let status: string | null = null;
  if (nationals) {
    if (nationals.inside) status = gap != null && gap > 0 ? `in by ${gapText}` : 'in';
    else if (gap === 0) status = 'tied at the cut';
    else if (gapText != null) status = `${gapText} out`;
  }
  return (
    <View style={{ paddingHorizontal: 8, paddingVertical: 2, borderRadius: 100, backgroundColor: top ? C.accentSoft(dark) : C.surface2(dark) }}>
      <Text style={{ fontSize: 11, fontWeight: '700', color: top ? C.accentOf(dark) : C.text2(dark) }}>
        {status == null ? `#${r.rank} ${r.label}` : `#${r.rank} ${r.label} · ${status}`}
      </Text>
    </View>
  );
}

function RivalRow({
  rival,
  name,
  gender,
  isLast,
  dark,
  prefs,
  onPress,
}: {
  rival: Rival;
  name: string;
  gender: string;
  isLast: boolean;
  dark: boolean;
  prefs: Prefs;
  onPress: () => void;
}) {
  return (
    <PressScale pressedScale={0.98} onPress={onPress}>
      <View style={[rowStyle(dark, isLast), { flexDirection: 'row', alignItems: 'center' }]}>
        <InitialsAvatar name={name} gender={gender} dark={dark} />
        <View style={{ flex: 1, marginLeft: 12 }}>
          <Text numberOfLines={1} style={{ fontSize: 14, fontWeight: '600', color: C.text1(dark) }}>
            {formatName(name)}
          </Text>
          <Text style={{ fontSize: 11, color: C.text3(dark) }}>
            {rival.event} · {prefs.mark(rival.event, rival.theirDisplay, rival.theirValue)}
          </Text>
        </View>
        <View style={{ alignItems: 'flex-end' }}>
          <Text style={{ fontSize: 15, fontWeight: '700', letterSpacing: -0.4, color: rival.isAhead ? C.accentOf(dark) : C.text1(dark) }}>
            {prefs.gap(rival.event, rival.gap)}
          </Text>
          <Text style={{ fontSize: 10, color: C.text3(dark) }}>{rival.isAhead ? 'to catch' : 'ahead'}</Text>
        </View>
      </View>
    </PressScale>
  );
}

const meetMonths = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

function MeetHistory({ appearances, dark, prefs }: { appearances: Row[]; dark: boolean; prefs: Prefs }) {
  const byMeet = new Map<string, Row[]>();
  const meetDates = new Map<string, string>();
  for (const a of appearances) {
    const meet = a.meet_name ?? 'Unknown Meet';
    byMeet.set(meet, [...(byMeet.get(meet) ?? []), a]);
    meetDates.set(meet, a.meet_date ?? '');
  }
  const sorted = [...byMeet.keys()].sort((a, b) => (meetDates.get(b)! < meetDates.get(a)! ? -1 : meetDates.get(b)! > meetDates.get(a)! ? 1 : 0));
  if (sorted.length === 0) {
    return (
      <View style={{ paddingVertical: 24 }}>
        <EmptyState icon="event" title="No meets yet" dark={dark} />
      </View>
    );
  }
  const meets = sorted.slice(0, 10);
  return (
    <GlassCard dark={dark}>
      {meets.map((meet, i) => {
        const rows = byMeet.get(meet)!;
        const d = parseMeetDate(meetDates.get(meet));
        return (
          <View key={meet} style={[rowStyle(dark, i === meets.length - 1), { paddingHorizontal: 16, flexDirection: 'row', alignItems: 'flex-start' }]}>
            <View style={{ width: 44, alignItems: 'center' }}>
              {d && (
                <>
                  <Text style={{ fontSize: 11, fontWeight: '700', letterSpacing: 0.4, color: C.accentOf(dark) }}>{meetMonths[d.getMonth()]}</Text>
                  <Text style={{ fontSize: 22, fontWeight: '800', letterSpacing: -0.6, lineHeight: 25, color: C.text1(dark) }}>{d.getDate()}</Text>
                  <Text style={{ fontSize: 11, fontWeight: '500', color: C.text3(dark) }}>'{String(d.getFullYear() % 100).padStart(2, '0')}</Text>
                </>
              )}
            </View>
            <View style={{ flex: 1, marginLeft: 12 }}>
              <Text style={{ fontSize: 10.5, fontWeight: '700', letterSpacing: 0.6, color: C.text3(dark) }}>
                {seasonLabel(seasonOf(rows[0])).toUpperCase()}
              </Text>
              <Text numberOfLines={2} style={{ marginTop: 2, fontSize: 14, fontWeight: '600', lineHeight: 18, color: C.text1(dark) }}>
                {meet}
              </Text>
              <View style={{ marginTop: 6, flexDirection: 'row', flexWrap: 'wrap', columnGap: 14, rowGap: 4 }}>
                {rows.map((r, j) => (
                  <Text key={j}>
                    <Text style={{ fontSize: 12, color: C.text3(dark) }}>{r.event ?? ''}  </Text>
                    <Text style={{ fontSize: 13, fontWeight: '700', color: C.text1(dark) }}>
                      {prefs.mark(r.event ?? '', r.display_value, r.mark_meters)}
                    </Text>
                  </Text>
                ))}
              </View>
            </View>
          </View>
        );
      })}
    </GlassCard>
  );
}
