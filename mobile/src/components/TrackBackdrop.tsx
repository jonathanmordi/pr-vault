import { LinearGradient } from 'expo-linear-gradient';
import { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import Animated, {
  Easing,
  cancelAnimation,
  useAnimatedProps,
  useReducedMotion,
  useSharedValue,
  withRepeat,
  withTiming,
} from 'react-native-reanimated';
import Svg, { Circle, G, Rect } from 'react-native-svg';

const AnimatedCircle = Animated.createAnimatedComponent(Circle);

const lanes = 6;
const laneWidth = 15;
const dots = 24;
const trail = 110;

/** A point [d] along a stadium (two straights joined by semicircles), clockwise from the top-left of the top straight. */
function pointOnStadium(d: number, cx: number, cy: number, straight: number, r: number) {
  'worklet';
  const arc = Math.PI * r;
  const length = 2 * straight + 2 * arc;
  let s = ((d % length) + length) % length;
  const left = cx - straight / 2;
  const right = cx + straight / 2;
  if (s < straight) return { x: left + s, y: cy - r };
  s -= straight;
  if (s < arc) {
    const a = -Math.PI / 2 + s / r;
    return { x: right + r * Math.cos(a), y: cy + r * Math.sin(a) };
  }
  s -= arc;
  if (s < straight) return { x: right - s, y: cy + r };
  s -= straight;
  const a = Math.PI / 2 + s / r;
  return { x: left + r * Math.cos(a), y: cy + r * Math.sin(a) };
}

/**
 * Red gradient with a running track drawn across it and a runner going round
 * the inside lane: the sign-in screen and the intro.
 */
export function TrackBackdrop({ dark }: { dark: boolean }) {
  const [size, setSize] = useState({ w: 0, h: 0 });
  const lap = useSharedValue(0);
  const reduce = useReducedMotion();

  useEffect(() => {
    if (reduce) return;
    lap.value = withRepeat(withTiming(1, { duration: 9000, easing: Easing.linear }), -1, false);
    return () => cancelAnimation(lap);
  }, [reduce, lap]);

  const colors = dark ? (['#6E0E0A', '#2A0604', '#000000'] as const) : (['#E8372D', '#C8140F', '#7E0A06'] as const);
  const { w, h } = size;
  const cx = w * 0.5;
  const cy = h * 0.34;
  const straight = w * 0.42;
  const inner = w * 0.2;
  const runnerR = inner + 1.5 * laneWidth;
  const length = 2 * straight + 2 * Math.PI * runnerR;

  return (
    <View style={StyleSheet.absoluteFill} onLayout={(e) => setSize({ w: e.nativeEvent.layout.width, h: e.nativeEvent.layout.height })}>
      <LinearGradient colors={colors} start={{ x: 1, y: 0 }} end={{ x: 0, y: 1 }} style={StyleSheet.absoluteFill} />
      {w > 0 && (
        <Svg width={w} height={h} style={StyleSheet.absoluteFill}>
          <G rotation={(-0.5 * 180) / Math.PI} origin={`${cx}, ${cy}`}>
            {Array.from({ length: lanes + 1 }, (_, i) => {
              const r = inner + i * laneWidth;
              return (
                <Rect
                  key={i}
                  x={cx - straight / 2 - r}
                  y={cy - r}
                  width={straight + 2 * r}
                  height={2 * r}
                  rx={r}
                  fill="none"
                  stroke="rgba(255, 255, 255, 0.11)"
                  strokeWidth={1.2}
                />
              );
            })}
            {/* The runner, in lane two, with a fading trail behind. */}
            {Array.from({ length: dots }, (_, i) => {
              const k = dots - i;
              const fade = 1 - k / dots;
              return (
                <TrailDot key={k} lap={lap} behind={(trail * k) / dots} length={length} cx={cx} cy={cy} straight={straight} r={runnerR} radius={1 + 2.2 * fade} opacity={0.5 * fade} />
              );
            })}
            <TrailDot lap={lap} behind={0} length={length} cx={cx} cy={cy} straight={straight} r={runnerR} radius={9} opacity={0.18} />
            <TrailDot lap={lap} behind={0} length={length} cx={cx} cy={cy} straight={straight} r={runnerR} radius={4} opacity={1} />
          </G>
        </Svg>
      )}
    </View>
  );
}

function TrailDot({
  lap,
  behind,
  length,
  cx,
  cy,
  straight,
  r,
  radius,
  opacity,
}: {
  lap: { value: number };
  behind: number;
  length: number;
  cx: number;
  cy: number;
  straight: number;
  r: number;
  radius: number;
  opacity: number;
}) {
  const props = useAnimatedProps(() => {
    const p = pointOnStadium(lap.value * length - behind, cx, cy, straight, r);
    return { cx: p.x, cy: p.y };
  });
  return <AnimatedCircle animatedProps={props} r={radius} fill={`rgba(255, 255, 255, ${opacity})`} />;
}
