import { useEffect, useState } from 'react';
import {
  FlatList,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import Animated, { FadeIn, FadeInDown, FadeOut, SlideOutRight } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { FadeSlideIn, PressScale } from '@/components/motion';
import { confirmAction, toast } from '@/components/overlay';
import { AppChip, ChipRow, EmptyState, Icon, InitialsAvatar, PrimaryButton, Spinner, WashHeader, pageTitleStyle } from '@/components/ui';
import { formatName } from '@/lib/format';
import { haptic } from '@/lib/haptics';
import { Prefs, prefsStore, usePrefs } from '@/lib/prefs';
import { Row } from '@/lib/prStats';
import { currentUserId } from '@/lib/session';
import { supabase } from '@/lib/supabase';
import { C, cardStyle, useDark } from '@/theme/colors';

const liftTypes = ['Squat', 'Bench Press', 'Power Clean', 'Deadlift'];

export function Maxes() {
  const dark = useDark();
  const prefs = usePrefs();
  const insets = useSafeAreaInsets();
  const myId = currentUserId();
  const [lift, setLift] = useState('Squat');
  // Every lift for the team, so switching lifts is instant.
  const [all, setAll] = useState<Row[]>([]);
  const [teamId, setTeamId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [animateRows, setAnimateRows] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [entryOpen, setEntryOpen] = useState(false);

  const loadMaxes = async (team = teamId) => {
    try {
      let q = supabase.from('lifting_maxes').select('weight_lbs, lift_type, athlete_id, profiles!inner(full_name, gender)');
      if (team) q = q.eq('team_id', team);
      const { data } = await q.order('weight_lbs', { ascending: false }).throwOnError();
      setAll(data ?? []);
    } catch {}
    setLoading(false);
    // Only the first screenful of the first load gets the entrance stagger.
    setTimeout(() => setAnimateRows(false), 0);
  };

  useEffect(() => {
    (async () => {
      let team: string | null = null;
      try {
        const { data } = await supabase.from('profiles').select('team_id').eq('id', myId!).single().throwOnError();
        team = (data as any)?.team_id ?? null;
        setTeamId(team);
      } catch {}
      await loadMaxes(team);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const confirmDelete = async (entry: Row) => {
    const liftType = lift;
    haptic.medium();
    const sure = await confirmAction({
      title: `Delete ${liftType} max?`,
      message: `${prefs.weight(entry.weight_lbs)} will be removed.`,
      confirmLabel: 'Delete',
      destructive: true,
    });
    if (!sure) return;
    haptic.heavy();
    try {
      await supabase.from('lifting_maxes').delete().eq('athlete_id', myId!).eq('lift_type', liftType).throwOnError();
    } catch {
      toast("Couldn't delete that max. Try again.");
    }
    await loadMaxes();
  };

  const board = all.filter((m) => m.lift_type === lift);

  return (
    <View style={{ flex: 1, backgroundColor: C.bg(dark) }}>
      <WashHeader dark={dark} style={{ paddingHorizontal: 20, paddingTop: insets.top + 16 }}>
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <Text style={[pageTitleStyle(dark), { flex: 1 }]}>Maxes</Text>
          <PressScale onPress={() => setEntryOpen(true)}>
            <View
              style={{
                height: 38,
                paddingLeft: 12,
                paddingRight: 16,
                borderRadius: 100,
                backgroundColor: C.accentOf(dark),
                flexDirection: 'row',
                alignItems: 'center',
              }}
            >
              <Icon name="add" size={18} color="#fff" />
              <Text style={{ marginLeft: 4, color: '#fff', fontSize: 14, fontWeight: '600' }}>Log Max</Text>
            </View>
          </PressScale>
        </View>
      </WashHeader>
      <View style={{ height: 16 }} />
      <ChipRow
        height={44}
        chips={liftTypes.map((l) => (
          <AppChip key={l} label={l} selected={l === lift} dark={dark} onPress={() => setLift(l)} />
        ))}
      />
      <View style={{ height: 8 }} />
      {loading ? (
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
          <Spinner color={C.accentOf(dark)} />
        </View>
      ) : (
        <Animated.View key={lift} entering={FadeIn.duration(180)} style={{ flex: 1 }}>
          <FlatList
            data={board}
            alwaysBounceVertical
            refreshControl={
              <RefreshControl
                refreshing={refreshing}
                tintColor={C.accentOf(dark)}
                onRefresh={async () => {
                  haptic.light();
                  setRefreshing(true);
                  await loadMaxes();
                  setRefreshing(false);
                }}
              />
            }
            contentContainerStyle={{ paddingBottom: 120, flexGrow: 1 }}
            keyExtractor={(m) => `${m.athlete_id}`}
            ListEmptyComponent={
              <View style={{ paddingTop: 110 }}>
                <EmptyState
                  icon="fitness-center"
                  title={`No ${lift} maxes yet`}
                  message="Log yours to start the board."
                  actionLabel="Log Max"
                  onAction={() => setEntryOpen(true)}
                  dark={dark}
                />
              </View>
            }
            renderItem={({ item, index }) => {
              const isMe = item.athlete_id === myId;
              return (
                <Animated.View exiting={SlideOutRight.duration(300)}>
                  <FadeSlideIn animate={animateRows && index < 12} delay={index * 40}>
                    <Pressable onLongPress={isMe ? () => confirmDelete(item) : undefined}>
                      <MaxRow
                        rank={index + 1}
                        rawName={item.profiles?.full_name ?? ''}
                        gender={item.profiles?.gender ?? 'M'}
                        weight={item.weight_lbs}
                        isMe={isMe}
                        dark={dark}
                        prefs={prefs}
                      />
                    </Pressable>
                  </FadeSlideIn>
                </Animated.View>
              );
            }}
          />
        </Animated.View>
      )}
      <MaxEntrySheet
        visible={entryOpen}
        teamId={teamId ?? ''}
        athleteId={myId ?? ''}
        initialLift={lift}
        onClose={() => setEntryOpen(false)}
        onSaved={() => loadMaxes()}
      />
    </View>
  );
}

function MaxRow({
  rank,
  rawName,
  gender,
  weight,
  isMe,
  dark,
  prefs,
}: {
  rank: number;
  rawName: string;
  gender: string;
  weight: number;
  isMe: boolean;
  dark: boolean;
  prefs: Prefs;
}) {
  return (
    <View
      style={{
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: 20,
        paddingVertical: 12,
        backgroundColor: isMe ? C.accentSoft(dark) : 'transparent',
      }}
    >
      <Text
        style={{
          width: 30,
          textAlign: 'center',
          fontSize: 17,
          fontWeight: '800',
          letterSpacing: -0.5,
          fontVariant: ['tabular-nums'],
          color: rank <= 3 ? C.accentOf(dark) : C.text3(dark),
        }}
      >
        {rank}
      </Text>
      <View style={{ width: 12 }} />
      <InitialsAvatar name={rawName} gender={gender} dark={dark} />
      <View style={{ flex: 1, marginLeft: 12 }}>
        <Text numberOfLines={1} style={{ fontSize: 15, fontWeight: '600', letterSpacing: -0.15, color: C.text1(dark) }}>
          {formatName(rawName || '—')}
        </Text>
        {isMe && <Text style={{ fontSize: 12, color: C.text3(dark) }}>You · hold to delete</Text>}
      </View>
      <Text style={{ fontSize: 17, fontWeight: '800', letterSpacing: -0.4, color: rank <= 3 ? C.accentOf(dark) : C.text1(dark) }}>
        {prefs.weight(weight)}
      </Text>
    </View>
  );
}

/** A floating card above the keyboard, like the other sheets. */
function MaxEntrySheet({
  visible,
  teamId,
  athleteId,
  initialLift,
  onClose,
  onSaved,
}: {
  visible: boolean;
  teamId: string;
  athleteId: string;
  initialLift: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const dark = useDark();
  const prefs = usePrefs();
  const insets = useSafeAreaInsets();
  const [lift, setLift] = useState(initialLift);
  const [weight, setWeight] = useState('');
  const [saving, setSaving] = useState(false);
  // Shown in the card: a toast would sit behind it.
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (visible) {
      setLift(initialLift);
      setWeight('');
      setError(null);
    }
  }, [visible, initialLift]);

  const save = async () => {
    const entered = parseFloat(weight.trim());
    const lbs = isNaN(entered) ? null : prefsStore.get().toLbs(entered);
    if (lbs == null || lbs <= 0) {
      setError('Enter a valid weight');
      return;
    }
    setError(null);
    setSaving(true);
    try {
      await supabase
        .from('lifting_maxes')
        .upsert(
          { athlete_id: athleteId, team_id: teamId, lift_type: lift, weight_lbs: lbs, updated_at: new Date().toISOString() },
          { onConflict: 'athlete_id,lift_type' },
        )
        .throwOnError();
      onSaved();
      onClose();
    } catch (e) {
      setError(`Couldn't save: ${(e as Error).message}`);
    }
    setSaving(false);
  };

  return (
    <Modal visible={visible} transparent animationType="none" onRequestClose={onClose}>
      {visible && (
        <KeyboardAvoidingView style={{ flex: 1, justifyContent: 'flex-end' }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
          <Animated.View entering={FadeIn.duration(200)} exiting={FadeOut.duration(160)} style={StyleSheet.absoluteFill}>
            <Pressable style={{ flex: 1, backgroundColor: 'rgba(0, 0, 0, 0.4)' }} onPress={onClose} />
          </Animated.View>
          <Animated.View entering={FadeInDown.springify().damping(18)} style={{ paddingHorizontal: 10, paddingBottom: Math.max(insets.bottom, 10) }}>
            <View style={[cardStyle(dark, 32, C.sheet(dark)), { paddingHorizontal: 22, paddingTop: 24, paddingBottom: 16 }]}>
              <Text style={{ fontSize: 21, fontWeight: '800', letterSpacing: -0.4, color: C.text1(dark) }}>Log a Max</Text>
              <ScrollView horizontal={false} scrollEnabled={false} contentContainerStyle={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginTop: 18 }}>
                {liftTypes.map((l) => (
                  <AppChip key={l} label={l} selected={l === lift} dark={dark} small onPress={() => setLift(l)} />
                ))}
              </ScrollView>
              <View
                style={{
                  marginTop: 18,
                  height: 72,
                  paddingHorizontal: 20,
                  borderRadius: 18,
                  backgroundColor: C.field(dark),
                  flexDirection: 'row',
                  alignItems: 'center',
                }}
              >
                <TextInput
                  value={weight}
                  onChangeText={(t) => (setWeight(t), setError(null))}
                  keyboardType="decimal-pad"
                  autoFocus
                  placeholder={prefs.liftUnits === 'kg' ? '140' : '315'}
                  placeholderTextColor={`${C.text3(dark)}80`}
                  keyboardAppearance={dark ? 'dark' : 'light'}
                  selectionColor={C.accentOf(dark)}
                  style={{ flex: 1, fontSize: 30, fontWeight: '800', letterSpacing: -0.8, color: C.text1(dark), paddingVertical: 0 }}
                />
                <Text style={{ fontSize: 17, fontWeight: '700', color: C.text3(dark) }}>{prefs.weightUnit}</Text>
              </View>
              {error && <Text style={{ marginTop: 10, fontSize: 13, color: C.accentOf(dark) }}>{error}</Text>}
              <View style={{ height: 18 }} />
              <PrimaryButton label="Save" loading={saving} onPress={save} dark={dark} />
            </View>
          </Animated.View>
        </KeyboardAvoidingView>
      )}
    </Modal>
  );
}
