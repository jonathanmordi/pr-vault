import { ComponentRef, useRef } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

import { C } from '@/theme/colors';

import { Spinner } from './ui';

/**
 * A one-time code shown as a box per digit. An invisible text field over the
 * boxes takes the typing, so paste and code autofill still work.
 */
export function CodeCells({
  value,
  length,
  onChange,
  dark,
  error = false,
  busy = false,
}: {
  value: string;
  length: number;
  onChange: (code: string) => void;
  dark: boolean;
  error?: boolean;
  busy?: boolean;
}) {
  const input = useRef<ComponentRef<typeof TextInput>>(null);
  const accent = C.accentOf(dark);
  return (
    <Pressable style={{ height: 60 }} onPress={() => input.current?.focus()}>
      <View style={{ flex: 1, flexDirection: 'row', gap: 8, opacity: busy ? 0.4 : 1 }}>
        {Array.from({ length }, (_, i) => (
          <View
            key={i}
            style={{
              flex: 1,
              borderRadius: 14,
              backgroundColor: C.field(dark),
              borderWidth: 1.5,
              borderColor: error || (!busy && i === value.length) ? accent : 'transparent',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <Text style={{ fontSize: 26, fontWeight: '800', color: C.text1(dark) }}>{value[i] ?? ''}</Text>
          </View>
        ))}
      </View>
      <TextInput
        ref={input}
        testID="code-input"
        value={value}
        autoFocus
        editable={!busy}
        keyboardType="number-pad"
        textContentType="oneTimeCode"
        autoComplete="one-time-code"
        maxLength={length}
        caretHidden
        keyboardAppearance={dark ? 'dark' : 'light'}
        onChangeText={(t) => onChange(t.replace(/\D/g, '').slice(0, length))}
        style={[StyleSheet.absoluteFill, { color: 'transparent', opacity: 0.02 }]}
      />
      {busy && (
        <View style={[StyleSheet.absoluteFill, { alignItems: 'center', justifyContent: 'center' }]} pointerEvents="none">
          <Spinner color={accent} />
        </View>
      )}
    </Pressable>
  );
}
