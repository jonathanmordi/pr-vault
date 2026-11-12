import { Stack } from 'expo-router';
import { NativeTabs } from 'expo-router/native-tabs';

import { useSession } from '@/lib/session';
import { OnboardingGate } from '@/screens/Onboarding';
import { C, useDark } from '@/theme/colors';

/**
 * The four tabs on the system tab bar (Liquid Glass on iOS, Material on
 * Android), behind the onboarding gate. A new gate per user, so signing in
 * as someone else checks their team.
 */
export default function TabsLayout() {
  const session = useSession();
  const dark = useDark();
  return (
    <OnboardingGate key={session?.user.id}>
      {/* Back from the intro's light status bar, which shares this route. */}
      <Stack.Screen options={{ statusBarStyle: dark ? 'light' : 'dark' }} />
      <NativeTabs tintColor={C.accentOf(dark)}>
        <NativeTabs.Trigger name="index">
          <NativeTabs.Trigger.Label>Leaderboard</NativeTabs.Trigger.Label>
          <NativeTabs.Trigger.Icon sf={{ default: 'chart.bar', selected: 'chart.bar.fill' }} md="leaderboard" />
        </NativeTabs.Trigger>
        <NativeTabs.Trigger name="profile">
          <NativeTabs.Trigger.Label>Profile</NativeTabs.Trigger.Label>
          <NativeTabs.Trigger.Icon sf={{ default: 'person', selected: 'person.fill' }} md="person" />
        </NativeTabs.Trigger>
        <NativeTabs.Trigger name="maxes">
          <NativeTabs.Trigger.Label>Maxes</NativeTabs.Trigger.Label>
          <NativeTabs.Trigger.Icon sf="dumbbell.fill" md="fitness_center" />
        </NativeTabs.Trigger>
        <NativeTabs.Trigger name="settings">
          <NativeTabs.Trigger.Label>Settings</NativeTabs.Trigger.Label>
          <NativeTabs.Trigger.Icon sf={{ default: 'gearshape', selected: 'gearshape.fill' }} md="settings" />
        </NativeTabs.Trigger>
      </NativeTabs>
    </OnboardingGate>
  );
}
