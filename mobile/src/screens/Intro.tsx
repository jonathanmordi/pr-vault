// How PR Vault works: four pages shown once after sign-up, and again from
// Settings. Each page has a small live demo built from the app's own pieces,
// so it shows the real thing instead of a screenshot.

import { Stack } from 'expo-router';
import { ComponentRef, ReactNode, useEffect, useRef, useState } from 'react';
import { Pressable, ScrollView, Text, View, useWindowDimensions } from 'react-native';
import Animated, {
  Easing,
  FadeIn,
  SharedValue,
  cancelAnimation,
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withRepeat,
  withTiming,
} from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Svg, { Circle, Polyline } from 'react-native-svg';

import { FilterPill } from '@/components/FilterPill';
import { FadeSlideIn, PressScale } from '@/components/motion';
import { SegmentToggle } from '@/components/SegmentToggle';
import { TrackBackdrop } from '@/components/TrackBackdrop';
import { BrandMark, Icon, InitialsAvatar } from '@/components/ui';
import { haptic } from '@/lib/haptics';
import { C, useDark } from '@/theme/colors';

const pageCount = 4;

/** A damped spring's motion as a curve: a quick start and a soft settle with a slight overshoot, like iOS. */
function fluid(t: number) {
  'worklet';
  const damping = 0.72;
  const w = 9;
  const wd = w * Math.sqrt(1 - damping * damping);
  return 1 - Math.exp(-damping * w * t) * (Math.cos(wd * t) + ((damping * w) / wd) * Math.sin(wd * t));
}

function easeInOutCubic(t: number) {
  'worklet';
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
}

export function Intro({ onDone }: { onDone: () => void }) {
  const dark = useDark();
  const insets = useSafeAreaInsets();
  const { width } = useWindowDimensions();
  const pager = useRef<ComponentRef<typeof ScrollView>>(null);
  const [page, setPage] = useState(0);
  const last = page === pageCount - 1;

  const next = () => {
    haptic.selection();
    if (last) return onDone();
    pager.current?.scrollTo({ x: width * (page + 1), animated: true });
  };

  const pages: { demo: ReactNode; title: string; body: string }[] = [
    {
      demo: <ResultsDemo active={page === 0} />,
      title: 'Your results, automatically',
      body: 'PR Vault pulls every result from TFRRS each night, so a meet shows up by the next morning. Indoor and outdoor PRs are kept separate.',
    },
    {
      demo: <BoardDemo dark={dark} />,
      title: 'Your team, ranked',
      body: "Heat Map shows who's improving most, PR Rankings the best marks, Trending who's PR'ing most. Tap the pill to switch season or gender. Try it.",
    },
    {
      demo: <TapDemo active={page === 2} dark={dark} />,
      title: 'Tap anyone',
      body: 'Their card pops up. Drag it up for the full profile: insights, progression and rivals. Swipe down to close.',
    },
    {
      demo: <LoopDemo active={page === 3} />,
      title: 'Stay in the loop',
      body: "The bell shows your teammates' PRs. Rivals are the teammates closest to you in each event, and Maxes is where you log your lifts.",
    },
  ];

  return (
    <View style={{ flex: 1, backgroundColor: C.bg(dark) }}>
      <Stack.Screen options={{ statusBarStyle: 'light' }} />
      <TrackBackdrop dark={dark} />
      <View style={{ flex: 1, paddingTop: insets.top, paddingBottom: insets.bottom }}>
        <View style={{ flexDirection: 'row', alignItems: 'center', paddingLeft: 24, paddingRight: 12, paddingTop: 10 }}>
          <BrandMark />
          <View style={{ flex: 1 }} />
          <Pressable onPress={onDone} disabled={last} style={{ padding: 10, opacity: last ? 0 : 1 }}>
            <Text style={{ fontSize: 15, fontWeight: '600', color: 'rgba(255, 255, 255, 0.8)' }}>Skip</Text>
          </Pressable>
        </View>
        <ScrollView
          ref={pager}
          horizontal
          pagingEnabled
          showsHorizontalScrollIndicator={false}
          style={{ flex: 1 }}
          onMomentumScrollEnd={(e) => {
            const i = Math.round(e.nativeEvent.contentOffset.x / width);
            if (i !== page) {
              haptic.selection();
              setPage(i);
            }
          }}
        >
          {pages.map((p) => (
            <IntroPage key={p.title} width={width} {...p} />
          ))}
        </ScrollView>
        <View style={{ flexDirection: 'row', justifyContent: 'center', paddingTop: 22 }}>
          {Array.from({ length: pageCount }, (_, i) => (
            <Dot key={i} on={i === page} />
          ))}
        </View>
        <View style={{ paddingHorizontal: 24, paddingTop: 18, paddingBottom: 12 }}>
          <PressScale onPress={next}>
            <View
              style={{
                height: 54,
                borderRadius: 16,
                backgroundColor: '#fff',
                alignItems: 'center',
                justifyContent: 'center',
                boxShadow: '0 8px 20px rgba(0, 0, 0, 0.18)',
              }}
            >
              <Animated.Text key={last ? 'go' : 'next'} entering={FadeIn.duration(200)} style={{ fontSize: 16, fontWeight: '700', color: C.accentOf(false) }}>
                {last ? "Let's go" : 'Next'}
              </Animated.Text>
            </View>
          </PressScale>
        </View>
      </View>
    </View>
  );
}

function IntroPage({ width, demo, title, body }: { width: number; demo: ReactNode; title: string; body: string }) {
  const [box, setBox] = useState({ w: 0, h: 0 });
  // Demos are drawn at one size and scaled down to fit small phones.
  const scale = box.w === 0 ? 1 : Math.min(1, box.w / 320, box.h / 330);
  return (
    <View style={{ width, paddingHorizontal: 24 }}>
      <View
        style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}
        onLayout={(e) => setBox({ w: e.nativeEvent.layout.width, h: e.nativeEvent.layout.height })}
      >
        <View style={{ width: 320, height: 330, alignItems: 'center', justifyContent: 'center', transform: [{ scale }] }}>{demo}</View>
      </View>
      <Text style={{ fontSize: 32, lineHeight: 34, fontWeight: '900', letterSpacing: -1.1, color: '#fff' }}>{title}</Text>
      <Text style={{ marginTop: 10, fontSize: 15.5, lineHeight: 22, color: 'rgba(255, 255, 255, 0.82)' }}>{body}</Text>
    </View>
  );
}

function Dot({ on }: { on: boolean }) {
  const style = useAnimatedStyle(
    () => ({
      width: withTiming(on ? 22 : 7, { duration: 320 }),
      backgroundColor: withTiming(on ? 'rgba(255, 255, 255, 1)' : 'rgba(255, 255, 255, 0.4)', { duration: 320 }),
    }),
    [on],
  );
  return <Animated.View style={[{ height: 7, borderRadius: 4, marginHorizontal: 3 }, style]} />;
}

/** A card like the sign-in screen's: solid white, or glassy on the red. */
function DemoCard({ children, solid = false }: { children: ReactNode; solid?: boolean }) {
  return (
    <View
      style={{
        width: 280,
        paddingHorizontal: 16,
        paddingVertical: 14,
        borderRadius: 20,
        backgroundColor: solid ? '#fff' : 'rgba(255, 255, 255, 0.13)',
        borderWidth: solid ? 0 : 0.8,
        borderColor: 'rgba(255, 255, 255, 0.22)',
        boxShadow: '0 10px 22px rgba(0, 0, 0, 0.2)',
      }}
    >
      {children}
    </View>
  );
}

const label = (color: string) => ({ fontSize: 11, fontWeight: '800' as const, letterSpacing: 0.7, color });

/** Replays its children's entrance whenever the page comes into view. */
function Entrance({ active, children }: { active: boolean; children: ReactNode[] }) {
  return (
    <View key={String(active)} style={{ alignItems: 'center' }}>
      {children.map((child, i) => (
        <FadeSlideIn key={i} delay={120 + 150 * i}>
          {child}
        </FadeSlideIn>
      ))}
    </View>
  );
}

/** Runs [shared] from 0 to 1 over [ms] on a loop while [active]; still with reduced motion. */
function useLoop(shared: SharedValue<number>, active: boolean, ms: number, restart = false) {
  const reduce = useReducedMotion();
  useEffect(() => {
    if (active && !reduce) {
      if (restart) shared.value = 0;
      shared.value = withRepeat(withTiming(1, { duration: ms, easing: Easing.linear }), -1, false);
    } else cancelAnimation(shared);
  }, [active, reduce, ms, restart, shared]);
}

// ─── 1. Results arrive on their own ────────────────────────────────────────────

function ResultsDemo({ active }: { active: boolean }) {
  const accent = C.accentOf(false);
  return (
    <Entrance active={active}>
      <DemoCard>
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <View style={{ paddingHorizontal: 8, paddingVertical: 4, borderRadius: 8, backgroundColor: 'rgba(255, 255, 255, 0.18)' }}>
            <Text style={label('#fff')}>TFRRS</Text>
          </View>
          <View style={{ flex: 1, marginLeft: 12 }}>
            <Text numberOfLines={1} style={{ fontSize: 14, fontWeight: '700', color: '#fff' }}>
              MAC Outdoor Championships
            </Text>
            <Text style={{ fontSize: 13, color: 'rgba(255, 255, 255, 0.75)' }}>Long Jump · 6.91m</Text>
          </View>
        </View>
      </DemoCard>
      <SyncLine active={active} />
      <DemoCard solid>
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <Icon name="bolt" size={16} color={accent} />
          <Text style={[label(accent), { marginLeft: 4 }]}>NEW PR</Text>
        </View>
        <Text style={{ marginTop: 6, fontSize: 30, fontWeight: '800', letterSpacing: -1, color: '#111114' }}>6.91m</Text>
        <Text style={{ fontSize: 13, color: '#6E6E76' }}>Outdoor long jump · +0.12m</Text>
      </DemoCard>
      <View style={{ marginTop: 14, flexDirection: 'row', gap: 10 }}>
        <SeasonChip label="Indoor" mark="6.73m" solid={false} />
        <SeasonChip label="Outdoor" mark="6.91m" solid />
      </View>
    </Entrance>
  );
}

function SeasonChip({ label: text, mark, solid }: { label: string; mark: string; solid: boolean }) {
  const ink = solid ? C.accentOf(false) : '#fff';
  return (
    <View style={{ paddingHorizontal: 14, paddingVertical: 8, borderRadius: 100, backgroundColor: solid ? '#fff' : 'rgba(255, 255, 255, 0.14)' }}>
      <Text>
        <Text style={{ fontSize: 13, color: ink, opacity: 0.8 }}>{text}  </Text>
        <Text style={{ fontSize: 13, fontWeight: '800', color: ink }}>{mark}</Text>
      </Text>
    </View>
  );
}

/** A dotted line with a dot travelling down it: the nightly sync. */
function SyncLine({ active }: { active: boolean }) {
  const t = useSharedValue(0);
  useLoop(t, active, 1600);
  const dot = useAnimatedStyle(() => ({ transform: [{ translateY: 42 * easeInOutCubic(t.value) }] }));
  return (
    <View style={{ height: 50, flexDirection: 'row', alignItems: 'center' }}>
      <View style={{ width: 10, height: 50 }}>
        <Svg width={10} height={50}>
          {Array.from({ length: 6 }, (_, i) => (
            <Circle key={i} cx={5} cy={4 + i * 8} r={1.5} fill="rgba(255, 255, 255, 0.35)" />
          ))}
        </Svg>
        <Animated.View style={[{ position: 'absolute', left: 1, top: 0, width: 8, height: 8, borderRadius: 4, backgroundColor: '#fff' }, dot]} />
      </View>
      <Text style={{ marginLeft: 10, fontSize: 12, fontWeight: '600', color: 'rgba(255, 255, 255, 0.7)' }}>every night</Text>
    </View>
  );
}

// ─── 2. The leaderboard, live ─────────────────────────────────────────────────

type Sample = {
  name: string;
  gender: string;
  marks: Record<string, [string, number]>;
  gains: Record<string, number>;
  prCounts: Record<string, number>;
};

const samples: Sample[] = [
  { name: 'Maya Brooks', gender: 'F', marks: { Indoor: ['5.88m', 5.88], Outdoor: ['6.02m', 6.02] }, gains: { Indoor: 3.1, Outdoor: 4.6 }, prCounts: { Indoor: 2, Outdoor: 4 } },
  { name: 'Jordan Ellis', gender: 'M', marks: { Indoor: ['7.04m', 7.04], Outdoor: ['7.21m', 7.21] }, gains: { Indoor: 5.2, Outdoor: 1.8 }, prCounts: { Indoor: 4, Outdoor: 2 } },
  { name: 'Sam Okoro', gender: 'M', marks: { Indoor: ['6.73m', 6.73], Outdoor: ['6.91m', 6.91] }, gains: { Indoor: 2.4, Outdoor: 3.9 }, prCounts: { Indoor: 3, Outdoor: 3 } },
  { name: 'Ava Morales', gender: 'F', marks: { Indoor: ['5.61m', 5.61], Outdoor: ['5.70m', 5.70] }, gains: { Indoor: 6.0, Outdoor: 2.2 }, prCounts: { Indoor: 5, Outdoor: 1 } },
];

const rowH = 50;

function BoardDemo({ dark }: { dark: boolean }) {
  const [tab, setTab] = useState('Heat');
  const [season, setSeason] = useState('Outdoor');
  const [gender, setGender] = useState('All');
  const metric = (s: Sample) => (tab === 'Heat' ? s.gains[season] : tab === 'Rankings' ? s.marks[season][1] : s.prCounts[season]);
  const shown = samples.filter((s) => gender === 'All' || s.gender === gender).sort((a, b) => metric(b) - metric(a));
  const value = (s: Sample) =>
    tab === 'Heat' ? `+${s.gains[season].toFixed(1)}%` : tab === 'Rankings' ? s.marks[season][0] : `${s.prCounts[season]} PRs`;

  const height = useAnimatedStyle(() => ({ height: withTiming(rowH * shown.length, { duration: 380 }) }), [shown.length]);

  return (
    <View
      style={{
        width: 320,
        paddingHorizontal: 14,
        paddingTop: 14,
        paddingBottom: 10,
        borderRadius: 26,
        backgroundColor: C.bg(dark),
        boxShadow: '0 14px 30px rgba(0, 0, 0, 0.25)',
      }}
    >
      <SegmentToggle options={['Heat', 'Rankings', 'Trending']} value={tab} dark={dark} height={34} fontSize={12.5} fill onChange={setTab} />
      <View style={{ marginTop: 12, flexDirection: 'row', alignItems: 'center' }}>
        <Text numberOfLines={1} style={{ flex: 1, fontSize: 15, fontWeight: '800', letterSpacing: -0.3, color: C.text1(dark) }}>
          Long Jump
        </Text>
        <FilterPill
          dark={dark}
          height={36}
          groups={[
            { options: ['Indoor', 'Outdoor'], value: season, onChange: setSeason },
            { options: ['All', 'M', 'F'], value: gender, onChange: setGender },
          ]}
        />
      </View>
      {/* Rows glide to their new places when the order changes. */}
      <Animated.View style={[{ marginTop: 6 }, height]}>
        {samples.map((s) => (
          <BoardRow key={s.name} sample={s} place={shown.indexOf(s)} value={value(s)} dark={dark} />
        ))}
      </Animated.View>
    </View>
  );
}

function BoardRow({ sample, place, value, dark }: { sample: Sample; place: number; value: string; dark: boolean }) {
  const style = useAnimatedStyle(
    () => ({
      top: withTiming(rowH * Math.max(0, place), { duration: 460, easing: Easing.out(Easing.back(1.2)) }),
      opacity: withTiming(place >= 0 ? 1 : 0, { duration: 220 }),
    }),
    [place],
  );
  return (
    <Animated.View style={[{ position: 'absolute', left: 0, right: 0, height: rowH, flexDirection: 'row', alignItems: 'center' }, style]}>
      <Text style={{ width: 22, fontSize: 15, fontWeight: '800', color: place < 3 ? C.accentOf(dark) : C.text3(dark) }}>{place + 1}</Text>
      <InitialsAvatar name={sample.name} gender={sample.gender} dark={dark} size={34} />
      <Text style={{ flex: 1, marginLeft: 10, fontSize: 14.5, fontWeight: '600', color: C.text1(dark) }}>{sample.name}</Text>
      <Animated.Text key={value} entering={FadeIn.duration(200)} style={{ fontSize: 15, fontWeight: '800', color: C.accentOf(dark) }}>
        {value}
      </Animated.Text>
    </Animated.View>
  );
}

// ─── 3. Tap anyone: a looping demo of the profile card ─────────────────────────

const demoW = 210;
const demoH = 320;

function TapDemo({ active, dark }: { active: boolean; dark: boolean }) {
  const c = useSharedValue(0);
  useLoop(c, active, 6400, true);

  // 0 → 1 over [a, b] of the loop, shaped by a curve.
  const phase = (v: number, a: number, b: number, spring = false) => {
    'worklet';
    const t = Math.min(1, Math.max(0, (v - a) / (b - a)));
    return spring ? fluid(t) : easeInOutCubic(t);
  };

  // The card: hidden → peek (tap) → full (drag up) → gone (swipe down).
  const card = useAnimatedStyle(() => {
    const peek = phase(c.value, 0.2, 0.32, true);
    const full = phase(c.value, 0.42, 0.56, true);
    const gone = phase(c.value, 0.78, 0.88);
    return {
      top: demoH - demoH * 0.42 * peek - (demoH * 0.42 - 18) * full + (demoH + 20) * gone,
      left: 6 * (1 - full),
      right: 6 * (1 - full),
      borderRadius: 22 - 8 * full,
    };
  });
  const more = useAnimatedStyle(() => ({ opacity: Math.min(1, Math.max(0, phase(c.value, 0.42, 0.56, true))) }));
  const dim = useAnimatedStyle(() => ({
    opacity: 0.35 * phase(c.value, 0.2, 0.32, true) * (1 - phase(c.value, 0.78, 0.88)),
  }));
  const tappedRow = useAnimatedStyle(() => ({ opacity: c.value > 0.16 && c.value < 0.86 ? 1 : 0 }));

  // The finger: to the row, tap, to the card, drag up, swipe down.
  const finger = useAnimatedStyle(() => {
    const v = c.value;
    const toRow = phase(v, 0.04, 0.16);
    const toCard = phase(v, 0.34, 0.42);
    const drag = phase(v, 0.42, 0.56, true);
    const swipe = phase(v, 0.76, 0.88);
    let x = demoW * 0.8 + (demoW * 0.55 - demoW * 0.8) * toRow;
    let y = demoH * 0.95 + (108 - demoH * 0.95) * toRow;
    x = x + (demoW * 0.5 - x) * toCard;
    y = y + (demoH - demoH * 0.42 + 14 - y) * toCard;
    y = y - (demoH * 0.42 - 32) * drag + demoH * 0.5 * swipe;
    const pressed = (v > 0.16 && v < 0.2) || (v > 0.4 && v < 0.57) || (v > 0.74 && v < 0.88);
    return {
      left: x - 18,
      top: y - 18,
      opacity: v < 0.02 || v > 0.92 ? 0 : 1,
      transform: [{ scale: withTiming(pressed ? 0.82 : 1, { duration: 140 }) }],
    };
  });

  const names = ['Jordan Ellis', 'Sam Okoro', 'Maya Brooks', 'Ava Morales'];
  const marks = ['7.21m', '6.91m', '6.02m', '5.70m'];
  return (
    <View
      style={{
        width: demoW,
        height: demoH,
        borderRadius: 30,
        borderWidth: 3,
        borderColor: 'rgba(255, 255, 255, 0.5)',
        backgroundColor: C.bg(dark),
        overflow: 'hidden',
        boxShadow: '0 14px 30px rgba(0, 0, 0, 0.28)',
      }}
    >
      {/* The leaderboard underneath. */}
      <View style={{ paddingHorizontal: 14, paddingTop: 18 }}>
        <Text style={{ fontSize: 15, fontWeight: '900', color: C.text1(dark) }}>Leaderboard</Text>
        <View style={{ height: 14 }} />
        {names.map((name, i) => (
          <View key={name} style={{ height: 40, marginBottom: 4, paddingHorizontal: 6, flexDirection: 'row', alignItems: 'center' }}>
            {i === 1 && (
              <Animated.View style={[{ position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, borderRadius: 10, backgroundColor: C.surface2(dark) }, tappedRow]} />
            )}
            <InitialsAvatar name={name} gender={i >= 2 ? 'F' : 'M'} dark={dark} size={26} />
            <Text style={{ flex: 1, marginLeft: 8, fontSize: 12.5, fontWeight: '600', color: C.text1(dark) }}>{name}</Text>
            <Text style={{ fontSize: 12, fontWeight: '800', color: C.accentOf(dark) }}>{marks[i]}</Text>
          </View>
        ))}
      </View>
      {/* Dims as the card rises. */}
      <Animated.View pointerEvents="none" style={[{ position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, backgroundColor: '#000' }, dim]} />
      {/* The profile card. */}
      <Animated.View style={[{ position: 'absolute', height: demoH, backgroundColor: C.sheet(dark), paddingHorizontal: 14, paddingTop: 8 }, card]}>
        <View style={{ alignSelf: 'center', width: 30, height: 4, borderRadius: 2, backgroundColor: `${C.text3(dark)}80` }} />
        <View style={{ marginTop: 10, flexDirection: 'row', alignItems: 'center' }}>
          <View style={{ width: 34, height: 34, borderRadius: 17, backgroundColor: C.accentAlt, alignItems: 'center', justifyContent: 'center' }}>
            <Text style={{ fontSize: 12, fontWeight: '800', color: '#fff' }}>SO</Text>
          </View>
          <Text numberOfLines={1} style={{ marginLeft: 8, fontSize: 15, fontWeight: '800', color: C.text1(dark) }}>
            Sam Okoro
          </Text>
        </View>
        <Text style={[label(C.text3(dark)), { marginTop: 10 }]}>PERSONAL BEST</Text>
        <Text style={{ fontSize: 24, fontWeight: '800', letterSpacing: -0.8, color: C.accentOf(dark) }}>6.91m</Text>
        {/* More shows as the card opens up. */}
        <Animated.View style={[{ marginTop: 10 }, more]}>
          <View style={{ padding: 10, borderRadius: 12, backgroundColor: C.surface(dark), flexDirection: 'row', alignItems: 'center' }}>
            <Icon name="trending-up" size={16} color={C.accentOf(dark)} />
            <Text style={{ flex: 1, marginLeft: 6, fontSize: 11.5, fontWeight: '600', color: C.text1(dark) }}>Outdoor long jump is trending up</Text>
          </View>
          <Svg width={demoW - 28} height={60} style={{ marginTop: 10 }}>
            <Polyline
              points={[0.85, 0.6, 0.7, 0.4, 0.45, 0.15].map((y, i) => `${((demoW - 28) * i) / 5},${60 * y}`).join(' ')}
              fill="none"
              stroke={C.accentOf(dark)}
              strokeWidth={2.2}
              strokeLinecap="round"
              strokeLinejoin="round"
            />
            <Circle cx={demoW - 28} cy={60 * 0.15} r={3.5} fill={C.accentOf(dark)} />
          </Svg>
        </Animated.View>
      </Animated.View>
      {/* The finger. */}
      <Animated.View
        pointerEvents="none"
        style={[
          {
            position: 'absolute',
            width: 36,
            height: 36,
            borderRadius: 18,
            backgroundColor: 'rgba(255, 255, 255, 0.55)',
            borderWidth: 2,
            borderColor: '#fff',
            boxShadow: '0 0 10px rgba(0, 0, 0, 0.25)',
          },
          finger,
        ]}
      />
    </View>
  );
}

// ─── 4. Activity, rivals and maxes ─────────────────────────────────────────────

function LoopDemo({ active }: { active: boolean }) {
  const ink = '#111114';
  const soft = '#6E6E76';
  const accent = C.accentOf(false);
  return (
    <Entrance active={active}>
      <DemoCard solid>
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <RingingBell active={active} />
          <View style={{ flex: 1, marginLeft: 12 }}>
            <Text style={{ fontSize: 13.5, color: ink }}>
              <Text style={{ fontWeight: '800' }}>Maya Brooks</Text> PR'd in 400 Meters
            </Text>
            <Text style={{ fontSize: 12, color: soft }}>Outdoor · 58.40 · −0.62s</Text>
          </View>
        </View>
      </DemoCard>
      <View style={{ height: 12 }} />
      <DemoCard>
        <Text style={label('rgba(255, 255, 255, 0.85)')}>RIVAL</Text>
        <Text style={{ marginTop: 4, fontSize: 17, fontWeight: '800', letterSpacing: -0.3, color: '#fff' }}>0.12m behind Jordan Ellis</Text>
        <Text style={{ fontSize: 12, color: 'rgba(255, 255, 255, 0.75)' }}>Closest teammate in the outdoor triple jump</Text>
      </DemoCard>
      <View style={{ height: 12 }} />
      <DemoCard solid>
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <Icon name="fitness-center" size={20} color={accent} />
          <Text style={{ flex: 1, marginLeft: 12, fontSize: 15, fontWeight: '700', color: ink }}>Squat</Text>
          <Text style={{ fontSize: 17, fontWeight: '800', color: ink }}>315 lbs</Text>
          <View style={{ marginLeft: 8, paddingHorizontal: 8, paddingVertical: 3, borderRadius: 100, backgroundColor: 'rgba(200, 20, 15, 0.12)' }}>
            <Text style={{ fontSize: 12, fontWeight: '800', color: accent }}>+10</Text>
          </View>
        </View>
      </DemoCard>
    </Entrance>
  );
}

/** The bell with an unread badge, giving a little ring now and then. */
function RingingBell({ active }: { active: boolean }) {
  const c = useSharedValue(0);
  useLoop(c, active, 2400);
  const ring = useAnimatedStyle(() => {
    // A quick shake in the first quarter of each cycle, then still.
    const t = Math.min(1, c.value / 0.25);
    const angle = t >= 1 ? 0 : Math.sin(t * Math.PI * 6) * 0.35 * (1 - t);
    return { transform: [{ rotate: `${angle}rad` }], transformOrigin: 'top center' };
  });
  const accent = C.accentOf(false);
  return (
    <Animated.View style={[{ width: 34, height: 34, alignItems: 'center', justifyContent: 'center' }, ring]}>
      <Icon name="notifications" size={26} color={accent} />
      <View
        style={{
          position: 'absolute',
          right: -2,
          top: -2,
          width: 17,
          height: 17,
          borderRadius: 9,
          backgroundColor: accent,
          borderWidth: 2,
          borderColor: '#fff',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <Text style={{ fontSize: 9, fontWeight: '800', color: '#fff' }}>3</Text>
      </View>
    </Animated.View>
  );
}
