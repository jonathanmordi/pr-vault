import { ComponentRef, ReactNode, useEffect, useRef, useState } from 'react';
import { Text, View } from 'react-native';
import Animated, { Easing, useAnimatedStyle, useSharedValue, withDelay, withTiming } from 'react-native-reanimated';
import Svg, { Path } from 'react-native-svg';

import { kv } from '@/lib/kv';
import { useDark } from '@/theme/colors';

import { useOverlay, usePortal } from './overlay';

/**
 * A small bubble under [children] the first time it's shown, pointing at it.
 * It doesn't block touches: the first tap anywhere dismisses it for good.
 * [id] is remembered once seen, so the tip never shows again.
 */
export function OneTimeTip({ id, message, children }: { id: string; message: string; children: ReactNode }) {
  const dark = useDark();
  const overlay = useOverlay();
  const anchor = useRef<ComponentRef<typeof View>>(null);
  const [at, setAt] = useState<{ right: number; top: number } | null>(null);
  const appear = useSharedValue(0);
  const key = `tip_seen:${id}`;

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        if (await kv.getBool(key)) return;
      } catch {
        return;
      }
      // A beat after the screen settles, then a soft pop in.
      setTimeout(() => {
        if (cancelled) return;
        anchor.current?.measureInWindow((x, y, w, h) => {
          if (cancelled || w === 0) return;
          setAt({ right: x + w, top: y + h + 10 });
          appear.value = withDelay(80, withTiming(1, { duration: 600, easing: Easing.out(Easing.back(1.4)) }));
        });
      }, 500);
    })();
    return () => {
      cancelled = true;
    };
  }, [key, appear]);

  useEffect(() => {
    if (!at) return;
    return overlay.onAnyTouch(() => {
      appear.value = withTiming(0, { duration: 180 });
      setTimeout(() => setAt(null), 180);
      kv.setBool(key, true).catch(() => {});
    });
  }, [at, overlay, key, appear]);

  const style = useAnimatedStyle(() => ({
    opacity: Math.min(1, appear.value),
    transform: [{ scale: 0.85 + 0.15 * appear.value }],
    transformOrigin: 'top right',
  }));

  const fill = dark ? '#FFFFFF' : '#1C1C1E';
  usePortal(
    at != null,
    at ? (
      <Animated.View
        pointerEvents="none"
        style={[{ position: 'absolute', top: at.top, right: undefined, left: at.right - 240, width: 240, alignItems: 'flex-end' }, style]}
      >
        <View style={{ marginRight: 22 }}>
          <Svg width={16} height={8}>
            <Path d="M0 8 L8 0 L16 8 Z" fill={fill} />
          </Svg>
        </View>
        <View
          style={{
            paddingHorizontal: 14,
            paddingVertical: 10,
            borderRadius: 14,
            backgroundColor: fill,
            boxShadow: '0 6px 18px rgba(0, 0, 0, 0.2)',
          }}
        >
          <Text style={{ fontSize: 13, fontWeight: '600', color: dark ? '#000' : '#fff' }}>{message}</Text>
        </View>
      </Animated.View>
    ) : null,
  );

  return (
    <View ref={anchor} collapsable={false}>
      {children}
    </View>
  );
}
