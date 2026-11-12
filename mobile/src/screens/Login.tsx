// Sign-in and sign-up. A red hero shows what the app does (a track, a few
// cards like the ones inside), with the form on a card below it.

import { AuthError, isAuthRetryableFetchError } from '@supabase/supabase-js';
import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { KeyboardAvoidingView, Platform, Text, View } from 'react-native';
import Animated, {
  Easing,
  FadeIn,
  LinearTransition,
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withRepeat,
  withTiming,
} from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { FadeSlideIn } from '@/components/motion';
import { toast } from '@/components/overlay';
import { SegmentToggle } from '@/components/SegmentToggle';
import { TrackBackdrop } from '@/components/TrackBackdrop';
import { BrandMark, Icon, IconName, InputField, PrimaryButton } from '@/components/ui';
import { onboardingApi } from '@/lib/onboardingApi';
import { C, useDark } from '@/theme/colors';

/** Email/password sign-in, and sign-up with a school email that's verified with an emailed code. */
export function Login() {
  const dark = useDark();
  const insets = useSafeAreaInsets();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [loading, setLoading] = useState(false);
  const [signUp, setSignUp] = useState(false);
  const [heroH, setHeroH] = useState(0);

  const openVerify = (address: string) => router.push({ pathname: '/verify', params: { email: address } });

  const submit = async () => {
    const address = email.trim();
    setLoading(true);
    try {
      if (signUp) {
        const res = await onboardingApi.signUp(address, password.trim(), name.trim());
        // With email confirmation on there's no session until the emailed
        // code is entered. Without it, the auth gate takes over straight away.
        if (!res.session) openVerify(address);
      } else {
        try {
          await onboardingApi.signIn(address, password.trim());
        } catch (e) {
          // Signed up but never entered the code: send a fresh one.
          if (!(e instanceof AuthError) || e.code !== 'email_not_confirmed') throw e;
          await onboardingApi.resendSignup(address);
          openVerify(address);
        }
      }
    } catch (e) {
      // A network failure comes back as an auth error too; say it plainly.
      toast(e instanceof AuthError && !isAuthRetryableFetchError(e) ? e.message : "Couldn't reach PR Vault. Check your connection.");
    }
    setLoading(false);
  };

  // Drops the cards, then the pitch, as the keyboard or the sign-up fields
  // take the room.
  const showCards = heroH >= 380;
  const showHeadline = heroH >= 130;
  const showPitch = heroH >= 200;

  return (
    <View style={{ flex: 1, backgroundColor: C.bg(dark) }}>
      <TrackBackdrop dark={dark} />
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <View
          style={{ flex: 1, paddingTop: insets.top + 12, paddingHorizontal: 24, paddingBottom: 24 }}
          onLayout={(e) => setHeroH(e.nativeEvent.layout.height - insets.top - 36)}
        >
          <BrandMark />
          <View style={{ flex: 1 }}>{showCards && <PreviewCards />}</View>
          {showHeadline && (
            <Text style={{ fontSize: 42, lineHeight: 43, fontWeight: '900', letterSpacing: -1.6, color: '#fff' }}>
              {signUp ? 'Join your\nteam.' : 'Every PR.\nOne vault.'}
            </Text>
          )}
          {showPitch && (
            <Text style={{ marginTop: 10, fontSize: 15, lineHeight: 21, color: 'rgba(255, 255, 255, 0.78)' }}>
              {signUp
                ? 'Your TFRRS results come with you. Rankings, rivals and lifts, all in one place.'
                : 'Your TFRRS results, team rankings, rivals and lifts, all in one place.'}
            </Text>
          )}
        </View>
        <Animated.View
          layout={LinearTransition.duration(280)}
          style={{
            backgroundColor: C.bg(dark),
            borderTopLeftRadius: 32,
            borderTopRightRadius: 32,
            paddingHorizontal: 20,
            paddingTop: 20,
            paddingBottom: Math.max(insets.bottom, 12) + 8,
          }}
        >
          <SegmentToggle
            options={['Sign In', 'Sign Up']}
            value={signUp ? 'Sign Up' : 'Sign In'}
            dark={dark}
            height={40}
            fontSize={14}
            fill
            onChange={(v) => setSignUp(v === 'Sign Up')}
          />
          <View style={{ height: 16 }} />
          {signUp && (
            <Animated.View entering={FadeIn.duration(200)} style={{ marginBottom: 10 }}>
              <InputField value={name} onChangeText={setName} hint="Full name" icon="person-outline" dark={dark} textContentType="name" autoComplete="name" />
            </Animated.View>
          )}
          <InputField
            value={email}
            onChangeText={setEmail}
            hint={signUp ? 'School email' : 'Email'}
            icon="mail-outline"
            dark={dark}
            keyboardType="email-address"
            autoCapitalize="none"
            autoCorrect={false}
            textContentType="emailAddress"
            autoComplete="email"
          />
          <View style={{ height: 10 }} />
          <InputField
            value={password}
            onChangeText={setPassword}
            hint="Password"
            icon="lock-outline"
            dark={dark}
            secureTextEntry
            textContentType={signUp ? 'newPassword' : 'password'}
            autoComplete={signUp ? 'new-password' : 'current-password'}
            onSubmitEditing={submit}
          />
          {signUp && (
            <Text style={{ marginTop: 12, fontSize: 13, lineHeight: 18, color: C.text3(dark) }}>
              Use your school email and you'll join your team automatically. We'll send a code to check it.
            </Text>
          )}
          <View style={{ height: 16 }} />
          <PrimaryButton label={signUp ? 'Create Account' : 'Sign In'} loading={loading} onPress={submit} dark={dark} />
        </Animated.View>
      </KeyboardAvoidingView>
    </View>
  );
}

type Preview = { icon: IconName; label: string; value: string; detail: string; solid: boolean };

const previews: Preview[] = [
  { icon: 'bolt', label: 'NEW PR', value: '6.91m', detail: 'Long jump · +0.12m', solid: true },
  { icon: 'military-tech', label: 'NATIONALS', value: '#12 in D3', detail: 'Inside the cut', solid: false },
  { icon: 'trending-up', label: 'TRENDING', value: '+2.6%', detail: 'Better in 3 of 4 meets', solid: false },
];

/** Three tilted cards that gently float: a new PR, a national rank and a trend, like the cards inside the app. */
function PreviewCards() {
  const [box, setBox] = useState({ w: 0, h: 0 });
  const float = useSharedValue(0);
  const reduce = useReducedMotion();
  useEffect(() => {
    if (reduce) return;
    float.value = withRepeat(withTiming(1, { duration: 6000, easing: Easing.linear }), -1, false);
  }, [reduce, float]);

  const { w, h } = box;
  // Shrink the cards on shorter screens instead of overlapping them.
  const scale = Math.max(0.75, Math.min(1, h / 300));
  const spots = [
    { x: 0, y: h * 0.06, tilt: -0.08, phase: 0 },
    { x: w * 0.46, y: h * 0.3, tilt: 0.06, phase: 0.33 },
    { x: w * 0.1, y: h * 0.58, tilt: -0.03, phase: 0.66 },
  ];
  return (
    <View style={{ flex: 1 }} onLayout={(e) => setBox({ w: e.nativeEvent.layout.width, h: e.nativeEvent.layout.height })}>
      {w > 0 &&
        previews.map((p, i) => (
          <FloatingCard key={p.label} preview={p} spot={spots[i]} scale={scale} float={float} delay={120 + 110 * i} />
        ))}
    </View>
  );
}

function FloatingCard({
  preview: p,
  spot,
  scale,
  float,
  delay,
}: {
  preview: Preview;
  spot: { x: number; y: number; tilt: number; phase: number };
  scale: number;
  float: { value: number };
  delay: number;
}) {
  const bob = useAnimatedStyle(() => ({ transform: [{ translateY: 6 * Math.sin(2 * Math.PI * (float.value + spot.phase)) }] }));
  const accent = C.accentOf(false);
  const ink = p.solid ? '#111114' : '#fff';
  const soft = p.solid ? '#6E6E76' : 'rgba(255, 255, 255, 0.75)';
  return (
    <Animated.View style={[{ position: 'absolute', left: spot.x, top: spot.y }, bob]}>
      <FadeSlideIn delay={delay}>
        <View
          style={{
            width: 168,
            paddingHorizontal: 14,
            paddingTop: 12,
            paddingBottom: 14,
            borderRadius: 20,
            backgroundColor: p.solid ? '#fff' : 'rgba(255, 255, 255, 0.13)',
            borderWidth: p.solid ? 0 : 0.8,
            borderColor: 'rgba(255, 255, 255, 0.22)',
            boxShadow: '0 10px 24px rgba(0, 0, 0, 0.22)',
            transform: [{ rotate: `${spot.tilt}rad` }, { scale }],
            transformOrigin: 'top left',
          }}
        >
          <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            <Icon name={p.icon} size={15} color={p.solid ? accent : '#fff'} />
            <Text style={{ marginLeft: 5, fontSize: 11, fontWeight: '800', letterSpacing: 0.7, color: p.solid ? accent : 'rgba(255, 255, 255, 0.85)' }}>
              {p.label}
            </Text>
          </View>
          <Text style={{ marginTop: 8, fontSize: 26, fontWeight: '800', letterSpacing: -0.8, lineHeight: 28, color: ink }}>{p.value}</Text>
          <Text style={{ marginTop: 3, fontSize: 12.5, color: soft }}>{p.detail}</Text>
        </View>
      </FadeSlideIn>
    </Animated.View>
  );
}
