import { router } from 'expo-router';
import { ReactNode, useEffect, useState } from 'react';
import { Modal, Pressable, ScrollView, Text, View } from 'react-native';
import Animated, { useAnimatedStyle, withTiming } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { FadeSlideIn, PressScale, kSpring } from '@/components/motion';
import { confirmAction, toast } from '@/components/overlay';
import { SegmentToggle } from '@/components/SegmentToggle';
import { BackCircle, CustomToggle, Icon, IconName, SectionTitle, Spinner, WashHeader, pageTitleStyle } from '@/components/ui';
import { haptic } from '@/lib/haptics';
import { OnboardingApi, TeamInfo, divisionLabel, onboardingApi } from '@/lib/onboardingApi';
import { Prefs, PrefsState, ThemeMode, prefsStore, usePrefs } from '@/lib/prefs';
import { useSession } from '@/lib/session';
import { C, cardStyle, useDark } from '@/theme/colors';

const themeLabels: Record<ThemeMode, string> = { system: 'Auto', light: 'Light', dark: 'Dark' };

function alertsSummary(p: Prefs) {
  const on = [p.alertMine, p.alertRivals, p.alertTeam];
  if (on.every(Boolean)) return 'All PRs';
  if (!on.some(Boolean)) return p.alertRecords ? 'School records only' : 'Off';
  return [p.alertMine && 'You', p.alertRivals && 'Rivals', p.alertTeam && 'Teammates'].filter(Boolean).join(', ');
}

const push = (path: '/notifications' | '/units' | '/tour') => {
  haptic.selection();
  router.push(path);
};

export function Settings({ api = onboardingApi }: { api?: OnboardingApi }) {
  const dark = useDark();
  const prefs = usePrefs();
  const session = useSession();
  const insets = useSafeAreaInsets();
  const [deleting, setDeleting] = useState(false);

  const confirmDelete = async () => {
    haptic.medium();
    if (!(await confirmAction({ title: 'Delete your account?', body: <DeletePoints dark={dark} />, confirmLabel: 'Delete account', destructive: true }))) return;
    if (!(await confirmAction({ title: 'Are you sure?', message: "Your account will be deleted. This can't be undone.", confirmLabel: 'Delete', destructive: true }))) return;
    // Block the screen while deleting; the sign-out afterwards swaps the
    // whole app back to the sign-in screen.
    setDeleting(true);
    try {
      await api.deleteAccount();
      setDeleting(false);
      await api.signOutLocally();
    } catch {
      setDeleting(false);
      toast("Couldn't delete your account. Try again.");
    }
  };

  return (
    <>
      <ScrollView style={{ backgroundColor: C.bg(dark) }} contentContainerStyle={{ paddingBottom: 104 }}>
        <WashHeader dark={dark} style={{ paddingHorizontal: 20, paddingTop: insets.top + 16, paddingBottom: 24 }}>
          <FadeSlideIn>
            <Text style={pageTitleStyle(dark)}>Settings</Text>
          </FadeSlideIn>
        </WashHeader>

        <FadeSlideIn delay={80}>
          <SectionHeader text="Account" dark={dark} />
          <Group dark={dark}>
            <SettingsRow icon="mail-outline" title={session?.user.email ?? 'Not signed in'} subtitle="Email address" dark={dark} divider />
            <TeamRow api={api} dark={dark} />
          </Group>
        </FadeSlideIn>
        <View style={{ height: 28 }} />

        <FadeSlideIn delay={160}>
          <SectionHeader text="Preferences" dark={dark} />
          <Group dark={dark}>
            <SettingsRow
              icon={dark ? 'dark-mode' : 'light-mode'}
              title="Appearance"
              subtitle={prefs.themeMode === 'system' ? 'Matches your phone' : themeLabels[prefs.themeMode]}
              dark={dark}
              divider
              below={
                <SegmentToggle
                  options={Object.values(themeLabels)}
                  value={themeLabels[prefs.themeMode]}
                  dark={dark}
                  fill
                  onChange={(label) =>
                    prefsStore.update({ themeMode: (Object.keys(themeLabels) as ThemeMode[]).find((k) => themeLabels[k] === label)! })
                  }
                />
              }
            />
            <SettingsRow
              icon="notifications-none"
              title="Notifications"
              subtitle={alertsSummary(prefs)}
              dark={dark}
              divider
              trailing={<Chevron dark={dark} />}
              onPress={() => push('/notifications')}
            />
            <SettingsRow
              icon="straighten"
              title="Units"
              subtitle={`${prefs.imperial ? 'Feet & inches' : 'Meters'} · ${prefs.weightUnit}`}
              dark={dark}
              divider
              trailing={<Chevron dark={dark} />}
              onPress={() => push('/units')}
            />
            <SettingsRow
              icon="auto-stories"
              title="How PR Vault works"
              subtitle="The quick tour"
              dark={dark}
              trailing={<Chevron dark={dark} />}
              onPress={() => push('/tour')}
            />
          </Group>
        </FadeSlideIn>
        <View style={{ height: 28 }} />

        <FadeSlideIn delay={240} style={{ paddingHorizontal: 20 }}>
          <PressScale
            onPress={async () => {
              if (await confirmAction({ title: 'Sign out?', message: "You'll need your email and password to sign back in.", confirmLabel: 'Sign Out' })) {
                await api.signOut();
              }
            }}
          >
            <View style={[cardStyle(dark, 16), { height: 52, alignItems: 'center', justifyContent: 'center' }]}>
              <Text style={{ fontSize: 16, fontWeight: '600', color: C.accentOf(dark) }}>Sign Out</Text>
            </View>
          </PressScale>
        </FadeSlideIn>
        <Pressable onPress={confirmDelete} style={{ alignSelf: 'center', padding: 12, marginTop: 4 }}>
          <Text style={{ fontSize: 13, fontWeight: '500', color: C.text3(dark) }}>Delete account</Text>
        </Pressable>
        <View style={{ height: 20 }} />

        <FadeSlideIn delay={320} style={{ alignItems: 'center' }}>
          <Text style={{ fontSize: 12, fontWeight: '500', color: C.text3(dark) }}>PR Vault v1.0.0</Text>
          <Text style={{ marginTop: 4, fontSize: 11, color: `${C.text3(dark)}80` }}>Built for athletes, by athletes.</Text>
        </FadeSlideIn>
      </ScrollView>
      <Modal visible={deleting} transparent>
        <View style={{ flex: 1, backgroundColor: 'rgba(0, 0, 0, 0.4)', alignItems: 'center', justifyContent: 'center' }}>
          <Spinner color="#fff" size="large" />
        </View>
      </Modal>
    </>
  );
}

/** Says exactly what deleting removes and what stays before it happens. */
function DeletePoints({ dark }: { dark: boolean }) {
  const point = (icon: IconName, text: string) => (
    <View style={{ flexDirection: 'row', alignItems: 'flex-start', marginBottom: 14 }}>
      <View style={{ width: 30, height: 30, borderRadius: 15, backgroundColor: C.surface2(dark), alignItems: 'center', justifyContent: 'center' }}>
        <Icon name={icon} size={16} color={C.text2(dark)} />
      </View>
      <Text style={{ flex: 1, marginLeft: 12, paddingTop: 5, fontSize: 14, lineHeight: 20, color: C.text2(dark) }}>{text}</Text>
    </View>
  );
  return (
    <View>
      {point('person-off', 'Your login and lifting maxes are deleted.')}
      {point('emoji-events', "Your TFRRS results stay on your team's leaderboards, since they're public. If you come back, you can link them again.")}
      {point('warning-amber', "This can't be undone.")}
    </View>
  );
}

// The team, loaded once per account and remembered, so switching tabs
// doesn't flash a placeholder.
let cachedFor: string | null = null;
let cachedTeam: TeamInfo | null = null;

function TeamRow({ api, dark }: { api: OnboardingApi; dark: boolean }) {
  const uid = api.userId;
  const [loading, setLoading] = useState(cachedFor !== uid);
  const [, rerender] = useState(0);

  useEffect(() => {
    let alive = true;
    api
      .myTeam()
      .then((team) => {
        cachedFor = uid;
        cachedTeam = team;
      })
      .catch(() => {}) // keep whatever we showed last
      .finally(() => {
        if (!alive) return;
        setLoading(false);
        rerender((n) => n + 1);
      });
    return () => {
      alive = false;
    };
  }, [api, uid]);

  const team = cachedFor === uid ? cachedTeam : null;
  return (
    <SettingsRow
      icon="school"
      title={team?.name ?? (loading ? 'Loading team…' : 'No team yet')}
      subtitle={['Team', team ? divisionLabel(team.division) : null].filter(Boolean).join(' · ')}
      dark={dark}
    />
  );
}

// ─── Notifications ────────────────────────────────────────────────────────────

export function NotificationSettings() {
  const dark = useDark();
  const prefs = usePrefs();
  const toggle = (icon: IconName, title: string, subtitle: string, key: keyof PrefsState, divider = true) => {
    const value = prefs.state[key] as boolean;
    return (
      <SettingsRow
        icon={icon}
        title={title}
        subtitle={subtitle}
        dark={dark}
        divider={divider}
        onPress={() => prefsStore.update({ [key]: !value })}
        trailing={<CustomToggle value={value} dark={dark} onChange={(v) => prefsStore.update({ [key]: v })} />}
      />
    );
  };
  return (
    <SubScreen title="Notifications">
      <SectionHeader text="Show in Activity" dark={dark} />
      <Group dark={dark}>
        {toggle('person-outline', 'Your PRs', 'Every time you set a new best', 'alertMine')}
        {toggle('compare-arrows', "Rivals' PRs", 'Your closest teammate in each event', 'alertRivals')}
        {toggle('groups', "Teammates' PRs", 'Everyone else on the team', 'alertTeam')}
        {toggle('emoji-events', 'School records', 'Always shown, even with teammates off', 'alertRecords', false)}
      </Group>
      <View style={{ height: 28 }} />
      <SectionHeader text="Bell" dark={dark} />
      <Group dark={dark}>{toggle('notifications-active', 'Unread badge', 'Count new PRs on the bell', 'showBadge', false)}</Group>
      <Footnote
        dark={dark}
        text="New PRs show up in Activity after the nightly TFRRS sync. Lock screen notifications need a paid Apple Developer account."
      />
    </SubScreen>
  );
}

// ─── Units ────────────────────────────────────────────────────────────────────

export function UnitsSettings() {
  const dark = useDark();
  const prefs = usePrefs();
  return (
    <SubScreen title="Units">
      <SectionHeader text="Field Events" dark={dark} />
      <Group dark={dark}>
        <ChoiceRow title="Meters" example="6.22m" selected={!prefs.imperial} dark={dark} divider onPress={() => prefsStore.update({ fieldUnits: 'metric' })} />
        <ChoiceRow title="Feet & inches" example={`20' 4.75"`} selected={prefs.imperial} dark={dark} onPress={() => prefsStore.update({ fieldUnits: 'imperial' })} />
      </Group>
      <Footnote
        dark={dark}
        text="Converted from the meter mark and rounded down to the quarter inch, like NCAA conversions. Times and multi-event points don't change."
      />
      <View style={{ height: 28 }} />
      <SectionHeader text="Lifting" dark={dark} />
      <Group dark={dark}>
        <ChoiceRow title="Pounds" example="225 lbs" selected={prefs.liftUnits === 'lbs'} dark={dark} divider onPress={() => prefsStore.update({ liftUnits: 'lbs' })} />
        <ChoiceRow title="Kilograms" example="102 kg" selected={prefs.liftUnits === 'kg'} dark={dark} onPress={() => prefsStore.update({ liftUnits: 'kg' })} />
      </Group>
    </SubScreen>
  );
}

// ─── Shared pieces ────────────────────────────────────────────────────────────

/** A pushed settings page with a back button and large title. */
function SubScreen({ title, children }: { title: string; children: ReactNode }) {
  const dark = useDark();
  const insets = useSafeAreaInsets();
  return (
    <ScrollView style={{ backgroundColor: C.bg(dark) }} contentContainerStyle={{ paddingBottom: 104 }}>
      <WashHeader dark={dark} style={{ paddingTop: insets.top }}>
        <View style={{ paddingLeft: 16, paddingTop: 8, alignItems: 'flex-start' }}>
          <BackCircle onPress={() => router.back()} dark={dark} size={32} soft />
        </View>
        <Text style={[pageTitleStyle(dark), { paddingHorizontal: 20, paddingTop: 12, paddingBottom: 24 }]}>{title}</Text>
      </WashHeader>
      <FadeSlideIn>{children}</FadeSlideIn>
    </ScrollView>
  );
}

function Group({ dark, children }: { dark: boolean; children: ReactNode }) {
  // Clipped so the pressed-row highlight keeps the card's corners.
  return (
    <View style={{ paddingHorizontal: 20 }}>
      <View style={[cardStyle(dark), { overflow: 'hidden' }]}>{children}</View>
    </View>
  );
}

function Footnote({ text, dark }: { text: string; dark: boolean }) {
  return <Text style={{ paddingHorizontal: 36, paddingTop: 10, fontSize: 12, lineHeight: 17, color: C.text3(dark) }}>{text}</Text>;
}

function Chevron({ dark }: { dark: boolean }) {
  return <Icon name="chevron-right" size={18} color={C.text3(dark)} />;
}

function SectionHeader({ text, dark }: { text: string; dark: boolean }) {
  return (
    <View style={{ paddingHorizontal: 20, paddingBottom: 12 }}>
      <SectionTitle text={text} dark={dark} />
    </View>
  );
}

/** One option in a pick-one list, with a live example of the format. */
function ChoiceRow({
  title,
  example,
  selected,
  dark,
  divider = false,
  onPress,
}: {
  title: string;
  example: string;
  selected: boolean;
  dark: boolean;
  divider?: boolean;
  onPress: () => void;
}) {
  const check = useAnimatedStyle(() => ({ transform: [{ scale: withTiming(selected ? 1 : 0, { duration: 220, easing: kSpring }) }] }), [selected]);
  return (
    <View>
      <Pressable
        accessibilityRole="radio"
        accessibilityState={{ checked: selected }}
        onPress={() => {
          if (selected) return;
          haptic.selection();
          onPress();
        }}
        style={{ paddingHorizontal: 20, paddingVertical: 15, flexDirection: 'row', alignItems: 'center' }}
      >
        <Text style={{ flex: 1, fontSize: 15, fontWeight: '500', color: C.text1(dark) }}>{title}</Text>
        <Text style={{ fontSize: 14, fontWeight: '600', color: selected ? C.accentOf(dark) : C.text3(dark) }}>{example}</Text>
        <Animated.View style={[{ marginLeft: 12 }, check]}>
          <Icon name="check" size={20} color={C.accentOf(dark)} />
        </Animated.View>
      </Pressable>
      {divider && <View style={{ height: 0.5, marginLeft: 20, backgroundColor: C.border(dark) }} />}
    </View>
  );
}

function SettingsRow({
  icon,
  title,
  subtitle,
  dark,
  divider = false,
  trailing,
  below,
  onPress,
}: {
  icon: IconName;
  title: string;
  subtitle?: string | null;
  dark: boolean;
  divider?: boolean;
  trailing?: ReactNode;
  /** Full-width control under the title, for ones too wide to trail. */
  below?: ReactNode;
  onPress?: () => void;
}) {
  return (
    <View>
      <Pressable
        disabled={!onPress}
        onPress={onPress}
        style={({ pressed }) => ({
          paddingHorizontal: 20,
          paddingVertical: 14,
          flexDirection: 'row',
          alignItems: below ? 'flex-start' : 'center',
          backgroundColor: pressed && onPress ? C.surface2(dark) : 'transparent',
        })}
      >
        <View style={{ width: 32, height: 32, borderRadius: 9, backgroundColor: C.accentSoft(dark), alignItems: 'center', justifyContent: 'center' }}>
          <Icon name={icon} size={17} color={C.accentOf(dark)} />
        </View>
        <View style={{ flex: 1, marginLeft: 14 }}>
          <Text style={{ fontSize: 15, fontWeight: '500', color: C.text1(dark) }}>{title}</Text>
          {subtitle ? <Text style={{ fontSize: 12, color: C.text3(dark) }}>{subtitle}</Text> : null}
          {below ? <View style={{ marginTop: 12 }}>{below}</View> : null}
        </View>
        {trailing ? <View style={{ marginLeft: 8 }}>{trailing}</View> : null}
      </Pressable>
      {divider && <View style={{ height: 0.5, marginLeft: 66, backgroundColor: C.border(dark) }} />}
    </View>
  );
}
