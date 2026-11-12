import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { Image } from 'expo-image';
import { LinearGradient } from 'expo-linear-gradient';
import { ComponentProps, ReactNode, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  StyleProp,
  StyleSheet,
  Text,
  TextInput,
  TextInputProps,
  TextStyle,
  View,
  ViewStyle,
} from 'react-native';
import Animated, { useAnimatedStyle, withTiming } from 'react-native-reanimated';

import { initialsFor } from '@/lib/format';
import { haptic } from '@/lib/haptics';
import { C, alpha, cardStyle, washAlpha, washTop } from '@/theme/colors';

import { PressScale, kSpring } from './motion';

export type IconName = ComponentProps<typeof MaterialIcons>['name'];

export function Icon({ name, size = 20, color }: { name: IconName; size?: number; color: string }) {
  return <MaterialIcons name={name} size={size} color={color} />;
}

export function Spinner({ color, size = 'small' }: { color: string; size?: 'small' | 'large' }) {
  return <ActivityIndicator color={color} size={size} />;
}

// ─── Cards ────────────────────────────────────────────────────────────────────

export function GlassCard({
  dark,
  children,
  style,
  testID,
}: {
  dark: boolean;
  children: ReactNode;
  style?: StyleProp<ViewStyle>;
  testID?: string;
}) {
  return (
    <View testID={testID} style={[cardStyle(dark), style]}>
      {children}
    </View>
  );
}

export function SkeletonBox({
  dark,
  width,
  height,
  radius = 8,
}: {
  dark: boolean;
  width?: number;
  height: number;
  radius?: number;
}) {
  return <View style={{ width, height, borderRadius: radius, backgroundColor: C.surface2(dark) }} />;
}

/** A hairline between rows of a card. */
export function Divider({ dark, inset = 0 }: { dark: boolean; inset?: number }) {
  return <View style={{ height: StyleSheet.hairlineWidth, marginLeft: inset, backgroundColor: C.border(dark) }} />;
}

// ─── Avatars ──────────────────────────────────────────────────────────────────

export function InitialsAvatar({
  name,
  gender,
  dark,
  size = 40,
}: {
  name: string;
  gender: string;
  dark: boolean;
  size?: number;
}) {
  const female = gender === 'F';
  // A muted pink in dark mode; the light-mode pink glares on black.
  const bg = female ? (dark ? 'rgba(212, 83, 126, 0.2)' : '#FDE8F0') : C.surface2(dark);
  const fg = female ? (dark ? '#ED93B1' : '#D4537E') : C.text2(dark);
  return (
    <View
      style={{
        width: size,
        height: size,
        borderRadius: size / 2,
        backgroundColor: bg,
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      <Text style={{ fontSize: size * 0.33, fontWeight: '700', color: fg }}>{initialsFor(name)}</Text>
    </View>
  );
}

/** A big gradient avatar with initials, for profile headers. */
export function GradientAvatar({
  name,
  female,
  dark,
  size,
}: {
  name: string;
  female: boolean;
  dark: boolean;
  size: number;
}) {
  const colors = female ? (['#D4537E', '#ED93B1'] as const) : ([C.accentOf(dark), C.accentAlt] as const);
  return (
    <LinearGradient
      colors={colors}
      start={{ x: 0, y: 0 }}
      end={{ x: 1, y: 1 }}
      style={{
        width: size,
        height: size,
        borderRadius: size / 2,
        alignItems: 'center',
        justifyContent: 'center',
        boxShadow: `0 4px 20px ${female ? 'rgba(212, 83, 126, 0.35)' : 'rgba(232, 55, 45, 0.35)'}`,
      }}
    >
      <Text style={{ fontSize: size * 0.34, fontWeight: '800', color: '#fff' }}>{initialsFor(name)}</Text>
    </LinearGradient>
  );
}

// ─── Type ─────────────────────────────────────────────────────────────────────

/** Big page title ("PR Vault", "Settings"). */
export const pageTitleStyle = (dark: boolean): TextStyle => ({
  fontSize: 32,
  fontWeight: '800',
  letterSpacing: -1.1,
  color: C.text1(dark),
});

export const sectionTitleStyle = (dark: boolean): TextStyle => ({
  fontSize: 20,
  fontWeight: '800',
  letterSpacing: -0.4,
  color: C.text1(dark),
});

/** Bold row title ("Personal Records"), with an optional trailing element. */
export function SectionTitle({ text, dark, trailing }: { text: string; dark: boolean; trailing?: ReactNode }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center' }}>
      <Text style={[sectionTitleStyle(dark), { flex: 1 }]}>{text}</Text>
      {trailing}
    </View>
  );
}

/**
 * A page header on the soft team-color wash, fading into the page. The
 * wash's top color also extends far above it, so pulling a page down past
 * the top shows more of it instead of the plain page color. [base] is the
 * color behind the page.
 */
export function WashHeader({
  dark,
  children,
  style,
  base,
}: {
  dark: boolean;
  children: ReactNode;
  style?: StyleProp<ViewStyle>;
  base?: string;
}) {
  const accent = C.accentOf(dark);
  return (
    <View>
      <View
        pointerEvents="none"
        style={{ position: 'absolute', left: 0, right: 0, top: -1000, height: 1000, backgroundColor: washTop(dark, base) }}
      />
      <LinearGradient colors={[alpha(accent, washAlpha(dark)), alpha(accent, 0)]} style={style}>
        {children}
      </LinearGradient>
    </View>
  );
}

// ─── Input field ──────────────────────────────────────────────────────────────

/**
 * Rounded text field with a leading icon, used on the sign-in and onboarding
 * screens. With [clearable] it shows a clear button while there's text.
 */
export function InputField({
  value,
  onChangeText,
  hint,
  icon,
  dark,
  clearable,
  onClear,
  ...rest
}: {
  value: string;
  onChangeText: (text: string) => void;
  hint: string;
  icon: IconName;
  dark: boolean;
  clearable?: boolean;
  onClear?: () => void;
} & Omit<TextInputProps, 'value' | 'onChangeText'>) {
  return (
    <View style={[styles.field, { backgroundColor: C.field(dark) }]}>
      <View style={{ width: 16 }} />
      <Icon name={icon} size={18} color={C.text3(dark)} />
      <View style={{ width: 12 }} />
      <TextInput
        value={value}
        onChangeText={onChangeText}
        placeholder={hint}
        placeholderTextColor={C.text3(dark)}
        keyboardAppearance={dark ? 'dark' : 'light'}
        selectionColor={C.accentOf(dark)}
        style={{ flex: 1, fontSize: 15, color: C.text1(dark), paddingVertical: 0 }}
        {...rest}
      />
      {clearable && value.length > 0 ? (
        <Pressable
          hitSlop={8}
          onPress={() => {
            onChangeText('');
            onClear?.();
          }}
          style={{ paddingLeft: 8, paddingRight: 14 }}
          accessibilityLabel="Clear"
        >
          <Icon name="cancel" size={18} color={C.text3(dark)} />
        </Pressable>
      ) : (
        <View style={{ width: 16 }} />
      )}
    </View>
  );
}

// ─── Buttons ──────────────────────────────────────────────────────────────────

export type ButtonTone =
  /** Team red, for the main action. */
  | 'accent'
  /** Black in light mode, white in dark: a strong neutral action. */
  | 'ink'
  /** Soft fill, for secondary actions like Cancel. */
  | 'soft';

/** Full-width rounded button. Shows a spinner and ignores taps while [loading]. */
export function PrimaryButton({
  label,
  onPress,
  dark,
  loading = false,
  tone = 'accent',
}: {
  label: string;
  onPress: () => void;
  dark: boolean;
  loading?: boolean;
  tone?: ButtonTone;
}) {
  const [fill, ink] =
    tone === 'accent'
      ? [C.accentOf(dark), '#FFFFFF']
      : tone === 'ink'
        ? [C.text1(dark), dark ? '#000000' : '#FFFFFF']
        : [C.surface2(dark), C.text1(dark)];
  return (
    <PressScale onPress={loading ? undefined : onPress}>
      <View
        style={{
          height: 52,
          borderRadius: 16,
          backgroundColor: fill,
          alignItems: 'center',
          justifyContent: 'center',
          boxShadow: tone === 'accent' ? `0 4px 14px ${alpha(fill, 0.22)}` : undefined,
        }}
      >
        {loading ? (
          <Spinner color={ink} />
        ) : (
          <Text style={{ color: ink, fontSize: 16, fontWeight: '600' }}>{label}</Text>
        )}
      </View>
    </PressScale>
  );
}

/** A small text button for secondary choices under a step's main button. */
export function LinkButton({
  label,
  onPress,
  dark,
  accent = false,
}: {
  label: string;
  onPress?: () => void;
  dark: boolean;
  accent?: boolean;
}) {
  const text = (
    <Text
      style={{
        paddingVertical: 12,
        textAlign: 'center',
        fontSize: 14,
        fontWeight: '600',
        color: !onPress ? C.text3(dark) : accent ? C.accentOf(dark) : C.text2(dark),
      }}
    >
      {label}
    </Text>
  );
  return onPress ? <PressScale onPress={onPress}>{text}</PressScale> : text;
}

/** A round back button. */
export function BackCircle({ onPress, dark, size = 38, soft = false }: { onPress: () => void; dark: boolean; size?: number; soft?: boolean }) {
  return (
    <PressScale onPress={onPress}>
      <View
        accessibilityLabel="Back"
        style={{
          width: size,
          height: size,
          borderRadius: size / 2,
          alignItems: 'center',
          justifyContent: 'center',
          backgroundColor: soft ? C.surface2(dark) : alpha(C.surface(dark), 0.8),
        }}
      >
        <Icon name={soft ? 'arrow-back' : 'arrow-back-ios-new'} size={16} color={soft ? C.text2(dark) : C.text1(dark)} />
      </View>
    </PressScale>
  );
}

// ─── Chips ────────────────────────────────────────────────────────────────────

/**
 * Filter chip. Selected is solid ink (black in light mode, white in dark), so
 * the team red stays free for highlights.
 */
export function AppChip({
  label,
  selected,
  dark,
  onPress,
  small = false,
}: {
  label: string;
  selected: boolean;
  dark: boolean;
  onPress: () => void;
  small?: boolean;
}) {
  const fill = useAnimatedStyle(
    () => ({
      backgroundColor: withTiming(selected ? C.text1(dark) : C.surface2(dark), { duration: 220, easing: kSpring }),
    }),
    [selected, dark],
  );
  return (
    <PressScale
      pressedScale={0.96}
      onPress={() => {
        if (selected) return;
        haptic.selection();
        onPress();
      }}
    >
      <Animated.View
        accessibilityState={{ selected }}
        style={[
          {
            height: small ? 32 : 36,
            paddingHorizontal: small ? 13 : 16,
            borderRadius: 100,
            alignItems: 'center',
            justifyContent: 'center',
          },
          fill,
        ]}
      >
        <Text
          style={{
            fontSize: small ? 12.5 : 13.5,
            fontWeight: '600',
            letterSpacing: -0.1,
            color: selected ? (dark ? '#000' : '#fff') : C.text2(dark),
          }}
        >
          {label}
        </Text>
      </Animated.View>
    </PressScale>
  );
}

/** A horizontal row of chips that scrolls edge to edge. */
export function ChipRow({ chips, height = 52 }: { chips: ReactNode[]; height?: number }) {
  return (
    <View style={{ height }}>
      <FlatList
        horizontal
        data={chips}
        keyExtractor={(_, i) => String(i)}
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={{ paddingHorizontal: 20, alignItems: 'center', gap: 8 }}
        renderItem={({ item }) => <>{item}</>}
      />
    </View>
  );
}

// ─── Empty state ──────────────────────────────────────────────────────────────

/** Centered icon, title and message for empty lists and errors, with an optional action. */
export function EmptyState({
  icon,
  title,
  dark,
  message,
  actionLabel,
  onAction,
}: {
  icon: IconName;
  title: string;
  dark: boolean;
  message?: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  return (
    <View style={{ paddingHorizontal: 40, alignItems: 'center' }}>
      <View
        style={{
          width: 64,
          height: 64,
          borderRadius: 32,
          backgroundColor: C.surface2(dark),
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <Icon name={icon} size={28} color={C.text2(dark)} />
      </View>
      <Text
        style={{
          marginTop: 16,
          textAlign: 'center',
          fontSize: 17,
          fontWeight: '700',
          letterSpacing: -0.2,
          color: C.text1(dark),
        }}
      >
        {title}
      </Text>
      {message ? (
        <Text style={{ marginTop: 6, textAlign: 'center', fontSize: 14, lineHeight: 20, color: C.text3(dark) }}>
          {message}
        </Text>
      ) : null}
      {actionLabel && onAction ? (
        <PressScale onPress={onAction} style={{ marginTop: 18 }}>
          <View style={{ paddingHorizontal: 20, paddingVertical: 11, borderRadius: 100, backgroundColor: C.text1(dark) }}>
            <Text style={{ fontSize: 14, fontWeight: '600', color: dark ? '#000' : '#fff' }}>{actionLabel}</Text>
          </View>
        </PressScale>
      ) : null}
    </View>
  );
}

// ─── Steps ────────────────────────────────────────────────────────────────────

/** A step's icon: white on an accent gradient circle with a soft glow. */
export function HeroIcon({ icon, dark }: { icon: IconName; dark: boolean }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <LinearGradient
        colors={[C.accentAlt, C.accentOf(false)]}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 1 }}
        style={{
          width: 76,
          height: 76,
          borderRadius: 38,
          alignItems: 'center',
          justifyContent: 'center',
          boxShadow: `0 10px 28px ${alpha(C.accentOf(dark), 0.3)}`,
        }}
      >
        <Icon name={icon} size={34} color="#fff" />
      </LinearGradient>
    </View>
  );
}

/** A step's title and explanation, centered. */
export function StepHeading({ title, body, dark }: { title: string; body?: string; dark: boolean }) {
  return (
    <View>
      <Text
        style={{
          textAlign: 'center',
          fontSize: 28,
          fontWeight: '800',
          letterSpacing: -0.8,
          lineHeight: 32,
          color: C.text1(dark),
        }}
      >
        {title}
      </Text>
      {body ? (
        <Text style={{ marginTop: 10, textAlign: 'center', fontSize: 15, lineHeight: 22, color: C.text2(dark) }}>{body}</Text>
      ) : null}
    </View>
  );
}

// ─── Toggle ───────────────────────────────────────────────────────────────────

export function CustomToggle({ value, onChange, dark }: { value: boolean; onChange: (v: boolean) => void; dark: boolean }) {
  const track = useAnimatedStyle(
    () => ({ backgroundColor: withTiming(value ? C.accentOf(dark) : C.surface3(dark), { duration: 200 }) }),
    [value, dark],
  );
  const thumb = useAnimatedStyle(
    () => ({ transform: [{ translateX: withTiming(value ? 18 : 0, { duration: 200, easing: kSpring }) }] }),
    [value],
  );
  return (
    <Pressable onPress={() => onChange(!value)} accessibilityRole="switch" accessibilityState={{ checked: value }}>
      <Animated.View style={[{ width: 44, height: 26, borderRadius: 13, padding: 3 }, track]}>
        <Animated.View style={[{ width: 20, height: 20, borderRadius: 10, backgroundColor: '#fff' }, thumb]} />
      </Animated.View>
    </Pressable>
  );
}

// ─── Brand ────────────────────────────────────────────────────────────────────

export const appIconSource = require('../../assets/brand/icon.png');

/** The app icon. */
export function AppIcon({ size = 34 }: { size?: number }) {
  return <Image source={appIconSource} style={{ width: size, height: size, borderRadius: size * 0.23 }} />;
}

/** The icon and "PR Vault", in white, for the red screens. */
export function BrandMark() {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center' }}>
      <AppIcon />
      <Text style={{ marginLeft: 10, fontSize: 18, fontWeight: '800', letterSpacing: -0.4, color: '#fff' }}>PR Vault</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  field: { height: 52, borderRadius: 16, flexDirection: 'row', alignItems: 'center' },
});
