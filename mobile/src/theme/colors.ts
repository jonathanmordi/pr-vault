import { useColorScheme } from 'react-native';

import { usePrefs } from '@/lib/prefs';

/** '#C8140F' at [a] opacity, as rgba(). */
export function alpha(hex: string, a: number) {
  const h = hex.replace('#', '');
  const n = parseInt(h.length === 8 ? h.slice(2) : h, 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
}

export const C = {
  accentAlt: '#E8372D',

  /** Brand red. Dark mode uses the brighter red so it doesn't go muddy on dark cards. */
  accentOf: (dark: boolean) => (dark ? '#E8372D' : '#C8140F'),

  // Neutral greys; the old olive-tinted ones made both themes look muddy.
  bg: (dark: boolean) => (dark ? '#000000' : '#F2F2F5'),
  surface: (dark: boolean) => (dark ? '#1C1C1E' : '#FFFFFF'),
  surface2: (dark: boolean) => (dark ? '#2C2C2E' : '#EEEEF1'),
  surface3: (dark: boolean) => (dark ? '#3A3A3C' : '#E4E4E8'),

  /** Bottom sheets. Lifted off black in dark mode so the sheet's edge shows against the dimmed screen behind it. */
  sheet: (dark: boolean) => (dark ? '#111113' : '#F2F2F5'),

  /** Search and text field fill, sitting directly on bg. */
  field: (dark: boolean) => (dark ? '#1C1C1E' : '#E4E4E9'),

  border: (dark: boolean) => (dark ? 'rgba(255, 255, 255, 0.12)' : '#E2E2E7'),

  text1: (dark: boolean) => (dark ? '#F5F5F7' : '#111114'),
  text2: (dark: boolean) => (dark ? '#AEAEB2' : '#4E4E57'),
  text3: (dark: boolean) => (dark ? '#8E8E93' : '#75757F'),

  accentSoft: (dark: boolean) => (dark ? 'rgba(232, 55, 45, 0.16)' : '#FCE9E8'),
};

/** How strongly the top wash starts. */
export const washAlpha = (dark: boolean) => (dark ? 0.2 : 0.09);

/** The wash's top color laid over [base], as one solid color. */
export function washTop(dark: boolean, base = C.bg(dark)) {
  const a = washAlpha(dark);
  const mix = (x: string, y: string) => {
    const p = (h: string) => parseInt(h.replace('#', ''), 16);
    const [ax, ay] = [p(x), p(y)];
    const ch = (s: number) => Math.round(((ax >> s) & 255) * a + ((ay >> s) & 255) * (1 - a));
    return `rgb(${ch(16)}, ${ch(8)}, ${ch(0)})`;
  };
  return mix(C.accentOf(dark), base);
}

/**
 * Card surface: a soft shadow in light mode, a faint outline in dark mode,
 * where shadows don't show on black.
 */
export function cardStyle(dark: boolean, radius = 20, color?: string) {
  return {
    backgroundColor: color ?? C.surface(dark),
    borderRadius: radius,
    ...(dark
      ? { borderWidth: 0.5, borderColor: C.border(dark) }
      : { boxShadow: '0 6px 18px rgba(0, 0, 0, 0.06), 0 1px 3px rgba(0, 0, 0, 0.03)' }),
  } as const;
}

/** Whether to draw in dark mode: the user's choice, or the phone's. */
export function useDark() {
  const mode = usePrefs().themeMode;
  const scheme = useColorScheme();
  return mode === 'system' ? scheme === 'dark' : mode === 'dark';
}
