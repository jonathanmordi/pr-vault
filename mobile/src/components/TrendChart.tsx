import { useEffect, useMemo, useState } from 'react';
import { Text, View } from 'react-native';
import { GestureDetector, useCompetingGestures, usePanGesture } from 'react-native-gesture-handler';
import Animated, { Easing, useAnimatedProps, useSharedValue, withTiming } from 'react-native-reanimated';
import Svg, { Circle, ClipPath, Defs, G, Line, LinearGradient, Path, Rect, Stop } from 'react-native-svg';

import { formatChartFullDate, formatChartShortDate } from '@/lib/format';
import { haptic } from '@/lib/haptics';
import { C, alpha } from '@/theme/colors';

export type ChartPoint = { value: number; display: string; meetName: string; date: string };

const AnimatedRect = Animated.createAnimatedComponent(Rect);

const chartHeight = 140;
const topPad = 60;
const botPad = 10;
const totalH = topPad + chartHeight + botPad;

/** A progression line with touch-to-explore callouts. */
export function TrendChart({ points, isField, dark }: { points: ChartPoint[]; isField: boolean; dark: boolean }) {
  const [width, setWidth] = useState(0);
  const [active, setActive] = useState<number | null>(null);
  const reveal = useSharedValue(0);

  useEffect(() => {
    // Draw the line in from left to right on first show.
    reveal.value = withTiming(1, { duration: 700, easing: Easing.out(Easing.cubic) });
  }, [reveal]);

  const values = points.map((p) => p.value);
  const prValue = values.length === 0 ? 0 : isField ? Math.max(...values) : Math.min(...values);

  const positions = useMemo(() => {
    const minV = Math.min(...values);
    const maxV = Math.max(...values);
    const range = maxV - minV;
    return values.map((v, i) => {
      const x = points.length === 1 ? width / 2 : (i / (points.length - 1)) * width;
      const norm = range === 0 ? 0.5 : isField ? (v - minV) / range : 1 - (v - minV) / range;
      return { x, y: topPad + chartHeight - norm * chartHeight };
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [width, points, isField]);

  const clipProps = useAnimatedProps(() => ({ width: (width + 16) * reveal.value }));

  const update = (x: number) => {
    let closest = 0;
    let dist = Infinity;
    positions.forEach((p, i) => {
      const d = Math.abs(p.x - x);
      if (d < dist) {
        dist = d;
        closest = i;
      }
    });
    if (closest !== active) {
      haptic.selection();
      setActive(closest);
    }
  };

  // Horizontal drags scrub the chart; vertical ones still scroll the page.
  const drag = usePanGesture({
    runOnJS: true,
    activeOffsetX: [-8, 8],
    failOffsetY: [-10, 10],
    onActivate: (e) => update(e.x),
    onUpdate: (e) => update(e.x),
    onFinalize: () => setActive(null),
  });
  const hold = usePanGesture({
    runOnJS: true,
    activateAfterLongPress: 250,
    onActivate: (e) => update(e.x),
    onUpdate: (e) => update(e.x),
    onFinalize: () => setActive(null),
  });
  const gesture = useCompetingGestures(hold, drag);

  if (points.length < 2) {
    return (
      <View style={{ height: 120, alignItems: 'center', justifyContent: 'center' }}>
        <Text style={{ fontSize: 13, color: C.text3(dark) }}>Not enough data to chart</Text>
      </View>
    );
  }

  const prPoint = points[values.indexOf(prValue)];
  const accent = C.accentOf(dark);
  const prY = positions[values.indexOf(prValue)]?.y ?? 0;
  const line = positions.map((p, i) => `${i === 0 ? 'M' : 'L'}${p.x},${p.y}`).join(' ');
  const fill = positions.length
    ? `M${positions[0].x},${totalH} ${positions.map((p) => `L${p.x},${p.y}`).join(' ')} L${positions[positions.length - 1].x},${totalH} Z`
    : '';

  return (
    <View>
      <View style={{ flexDirection: 'row', alignItems: 'baseline' }}>
        <Text style={{ fontSize: 28, fontWeight: '700', color: accent, letterSpacing: -1 }}>{prPoint.display}</Text>
        <Text style={{ marginLeft: 8, fontSize: 13, fontWeight: '600', color: C.text3(dark) }}>PR</Text>
        <View style={{ flex: 1 }} />
        <Text style={{ fontSize: 12, color: C.text3(dark) }}>{points.length} results</Text>
      </View>
      <GestureDetector gesture={gesture}>
        <View style={{ height: 210, marginTop: 20 }} onLayout={(e) => setWidth(e.nativeEvent.layout.width)}>
          {width > 0 && (
            <Svg width={width} height={totalH} style={{ overflow: 'visible' }}>
              <Defs>
                <LinearGradient id="fill" x1="0" y1="0" x2="0" y2="1">
                  <Stop offset="0" stopColor={accent} stopOpacity={0.12} />
                  <Stop offset="1" stopColor={accent} stopOpacity={0} />
                </LinearGradient>
                <ClipPath id="reveal">
                  <AnimatedRect x={-8} y={-8} height={totalH + 16} animatedProps={clipProps} />
                </ClipPath>
              </Defs>
              <G clipPath="url(#reveal)">
                <Line x1={0} y1={prY} x2={width} y2={prY} stroke={alpha(accent, 0.3)} strokeWidth={1} strokeDasharray="6 4" />
                <Path d={fill} fill="url(#fill)" />
                <Path d={line} stroke={accent} strokeWidth={2.5} strokeLinecap="round" strokeLinejoin="round" fill="none" />
                {positions.map((p, i) => {
                  const isPr = values[i] === prValue;
                  const isActive = i === active;
                  const r = isActive ? 6 : isPr ? 5 : 3;
                  return (
                    <G key={i}>
                      {isActive && (
                        <Line x1={p.x} y1={0} x2={p.x} y2={totalH} stroke={dark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.12)'} strokeWidth={0.5} />
                      )}
                      <Circle
                        cx={p.x}
                        cy={p.y}
                        r={r}
                        fill={alpha(accent, isActive || isPr ? 1 : 0.5)}
                        stroke={isActive || isPr ? '#fff' : undefined}
                        strokeWidth={isActive || isPr ? 2.5 : 0}
                      />
                    </G>
                  );
                })}
              </G>
            </Svg>
          )}
          {active != null && active < points.length && (
            <Callout pos={positions[active]} point={points[active]} chartWidth={width} dark={dark} />
          )}
        </View>
      </GestureDetector>
      <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 4 }}>
        <Text style={{ fontSize: 10, color: C.text3(dark) }}>{formatChartShortDate(points[0].date)}</Text>
        <Text numberOfLines={1} style={{ flex: 1, textAlign: 'center', fontSize: 10, color: alpha(C.text3(dark), 0.6) }}>
          Touch and hold to explore
        </Text>
        <Text style={{ fontSize: 10, color: C.text3(dark) }}>{formatChartShortDate(points[points.length - 1].date)}</Text>
      </View>
    </View>
  );
}

function Callout({
  pos,
  point,
  chartWidth,
  dark,
}: {
  pos: { x: number; y: number };
  point: ChartPoint;
  chartWidth: number;
  dark: boolean;
}) {
  const w = 136;
  const h = 62;
  const tail = 7;
  const gap = 8;
  const left = Math.max(0, Math.min(chartWidth - w, pos.x - w / 2));
  const top = pos.y - h - tail - gap;
  const tailLeft = Math.max(14, Math.min(w - 14, pos.x - left)) - 6;
  const meet = point.meetName.length > 22 ? `${point.meetName.slice(0, 20)}…` : point.meetName;
  return (
    <View pointerEvents="none" style={{ position: 'absolute', left, top, width: w }}>
      <View
        style={{
          paddingHorizontal: 10,
          paddingVertical: 7,
          borderRadius: 10,
          backgroundColor: C.surface(dark),
          borderWidth: 0.5,
          borderColor: C.border(dark),
          boxShadow: '0 4px 16px rgba(0, 0, 0, 0.1)',
        }}
      >
        <Text style={{ fontSize: 16, fontWeight: '700', color: C.text1(dark) }}>{point.display}</Text>
        <Text numberOfLines={1} style={{ marginTop: 1, fontSize: 11, color: C.text2(dark) }}>{meet}</Text>
        <Text style={{ fontSize: 11, color: C.text3(dark) }}>{formatChartFullDate(point.date)}</Text>
      </View>
      <Svg width={w} height={tail} style={{ marginTop: -0.5 }}>
        <Path d={`M${tailLeft},0 L${tailLeft + 6},${tail} L${tailLeft + 12},0 Z`} fill={C.surface(dark)} />
        <Path d={`M${tailLeft},0 L${tailLeft + 6},${tail} L${tailLeft + 12},0`} stroke={C.border(dark)} strokeWidth={0.5} fill="none" />
      </Svg>
    </View>
  );
}
