// Tracks which PR alerts the user has already seen so the bell can show an
// unread count. Seen keys are stored per user.

import { kv } from './kv';
import { prefsStore } from './prefs';
import { PrEvent, Rival, eventKey } from './prStats';
import { Observable } from './store';
import { TeamData, TeamSnapshot } from './teamData';

export class ActivityFeed {
  static readonly instance = new ActivityFeed();

  static readonly feedSize = 100;

  readonly unread = new Observable(0);

  private constructor() {
    // Notification settings change what's in the feed, so recount.
    prefsStore.subscribe(() => {
      const snap = TeamData.instance.cached;
      if (snap) this.refresh(snap);
    });
  }

  private static recent(snap: TeamSnapshot) {
    return snap.prEvents.slice(0, ActivityFeed.feedSize);
  }

  /** The recent PRs the user's notification settings let through. */
  static itemsOf(snap: TeamSnapshot): PrEvent[] {
    const p = prefsStore.get();
    const me = snap.userId;
    const rivals = me == null ? new Map<string, Rival>() : snap.rivalsOf(me);
    return ActivityFeed.recent(snap).filter((e) => {
      if (p.alertRecords && e.schoolRecord) return true;
      if (e.athleteId === me) return p.alertMine;
      if (rivals.get(eventKey(e.event, e.season))?.athleteId === e.athleteId) return p.alertRivals;
      return p.alertTeam;
    });
  }

  private prefsKey(snap: TeamSnapshot) {
    return `activity_seen_v1:${snap.userId}`;
  }

  private async loadSeen(snap: TeamSnapshot): Promise<Set<string> | null> {
    try {
      const list = await kv.getStringList(this.prefsKey(snap));
      return list ? new Set(list) : null;
    } catch {
      return null;
    }
  }

  /**
   * Recounts unread alerts. On first run everything already in the feed
   * counts as seen, so nobody opens the app to a badge of 100.
   */
  async refresh(snap: TeamSnapshot) {
    const seen = await this.loadSeen(snap);
    if (!seen) {
      await this.markAllSeen(snap);
      return;
    }
    this.unread.value = ActivityFeed.itemsOf(snap).filter((e) => !seen.has(e.key)).length;
  }

  /** Marks the whole feed as read and returns the keys that were unread. */
  async markAllSeen(snap: TeamSnapshot): Promise<Set<string>> {
    // Hidden alerts count as seen too, so turning a filter back on doesn't
    // bring back old PRs as unread.
    const keys = ActivityFeed.recent(snap).map((e) => e.key);
    const seen = (await this.loadSeen(snap)) ?? new Set(keys);
    const fresh = new Set(keys.filter((k) => !seen.has(k)));
    try {
      await kv.setStringList(this.prefsKey(snap), keys);
    } catch {}
    this.unread.value = 0;
    return fresh;
  }
}
