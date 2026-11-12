// The signed-in session, kept in sync with Supabase so code can read the
// user without awaiting, and components re-render when it changes.

import type { Session, User } from '@supabase/supabase-js';
import { useSyncExternalStore } from 'react';

import { supabase } from './supabase';
import { TeamData } from './teamData';

let session: Session | null = null;
let ready = false;
const listeners = new Set<() => void>();

function emit() {
  for (const l of listeners) l();
}

/** Reads the session saved on the phone, then follows sign-ins and sign-outs. */
export async function initSession() {
  if (ready) return;
  try {
    const { data } = await supabase.auth.getSession();
    session = data.session;
  } catch {}
  ready = true;
  supabase.auth.onAuthStateChange((event, s) => {
    session = s;
    // Signing out, or deleting the account, forgets the team data saved on
    // the phone.
    if (event === 'SIGNED_OUT') TeamData.instance.clear();
    emit();
  });
  emit();
}

export const currentSession = () => session;
export const currentUser = (): User | null => session?.user ?? null;
export const currentUserId = () => session?.user.id ?? null;

const subscribe = (l: () => void) => {
  listeners.add(l);
  return () => {
    listeners.delete(l);
  };
};

export function useSession() {
  return useSyncExternalStore(subscribe, () => session);
}

export function useSessionReady() {
  return useSyncExternalStore(subscribe, () => ready);
}
