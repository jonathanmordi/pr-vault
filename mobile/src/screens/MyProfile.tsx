import { useEffect, useRef, useState } from 'react';
import { ScrollView, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { FadeSlideIn, PressScale } from '@/components/motion';
import { confirmAction, toast } from '@/components/overlay';
import {
  Divider,
  EmptyState,
  GlassCard,
  GradientAvatar,
  InitialsAvatar,
  InputField,
  SectionTitle,
  Spinner,
  WashHeader,
  pageTitleStyle,
} from '@/components/ui';
import { formatName } from '@/lib/format';
import { Row } from '@/lib/prStats';
import { currentUser } from '@/lib/session';
import { supabase } from '@/lib/supabase';
import { TeamData, TeamSnapshot } from '@/lib/teamData';
import { C, useDark } from '@/theme/colors';

import { AthleteProfile } from './AthleteProfile';

type Profile = { full_name?: string; gender?: string; role?: string };

/**
 * The Profile tab: your own profile once your TFRRS results are linked,
 * otherwise a search to link them.
 */
export function MyProfile() {
  const dark = useDark();
  const insets = useSafeAreaInsets();
  const uid = currentUser()?.id ?? null;

  // If the team's data has your PRs you're linked, so show your profile at
  // once instead of waiting to check with the server.
  const saved = (team: TeamSnapshot | null) => {
    if (!team || !uid) return null;
    const prs = team.prsOf(uid);
    if (prs.length === 0) return null;
    const me = prs[0].profiles;
    return { full_name: me?.full_name ?? 'Unknown', gender: me?.gender ?? 'M' };
  };

  const initial = saved(TeamData.instance.cached);
  const [profile, setProfile] = useState<Profile | null>(initial);
  const [linked, setLinked] = useState(initial != null);
  const [loading, setLoading] = useState(initial == null);
  const linkedRef = useRef(linked);
  linkedRef.current = linked;

  // Linking search flow.
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Row[]>([]);
  const [searching, setSearching] = useState(false);
  const [linking, setLinking] = useState(false);
  const debounce = useRef<ReturnType<typeof setTimeout> | null>(null);
  const searchSeq = useRef(0);

  const load = async () => {
    if (!uid) return;
    try {
      const { data: p } = await supabase.from('profiles').select().eq('id', uid).maybeSingle().throwOnError();
      if (p) {
        const { data: prs } = await supabase.from('track_prs').select().eq('athlete_id', uid).order('event').throwOnError();
        setProfile(p);
        setLinked((prs ?? []).length > 0);
        setLoading(false);
        return;
      }
    } catch {
      // Offline: keep showing the saved profile rather than the link flow.
      if (linkedRef.current) return;
    }

    const user = currentUser();
    const name = user?.user_metadata?.full_name ?? (user?.email ?? '').split('@')[0];
    try {
      // New profiles start teamless; team_id is only ever set by join_team.
      await supabase.from('profiles').insert({ id: uid, full_name: name, role: 'athlete' }).throwOnError();
    } catch {}
    setProfile({ full_name: name, role: 'athlete' });
    setLinked(false);
    setLoading(false);
  };

  useEffect(() => {
    if (!linkedRef.current) {
      TeamData.instance.restore().then((t) => {
        const p = saved(t);
        if (p && !linkedRef.current) {
          setProfile(p);
          setLinked(true);
          setLoading(false);
        }
      });
    }
    load();
    return () => {
      if (debounce.current) clearTimeout(debounce.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const searchAthletes = async (q: string) => {
    // Responses can arrive out of order; only the latest search may win.
    const seq = ++searchSeq.current;
    if (q.length < 2) {
      setResults([]);
      setSearching(false);
      return;
    }
    setSearching(true);
    try {
      const { data } = await supabase
        .from('profiles')
        .select('id, full_name, gender, tfrrs_athlete_id')
        .not('tfrrs_athlete_id', 'is', null)
        .ilike('full_name', `%${q}%`)
        .limit(10)
        .throwOnError();
      if (seq !== searchSeq.current) return;
      setResults(data ?? []);
    } catch {}
    if (seq === searchSeq.current) setSearching(false);
  };

  /** Waits for a pause in typing instead of querying on every keystroke. */
  const onQuery = (q: string) => {
    setQuery(q);
    if (debounce.current) clearTimeout(debounce.current);
    debounce.current = setTimeout(() => searchAthletes(q), 250);
  };

  const link = async (tfrrsProfile: Row) => {
    const name = formatName(tfrrsProfile.full_name ?? 'Unknown');
    const ok = await confirmAction({
      title: `Are you ${name}?`,
      message: 'Their PRs, meets and rankings from TFRRS will move onto your account.',
      confirmLabel: "Yes, that's me",
      cancelLabel: 'Not me',
    });
    if (!ok) return;
    setLinking(true);
    try {
      // Moves the scraped profile's PRs and meet history onto our account in
      // one server-side transaction (see claim_tfrrs_profile).
      await supabase.rpc('claim_tfrrs_profile', { p_profile_id: tfrrsProfile.id }).throwOnError();
      // Our results just moved to a new athlete id; drop the stale cache.
      TeamData.instance.load({ force: true }).catch(() => {});
      await load();
    } catch (e) {
      toast(`Failed to link profile: ${(e as Error).message}`);
    }
    setLinking(false);
  };

  if (loading) {
    return (
      <View style={{ flex: 1, backgroundColor: C.bg(dark), alignItems: 'center', justifyContent: 'center' }}>
        <Spinner color={C.accentOf(dark)} />
      </View>
    );
  }

  // Linked: your own athlete profile.
  if (linked && profile && uid) {
    return <AthleteProfile athleteId={uid} athleteName={profile.full_name ?? 'Unknown'} gender={profile.gender ?? 'M'} showBackButton={false} />;
  }

  if (!profile) {
    return (
      <View style={{ flex: 1, backgroundColor: C.bg(dark), justifyContent: 'center' }}>
        <EmptyState icon="person-off" title="Profile not found" dark={dark} />
      </View>
    );
  }

  const name = profile.full_name ?? 'Unknown';
  return (
    <ScrollView style={{ backgroundColor: C.bg(dark) }} contentContainerStyle={{ paddingBottom: 120 }} keyboardShouldPersistTaps="handled" keyboardDismissMode="on-drag">
      <WashHeader dark={dark} style={{ paddingHorizontal: 20, paddingTop: insets.top + 16, paddingBottom: 24 }}>
        <Text style={pageTitleStyle(dark)}>My Profile</Text>
        <FadeSlideIn style={{ marginTop: 24, flexDirection: 'row', alignItems: 'center' }}>
          <GradientAvatar name={name} female={false} dark={dark} size={72} />
          <View style={{ flex: 1, marginLeft: 16 }}>
            <Text style={{ fontSize: 24, fontWeight: '800', letterSpacing: -0.6, color: C.text1(dark) }}>{formatName(name)}</Text>
            <Text style={{ marginTop: 2, fontSize: 14, color: C.text2(dark) }}>
              {profile.role === 'coach' ? 'Coach' : 'Athlete · not linked to TFRRS yet'}
            </Text>
          </View>
        </FadeSlideIn>
      </WashHeader>
      <FadeSlideIn delay={80} style={{ paddingHorizontal: 20 }}>
        <SectionTitle text="Link your TFRRS profile" dark={dark} />
        <Text style={{ marginTop: 6, fontSize: 14, lineHeight: 20, color: C.text2(dark) }}>
          Find your name to bring in your race results and PRs.
        </Text>
        <View style={{ height: 16 }} />
        <InputField
          value={query}
          onChangeText={onQuery}
          hint="Search by name"
          icon="search"
          dark={dark}
          clearable
          autoCorrect={false}
          onClear={() => {
            if (debounce.current) clearTimeout(debounce.current);
            searchSeq.current++; // drop any search still in flight
            setResults([]);
            setSearching(false);
          }}
        />
        <View style={{ height: 16 }} />
        {searching || linking ? (
          <View style={{ paddingTop: 8, alignItems: 'center' }}>
            <Spinner color={C.accentOf(dark)} />
            {linking && <Text style={{ marginTop: 10, fontSize: 14, color: C.text2(dark) }}>Linking your profile…</Text>}
          </View>
        ) : results.length > 0 ? (
          <GlassCard dark={dark}>
            {results.map((r, i) => (
              <View key={r.id}>
                {i > 0 && <Divider dark={dark} inset={68} />}
                <PressScale pressedScale={0.98} onPress={() => link(r)}>
                  <View style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12 }}>
                    <InitialsAvatar name={r.full_name ?? ''} gender={r.gender ?? 'M'} dark={dark} />
                    <View style={{ marginLeft: 12 }}>
                      <Text style={{ fontSize: 16, fontWeight: '600', color: C.text1(dark) }}>{formatName(r.full_name ?? '')}</Text>
                      <Text style={{ fontSize: 13, color: C.text3(dark) }}>TFRRS #{r.tfrrs_athlete_id ?? ''}</Text>
                    </View>
                  </View>
                </PressScale>
              </View>
            ))}
          </GlassCard>
        ) : query.length >= 2 ? (
          <EmptyState icon="search-off" title="No athletes found" message="Try your last name." dark={dark} />
        ) : null}
      </FadeSlideIn>
    </ScrollView>
  );
}
