import { ComponentRef, useEffect, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import {
  GestureDetector,
  useCompetingGestures,
  usePanGesture,
  useTapGesture,
} from 'react-native-gesture-handler';
import Animated, {
  SharedValue,
  interpolate,
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withSpring,
  withTiming,
} from 'react-native-reanimated';

import { haptic } from '@/lib/haptics';
import { C } from '@/theme/colors';

import { usePortal } from './overlay';
import { Icon } from './ui';

/** One column of a FilterPill: pick one of [options]. */
export type FilterGroup = {
  options: string[];
  value: string;
  onChange: (v: string) => void;
};

const pad = 3;
const gap = 4;
const labelStyle = { fontSize: 13, fontWeight: '700' } as const;

// Opening overshoots a touch; closing settles without a bounce.
const openSpring = { mass: 1, stiffness: 420, damping: 32 };
const closeSpring = { mass: 1, stiffness: 520, damping: 46 };

type Layout = { closed: number; open: number; columns: number[] };

/**
 * Filters folded into one pill that reads like "Outdoor · All". Tap it and it
 * springs open downward into a column per filter, the highlight splitting
 * into one per column. Tap a choice, or press and slide down and let go on
 * one; it folds back up shortly after a pick, or when you tap anywhere else.
 */
export function FilterPill({
  groups,
  dark,
  height = 42,
  testID,
}: {
  groups: FilterGroup[];
  dark: boolean;
  height?: number;
  testID?: string;
}) {
  const row = height - 2 * pad;
  const [widths, setWidths] = useState<Record<string, number>>({});
  const [open, setOpen] = useState(false);
  const [anchor, setAnchor] = useState<{ x: number; y: number } | null>(null);
  const [picked, setPicked] = useState<Record<number, number>>({});
  const [slideColumn, setSlideColumn] = useState<number | null>(null);
  const t = useSharedValue(0);
  const pressed = useSharedValue(0);
  const rows = [useSharedValue(0), useSharedValue(0), useSharedValue(0)];
  const pill = useRef<ComponentRef<typeof View>>(null);
  const autoClose = useRef<ReturnType<typeof setTimeout> | null>(null);
  const slideRow = useRef<number | null>(null);
  const fromClosed = useRef(false);

  // A new value from the parent replaces the one just picked.
  const valuesKey = groups.map((g) => g.value).join('|');
  useEffect(() => setPicked({}), [valuesKey]);

  const selected = (c: number) => {
    const g = groups[c];
    return picked[c] ?? Math.max(0, g.options.indexOf(g.value));
  };

  // Highlights rest on their choice unless a finger is sliding them.
  useEffect(() => {
    groups.forEach((_, c) => {
      if (c !== slideColumn) rows[c].value = withTiming(selected(c), { duration: 420 });
    });
  });

  const allLabels = [...new Set([...groups.flatMap((g) => g.options), ' · '])];
  const measured = allLabels.every((l) => widths[l] != null);
  const layout: Layout | null = measured ? computeLayout(groups, widths) : null;

  const live = useRef({ groups, layout, picked });
  live.current = { groups, layout, picked };

  const show = () => {
    if (autoClose.current) clearTimeout(autoClose.current);
    pill.current?.measureInWindow((x, y) => {
      setAnchor({ x, y });
      setOpen(true);
      t.value = withSpring(1, openSpring);
    });
  };

  const hide = () => {
    if (autoClose.current) clearTimeout(autoClose.current);
    t.value = withSpring(0, closeSpring, (done) => {
      if (done) runOnJS(closeNow)();
    });
  };
  const closeNow = () => setOpen(false);

  const columnAt = (dx: number) => {
    const l = live.current.layout;
    if (!l) return 0;
    let x = pad;
    for (let c = 0; c < l.columns.length; c++) {
      x += l.columns[c] + gap;
      if (dx < x - gap / 2) return c;
    }
    return l.columns.length - 1;
  };
  const rowAt = (c: number, dy: number) => {
    const last = live.current.groups[c].options.length - 1;
    return Math.max(0, Math.min(last, (dy - pad - row / 2) / row));
  };

  const pick = (c: number, r: number) => {
    const g = live.current.groups[c];
    if (r !== selected(c)) {
      haptic.selection();
      setPicked((p) => ({ ...p, [c]: r }));
      rows[c].value = withTiming(r, { duration: 420 });
      g.onChange(g.options[r]);
    }
    // Fold up once the highlight has settled, unless another choice comes.
    if (autoClose.current) clearTimeout(autoClose.current);
    autoClose.current = setTimeout(hide, fromClosed.current ? 260 : 700);
    fromClosed.current = false;
  };

  const startSlide = (x: number, y: number, closed: boolean) => {
    haptic.light();
    if (autoClose.current) clearTimeout(autoClose.current);
    fromClosed.current = closed;
    const c = columnAt(x);
    const r = rowAt(c, y);
    setSlideColumn(c);
    slideRow.current = r;
    rows[c].value = r;
    if (closed) show();
  };
  const slideTo = (y: number, c: number | null) => {
    if (c == null) return;
    const r = rowAt(c, y);
    if (slideRow.current != null && Math.round(slideRow.current) !== Math.round(r)) haptic.selection();
    slideRow.current = r;
    rows[c].value = r;
  };
  const endSlide = (c: number | null) => {
    const r = slideRow.current;
    setSlideColumn(null);
    slideRow.current = null;
    if (c != null && r != null) pick(c, Math.round(r));
  };

  // On the closed pill: tap opens; slide or hold-and-slide opens and picks.
  const shift = layout ? layout.open - layout.closed : 0;
  const slideColumnRef = useRef<number | null>(null);
  slideColumnRef.current = slideColumn;
  const closedTap = useTapGesture({
    runOnJS: true,
    onBegin: () => (pressed.value = withTiming(1, { duration: 120 })),
    onActivate: () => {
      haptic.selection();
      show();
    },
    onFinalize: () => (pressed.value = withTiming(0, { duration: 180 })),
  });
  const closedDrag = usePanGesture({
    runOnJS: true,
    activeOffsetY: [-4, 4],
    onActivate: (e) => startSlide(e.x + shift, e.y, true),
    onUpdate: (e) => slideTo(e.y, slideColumnRef.current ?? columnAt(e.x + shift)),
    onFinalize: () => endSlide(slideColumnRef.current),
  });
  const closedHold = usePanGesture({
    runOnJS: true,
    activateAfterLongPress: 300,
    onActivate: (e) => startSlide(e.x + shift, e.y, true),
    onUpdate: (e) => slideTo(e.y, slideColumnRef.current ?? columnAt(e.x + shift)),
    onFinalize: () => endSlide(slideColumnRef.current),
  });
  const closedGesture = useCompetingGestures(closedHold, closedDrag, closedTap);

  // On the open panel, in the open layout's coordinates.
  const openTap = useTapGesture({
    runOnJS: true,
    onBegin: () => autoClose.current && clearTimeout(autoClose.current),
    onActivate: (e) => {
      const c = columnAt(e.x);
      const n = live.current.groups[c].options.length;
      pick(c, Math.max(0, Math.min(n - 1, Math.floor((e.y - pad) / row))));
    },
  });
  const openDrag = usePanGesture({
    runOnJS: true,
    activeOffsetY: [-4, 4],
    onActivate: (e) => startSlide(e.x, e.y, false),
    onUpdate: (e) => slideTo(e.y, slideColumnRef.current),
    onFinalize: () => endSlide(slideColumnRef.current),
  });
  const openGesture = useCompetingGestures(openDrag, openTap);

  const summary = groups.map((g, c) => g.options[selected(c)]).join(' · ');
  const pressStyle = useAnimatedStyle(() => ({ transform: [{ scale: 1 - 0.05 * pressed.value }] }));

  usePortal(
    open && anchor != null && layout != null,
    layout && anchor ? (
      <>
        <Pressable style={StyleSheet.absoluteFill} onPress={hide} accessibilityLabel="Close filters" />
        <OpenPanel
          t={t}
          rows={rows}
          layout={layout}
          anchor={anchor}
          height={height}
          row={row}
          dark={dark}
          groups={groups}
          selected={selected}
          slideColumn={slideColumn}
          gesture={openGesture}
        />
      </>
    ) : null,
  );

  return (
    <View testID={testID}>
      {/* Hidden copies of every label, to size the pill. */}
      <View style={styles.measure} pointerEvents="none">
        {allLabels.map((l) => (
          <Text
            key={l}
            style={labelStyle}
            onLayout={(e) => {
              const w = e.nativeEvent.layout.width;
              setWidths((ws) => (ws[l] === w ? ws : { ...ws, [l]: w }));
            }}
          >
            {l}
          </Text>
        ))}
      </View>
      <GestureDetector gesture={closedGesture}>
        <Animated.View
          ref={pill}
          accessibilityRole="button"
          accessibilityLabel={summary}
          style={[
            {
              width: layout?.closed,
              height,
              borderRadius: height / 2,
              backgroundColor: C.surface2(dark),
              padding: pad,
              opacity: open ? 0 : 1,
            },
            pressStyle,
          ]}
        >
          <View
            style={{
              flex: 1,
              borderRadius: row / 2,
              backgroundColor: C.accentOf(dark),
              flexDirection: 'row',
              alignItems: 'center',
              justifyContent: 'center',
              paddingHorizontal: 8,
            }}
          >
            <Text numberOfLines={1} style={[labelStyle, { color: '#fff' }]}>
              {summary}
            </Text>
            <Icon name="keyboard-arrow-down" size={16} color="#fff" />
          </View>
        </Animated.View>
      </GestureDetector>
    </View>
  );
}

function computeLayout(groups: FilterGroup[], widths: Record<string, number>): Layout {
  const widest = groups.map((g) => Math.max(...g.options.map((o) => widths[o] ?? 0)));
  const columns = widest.map((w) => w + 28);
  const summary = widest.reduce((a, b) => a + b, 0) + (widths[' · '] ?? 0) * (groups.length - 1);
  const closed = Math.ceil(2 * pad + 24 + summary + 18);
  let open = 2 * pad + columns.reduce((a, b) => a + b, 0) + gap * (columns.length - 1);
  if (open < closed) {
    const extra = (closed - open) / columns.length;
    for (let i = 0; i < columns.length; i++) columns[i] += extra;
    open = closed;
  }
  return { closed, open, columns };
}

function OpenPanel({
  t,
  rows,
  layout,
  anchor,
  height,
  row,
  dark,
  groups,
  selected,
  slideColumn,
  gesture,
}: {
  t: SharedValue<number>;
  rows: SharedValue<number>[];
  layout: Layout;
  anchor: { x: number; y: number };
  height: number;
  row: number;
  dark: boolean;
  groups: FilterGroup[];
  selected: (c: number) => number;
  slideColumn: number | null;
  gesture: ReturnType<typeof useCompetingGestures>;
}) {
  const maxRows = Math.max(1, ...groups.map((g) => g.options.length));
  const openH = 2 * pad + row * maxRows;
  const right = anchor.x + layout.closed;

  const frame = useAnimatedStyle(() => {
    const w = layout.closed + (layout.open - layout.closed) * t.value;
    const shown = Math.min(1, Math.max(0, t.value));
    return {
      left: right - w,
      width: w,
      height: height + (openH - height) * t.value,
      borderRadius: height / 2 - 3 * shown,
      boxShadow: `0 ${12 * shown}px 28px rgba(0, 0, 0, ${(dark ? 0.5 : 0.16) * shown})`,
    };
  });

  // The closed highlight, in the open layout's coordinates.
  const closedX = layout.open - layout.closed + pad;
  const cellX = (c: number) => {
    let x = pad;
    for (let i = 0; i < c; i++) x += layout.columns[i] + gap;
    return x;
  };

  const summaryStyle = useAnimatedStyle(() => ({ opacity: Math.max(0, Math.min(1, 1 - t.value * 2.5)) }));

  return (
    <Animated.View
      style={[
        { position: 'absolute', top: anchor.y, overflow: 'hidden', backgroundColor: C.surface2(dark) },
        frame,
      ]}
    >
      <GestureDetector gesture={gesture}>
        <View style={{ position: 'absolute', right: 0, top: 0, width: layout.open, height: openH }}>
          {groups.map((_, c) => (
            <Thumb
              key={`thumb${c}`}
              t={t}
              rowValue={rows[c]}
              from={{ x: closedX, w: layout.closed - 2 * pad }}
              to={{ x: cellX(c), w: layout.columns[c] }}
              row={row}
              lifted={slideColumn === c}
              dark={dark}
            />
          ))}
          <Animated.View
            pointerEvents="none"
            style={[
              {
                position: 'absolute',
                left: closedX,
                top: pad,
                width: layout.closed - 2 * pad,
                height: row,
                flexDirection: 'row',
                alignItems: 'center',
                justifyContent: 'center',
              },
              summaryStyle,
            ]}
          >
            <Text numberOfLines={1} style={[labelStyle, { color: '#fff' }]}>
              {groups.map((g, c) => g.options[selected(c)]).join(' · ')}
            </Text>
            <Icon name="keyboard-arrow-down" size={16} color="#fff" />
          </Animated.View>
          {groups.map((g, c) =>
            g.options.map((o, r) => (
              <Choice
                key={`${c}:${o}`}
                t={t}
                r={r}
                label={o}
                on={selected(c) === r && slideColumn !== c}
                rowValue={rows[c]}
                x={cellX(c)}
                width={layout.columns[c]}
                row={row}
                dark={dark}
              />
            )),
          )}
        </View>
      </GestureDetector>
    </Animated.View>
  );
}

function Thumb({
  t,
  rowValue,
  from,
  to,
  row,
  lifted,
  dark,
}: {
  t: SharedValue<number>;
  rowValue: SharedValue<number>;
  from: { x: number; w: number };
  to: { x: number; w: number };
  row: number;
  lifted: boolean;
  dark: boolean;
}) {
  const style = useAnimatedStyle(() => {
    const p = t.value;
    const top = pad + (rowValue.value * row) * p;
    return {
      left: from.x + (to.x - from.x) * p,
      width: from.w + (to.w - from.w) * p,
      top,
      transform: [{ scale: withTiming(lifted ? 1.06 : 1, { duration: 220 }) }],
    };
  });
  return (
    <Animated.View
      pointerEvents="none"
      style={[{ position: 'absolute', height: row, borderRadius: row / 2, backgroundColor: C.accentOf(dark) }, style]}
    />
  );
}

function Choice({
  t,
  r,
  label,
  rowValue,
  x,
  width,
  row,
  dark,
}: {
  t: SharedValue<number>;
  r: number;
  label: string;
  on: boolean;
  rowValue: SharedValue<number>;
  x: number;
  width: number;
  row: number;
  dark: boolean;
}) {
  // The choices fade in a row at a time; the one under the highlight is white.
  const box = useAnimatedStyle(() => {
    const shown = Math.min(1, Math.max(0, t.value));
    const o = Math.max(0, Math.min(1, (shown - 0.35 - 0.08 * r) / 0.4));
    return { opacity: o, transform: [{ translateY: (1 - o) * -6 }] };
  });
  const white = useAnimatedStyle(() => ({ opacity: interpolate(Math.abs(rowValue.value - r), [0, 0.5], [1, 0], 'clamp') }));
  return (
    <Animated.View
      pointerEvents="none"
      accessibilityRole="button"
      accessibilityLabel={label}
      style={[{ position: 'absolute', left: x, top: pad + row * r, width, height: row, alignItems: 'center', justifyContent: 'center' }, box]}
    >
      <Text style={[labelStyle, { color: C.text2(dark) }]}>{label}</Text>
      <Animated.Text style={[labelStyle, { color: '#fff', position: 'absolute' }, white]}>{label}</Animated.Text>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  measure: { position: 'absolute', opacity: 0, flexDirection: 'row', alignItems: 'flex-start', left: -1000 },
});
