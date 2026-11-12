import { useEffect, useRef, useState } from 'react';
import { LayoutChangeEvent, Text, View } from 'react-native';
import {
  GestureDetector,
  useCompetingGestures,
  usePanGesture,
  useTapGesture,
} from 'react-native-gesture-handler';
import Animated, { Easing, useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';

import { haptic } from '@/lib/haptics';
import { C } from '@/theme/colors';

/**
 * Pick-one pill control. Tap a segment, or press and slide: the thumb follows
 * your finger and the segment under it is picked when you let go.
 *
 * Every segment is as wide as the widest label, so 'All' doesn't get more
 * room than 'M' or 'F'. With [fill] the control stretches to its parent's
 * width instead.
 */
export function SegmentToggle({
  options,
  value,
  dark,
  onChange,
  height = 30,
  fontSize = 12,
  fill = false,
  testID,
}: {
  options: string[];
  value: string;
  dark: boolean;
  onChange: (v: string) => void;
  /** 30 for compact switches; 40 for a screen's main tabs. */
  height?: number;
  fontSize?: number;
  fill?: boolean;
  testID?: string;
}) {
  const n = options.length;
  const index = Math.max(0, Math.min(n - 1, options.indexOf(value)));
  const [width, setWidth] = useState(0);
  const [labelW, setLabelW] = useState(0);
  const [hover, setHover] = useState<number | null>(null);
  const sliding = useSharedValue(0);
  const at = useSharedValue(n > 1 ? index / (n - 1) : 0.5);

  // Latest values for gesture callbacks.
  const live = useRef({ width, n, value, options, onChange, hover });
  live.current = { width, n, value, options, onChange, hover };

  const rest = n > 1 ? index / (n - 1) : 0.5;
  useEffect(() => {
    at.value = withTiming(rest, { duration: 320, easing: Easing.out(Easing.back(1.6)) });
  }, [rest, at]);

  // Each label's natural width, to size every segment like the widest.
  const measured = useRef(new Map<number, number>());

  const indexAt = (x: number) => {
    const { width: w, n: count } = live.current;
    return Math.max(0, Math.min(count - 1, Math.floor((x / Math.max(w, 1)) * count)));
  };
  const fractionAt = (x: number) => {
    const { width: w, n: count } = live.current;
    if (count < 2) return 0;
    const segment = w / count;
    return Math.max(0, Math.min(1, (x - segment / 2) / (w - segment)));
  };
  const pick = (i: number) => {
    const { options: opts, value: v, onChange: change } = live.current;
    if (opts[i] !== v) change(opts[i]);
  };

  const startSlide = (x: number) => {
    haptic.light();
    sliding.value = withTiming(1, { duration: 200 });
    at.value = fractionAt(x);
    setHover(indexAt(x));
  };
  const moveSlide = (x: number) => {
    const i = indexAt(x);
    if (i !== live.current.hover) haptic.selection();
    at.value = fractionAt(x);
    setHover(i);
  };
  const endSlide = () => {
    const i = live.current.hover;
    sliding.value = withTiming(0, { duration: 200 });
    setHover(null);
    if (i != null) {
      const { n: count } = live.current;
      at.value = withTiming(count > 1 ? i / (count - 1) : 0.5, { duration: 320, easing: Easing.out(Easing.back(1.6)) });
      pick(i);
    }
  };

  const tap = useTapGesture({
    runOnJS: true,
    onActivate: (e) => {
      const i = indexAt(e.x);
      if (live.current.options[i] === live.current.value) return;
      haptic.selection();
      pick(i);
    },
  });
  const drag = usePanGesture({
    runOnJS: true,
    activeOffsetX: [-6, 6],
    failOffsetY: [-14, 14],
    onActivate: (e) => startSlide(e.x),
    onUpdate: (e) => moveSlide(e.x),
    onFinalize: () => endSlide(),
  });
  const hold = usePanGesture({
    runOnJS: true,
    activateAfterLongPress: 300,
    onActivate: (e) => startSlide(e.x),
    onUpdate: (e) => moveSlide(e.x),
    onFinalize: () => endSlide(),
  });
  const gesture = useCompetingGestures(hold, drag, tap);

  const segW = width / Math.max(n, 1);
  const thumb = useAnimatedStyle(() => ({
    width: segW,
    transform: [{ translateX: at.value * (width - segW) }, { scale: 1 + 0.12 * sliding.value }],
  }));

  const shown = hover ?? index;
  const fixedSegment = !fill && labelW > 0 ? labelW + 24 : undefined;

  return (
    <View
      testID={testID}
      style={{
        height,
        padding: 3,
        borderRadius: 100,
        backgroundColor: C.surface2(dark),
        alignSelf: fill ? 'stretch' : 'flex-start',
      }}
    >
      <GestureDetector gesture={gesture}>
        <View
          style={{ flex: 1, flexDirection: 'row' }}
          onLayout={(e: LayoutChangeEvent) => setWidth(e.nativeEvent.layout.width)}
          accessibilityRole="tablist"
        >
          {width > 0 && (
            <Animated.View
              pointerEvents="none"
              style={[{ position: 'absolute', top: 0, bottom: 0, left: 0, borderRadius: 100, backgroundColor: C.accentOf(dark) }, thumb]}
            />
          )}
          {options.map((o, i) => (
            <View
              key={o}
              accessibilityRole="tab"
              accessibilityState={{ selected: i === index }}
              accessibilityLabel={o}
              style={[
                { alignItems: 'center', justifyContent: 'center', paddingHorizontal: 12 },
                fill || fixedSegment == null ? { flex: fill ? 1 : undefined } : { width: fixedSegment, paddingHorizontal: 0 },
              ]}
            >
              <Text
                numberOfLines={1}
                onLayout={(e) => {
                  if (fill || fixedSegment != null) return;
                  measured.current.set(i, e.nativeEvent.layout.width);
                  if (measured.current.size === n) setLabelW(Math.ceil(Math.max(...measured.current.values())));
                }}
                style={{ fontSize, fontWeight: '600', color: shown === i ? '#fff' : C.text3(dark) }}
              >
                {o}
              </Text>
            </View>
          ))}
        </View>
      </GestureDetector>
    </View>
  );
}
