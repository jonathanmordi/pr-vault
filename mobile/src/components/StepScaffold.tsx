import { LinearGradient } from 'expo-linear-gradient';
import { ReactNode } from 'react';
import { KeyboardAvoidingView, Platform, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { C, alpha, useDark, washAlpha } from '@/theme/colors';

import { BackCircle } from './ui';

/**
 * The backdrop for sign-in and onboarding steps: the page color under a tall
 * accent wash, with an optional back button.
 */
export function StepScaffold({ children, onBack }: { children: ReactNode; onBack?: () => void }) {
  const dark = useDark();
  const accent = C.accentOf(dark);
  return (
    <View style={{ flex: 1, backgroundColor: C.bg(dark) }}>
      <LinearGradient
        colors={[alpha(accent, washAlpha(dark) * 1.4), alpha(accent, 0)]}
        locations={[0, 0.55]}
        style={StyleSheet.absoluteFill}
      />
      <SafeAreaView style={{ flex: 1 }}>
        <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
          {onBack && (
            <View style={{ paddingHorizontal: 16, paddingTop: 8, alignItems: 'flex-start' }}>
              <BackCircle onPress={onBack} dark={dark} />
            </View>
          )}
          <View style={{ flex: 1, paddingHorizontal: 24 }}>{children}</View>
        </KeyboardAvoidingView>
      </SafeAreaView>
    </View>
  );
}
