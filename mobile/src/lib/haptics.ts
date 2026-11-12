import * as Haptics from 'expo-haptics';

// Fire and forget; haptics are a nicety and never worth an error.
const safe = (p: () => Promise<unknown>) => () => {
  p().catch(() => {});
};

export const haptic = {
  selection: safe(() => Haptics.selectionAsync()),
  light: safe(() => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light)),
  medium: safe(() => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium)),
  heavy: safe(() => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy)),
};
