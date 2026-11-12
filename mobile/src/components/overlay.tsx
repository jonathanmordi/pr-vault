// Things drawn above every screen: portals (the open filter pill, tips),
// toasts, and confirm cards. Mounted once at the root.

import { ReactNode, createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { Keyboard, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import Animated, { FadeIn, FadeInDown, FadeOut, FadeOutDown } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { C, cardStyle, useDark } from '@/theme/colors';

import { PrimaryButton } from './ui';

type Portal = { id: number; node: ReactNode };

type OverlayApi = {
  mount(node: ReactNode): number;
  update(id: number, node: ReactNode): void;
  unmount(id: number): void;
  /** Called with every touch that starts anywhere, without taking it. */
  onAnyTouch(listener: () => void): () => void;
};

const OverlayContext = createContext<OverlayApi | null>(null);

let showToast: (message: string) => void = () => {};
let showConfirm: (c: ConfirmRequest) => void = () => {};

/** A short message at the bottom of the screen, like a snackbar. */
export const toast = (message: string) => showToast(message);

type ConfirmRequest = ConfirmOptions & { resolve: (ok: boolean) => void };

export type ConfirmOptions = {
  title: string;
  message?: string;
  body?: ReactNode;
  confirmLabel: string;
  cancelLabel?: string;
  destructive?: boolean;
};

/**
 * "Are you sure?" as a card that rises from the bottom, with the action and
 * Cancel as big buttons. True if confirmed.
 */
export function confirmAction(options: ConfirmOptions): Promise<boolean> {
  Keyboard.dismiss();
  return new Promise((resolve) => showConfirm({ ...options, resolve }));
}

export function OverlayProvider({ children }: { children: ReactNode }) {
  const [portals, setPortals] = useState<Portal[]>([]);
  const nextId = useRef(1);
  const touchListeners = useRef(new Set<() => void>());

  const api = useMemo<OverlayApi>(
    () => ({
      mount(node) {
        const id = nextId.current++;
        setPortals((ps) => [...ps, { id, node }]);
        return id;
      },
      update(id, node) {
        setPortals((ps) => ps.map((p) => (p.id === id ? { id, node } : p)));
      },
      unmount(id) {
        setPortals((ps) => ps.filter((p) => p.id !== id));
      },
      onAnyTouch(listener) {
        touchListeners.current.add(listener);
        return () => {
          touchListeners.current.delete(listener);
        };
      },
    }),
    [],
  );

  return (
    <OverlayContext.Provider value={api}>
      <View
        style={{ flex: 1 }}
        onStartShouldSetResponderCapture={() => {
          for (const l of [...touchListeners.current]) l();
          return false;
        }}
      >
        {children}
        {portals.map((p) => (
          <View key={p.id} style={StyleSheet.absoluteFill} pointerEvents="box-none">
            {p.node}
          </View>
        ))}
        <ToastHost />
        <ConfirmHost />
      </View>
    </OverlayContext.Provider>
  );
}

export function useOverlay() {
  const api = useContext(OverlayContext);
  if (!api) throw new Error('useOverlay outside OverlayProvider');
  return api;
}

/** Renders [node] above every screen while [visible]. */
export function usePortal(visible: boolean, node: ReactNode) {
  const overlay = useOverlay();
  const id = useRef<number | null>(null);
  useEffect(() => {
    if (visible && id.current == null) id.current = overlay.mount(node);
    else if (visible && id.current != null) overlay.update(id.current, node);
    else if (!visible && id.current != null) {
      overlay.unmount(id.current);
      id.current = null;
    }
  });
  useEffect(
    () => () => {
      if (id.current != null) overlay.unmount(id.current);
    },
    [overlay],
  );
}

function ToastHost() {
  const dark = useDark();
  const insets = useSafeAreaInsets();
  const [message, setMessage] = useState<{ text: string; key: number } | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    showToast = (text) => {
      if (timer.current) clearTimeout(timer.current);
      setMessage({ text, key: Date.now() });
      timer.current = setTimeout(() => setMessage(null), 4000);
    };
    return () => {
      showToast = () => {};
    };
  }, []);

  if (!message) return null;
  return (
    <Animated.View
      key={message.key}
      entering={FadeInDown.duration(220)}
      exiting={FadeOutDown.duration(180)}
      pointerEvents="box-none"
      style={{ position: 'absolute', left: 16, right: 16, bottom: insets.bottom + 108 }}
    >
      <Pressable onPress={() => setMessage(null)}>
        <View
          accessibilityLiveRegion="polite"
          style={{
            paddingHorizontal: 18,
            paddingVertical: 14,
            borderRadius: 14,
            backgroundColor: dark ? '#F5F5F7' : '#1C1C1E',
            boxShadow: '0 6px 18px rgba(0, 0, 0, 0.2)',
          }}
        >
          <Text style={{ fontSize: 14, fontWeight: '500', color: dark ? '#000' : '#fff' }}>{message.text}</Text>
        </View>
      </Pressable>
    </Animated.View>
  );
}

function ConfirmHost() {
  const dark = useDark();
  const insets = useSafeAreaInsets();
  const [request, setRequest] = useState<ConfirmRequest | null>(null);

  useEffect(() => {
    showConfirm = (r) => setRequest(r);
    return () => {
      showConfirm = () => {};
    };
  }, []);

  const close = useCallback(
    (ok: boolean) => {
      request?.resolve(ok);
      setRequest(null);
    },
    [request],
  );

  return (
    <Modal visible={request != null} transparent animationType="none" onRequestClose={() => close(false)}>
      {request && (
        <View style={{ flex: 1, justifyContent: 'flex-end' }}>
          <Animated.View entering={FadeIn.duration(200)} exiting={FadeOut.duration(160)} style={StyleSheet.absoluteFill}>
            <Pressable style={{ flex: 1, backgroundColor: 'rgba(0, 0, 0, 0.4)' }} onPress={() => close(false)} />
          </Animated.View>
          <Animated.View
            entering={FadeInDown.springify().damping(18).stiffness(180)}
            style={{ paddingHorizontal: 10, paddingBottom: Math.max(insets.bottom, 10) }}
          >
            <View style={[cardStyle(dark, 32, C.sheet(dark)), { paddingHorizontal: 22, paddingTop: 24, paddingBottom: 16 }]}>
              <Text style={{ fontSize: 21, fontWeight: '800', letterSpacing: -0.4, color: C.text1(dark) }}>{request.title}</Text>
              {request.message ? (
                <Text style={{ marginTop: 8, fontSize: 15, lineHeight: 21, color: C.text2(dark) }}>{request.message}</Text>
              ) : null}
              {request.body ? <View style={{ marginTop: 16 }}>{request.body}</View> : null}
              <View style={{ height: 22 }} />
              <PrimaryButton
                label={request.confirmLabel}
                dark={dark}
                tone={request.destructive ? 'accent' : 'ink'}
                onPress={() => close(true)}
              />
              <View style={{ height: 10 }} />
              <PrimaryButton label={request.cancelLabel ?? 'Cancel'} dark={dark} tone="soft" onPress={() => close(false)} />
            </View>
          </Animated.View>
        </View>
      )}
    </Modal>
  );
}
