import { AuthError, PostgrestError } from '@supabase/supabase-js';
import { router } from 'expo-router';
import { ReactNode, useEffect, useRef, useState } from 'react';
import { ScrollView, Text, View } from 'react-native';
import Animated, { FadeIn, FadeOut } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { CodeCells } from '@/components/CodeCells';
import { PressScale } from '@/components/motion';
import { confirmAction, toast } from '@/components/overlay';
import { StepScaffold } from '@/components/StepScaffold';
import {
  Divider,
  EmptyState,
  GlassCard,
  HeroIcon,
  IconName,
  InitialsAvatar,
  InputField,
  LinkButton,
  PrimaryButton,
  Spinner,
  StepHeading,
  WashHeader,
  pageTitleStyle,
  sectionTitleStyle,
} from '@/components/ui';
import { formatName } from '@/lib/format';
import { haptic } from '@/lib/haptics';
import { OnboardingApi, RosterEntry, kCodeLength, onboardingApi } from '@/lib/onboardingApi';
import { classYearLabel } from '@/lib/prStats';
import { C, useDark } from '@/theme/colors';

import { Intro } from './Intro';

type Stage = 'checking' | 'claim' | 'noTeam' | 'unverified' | 'offline' | 'serverError' | 'intro' | 'invite' | 'done';

/**
 * Shows [children] once the signed-in user is on a team. New users join
 * their school's team through their verified school email, then pick
 * themselves from the TFRRS roster. An invite code is the fallback.
 */
export function OnboardingGate({ children, api = onboardingApi }: { children: ReactNode; api?: OnboardingApi }) {
  const [stage, setStage] = useState<Stage>('checking');
  const [beforeInvite, setBeforeInvite] = useState<Stage>('noTeam');
  const mounted = useRef(true);
  useEffect(
    () => () => {
      mounted.current = false;
    },
    [],
  );
  const set = (s: Stage) => mounted.current && setStage(s);

  /** The how-it-works intro, once, then the app. */
  const afterOnboarding = async (uid: string): Promise<Stage> => ((await api.sawIntro(uid)) ? 'done' : 'intro');

  const finish = async () => {
    const uid = api.userId;
    if (!uid) return set('done');
    await api.markOnboarded(uid);
    set(await afterOnboarding(uid));
  };

  const check = async () => {
    const uid = api.userId;
    if (!uid) return;
    if (await api.wasOnboarded(uid)) return set(await afterOnboarding(uid));
    set('checking');
    try {
      if ((await api.teamIdOf(uid)) != null) return await finish();
      const outcome = await api.joinByEmail();
      set(outcome === 'joined' ? 'claim' : outcome === 'noTeamForDomain' ? 'noTeam' : 'unverified');
    } catch (e) {
      // A PostgREST error means we reached the server; it's the request that failed.
      set(e instanceof PostgrestError ? 'serverError' : 'offline');
    }
  };

  useEffect(() => {
    check();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const introDone = async () => {
    const uid = api.userId;
    if (uid) await api.markIntroSeen(uid);
    set('done');
  };

  const useInviteCode = () => {
    setBeforeInvite(stage);
    set('invite');
  };

  const domain = (api.email ?? '').split('@').pop();
  let page: ReactNode;
  switch (stage) {
    case 'done':
      page = children;
      break;
    case 'checking':
      page = <Splash />;
      break;
    case 'claim':
      page = <ClaimProfile api={api} onDone={finish} />;
      break;
    case 'intro':
      page = <Intro onDone={introDone} />;
      break;
    case 'invite':
      page = <InviteCode api={api} onBack={() => set(beforeInvite)} onJoined={() => set('claim')} />;
      break;
    case 'noTeam':
      page = (
        <GateMessage
          icon="school"
          title={`PR Vault isn't at ${domain} yet`}
          body="Right now it's open to teams that have been set up. If your team gave you an invite code, you can use that instead."
          action="Use an invite code"
          onAction={useInviteCode}
          onSignOut={() => api.signOut()}
        />
      );
      break;
    case 'unverified':
      page = (
        <GateMessage
          icon="mark-email-unread"
          title="We couldn't confirm your email"
          body="This account was created without an email code, so we can't match it to your team. Join with an invite code, or sign out and make a new account with a different school address."
          action="Use an invite code"
          onAction={useInviteCode}
          onSignOut={() => api.signOut()}
        />
      );
      break;
    case 'offline':
      page = (
        <GateMessage
          icon="cloud-off"
          title="Couldn't reach PR Vault"
          body="Check your connection and try again."
          action="Try again"
          onAction={check}
          onSignOut={() => api.signOut()}
        />
      );
      break;
    case 'serverError':
      page = (
        <GateMessage
          icon="error-outline"
          title="Couldn't finish setting up your account"
          body="Something went wrong on PR Vault's end. Try again in a bit, or join with an invite code."
          action="Try again"
          onAction={check}
          secondary="Use an invite code"
          onSecondary={useInviteCode}
          onSignOut={() => api.signOut()}
        />
      );
      break;
  }

  return (
    <Animated.View key={stage} entering={FadeIn.duration(300)} exiting={FadeOut.duration(200)} style={{ flex: 1 }}>
      {page}
    </Animated.View>
  );
}

function Splash() {
  const dark = useDark();
  return (
    <View style={{ flex: 1, backgroundColor: C.bg(dark), alignItems: 'center', justifyContent: 'center' }}>
      <Spinner color={C.accentOf(dark)} />
    </View>
  );
}

/** A full-screen explanation with one action and a way to sign out. */
function GateMessage({
  icon,
  title,
  body,
  action,
  onAction,
  secondary,
  onSecondary,
  onSignOut,
}: {
  icon: IconName;
  title: string;
  body: string;
  action: string;
  onAction: () => void;
  secondary?: string;
  onSecondary?: () => void;
  onSignOut: () => void;
}) {
  const dark = useDark();
  return (
    <StepScaffold>
      <View style={{ flex: 1 }} />
      <HeroIcon icon={icon} dark={dark} />
      <View style={{ height: 28 }} />
      <StepHeading title={title} body={body} dark={dark} />
      <View style={{ flex: 1 }} />
      <PrimaryButton label={action} onPress={onAction} dark={dark} />
      {secondary && (
        <View style={{ marginTop: 10 }}>
          <PrimaryButton label={secondary} onPress={onSecondary ?? (() => {})} dark={dark} tone="soft" />
        </View>
      )}
      <View style={{ height: 4 }} />
      <LinkButton label="Sign out" onPress={onSignOut} dark={dark} />
      <View style={{ height: 12 }} />
    </StepScaffold>
  );
}

// ─── Verify email ─────────────────────────────────────────────────────────────

/** Matches auth.email.max_frequency; resending sooner is rejected. */
const resendWait = 60;

/**
 * Collects the code emailed after sign-up. Verifying signs the user in, and
 * the auth gate swaps this screen for the app.
 */
export function VerifyEmail({ email, api = onboardingApi }: { email: string; api?: OnboardingApi }) {
  const dark = useDark();
  const [code, setCode] = useState('');
  const [verifying, setVerifying] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [cooldown, setCooldown] = useState(resendWait); // a code was just sent

  useEffect(() => {
    if (cooldown <= 0) return;
    const t = setTimeout(() => setCooldown((c) => c - 1), 1000);
    return () => clearTimeout(t);
  }, [cooldown]);

  const verify = async (value: string) => {
    if (verifying) return;
    setVerifying(true);
    try {
      await api.verifySignup(email, value);
    } catch (e) {
      setCode('');
      setVerifying(false);
      setError(
        e instanceof AuthError
          ? "That code didn't work. Check the newest email, or send a new one."
          : "Couldn't reach PR Vault. Check your connection and try again.",
      );
    }
  };

  const onChange = (value: string) => {
    setCode(value);
    if (error) setError(null);
    if (value.length === kCodeLength) verify(value);
  };

  const resend = async () => {
    try {
      await api.resendSignup(email);
      setCooldown(resendWait);
      toast('New code sent');
    } catch (e) {
      if (e instanceof AuthError) setError(e.message);
    }
  };

  return (
    <StepScaffold onBack={() => router.back()}>
      <View style={{ height: 36 }} />
      <HeroIcon icon="mark-email-read" dark={dark} />
      <View style={{ height: 28 }} />
      <StepHeading title="Check your email" body={`We sent a ${kCodeLength}-digit code to\n${email}`} dark={dark} />
      <View style={{ height: 32 }} />
      <CodeCells value={code} length={kCodeLength} onChange={onChange} error={error != null} busy={verifying} dark={dark} />
      {error && <Text style={{ marginTop: 12, textAlign: 'center', fontSize: 13, lineHeight: 18, color: C.accentOf(dark) }}>{error}</Text>}
      <View style={{ height: 16 }} />
      <LinkButton
        label={cooldown > 0 ? `Send a new code in ${cooldown}s` : 'Send a new code'}
        onPress={cooldown > 0 ? undefined : resend}
        dark={dark}
        accent
      />
    </StepScaffold>
  );
}

// ─── Which one is you? ────────────────────────────────────────────────────────

/**
 * Last onboarding step: pick your scraped TFRRS profile so your PRs and meets
 * move onto your account. Skippable; the Profile tab can link later.
 */
export function ClaimProfile({ api, onDone }: { api: OnboardingApi; onDone: () => void }) {
  const dark = useDark();
  const insets = useSafeAreaInsets();
  const [query, setQuery] = useState('');
  const [roster, setRoster] = useState<RosterEntry[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [claiming, setClaiming] = useState<string | null>(null);

  const load = async () => {
    setFailed(false);
    try {
      setRoster(await api.unclaimedRoster());
    } catch {
      setFailed(true);
    }
  };

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const q = query.trim().toLowerCase();
  const matches = (roster ?? []).filter((r) => !q || formatName(r.name).toLowerCase().includes(q) || r.name.toLowerCase().includes(q));

  const pick = async (entry: RosterEntry) => {
    const name = formatName(entry.name);
    const ok = await confirmAction({
      title: `Are you ${name}?`,
      message: 'Their PRs, meets and rankings from TFRRS will move onto your account.',
      confirmLabel: "Yes, that's me",
      cancelLabel: 'Not me',
    });
    if (!ok) return;
    haptic.medium();
    setClaiming(entry.id);
    try {
      await api.claim(entry.id);
      onDone();
    } catch {
      setClaiming(null);
      toast("Couldn't link that profile. Try again.");
      load(); // someone else may have just claimed it
    }
  };

  /** One card of names, separated by hairlines. */
  const group = (entries: RosterEntry[]) => (
    <GlassCard dark={dark}>
      {entries.map((entry, i) => {
        const detail = entry.onRoster ? classYearLabel(entry.classYear) : 'Alum';
        return (
          <View key={entry.id}>
            {i > 0 && <Divider dark={dark} inset={68} />}
            <PressScale pressedScale={0.98} onPress={claiming == null ? () => pick(entry) : undefined}>
              <View style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12 }}>
                <InitialsAvatar name={entry.name} gender={entry.gender} dark={dark} />
                <View style={{ flex: 1, marginLeft: 12 }}>
                  <Text style={{ fontSize: 16, fontWeight: '600', color: C.text1(dark) }}>{formatName(entry.name)}</Text>
                  {detail && <Text style={{ fontSize: 13, color: C.text3(dark) }}>{detail}</Text>}
                </View>
                {claiming === entry.id && <Spinner color={C.accentOf(dark)} />}
              </View>
            </PressScale>
          </View>
        );
      })}
    </GlassCard>
  );

  const current = matches.filter((e) => e.onRoster);
  const alumni = matches.filter((e) => !e.onRoster);

  return (
    <ScrollView style={{ backgroundColor: C.bg(dark) }} keyboardShouldPersistTaps="handled" keyboardDismissMode="on-drag">
      <WashHeader dark={dark} style={{ paddingHorizontal: 20, paddingTop: insets.top + 32 }}>
        <Text style={pageTitleStyle(dark)}>Which one is you?</Text>
        <Text style={{ marginTop: 8, fontSize: 15, lineHeight: 21, color: C.text2(dark) }}>
          Pick your name from your team on TFRRS to bring in your PRs and meets.
        </Text>
      </WashHeader>
      <View style={{ paddingHorizontal: 20, paddingTop: 20, paddingBottom: 16 }}>
        <InputField value={query} onChangeText={setQuery} hint="Search your name" icon="search" dark={dark} clearable autoCorrect={false} />
      </View>
      {failed ? (
        <View style={{ paddingTop: 24 }}>
          <EmptyState icon="cloud-off" title="Couldn't load your team" actionLabel="Try again" onAction={load} dark={dark} />
        </View>
      ) : roster == null ? (
        <View style={{ paddingTop: 40, alignItems: 'center' }}>
          <Spinner color={C.accentOf(dark)} />
        </View>
      ) : (
        // Current roster first; graduates and others who've left can still
        // find themselves under Alumni.
        <View style={{ paddingHorizontal: 20 }}>
          {current.length > 0 && group(current)}
          {alumni.length > 0 && (
            <>
              <Text style={[sectionTitleStyle(dark), { paddingHorizontal: 4, paddingTop: 24, paddingBottom: 10 }]}>Alumni</Text>
              {group(alumni)}
            </>
          )}
        </View>
      )}
      <View style={{ paddingHorizontal: 20, paddingTop: 12, paddingBottom: insets.bottom + 32 }}>
        <LinkButton
          label={roster != null && matches.length === 0 ? "Can't find yourself? Skip for now" : "I'm not on TFRRS yet"}
          onPress={claiming == null ? onDone : undefined}
          dark={dark}
        />
      </View>
    </ScrollView>
  );
}

// ─── Invite code ──────────────────────────────────────────────────────────────

/** Fallback for joining a team without a matching school email. */
export function InviteCode({ api, onBack, onJoined }: { api: OnboardingApi; onBack: () => void; onJoined: () => void }) {
  const dark = useDark();
  const [code, setCode] = useState('');
  const [loading, setLoading] = useState(false);

  const submit = async () => {
    const value = code.trim().toUpperCase();
    if (!value) return;
    setLoading(true);
    try {
      if (await api.joinByCode(value)) {
        setLoading(false);
        onJoined();
        return;
      }
      toast("That code doesn't match a team.");
    } catch (e) {
      toast(`Something went wrong: ${(e as Error).message}`);
    }
    setLoading(false);
  };

  return (
    <StepScaffold onBack={onBack}>
      <View style={{ flex: 1 }} />
      <HeroIcon icon="key" dark={dark} />
      <View style={{ height: 28 }} />
      <StepHeading title="Enter invite code" body="If your team gave you a code, enter it here." dark={dark} />
      <View style={{ flex: 1 }} />
      <InputField value={code} onChangeText={setCode} hint="Invite code" icon="tag" dark={dark} autoCapitalize="characters" autoCorrect={false} onSubmitEditing={submit} />
      <View style={{ height: 14 }} />
      <PrimaryButton label="Join Team" loading={loading} onPress={submit} dark={dark} />
      <View style={{ height: 24 }} />
    </StepScaffold>
  );
}
