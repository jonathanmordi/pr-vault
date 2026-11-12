import { ReactNode, useEffect } from 'react';
import { Pressable, StyleProp, ViewStyle } from 'react-native';
import Animated, {
  Easing,
  ReduceMotion,
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withDelay,
  withRepeat,
  withSequence,
  withTiming,
} from 'react-native-reanimated';

/** iOS-like ease-out used for most transitions. */
export const kSpring = Easing.out(Easing.cubic);

/**
 * Fades and slides [children] in once, after [delay] ms. With [animate]
 * false they show at once, so list rows that scroll into view later don't
 * replay the entrance.
 */
export function FadeSlideIn({
  children,
  delay = 0,
  animate = true,
  style,
}: {
  children: ReactNode;
  delay?: number;
  animate?: boolean;
  style?: StyleProp<ViewStyle>;
}) {
  const t = useSharedValue(animate ? 0 : 1);
  useEffect(() => {
    if (animate) t.value = withDelay(delay, withTiming(1, { duration: 500, easing: Easing.out(Easing.quad) }));
    // Read once on mount, like the original.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const anim = useAnimatedStyle(() => ({
    opacity: t.value,
    transform: [{ translateY: (1 - t.value) * 10 }],
  }));
  return <Animated.View style={[style, anim]}>{children}</Animated.View>;
}

/** Shrinks a touch while pressed, then calls [onPress]. */
export function PressScale({
  children,
  onPress,
  onLongPress,
  pressedScale = 0.97,
  disabled,
  style,
  testID,
}: {
  children: ReactNode;
  onPress?: () => void;
  onLongPress?: () => void;
  pressedScale?: number;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
  testID?: string;
}) {
  const scale = useSharedValue(1);
  const anim = useAnimatedStyle(() => ({ transform: [{ scale: scale.value }] }));
  return (
    <Pressable
      testID={testID}
      disabled={disabled}
      onPressIn={() => (scale.value = withTiming(pressedScale, { duration: 120, easing: kSpring }))}
      onPressOut={() => (scale.value = withTiming(1, { duration: 120, easing: kSpring }))}
      onPress={onPress}
      onLongPress={onLongPress}
      accessibilityRole="button"
    >
      <Animated.View style={[style, anim]}>{children}</Animated.View>
    </Pressable>
  );
}

/** Gently pulses its children; wrap a group of SkeletonBoxes so they share one animation. */
export function SkeletonPulse({ children }: { children: ReactNode }) {
  const o = useSharedValue(0.45);
  useEffect(() => {
    o.value = withRepeat(withTiming(1, { duration: 900, easing: Easing.inOut(Easing.quad) }), -1, true);
  }, [o]);
  const anim = useAnimatedStyle(() => ({ opacity: o.value }));
  return <Animated.View style={anim}>{children}</Animated.View>;
}

/**
 * Gently moves [children] up and down a few times, to hint it can be dragged
 * that way. Still when the system asks for reduced motion.
 */
export function Bob({ children, distance = 3 }: { children: ReactNode; distance?: number }) {
  const y = useSharedValue(0);
  const reduce = useReducedMotion();
  useEffect(() => {
    if (reduce) return;
    const half = { duration: 350, easing: Easing.out(Easing.sin), reduceMotion: ReduceMotion.System };
    const bounce = withSequence(
      withTiming(-distance, half),
      withTiming(0, { ...half, easing: Easing.in(Easing.sin) }),
    );
    y.value = withRepeat(withSequence(bounce, bounce), 3, false);
  }, [reduce, distance, y]);
  const anim = useAnimatedStyle(() => ({ transform: [{ translateY: y.value }] }));
  return <Animated.View style={anim}>{children}</Animated.View>;
}
