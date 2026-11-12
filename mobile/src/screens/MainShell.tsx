import { BlurView } from 'expo-blur';
import { Stack } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Keyboard, StyleSheet, Text, View } from 'react-native';
import { GestureDetector, useCompetingGestures, usePanGesture, useTapGesture } from 'react-native-gesture-handler';
import Animated, { Easing, useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';

import { kSpring } from '@/components/motion';
import { Icon, IconName } from '@/components/ui';
import { haptic } from '@/lib/haptics';
import { C, useDark } from '@/theme/colors';

import { SheetBackdrop } from './athleteSheet';
import { Leaderboard } from './Leaderboard';
import { Maxes } from './Maxes';
import { MyProfile } from './MyProfile';
import { Settings } from './Settings';

const items: { icon: IconName; activeIcon: IconName; label: string }[] = [
  { icon: 'leaderboard', activeIcon: 'leaderboard', label: 'Leaderboard' },
  { icon: 'person-outline', activeIcon: 'person', label: 'Profile' },
  { icon: 'fitness-center', activeIcon: 'fitness-center', label: 'Maxes' },
  { icon: 'settings', activeIcon: 'settings', label: 'Settings' },
];

const screens = [Leaderboard, MyProfile, Maxes, Settings];

/** Hosts the tabs with the floating bottom nav. */
export function MainShell() {
  const dark = useDark();
  const [current, setCurrent] = useState(0);
  // Tabs are built the first time they're opened and then kept alive, so
  // switching back is instant instead of refetching behind a spinner.
  const [visited, setVisited] = useState(() => new Set([0]));

  const select = (i: number) => {
    if (i === current) return;
    haptic.selection();
    Keyboard.dismiss();
    setCurrent(i);
    setVisited((v) => new Set(v).add(i));
  };

  return (
    <SheetBackdrop>
      {/* Back from the intro's light status bar, which shares this route. */}
      <Stack.Screen options={{ statusBarStyle: dark ? 'light' : 'dark' }} />
      <View style={{ flex: 1, backgroundColor: C.bg(dark) }}>
        {screens.map((Screen, i) => (
          <TabPage key={i} active={i === current}>
            {visited.has(i) ? <Screen /> : null}
          </TabPage>
        ))}
        <View style={{ position: 'absolute', left: 24, right: 24, bottom: 32 }}>
          <FloatingNav current={current} onSelect={select} dark={dark} />
        </View>
      </View>
    </SheetBackdrop>
  );
}

/** Cross-fades between tabs. Hidden tabs keep their state but don't take taps. */
function TabPage({ active, children }: { active: boolean; children: React.ReactNode }) {
  const style = useAnimatedStyle(() => ({ opacity: withTiming(active ? 1 : 0, { duration: 200, easing: Easing.out(Easing.quad) }) }), [active]);
  return (
    <Animated.View pointerEvents={active ? 'auto' : 'none'} style={[StyleSheet.absoluteFill, style]} accessibilityElementsHidden={!active} importantForAccessibility={active ? 'auto' : 'no-hide-descendants'}>
      {children}
    </Animated.View>
  );
}

/** Gap between the bar's edge and the highlight. */
const inset = 6;

/**
 * Pill-shaped tab bar. Tap a tab, or press and slide along the bar: the
 * highlight follows your finger and the tab under it opens when you let go.
 */
function FloatingNav({ current, onSelect, dark }: { current: number; onSelect: (i: number) => void; dark: boolean }) {
  const [width, setWidth] = useState(0);
  const [hover, setHover] = useState<number | null>(null);
  const slot = (width - inset * 2) / items.length;
  const x = useSharedValue(0);
  const sliding = useSharedValue(0);

  const indexAt = (px: number) => Math.max(0, Math.min(items.length - 1, Math.floor((px - inset) / slot)));
  const restAt = (i: number) => inset + slot * i;
  const settle = (i: number) => {
    x.value = withTiming(restAt(i), { duration: 380, easing: Easing.out(Easing.back(1.4)) });
  };
  const placed = useRef(false);
  useEffect(() => {
    if (width === 0) return;
    // Rests on the open tab; the first time without animating.
    if (placed.current) settle(current);
    else x.value = restAt(current);
    placed.current = true;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [current, width]);

  const start = (px: number) => {
    haptic.light();
    sliding.value = withTiming(1, { duration: 220, easing: kSpring });
    x.value = Math.max(inset, Math.min(width - inset - slot, px - slot / 2));
    setHover(indexAt(px));
  };
  const move = (px: number) => {
    const i = indexAt(px);
    if (i !== hover) haptic.selection();
    x.value = Math.max(inset, Math.min(width - inset - slot, px - slot / 2));
    setHover(i);
  };
  const end = () => {
    const i = hover;
    sliding.value = withTiming(0, { duration: 220, easing: kSpring });
    setHover(null);
    if (i != null) {
      settle(i);
      onSelect(i);
    } else settle(current);
  };

  const tap = useTapGesture({ runOnJS: true, onActivate: (e) => onSelect(indexAt(e.x)) });
  const drag = usePanGesture({ runOnJS: true, activeOffsetX: [-6, 6], onActivate: (e) => start(e.x), onUpdate: (e) => move(e.x), onFinalize: end });
  const hold = usePanGesture({ runOnJS: true, activateAfterLongPress: 300, onActivate: (e) => start(e.x), onUpdate: (e) => move(e.x), onFinalize: end });
  const gesture = useCompetingGestures(hold, drag, tap);

  const highlight = useAnimatedStyle(() => ({
    left: x.value,
    width: slot,
    transform: [{ scale: 1 + 0.08 * sliding.value }],
  }));
  const bar = useAnimatedStyle(() => ({ transform: [{ scale: 1 + 0.03 * sliding.value }] }));
  const shown = hover ?? current;

  return (
    <Animated.View
      style={[
        { borderRadius: 32, boxShadow: `0 8px 24px rgba(0, 0, 0, ${dark ? 0.35 : 0.08})` },
        bar,
      ]}
    >
      {/* Nearly solid, with a touch of blur at the edges of what scrolls under. */}
      <View style={{ borderRadius: 32, overflow: 'hidden' }}>
        <BlurView intensity={60} tint={dark ? 'dark' : 'light'} style={StyleSheet.absoluteFill} />
        <GestureDetector gesture={gesture}>
          <View
            onLayout={(e) => setWidth(e.nativeEvent.layout.width)}
            accessibilityRole="tablist"
            style={{
              height: 64,
              borderRadius: 32,
              backgroundColor: dark ? 'rgba(28, 28, 30, 0.95)' : 'rgba(255, 255, 255, 0.95)',
              borderWidth: 0.5,
              borderColor: dark ? 'rgba(255, 255, 255, 0.10)' : 'rgba(0, 0, 0, 0.06)',
              flexDirection: 'row',
              paddingHorizontal: inset,
            }}
          >
            {width > 0 && (
              <Animated.View
                pointerEvents="none"
                style={[{ position: 'absolute', top: inset, bottom: inset, borderRadius: 100, backgroundColor: C.accentSoft(dark) }, highlight]}
              />
            )}
            {items.map((item, i) => (
              <NavItem key={item.label} {...item} active={shown === i} dark={dark} />
            ))}
          </View>
        </GestureDetector>
      </View>
    </Animated.View>
  );
}

/** Icon and label for one tab. Taps are handled by the bar. */
function NavItem({ icon, activeIcon, label, active, dark }: { icon: IconName; activeIcon: IconName; label: string; active: boolean; dark: boolean }) {
  const color = active ? C.accentOf(dark) : C.text3(dark);
  const pop = useAnimatedStyle(() => ({ transform: [{ scale: withTiming(active ? 1.08 : 1, { duration: 250, easing: kSpring }) }] }), [active]);
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }} accessibilityRole="tab" accessibilityLabel={label} accessibilityState={{ selected: active }}>
      <Animated.View style={pop}>
        <Icon name={active ? activeIcon : icon} size={22} color={color} />
      </Animated.View>
      <Text numberOfLines={1} style={{ marginTop: 4, fontSize: 10, fontWeight: active ? '600' : '400', color }}>
        {label}
      </Text>
    </View>
  );
}
