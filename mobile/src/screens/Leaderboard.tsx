import { router } from 'expo-router';
import { LinearGradient } from 'expo-linear-gradient';
import { useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, PixelRatio, Pressable, RefreshControl, ScrollView, Text, TextInput, View } from 'react-native';
import Animated, { FadeIn, FadeOut, LinearTransition, useAnimatedStyle, withTiming } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Svg, { Polyline } from 'react-native-svg';

import { FilterPill } from '@/components/FilterPill';
import { FadeSlideIn, PressScale, SkeletonPulse } from '@/components/motion';
import { OneTimeTip } from '@/components/OneTimeTip';
import { toast } from '@/components/overlay';
import { SegmentToggle } from '@/components/SegmentToggle';
import {
  AppChip,
  AppIcon,
  ChipRow,
  EmptyState,
  Icon,
  IconName,
  InitialsAvatar,
  SectionTitle,
  SkeletonBox,
  WashHeader,
  pageTitleStyle,
} from '@/components/ui';
import { ActivityFeed } from '@/lib/activityFeed';
import { formatName, formatShortMeetDate } from '@/lib/format';
import { haptic } from '@/lib/haptics';
import { Prefs, usePrefs } from '@/lib/prefs';
import { AthleteTrend, Row, TrendWindow, eventKey, isFieldEvent, kSeasons, seasonLabel, seasonOf, trendingAthletes } from '@/lib/prStats';
import { useObservable } from '@/lib/store';
import { TeamData, TeamSnapshot } from '@/lib/teamData';
import { C, alpha, cardStyle, useDark } from '@/theme/colors';

import { showAthleteSheet } from './athleteSheet';

// ─── Event categories with subcategories ─────────────────────────────────────

const eventGroups: Record<string, string[] | null> = {
  All: null,
  Sprints: ['55 Meters', '60 Meters', '100 Meters', '200 Meters', '300 Meters', '400 Meters'],
  Mid: ['500 Meters', '600 Meters', '800 Meters', '1000 Meters', '1500 Meters', 'Mile', '3000 Meters', '5000 Meters', '10,000 Meters', '3000 Steeplechase'],
  Hurdles: ['55 Hurdles', '60 Hurdles', '110 Hurdles', '100 Hurdles', '400 Hurdles'],
  Jumps: ['High Jump', 'Long Jump', 'Triple Jump', 'Pole Vault'],
  Throws: ['Shot Put', 'Discus', 'Hammer', 'Javelin', 'Weight Throw'],
};

type Tab = 'heat' | 'rankings' | 'trending';
const tabLabels: Record<Tab, string> = { heat: 'Heat Map', rankings: 'PR Rankings', trending: 'Trending' };

const delta = (e: Row) => Number(e.improvement_delta_pct ?? 0);

export function Leaderboard() {
  const dark = useDark();
  const prefs = usePrefs();
  const insets = useSafeAreaInsets();
  const [snap, setSnap] = useState<TeamSnapshot | null>(() => TeamData.instance.cached);
  const [loading, setLoading] = useState(() => TeamData.instance.cached == null);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [initialLoad, setInitialLoad] = useState(true);

  const [group, setGroup] = useState('All');
  const [subEvent, setSubEvent] = useState<string | null>(null); // specific event within a group
  const [tab, setTab] = useState<Tab>('heat');
  const [search, setSearch] = useState('');
  const [gender, setGender] = useState('All');
  const [pickedSeason, setPickedSeason] = useState<string | null>(null); // null = the season of the team's latest results
  const [pickedWindow, setPickedWindow] = useState<TrendWindow | null>(null); // null = the snapshot's current season
  const [trendByPoints, setTrendByPoints] = useState(false);
  /** PR Rankings: include alumni (everyone who's competed for the team). */
  const [allTime, setAllTime] = useState(false);
  const snapRef = useRef(snap);
  snapRef.current = snap;

  const apply = (s: TeamSnapshot) => {
    setSnap(s);
    setLoading(false);
    setError(null);
  };

  const load = async (force = false) => {
    try {
      const s = await TeamData.instance.load({ force });
      apply(s);
      ActivityFeed.instance.refresh(s);
      setTimeout(() => setInitialLoad(false), 100);
    } catch {
      // Offline at launch: last time's copy, if the phone has one.
      const saved = snapRef.current ?? (await TeamData.instance.restore());
      if (saved) {
        if (!snapRef.current) {
          apply(saved);
          ActivityFeed.instance.refresh(saved);
        }
        // Keep showing what we have; just say the refresh failed.
        toast("Couldn't refresh. Check your connection.");
      } else {
        setLoading(false);
        setError("Couldn't load the leaderboard. Pull down to try again.");
      }
    }
  };

  useEffect(() => {
    if (!TeamData.instance.cached) {
      // Last time's copy from the phone, while the latest downloads.
      TeamData.instance.restore().then((s) => {
        if (!s || snapRef.current) return;
        apply(s);
        ActivityFeed.instance.refresh(s);
      });
    }
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const refresh = async () => {
    haptic.light();
    setRefreshing(true);
    await load(true);
    setRefreshing(false);
  };

  const seasonNow = pickedSeason && snap?.seasons.includes(pickedSeason) ? pickedSeason : (snap?.latestSeason ?? 'outdoor');
  const trendWindow = pickedWindow && snap?.windows.some((w) => w.id === pickedWindow.id) ? pickedWindow : (snap?.currentSeason ?? TrendWindow.allTime);

  /** The season's PRs; indoor and outdoor are never ranked together. */
  const seasonEntries = useMemo(() => (snap?.prs ?? []).filter((e) => seasonOf(e) === seasonNow), [snap, seasonNow]);

  /** Events with PRs this season, so indoor hides the 100m and outdoor hides the 60m. */
  const seasonEvents = useMemo(() => new Set(seasonEntries.map((e) => e.event ?? '')), [seasonEntries]);
  const groupHasEvents = (g: string, events: Set<string>) => g === 'All' || (eventGroups[g] ?? []).some((e) => events.has(e));

  // Sparklines per athlete, event and season. Appearances arrive oldest first.
  const sparklines = useMemo(() => {
    const out = new Map<string, number[]>();
    for (const a of snap?.appearances ?? []) {
      const val = a.time_seconds ?? a.mark_meters;
      if (val != null && val > 0) {
        const key = `${a.athlete_id}_${eventKey(a.event ?? '', seasonOf(a))}`;
        const list = out.get(key);
        if (list) list.push(val);
        else out.set(key, [val]);
      }
    }
    return out;
  }, [snap]);

  const setSeason = (label: string) => {
    const season = kSeasons.find((s) => seasonLabel(s) === label)!;
    setPickedSeason(season);
    const events = new Set((snap?.prs ?? []).filter((e) => seasonOf(e) === season).map((e) => e.event ?? ''));
    if (subEvent && !events.has(subEvent)) setSubEvent(null);
    if (!groupHasEvents(group, events)) {
      setGroup('All');
      setSubEvent(null);
    }
  };

  const filtered = useMemo(() => {
    let list: Row[];
    if (subEvent) {
      list = seasonEntries.filter((e) => e.event === subEvent);
    } else if (group === 'All') {
      // Each athlete's biggest improvement.
      const best = new Map<string, Row>();
      for (const e of seasonEntries) {
        const cur = best.get(e.athlete_id);
        if (!cur || delta(e) > delta(cur)) best.set(e.athlete_id, e);
      }
      list = [...best.values()];
    } else {
      list = seasonEntries.filter((e) => (eventGroups[group] ?? []).includes(e.event));
    }
    if (gender !== 'All') list = list.filter((e) => (e.profiles?.gender ?? 'M') === gender);
    // Alumni only show on PR Rankings' all-time view; Heat Map is about now.
    if (snap && !(tab === 'rankings' && allTime)) list = list.filter((e) => snap.isCurrent(e.athlete_id));
    if (search) {
      const q = search.toLowerCase();
      list = list.filter(
        (e) => String(e.profiles?.full_name ?? '').toLowerCase().includes(q) || String(e.event ?? '').toLowerCase().includes(q),
      );
    }
    if (tab === 'heat') {
      list.sort((a, b) => delta(b) - delta(a));
    } else {
      list.sort((a, b) => {
        const af = isFieldEvent(a.event ?? '');
        const bf = isFieldEvent(b.event ?? '');
        if (af && bf) return Number(b.best_mark_meters ?? 0) - Number(a.best_mark_meters ?? 0);
        if (!af && !bf) return Number(a.best_time_seconds ?? 9999) - Number(b.best_time_seconds ?? 9999);
        return 0;
      });
    }
    return list;
  }, [seasonEntries, subEvent, group, gender, snap, tab, allTime, search]);

  const openDetail = (entry: Row) =>
    showAthleteSheet({
      athleteId: entry.athlete_id ?? '',
      athleteName: entry.profiles?.full_name ?? 'Unknown',
      gender: entry.profiles?.gender ?? 'M',
      season: seasonOf(entry),
      focus: { event: entry.event ?? '', display: entry.best_display, meters: entry.best_mark_meters, improvementPct: delta(entry) },
    });

  const openAthlete = (id: string) =>
    snap && showAthleteSheet({ athleteId: id, athleteName: snap.nameOf(id), gender: snap.genderOf(id), season: seasonNow });

  const showSubChips = group !== 'All' && eventGroups[group] != null;
  const showTrendControls = tab === 'trending' && snap != null;
  const showRosterControls = tab === 'rankings' && (snap?.hasAlumni ?? false);
  const listKey = `${tab}|${seasonNow}|${group}|${subEvent}|${gender}|${trendWindow.id}|${trendByPoints}|${allTime}`;

  const refreshControl = <RefreshControl refreshing={refreshing} onRefresh={refresh} tintColor={C.accentOf(dark)} />;

  let body;
  if (loading) {
    body = <SkeletonRows dark={dark} />;
  } else if (!snap) {
    body = <Message dark={dark} icon="cloud-off" text={error ?? "Couldn't load the leaderboard."} refreshControl={refreshControl} />;
  } else if (tab === 'trending') {
    body = (
      <Trending
        snap={snap}
        dark={dark}
        season={seasonNow}
        window={trendWindow}
        events={subEvent ? new Set([subEvent]) : eventGroups[group] ? new Set(eventGroups[group]) : null}
        gender={gender}
        search={search}
        byPoints={trendByPoints}
        onOpen={openAthlete}
        refreshControl={refreshControl}
      />
    );
  } else {
    body = (
      <Ranked
        list={filtered}
        tab={tab}
        dark={dark}
        prefs={prefs}
        podiumAllowed={tab === 'heat' && group === 'All' && !subEvent && !search}
        initialLoad={initialLoad}
        sparklines={sparklines}
        onOpen={openDetail}
        refreshControl={refreshControl}
      />
    );
  }

  return (
    <View style={{ flex: 1, backgroundColor: C.bg(dark) }}>
      <WashHeader dark={dark} style={{ paddingHorizontal: 20, paddingTop: insets.top + 16, paddingBottom: 8 }}>
        <FadeSlideIn style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
          <Text style={pageTitleStyle(dark)}>PR Vault</Text>
          <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            <BellButton dark={dark} prefs={prefs} onPress={() => (haptic.selection(), router.push('/activity'))} />
            <View style={{ width: 4 }} />
            <AppIcon size={36} />
          </View>
        </FadeSlideIn>

        {/* Search, then season and gender in one pill: "Outdoor · All". */}
        <FadeSlideIn delay={60} style={{ marginTop: 16, flexDirection: 'row', alignItems: 'center', zIndex: 2 }}>
          <View style={{ flex: 1, height: 42, borderRadius: 12, backgroundColor: C.field(dark), flexDirection: 'row', alignItems: 'center' }}>
            <View style={{ paddingLeft: 12, paddingRight: 8 }}>
              <Icon name="search" size={16} color={C.text3(dark)} />
            </View>
            <TextInput
              value={search}
              onChangeText={setSearch}
              placeholder="Search athletes or events…"
              placeholderTextColor={C.text3(dark)}
              returnKeyType="search"
              keyboardAppearance={dark ? 'dark' : 'light'}
              selectionColor={C.accentOf(dark)}
              style={{ flex: 1, fontSize: 15, color: C.text1(dark), paddingVertical: 0 }}
            />
            {search.length > 0 && (
              <Pressable onPress={() => setSearch('')} style={{ padding: 8 }} accessibilityLabel="Clear search">
                <Icon name="close" size={16} color={C.text3(dark)} />
              </Pressable>
            )}
          </View>
          <View style={{ width: 8 }} />
          <OneTimeTip id="filter_pill" message="Tap to switch season or gender">
            <FilterPill
              testID="filters"
              dark={dark}
              groups={[
                ...((snap?.seasons.length ?? 0) > 1
                  ? [{ options: snap!.seasons.map(seasonLabel), value: seasonLabel(seasonNow), onChange: setSeason }]
                  : []),
                { options: ['All', 'M', 'F'], value: gender, onChange: setGender },
              ]}
            />
          </OneTimeTip>
        </FadeSlideIn>

        {/* Main tabs: the same sliding pill as the other switches. */}
        <FadeSlideIn delay={120} style={{ marginTop: 16 }}>
          <SegmentToggle
            options={Object.values(tabLabels)}
            value={tabLabels[tab]}
            dark={dark}
            height={40}
            fontSize={14}
            fill
            onChange={(label) => setTab((Object.keys(tabLabels) as Tab[]).find((k) => tabLabels[k] === label)!)}
          />
        </FadeSlideIn>
      </WashHeader>

      <ChipRow
        chips={Object.keys(eventGroups)
          .filter((g) => groupHasEvents(g, seasonEvents))
          .map((g) => (
            <AppChip key={g} label={g} selected={g === group} dark={dark} onPress={() => (setGroup(g), setSubEvent(null))} />
          ))}
      />
      <Animated.View layout={LinearTransition.duration(220)}>
        {showSubChips && (
          <Animated.View entering={FadeIn.duration(180)} exiting={FadeOut.duration(120)}>
            <ChipRow
              height={44}
              chips={[
                <AppChip key="all" label={`All ${group}`} selected={subEvent == null} dark={dark} small onPress={() => setSubEvent(null)} />,
                ...(eventGroups[group] ?? [])
                  .filter((e) => seasonEvents.has(e))
                  .map((ev) => (
                    <AppChip
                      key={ev}
                      label={ev.replace(' Meters', '').replace(' Hurdles', 'H')}
                      selected={subEvent === ev}
                      dark={dark}
                      small
                      onPress={() => setSubEvent(ev)}
                    />
                  )),
              ]}
            />
          </Animated.View>
        )}
        {showTrendControls && (
          <Animated.View entering={FadeIn.duration(180)} exiting={FadeOut.duration(120)} style={{ height: 44, flexDirection: 'row', alignItems: 'center' }}>
            <View style={{ flex: 1 }}>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingLeft: 20, paddingRight: 24, gap: 8, alignItems: 'center' }}>
                {snap!.windows.map((w) => (
                  <AppChip key={w.id} label={w.label} selected={w.id === trendWindow.id} dark={dark} small onPress={() => setPickedWindow(w)} />
                ))}
              </ScrollView>
              {/* Fade the chips out before the toggle instead of cutting them. */}
              <LinearGradient
                pointerEvents="none"
                colors={[alpha(C.bg(dark), 0), C.bg(dark)]}
                start={{ x: 0, y: 0 }}
                end={{ x: 1, y: 0 }}
                style={{ position: 'absolute', right: 0, top: 0, bottom: 0, width: 28 }}
              />
            </View>
            <View style={{ marginLeft: 4, marginRight: 20 }}>
              <SegmentToggle options={['PRs', 'Points']} value={trendByPoints ? 'Points' : 'PRs'} dark={dark} onChange={(v) => setTrendByPoints(v === 'Points')} />
            </View>
          </Animated.View>
        )}
        {showRosterControls && (
          <Animated.View entering={FadeIn.duration(180)} exiting={FadeOut.duration(120)} style={{ height: 44, flexDirection: 'row', alignItems: 'center' }}>
            <Text numberOfLines={1} style={{ flex: 1, paddingLeft: 20, fontSize: 12, fontWeight: '500', color: C.text3(dark) }}>
              {allTime ? 'Everyone who has competed for the team' : 'Current roster'}
            </Text>
            <View style={{ marginRight: 20 }}>
              <SegmentToggle options={['Current', 'All-time']} value={allTime ? 'All-time' : 'Current'} dark={dark} onChange={(v) => setAllTime(v === 'All-time')} />
            </View>
          </Animated.View>
        )}
        <View style={{ height: 0.5, backgroundColor: C.border(dark) }} />
      </Animated.View>
      {/* Cross-fade when the filters change instead of snapping. */}
      <Animated.View key={loading ? 'loading' : listKey} entering={FadeIn.duration(180)} style={{ flex: 1 }}>
        {body}
      </Animated.View>
    </View>
  );
}

// ─── Bell with unread badge ───────────────────────────────────────────────────

function BellButton({ dark, prefs, onPress }: { dark: boolean; prefs: Prefs; onPress: () => void }) {
  const count = useObservable(ActivityFeed.instance.unread);
  const unread = prefs.showBadge ? count : 0;
  const badge = useAnimatedStyle(() => ({ transform: [{ scale: withTiming(unread > 0 ? 1 : 0, { duration: 250 }) }] }), [unread]);
  return (
    <PressScale onPress={onPress}>
      <View style={{ padding: 8 }} accessibilityLabel={unread > 0 ? `Activity, ${unread} new` : 'Activity'}>
        <Icon name={unread > 0 ? 'notifications' : 'notifications-none'} size={22} color={C.text2(dark)} />
        <Animated.View
          style={[
            {
              position: 'absolute',
              top: 4,
              right: 2,
              height: 17,
              minWidth: 17,
              paddingHorizontal: 4,
              borderRadius: 9,
              backgroundColor: C.accentOf(dark),
              borderWidth: 1.5,
              borderColor: C.bg(dark),
              alignItems: 'center',
              justifyContent: 'center',
            },
            badge,
          ]}
        >
          <Text style={{ fontSize: 9, fontWeight: '700', color: '#fff' }}>{unread > 9 ? '9+' : `${unread}`}</Text>
        </Animated.View>
      </View>
    </PressScale>
  );
}

// ─── Lists ────────────────────────────────────────────────────────────────────

function Message({ dark, icon, text, refreshControl }: { dark: boolean; icon: IconName; text: string; refreshControl: React.ReactElement<any> }) {
  // Scrollable so pull-to-refresh still works on an empty or failed page.
  return (
    <ScrollView refreshControl={refreshControl} contentContainerStyle={{ paddingTop: 90, paddingBottom: 120 }} alwaysBounceVertical>
      <EmptyState icon={icon} title={text} dark={dark} />
    </ScrollView>
  );
}

type RankedItem = { kind: 'podium' } | { kind: 'title' } | { kind: 'row'; entry: Row; index: number };

function Ranked({
  list,
  tab,
  dark,
  prefs,
  podiumAllowed,
  initialLoad,
  sparklines,
  onOpen,
  refreshControl,
}: {
  list: Row[];
  tab: Tab;
  dark: boolean;
  prefs: Prefs;
  podiumAllowed: boolean;
  initialLoad: boolean;
  sparklines: Map<string, number[]>;
  onOpen: (entry: Row) => void;
  refreshControl: React.ReactElement<any>;
}) {
  if (list.length === 0) return <Message dark={dark} icon="search" text="No results found" refreshControl={refreshControl} />;

  const podium = podiumAllowed ? list.filter((e) => delta(e) > 0.01).slice(0, 5) : [];
  // The featured cards are the top of the ranking, so the list carries on
  // from there instead of repeating them.
  const items: RankedItem[] = [];
  if (podium.length > 0) {
    items.push({ kind: 'podium' });
    if (list.length > podium.length) items.push({ kind: 'title' });
  }
  list.forEach((entry, index) => {
    if (index >= podium.length) items.push({ kind: 'row', entry, index });
  });

  return (
    <FlatList
      data={items}
      refreshControl={refreshControl}
      alwaysBounceVertical
      keyboardDismissMode="on-drag"
      contentContainerStyle={{ paddingBottom: 120 }}
      keyExtractor={(item) => (item.kind === 'row' ? `lb-${item.entry.athlete_id}-${item.entry.event}` : item.kind)}
      renderItem={({ item }) => {
        if (item.kind === 'podium') return <Podium entries={podium} dark={dark} onOpen={onOpen} />;
        if (item.kind === 'title')
          return (
            <View style={{ paddingHorizontal: 20, paddingTop: 16, paddingBottom: 4 }}>
              <SectionTitle text="Everyone else" dark={dark} />
            </View>
          );
        const { entry, index } = item;
        return (
          // Stagger only the first screenful of the first load.
          <FadeSlideIn animate={initialLoad && index < 12} delay={200 + index * 40}>
            <LeaderboardRow
              entry={entry}
              index={index}
              tab={tab}
              dark={dark}
              prefs={prefs}
              sparkData={sparklines.get(`${entry.athlete_id}_${eventKey(entry.event ?? '', seasonOf(entry))}`) ?? []}
              onPress={() => onOpen(entry)}
            />
          </FadeSlideIn>
        );
      }}
    />
  );
}

function Trending({
  snap,
  dark,
  season,
  window,
  events,
  gender,
  search,
  byPoints,
  onOpen,
  refreshControl,
}: {
  snap: TeamSnapshot;
  dark: boolean;
  season: string;
  window: TrendWindow;
  events: Set<string> | null;
  gender: string;
  search: string;
  byPoints: boolean;
  onOpen: (id: string) => void;
  refreshControl: React.ReactElement<any>;
}) {
  const q = search.toLowerCase();
  const prs = snap.prEvents.filter((p) => {
    if (p.season !== season) return false;
    if (!window.contains(p.date)) return false;
    if (events && !events.has(p.event)) return false;
    if (gender !== 'All' && snap.genderOf(p.athleteId) !== gender) return false;
    if (q && !snap.nameOf(p.athleteId).toLowerCase().includes(q) && !p.event.toLowerCase().includes(q)) return false;
    return true;
  });
  const rows = trendingAthletes(prs, byPoints);

  if (rows.length === 0) {
    const when = window.id === TrendWindow.allTime.id ? '' : window.isSeason ? ` in the ${window.label} season` : ' in the last 30 days';
    return (
      <Message
        dark={dark}
        icon="local-fire-department"
        text={`No ${seasonLabel(season).toLowerCase().replace('xc', 'XC')} PRs${when} yet.`}
        refreshControl={refreshControl}
      />
    );
  }

  return (
    <FlatList
      data={rows}
      refreshControl={refreshControl}
      alwaysBounceVertical
      keyboardDismissMode="on-drag"
      contentContainerStyle={{ paddingBottom: 120 }}
      keyExtractor={(r) => `tr-${r.athleteId}`}
      renderItem={({ item, index }) => (
        <TrendingRow
          trend={item}
          index={index}
          name={snap.nameOf(item.athleteId)}
          gender={snap.genderOf(item.athleteId)}
          byPoints={byPoints}
          dark={dark}
          onPress={() => onOpen(item.athleteId)}
        />
      )}
    />
  );
}

function SkeletonRows({ dark }: { dark: boolean }) {
  return (
    <SkeletonPulse>
      <View style={{ paddingTop: 8 }}>
        {Array.from({ length: 8 }, (_, i) => (
          <View key={i} style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 20, paddingVertical: 12 }}>
            <SkeletonBox dark={dark} width={30} height={30} radius={15} />
            <View style={{ width: 12 }} />
            <SkeletonBox dark={dark} width={40} height={40} radius={20} />
            <View style={{ flex: 1, marginLeft: 12, gap: 6 }}>
              <SkeletonBox dark={dark} width={110 + (i % 3) * 30} height={12} />
              <SkeletonBox dark={dark} width={70} height={10} />
            </View>
            <SkeletonBox dark={dark} width={56} height={22} radius={11} />
          </View>
        ))}
      </View>
    </SkeletonPulse>
  );
}

/** The row's place as a bold number; the top three in the team color. */
function RankBadge({ index, dark }: { index: number; dark: boolean }) {
  return (
    <Text
      style={{
        width: 30,
        textAlign: 'center',
        fontSize: 17,
        fontWeight: '800',
        letterSpacing: -0.5,
        fontVariant: ['tabular-nums'],
        color: index < 3 ? C.accentOf(dark) : C.text3(dark),
      }}
    >
      {index + 1}
    </Text>
  );
}

function TrendingRow({
  trend,
  index,
  name,
  gender,
  byPoints,
  dark,
  onPress,
}: {
  trend: AthleteTrend;
  index: number;
  name: string;
  gender: string;
  byPoints: boolean;
  dark: boolean;
  onPress: () => void;
}) {
  const events = trend.events;
  const eventText = events.length <= 2 ? events.join(', ') : `${events.slice(0, 2).join(', ')} +${events.length - 2}`;
  const prs = `${trend.prCount} PR${trend.prCount === 1 ? '' : 's'}`;
  return (
    <PressScale pressedScale={0.98} onPress={onPress}>
      <View style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 20, paddingVertical: 12 }}>
        <RankBadge index={index} dark={dark} />
        <View style={{ width: 12 }} />
        <InitialsAvatar name={name} gender={gender} dark={dark} />
        <View style={{ flex: 1, marginLeft: 12 }}>
          <Text numberOfLines={1} style={{ fontSize: 15.5, fontWeight: '600', letterSpacing: -0.15, color: C.text1(dark) }}>
            {formatName(name)}
          </Text>
          <Text numberOfLines={1} style={{ marginTop: 2, fontSize: 12.5, fontWeight: '500', color: C.text3(dark) }}>
            {eventText} · last {formatShortMeetDate(trend.lastPr)}
          </Text>
        </View>
        <View style={{ marginLeft: 8, alignItems: 'flex-end' }}>
          <Text style={{ fontSize: 16, fontWeight: '700', color: C.accentOf(dark), letterSpacing: -0.4 }}>
            {byPoints ? `${trend.points} pts` : prs}
          </Text>
          <Text style={{ fontSize: 11.5, color: C.text3(dark) }}>{byPoints ? prs : `${trend.points} pts`}</Text>
        </View>
      </View>
    </PressScale>
  );
}

/** Top improvers as a row of featured cards, edge to edge. #1 gets the team color. */
function Podium({ entries, dark, onOpen }: { entries: Row[]; dark: boolean; onOpen: (e: Row) => void }) {
  const textGrowth = Math.max(0, Math.min(1, PixelRatio.getFontScale() - 1));
  return (
    <View style={{ paddingTop: 20, paddingBottom: 12 }}>
      <View style={{ paddingHorizontal: 20 }}>
        <SectionTitle text="Top Improvers" dark={dark} />
      </View>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        style={{ marginTop: 12 }}
        contentContainerStyle={{ paddingHorizontal: 20, gap: 10, paddingBottom: 10 }}
      >
        {entries.map((e, i) => (
          <ImproverCard key={`${e.athlete_id}${e.event}`} entry={e} rank={i + 1} dark={dark} height={190 + textGrowth * 60} onPress={() => onOpen(e)} />
        ))}
      </ScrollView>
    </View>
  );
}

function ImproverCard({ entry, rank, dark, height, onPress }: { entry: Row; rank: number; dark: boolean; height: number; onPress: () => void }) {
  const lead = rank === 1;
  const rawName = entry.profiles?.full_name ?? '';
  const ink = lead ? '#fff' : C.text1(dark);
  const soft = lead ? 'rgba(255, 255, 255, 0.75)' : C.text3(dark);
  const inner = (
    <>
      <View style={{ flexDirection: 'row', alignItems: 'center' }}>
        <Text style={{ fontSize: 30, fontWeight: '900', letterSpacing: -1, lineHeight: 32, color: lead ? '#fff' : C.accentOf(dark) }}>{rank}</Text>
        <View style={{ flex: 1 }} />
        <InitialsAvatar name={rawName} gender={entry.profiles?.gender ?? 'M'} dark={dark} />
      </View>
      <View style={{ flex: 1 }} />
      <Text numberOfLines={2} style={{ fontSize: 15, fontWeight: '700', letterSpacing: -0.2, lineHeight: 18, color: ink }}>
        {formatName(rawName || 'Unknown')}
      </Text>
      <Text numberOfLines={1} style={{ marginTop: 2, fontSize: 12, color: soft }}>{entry.event ?? ''}</Text>
      <Text style={{ marginTop: 10, fontSize: 20, fontWeight: '800', letterSpacing: -0.5, color: lead ? '#fff' : C.accentOf(dark) }}>
        +{delta(entry).toFixed(2)}%
      </Text>
    </>
  );
  return (
    <PressScale onPress={onPress}>
      {lead ? (
        <LinearGradient
          colors={[C.accentOf(dark), C.accentAlt]}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 1 }}
          style={{ width: 150, height, padding: 14, borderRadius: 20, boxShadow: `0 6px 18px ${alpha(C.accentOf(dark), 0.35)}` }}
        >
          {inner}
        </LinearGradient>
      ) : (
        <View style={[cardStyle(dark), { width: 150, height, padding: 14 }]}>{inner}</View>
      )}
    </PressScale>
  );
}

/** The last eight results as a tiny line; up is better for both times and marks. */
function Sparkline({ data, isField, color }: { data: number[]; isField: boolean; color: string }) {
  const recent = data.length > 8 ? data.slice(data.length - 8) : data;
  const minV = Math.min(...recent);
  const maxV = Math.max(...recent);
  if (recent.length < 2 || maxV === minV) return <View style={{ width: 40, height: 24 }} />;
  const points = recent
    .map((v, i) => {
      const x = (i / (recent.length - 1)) * 40;
      const norm = isField ? (v - minV) / (maxV - minV) : 1 - (v - minV) / (maxV - minV);
      return `${x},${24 - norm * 24}`;
    })
    .join(' ');
  return (
    <Svg width={40} height={24}>
      <Polyline points={points} fill="none" stroke={color} strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" />
    </Svg>
  );
}

function LeaderboardRow({
  entry: e,
  index,
  tab,
  dark,
  prefs,
  sparkData,
  onPress,
}: {
  entry: Row;
  index: number;
  tab: Tab;
  dark: boolean;
  prefs: Prefs;
  sparkData: number[];
  onPress: () => void;
}) {
  const [pressed, setPressed] = useState(false);
  const event = e.event ?? '';
  const d = delta(e);
  const alum = e.profiles?.on_roster === false;
  return (
    <Pressable onPress={onPress} onPressIn={() => setPressed(true)} onPressOut={() => setPressed(false)}>
      <View
        style={{
          flexDirection: 'row',
          alignItems: 'center',
          paddingHorizontal: 20,
          paddingVertical: 12,
          backgroundColor: pressed ? C.accentSoft(dark) : 'transparent',
        }}
      >
        <RankBadge index={index} dark={dark} />
        <View style={{ width: 12 }} />
        <InitialsAvatar name={e.profiles?.full_name ?? 'Unknown'} gender={e.profiles?.gender ?? 'M'} dark={dark} />
        <View style={{ flex: 1, marginLeft: 12 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            <Text numberOfLines={1} style={{ flexShrink: 1, fontSize: 15.5, fontWeight: '600', letterSpacing: -0.15, color: C.text1(dark) }}>
              {formatName(e.profiles?.full_name ?? 'Unknown')}
            </Text>
            {alum && (
              <View style={{ marginLeft: 6, paddingHorizontal: 6, paddingVertical: 1, borderRadius: 100, backgroundColor: C.surface2(dark) }}>
                <Text style={{ fontSize: 9, fontWeight: '700', letterSpacing: 0.4, color: C.text3(dark) }}>ALUM</Text>
              </View>
            )}
          </View>
          <Text style={{ marginTop: 2, fontSize: 12.5, fontWeight: '500', color: C.text3(dark) }}>{event}</Text>
        </View>
        <View style={{ width: 8 }} />
        {sparkData.length >= 2 && (
          <View style={{ marginRight: 8 }}>
            <Sparkline data={sparkData} isField={isFieldEvent(event)} color={d > 0 ? alpha(C.accentOf(dark), 0.7) : C.text3(dark)} />
          </View>
        )}
        {tab === 'heat' ? (
          d > 0 ? (
            <View
              style={{
                flexDirection: 'row',
                alignItems: 'center',
                paddingHorizontal: 8,
                paddingVertical: 3,
                borderRadius: 100,
                backgroundColor: C.accentSoft(dark),
              }}
            >
              <Icon name="arrow-upward" size={9} color={C.accentOf(dark)} />
              <Text style={{ marginLeft: 2, fontSize: 11, fontWeight: '600', color: C.accentOf(dark) }}>{d.toFixed(2)}%</Text>
            </View>
          ) : (
            <Text style={{ color: C.text3(dark) }}>—</Text>
          )
        ) : (
          <View style={{ alignItems: 'flex-end' }}>
            <Text style={{ fontSize: 16, fontWeight: '700', color: C.accentOf(dark), letterSpacing: -0.5 }}>
              {prefs.mark(event, e.best_display, e.best_mark_meters)}
            </Text>
            {d > 0 && <Text style={{ fontSize: 11.5, color: C.text3(dark) }}>+{d.toFixed(1)}%</Text>}
          </View>
        )}
      </View>
    </Pressable>
  );
}
