import { AuthError, PostgrestError } from '@supabase/supabase-js';

import { kv } from './kv';
import { currentUser } from './session';
import { supabase } from './supabase';
import { TeamData } from './teamData';

/** Digits in the email verification code. Matches auth.email.otp_length in backend/supabase/config.toml. */
export const kCodeLength = 6;

export type JoinOutcome = 'joined' | 'noTeamForDomain' | 'unverified';

export type TeamInfo = { name: string; division: string | null };

/** 'NCAA D3', 'NAIA', 'High school'. */
export function divisionLabel(division: string | null): string | null {
  switch (division) {
    case 'D1':
    case 'D2':
    case 'D3':
      return `NCAA ${division}`;
    case 'HS':
      return 'High school';
    default:
      return division;
  }
}

export type RosterEntry = {
  id: string;
  name: string;
  gender: string;
  /** False for alumni, who've dropped off the current TFRRS roster. */
  onRoster: boolean;
  /** As TFRRS shows it, e.g. 'SR-4'. */
  classYear: string | null;
};

/** Throws a Supabase auth error instead of returning it. */
function check<T extends { error: AuthError | null }>(res: T): T {
  if (res.error) throw res.error;
  return res;
}

/**
 * The Supabase calls sign-up and onboarding make, behind one seam so the
 * screens can be tested without a backend.
 */
export class OnboardingApi {
  get userId() {
    return currentUser()?.id ?? null;
  }

  get email() {
    return currentUser()?.email ?? null;
  }

  /** The signed-in user's team, or null if they aren't on one. */
  async myTeam(): Promise<TeamInfo | null> {
    const uid = this.userId;
    if (!uid) return null;
    const { data } = await supabase.from('profiles').select('teams(name, division)').eq('id', uid).maybeSingle().throwOnError();
    const team = (data as any)?.teams;
    if (!team) return null;
    return { name: team.name, division: team.division ?? null };
  }

  async teamIdOf(userId: string): Promise<string | null> {
    const { data } = await supabase.from('profiles').select('team_id').eq('id', userId).maybeSingle().throwOnError();
    return (data as any)?.team_id ?? null;
  }

  /** Joins the team that uses the signed-in user's email domain (see join_team_by_email in backend/supabase/migrations). */
  async joinByEmail(): Promise<JoinOutcome> {
    try {
      const { data } = await supabase.rpc('join_team_by_email').throwOnError();
      return data == null ? 'noTeamForDomain' : 'joined';
    } catch (e) {
      if (e instanceof PostgrestError && e.message.includes('verify your email')) return 'unverified';
      throw e;
    }
  }

  /** Joins by invite code. False if no team uses the code. */
  async joinByCode(code: string): Promise<boolean> {
    const { data } = await supabase.rpc('join_team', { p_code: code }).throwOnError();
    return data != null;
  }

  /** Scraped TFRRS profiles on the user's team that nobody has claimed. */
  async unclaimedRoster(): Promise<RosterEntry[]> {
    const { data } = await supabase.rpc('unclaimed_roster').throwOnError();
    return ((data as any[]) ?? []).map((r) => ({
      id: r.id,
      name: r.full_name ?? '',
      gender: r.gender ?? 'M',
      onRoster: r.on_roster ?? true,
      classYear: r.class_year ?? null,
    }));
  }

  /** Moves a scraped profile's PRs, meets and ranks onto the user's account. */
  async claim(profileId: string) {
    await supabase.rpc('claim_tfrrs_profile', { p_profile_id: profileId }).throwOnError();
    TeamData.instance.load({ force: true }).catch(() => {});
  }

  async signUp(email: string, password: string, fullName: string) {
    return check(await supabase.auth.signUp({ email, password, options: { data: { full_name: fullName } } })).data;
  }

  async signIn(email: string, password: string) {
    check(await supabase.auth.signInWithPassword({ email, password }));
  }

  async verifySignup(email: string, code: string) {
    check(await supabase.auth.verifyOtp({ type: 'signup', email, token: code }));
  }

  async resendSignup(email: string) {
    check(await supabase.auth.resend({ type: 'signup', email }));
  }

  async signOut() {
    await supabase.auth.signOut();
  }

  /**
   * Deletes the login and lifting maxes. TFRRS results stay with the team and
   * go back on the roster (see delete_my_account in backend/supabase/migrations).
   */
  async deleteAccount() {
    await supabase.rpc('delete_my_account').throwOnError();
  }

  /** Drops the session on this phone only, for after the login was deleted. */
  async signOutLocally() {
    await supabase.auth.signOut({ scope: 'local' });
  }

  /** Remembered per user so returning users skip the team check on launch. */
  async wasOnboarded(userId: string) {
    try {
      return (await kv.getBool(`onboarded:${userId}`)) ?? false;
    } catch {
      return false;
    }
  }

  async markOnboarded(userId: string) {
    try {
      await kv.setBool(`onboarded:${userId}`, true);
    } catch {}
  }

  /** Whether this user has seen the how-it-works intro. */
  async sawIntro(userId: string) {
    try {
      return (await kv.getBool(`intro_seen:${userId}`)) ?? false;
    } catch {
      return true; // without storage, don't show it every launch
    }
  }

  async markIntroSeen(userId: string) {
    try {
      await kv.setBool(`intro_seen:${userId}`, true);
    } catch {}
  }
}

export const onboardingApi = new OnboardingApi();
