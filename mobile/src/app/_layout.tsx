import { BottomSheetModalProvider } from '@gorhom/bottom-sheet';
import { DarkTheme, DefaultTheme, Stack, ThemeProvider } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { useEffect, useState } from 'react';
import { GestureHandlerRootView } from 'react-native-gesture-handler';

import { OverlayProvider } from '@/components/overlay';
import { prefsStore } from '@/lib/prefs';
import { initSession, useSession } from '@/lib/session';
import { AthleteSheetHost } from '@/screens/athleteSheet';
import { C, useDark } from '@/theme/colors';

SplashScreen.preventAutoHideAsync().catch(() => {});

/** Waits for saved settings and the session, then gates the app on being signed in. */
export default function RootLayout() {
  const [ready, setReady] = useState(false);
  const session = useSession();
  const dark = useDark();

  useEffect(() => {
    Promise.all([prefsStore.load(), initSession()]).finally(() => {
      setReady(true);
      SplashScreen.hideAsync().catch(() => {});
    });
  }, []);

  if (!ready) return null;

  const base = dark ? DarkTheme : DefaultTheme;
  const theme = {
    ...base,
    colors: { ...base.colors, background: C.bg(dark), card: C.bg(dark), primary: C.accentOf(dark), text: C.text1(dark), border: C.border(dark) },
  };

  return (
    <GestureHandlerRootView style={{ flex: 1, backgroundColor: C.bg(dark) }}>
      <ThemeProvider value={theme}>
        <BottomSheetModalProvider>
          <OverlayProvider>
            <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: C.bg(dark) }, statusBarStyle: dark ? 'light' : 'dark' }}>
              <Stack.Protected guard={session != null} redirectTo="/sign-in">
                <Stack.Screen name="index" />
                <Stack.Screen name="activity" />
                <Stack.Screen name="athlete/[id]" />
                <Stack.Screen name="notifications" />
                <Stack.Screen name="units" />
                <Stack.Screen name="tour" options={{ animation: 'fade', statusBarStyle: 'light' }} />
              </Stack.Protected>
              <Stack.Protected guard={session == null} redirectTo="/">
                <Stack.Screen name="sign-in" options={{ animation: 'fade', statusBarStyle: 'light' }} />
                <Stack.Screen name="verify" />
              </Stack.Protected>
            </Stack>
            <AthleteSheetHost />
          </OverlayProvider>
        </BottomSheetModalProvider>
      </ThemeProvider>
    </GestureHandlerRootView>
  );
}
