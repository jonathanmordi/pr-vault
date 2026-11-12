// A copy of the team's data saved on the phone, so the app can show it the
// moment it opens and while offline. The latest data still comes from the
// server; this is only the starting point.

import { Directory, File, Paths } from 'expo-file-system';

/** Saves and reads one JSON object per user. */
export interface TeamCacheStore {
  read(userId: string): Promise<Record<string, any> | null>;
  write(userId: string, data: Record<string, any>): Promise<void>;
  /** Removes every user's copy, e.g. on sign-out. */
  clear(): Promise<void>;
}

/** Keeps copies in memory, for tests. */
export class MemoryTeamCacheStore implements TeamCacheStore {
  copies = new Map<string, Record<string, any>>();

  async read(userId: string) {
    return this.copies.get(userId) ?? null;
  }

  async write(userId: string, data: Record<string, any>) {
    this.copies.set(userId, data);
  }

  async clear() {
    this.copies.clear();
  }
}

const prefix = 'team_';

/**
 * One JSON file per user in the app's cache folder, which the system may
 * clear when space runs low; then the app just downloads again.
 */
export class DeviceTeamCacheStore implements TeamCacheStore {
  private file(userId: string) {
    return new File(Paths.cache, `${prefix}${userId.replace(/[^A-Za-z0-9-]/g, '')}.json`);
  }

  async read(userId: string) {
    const file = this.file(userId);
    if (!file.exists) return null;
    return JSON.parse(await file.text());
  }

  async write(userId: string, data: Record<string, any>) {
    const file = this.file(userId);
    // Written aside and moved into place, so a crash mid-write never leaves
    // a half-written copy.
    const tmp = new File(Paths.cache, `${file.name}.tmp`);
    if (tmp.exists) tmp.delete();
    tmp.create();
    await tmp.write(JSON.stringify(data));
    await tmp.move(file, { overwrite: true });
  }

  async clear() {
    const dir = new Directory(Paths.cache);
    if (!dir.exists) return;
    for (const f of dir.list()) {
      if (f instanceof File && f.name.startsWith(prefix) && f.name.includes('.json')) f.delete();
    }
  }
}
