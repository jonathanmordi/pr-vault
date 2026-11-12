import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { FlatList, RefreshControl, ScrollView, Text, View } from 'react-native';
import Animated, { FadeIn } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { PressScale } from '@/components/motion';
import { AppChip, BackCircle, ChipRow, EmptyState, InitialsAvatar, Spinner, WashHeader, pageTitleStyle, sectionTitleStyle } from '@/components/ui';
import { ActivityFeed } from '@/lib/activityFeed';
import { formatName, formatShortMeetDate, monthLabel } from '@/lib/format';
import { haptic } from '@/lib/haptics';
import { usePrefs } from '@/lib/prefs';
import { PrEvent, Rival, eventKey, isFieldEvent, seasonLabel } from '@/lib/prStats';
import { TeamData, TeamSnapshot } from '@/lib/teamData';
import { C, useDark } from '@/theme/colors';

import { SheetBackdrop, showAthleteSheet } from './athleteSheet';

type Filter = 'All' | 'Rivals' | 'You';

export function Activity() {
  const dark = useDark();
  usePrefs(); // notification settings decide what's listed
  const insets = useSafeAreaInsets();
  const myId = TeamData.instance.currentUserId();
  const [snap, setSnap] = useState<TeamSnapshot | null>(() => TeamData.instance.cached);
  const [fresh, setFresh] = useState<Set<string>>(new Set());
  const [filter, setFilter] = useState<Filter>('All');
  const [loading, setLoading] = useState(() => TeamData.instance.cached == null);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const snapRef = useRef(snap);
  snapRef.current = snap;

  const apply = (s: TeamSnapshot, newKeys: Set<string>) => {
    setSnap(s);
    setFresh((f) => new Set([...f, ...newKeys]));
    setLoading(false);
    setError(null);
  };

  const load = async (force = false) => {
    try {
      const s = await TeamData.instance.load({ force });
      const newKeys = await ActivityFeed.instance.markAllSeen(s);
      apply(s, newKeys);
    } catch {
      // Offline: last time's copy if there is one, otherwise say so.
      const saved = snapRef.current ?? (await TeamData.instance.restore());
      if (saved) apply(saved, new Set());
      else {
        setLoading(false);
        setError("Couldn't load activity. Pull down to try again.");
      }
    }
  };

  useEffect(() => {
    if (!TeamData.instance.cached) {
      TeamData.instance.restore().then((s) => {
        if (s && !snapRef.current) apply(s, new Set());
      });
    }
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const myRivals: Map<string, Rival> = snap && myId ? snap.rivalsOf(myId) : new Map();
  const isRival = (p: PrEvent) => myRivals.get(eventKey(p.event, p.season))?.athleteId === p.athleteId;

  const items = (() => {
    if (!snap) return [];
    const all = ActivityFeed.itemsOf(snap);
    if (filter === 'Rivals') return all.filter(isRival);
    if (filter === 'You') return all.filter((p) => p.athleteId === myId);
    return all;
  })();

  const openAthlete = (id: string) =>
    snap && showAthleteSheet({ athleteId: id, athleteName: snap.nameOf(id), gender: snap.genderOf(id) });

  const refreshControl = (
    <RefreshControl
      refreshing={refreshing}
      tintColor={C.accentOf(dark)}
      onRefresh={async () => {
        haptic.light();
        setRefreshing(true);
        await load(true);
        setRefreshing(false);
      }}
    />
  );

  const message = (text: string, icon: 'cloud-off' | 'notifications-none') => (
    <ScrollView refreshControl={refreshControl} contentContainerStyle={{ paddingTop: 110 }} alwaysBounceVertical>
      <EmptyState icon={icon} title={text} dark={dark} />
    </ScrollView>
  );

  let body;
  if (loading) {
    body = (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <Spinner color={C.accentOf(dark)} />
      </View>
    );
  } else if (!snap || error) {
    body = message(error ?? "Couldn't load activity.", 'cloud-off');
  } else if (items.length === 0) {
    const linked = myId != null && snap.prs.some((p) => p.athlete_id === myId);
    const text =
      filter === 'Rivals'
        ? linked
          ? 'No PRs from your rivals yet.'
          : 'Link your TFRRS profile to get rivals.'
        : filter === 'You'
          ? linked
            ? "You haven't set a PR yet. Soon."
            : 'Link your TFRRS profile to see your PRs.'
          : 'No PRs yet.';
    body = message(text, 'notifications-none');
  } else {
    // Interleave month headers with the items.
    const rows: (string | PrEvent)[] = [];
    let month: string | null = null;
    for (const p of items) {
      const m = monthLabel(p.date);
      if (m !== month) {
        rows.push(m);
        month = m;
      }
      rows.push(p);
    }
    body = (
      <FlatList
        data={rows}
        refreshControl={refreshControl}
        alwaysBounceVertical
        contentContainerStyle={{ paddingBottom: insets.bottom + 40 }}
        keyExtractor={(r) => (typeof r === 'string' ? r : r.key)}
        renderItem={({ item }) =>
          typeof item === 'string' ? (
            <Text style={[sectionTitleStyle(dark), { fontSize: 17, paddingHorizontal: 20, paddingTop: 20, paddingBottom: 6 }]}>{item}</Text>
          ) : (
            <ActivityRow
              pr={item}
              name={snap.nameOf(item.athleteId)}
              gender={snap.genderOf(item.athleteId)}
              isMine={item.athleteId === myId}
              isRival={isRival(item)}
              isNew={fresh.has(item.key)}
              dark={dark}
              onPress={() => openAthlete(item.athleteId)}
            />
          )
        }
      />
    );
  }

  return (
    <SheetBackdrop>
      <View style={{ flex: 1, backgroundColor: C.bg(dark) }}>
        <WashHeader dark={dark} style={{ paddingLeft: 16, paddingRight: 20, paddingTop: insets.top + 12 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            <BackCircle onPress={() => router.back()} dark={dark} size={32} soft />
            <Text style={[pageTitleStyle(dark), { marginLeft: 12 }]}>Activity</Text>
          </View>
        </WashHeader>
        <View style={{ height: 16 }} />
        <ChipRow
          height={40}
          chips={(['All', 'Rivals', 'You'] as Filter[]).map((f) => (
            <AppChip key={f} label={f} selected={f === filter} dark={dark} onPress={() => setFilter(f)} />
          ))}
        />
        <View style={{ height: 12 }} />
        <View style={{ height: 0.5, backgroundColor: C.border(dark) }} />
        <Animated.View key={filter} entering={FadeIn.duration(180)} style={{ flex: 1 }}>
          {body}
        </Animated.View>
      </View>
    </SheetBackdrop>
  );
}

function ActivityRow({
  pr,
  name,
  gender,
  isMine,
  isRival,
  isNew,
  dark,
  onPress,
}: {
  pr: PrEvent;
  name: string;
  gender: string;
  isMine: boolean;
  isRival: boolean;
  isNew: boolean;
  dark: boolean;
  onPress: () => void;
}) {
  const prefs = usePrefs();
  const sign = isFieldEvent(pr.event) ? '+' : '−';
  const detail = [
    seasonLabel(pr.season),
    prefs.mark(pr.event, pr.display, pr.value),
    `${sign}${prefs.gap(pr.event, pr.gap)} (${pr.improvementPct.toFixed(1)}%)`,
    ...(pr.meetName ? [pr.meetName] : []),
  ].join(' · ');

  const tag = (text: string, filled = false) => (
    <View style={{ paddingHorizontal: 8, paddingVertical: 2, borderRadius: 100, backgroundColor: filled ? C.accentOf(dark) : C.accentSoft(dark) }}>
      <Text style={{ fontSize: 10, fontWeight: '700', letterSpacing: 0.4, color: filled ? '#fff' : C.accentOf(dark) }}>{text}</Text>
    </View>
  );

  return (
    <PressScale pressedScale={0.98} onPress={onPress}>
      <View
        style={{
          flexDirection: 'row',
          alignItems: 'flex-start',
          paddingHorizontal: 20,
          paddingVertical: 12,
          backgroundColor: isNew ? C.accentSoft(dark) : 'transparent',
        }}
      >
        <InitialsAvatar name={name} gender={gender} dark={dark} />
        <View style={{ flex: 1, marginLeft: 12 }}>
          <Text style={{ fontSize: 14, color: C.text1(dark) }}>
            <Text style={{ fontWeight: '700' }}>{isMine ? 'You' : formatName(name)}</Text> PR'd in {pr.event}
          </Text>
          <Text numberOfLines={2} style={{ marginTop: 3, fontSize: 12, color: C.text3(dark) }}>
            {detail}
          </Text>
          {(isRival || pr.schoolRecord) && (
            <View style={{ marginTop: 6, flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
              {isRival && tag('RIVAL', true)}
              {pr.schoolRecord && tag('🏆 SCHOOL RECORD')}
            </View>
          )}
        </View>
        <View style={{ marginLeft: 8, alignItems: 'flex-end' }}>
          <Text style={{ fontSize: 11, color: C.text3(dark) }}>{formatShortMeetDate(pr.date)}</Text>
          <Text style={{ marginTop: 4, fontSize: 11, fontWeight: '700', color: C.accentOf(dark) }}>+{pr.points} pts</Text>
        </View>
      </View>
    </PressScale>
  );
}
