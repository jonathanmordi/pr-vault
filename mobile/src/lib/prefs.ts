// Settings picked in the Settings tab, saved across launches. Components read
// them with usePrefs(), which re-renders them on change, so switching units
// in Settings updates every tab.

import { useSyncExternalStore } from 'react';

import { kv } from './kv';
import { formatGap, markDisplay } from './prStats';

export type ThemeMode = 'system' | 'light' | 'dark';
export type FieldUnits = 'metric' | 'imperial';
export type LiftUnits = 'lbs' | 'kg';

export const kLbToKg = 0.45359237;

export type PrefsState = {
  themeMode: ThemeMode;
  fieldUnits: FieldUnits;
  liftUnits: LiftUnits;
  // Which PRs show in the Activity feed and count toward the bell.
  alertMine: boolean;
  alertRivals: boolean;
  alertTeam: boolean;
  alertRecords: boolean;
  showBadge: boolean;
};

const defaults: PrefsState = {
  themeMode: 'system',
  fieldUnits: 'metric',
  liftUnits: 'lbs',
  alertMine: true,
  alertRivals: true,
  alertTeam: true,
  alertRecords: true,
  showBadge: true,
};

const boolKeys = {
  alertMine: 'alert_mine',
  alertRivals: 'alert_rivals',
  alertTeam: 'alert_team',
  alertRecords: 'alert_records',
  showBadge: 'show_badge',
} as const;

/** The settings plus formatting in the chosen units. */
export class Prefs {
  constructor(readonly state: PrefsState) {}

  get themeMode() { return this.state.themeMode; }
  get fieldUnits() { return this.state.fieldUnits; }
  get liftUnits() { return this.state.liftUnits; }
  get alertMine() { return this.state.alertMine; }
  get alertRivals() { return this.state.alertRivals; }
  get alertTeam() { return this.state.alertTeam; }
  get alertRecords() { return this.state.alertRecords; }
  get showBadge() { return this.state.showBadge; }

  get imperial() {
    return this.state.fieldUnits === 'imperial';
  }

  /** A field mark in the chosen units; track times are left as scraped. */
  mark(event: string, display: string | null | undefined, meters: number | null | undefined) {
    return markDisplay(event, display ?? '—', meters ?? null, this.imperial);
  }

  gap(event: string, gap: number) {
    return formatGap(event, gap, this.imperial);
  }

  /** A stored weight in the chosen units, e.g. "225 lbs" or "102.5 kg". */
  weight(lbs: number) {
    if (this.state.liftUnits === 'lbs') return `${Math.round(lbs)} lbs`;
    const kg = Math.round(lbs * kLbToKg * 2) / 2;
    return `${kg} kg`;
  }

  get weightUnit() {
    return this.state.liftUnits === 'kg' ? 'kg' : 'lbs';
  }

  /** Converts a weight typed in the chosen units to whole pounds for storage. */
  toLbs(entered: number) {
    return this.state.liftUnits === 'kg' ? Math.round(entered / kLbToKg) : Math.round(entered);
  }
}

let current = new Prefs(defaults);
const listeners = new Set<() => void>();

function emit() {
  for (const l of listeners) l();
}

export const prefsStore = {
  get: () => current,

  subscribe(listener: () => void) {
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  },

  async load() {
    try {
      const theme = await kv.getString('theme_mode');
      const field = await kv.getString('field_units');
      const lift = await kv.getString('lift_units');
      const state: PrefsState = {
        ...defaults,
        themeMode: theme === 'light' || theme === 'dark' ? theme : 'system',
        fieldUnits: field === 'imperial' ? 'imperial' : 'metric',
        liftUnits: lift === 'kg' ? 'kg' : 'lbs',
      };
      for (const [k, key] of Object.entries(boolKeys) as [keyof typeof boolKeys, string][]) {
        state[k] = (await kv.getBool(key)) ?? true;
      }
      current = new Prefs(state);
      emit();
    } catch {
      // Defaults are fine if storage is unavailable.
    }
  },

  /** Applies [change], re-renders listeners and saves. */
  update(change: Partial<PrefsState>) {
    current = new Prefs({ ...current.state, ...change });
    emit();
    save(current.state);
  },

  /** Back to the defaults, for tests. */
  reset() {
    current = new Prefs(defaults);
    emit();
  },
};

async function save(s: PrefsState) {
  try {
    await Promise.all([
      kv.setString('theme_mode', s.themeMode),
      kv.setString('field_units', s.fieldUnits),
      kv.setString('lift_units', s.liftUnits),
      ...(Object.entries(boolKeys) as [keyof typeof boolKeys, string][]).map(([k, key]) => kv.setBool(key, s[k])),
    ]);
  } catch {}
}

export function usePrefs() {
  return useSyncExternalStore(prefsStore.subscribe, prefsStore.get);
}
