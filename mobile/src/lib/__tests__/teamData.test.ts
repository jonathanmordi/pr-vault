// The team's data saved on the phone: shown at once on the next launch and
// when offline, refreshed in the background, and forgotten on sign-out.
import { sampleTeam, sampleUserId } from '@/test/sampleTeam';

import { MemoryTeamCacheStore } from '../teamCache';
import { TeamData, TeamSnapshot } from '../teamData';

const team = sampleTeam();
let requests = 0;
let offline = false;
let store: MemoryTeamCacheStore;

beforeEach(() => {
  requests = 0;
  offline = false;
  store = new MemoryTeamCacheStore();
  const data = TeamData.instance;
  data.store = store;
  data.currentUserId = () => sampleUserId;
  const serve = <T>(rows: T) => async () => {
    requests++;
    if (offline) throw new TypeError('Network request failed');
    return rows;
  };
  data.source = () => ({
    prs: serve(team.prs),
    appearances: serve(team.appearances),
    records: serve(team.records),
  });
  data.newSession();
});

test('a saved copy reads back the same, but not for someone else or an older app', () => {
  const copy = JSON.parse(JSON.stringify(team.toCache()));
  const back = TeamSnapshot.fromCache(copy, sampleUserId)!;
  expect(back.prs.length).toBe(team.prs.length);
  expect(back.appearances.length).toBe(team.appearances.length);
  expect(back.nameOf('okafor')).toBe('Okafor, Daniel');
  expect(back.prEvents.length).toBe(team.prEvents.length);

  expect(TeamSnapshot.fromCache(copy, 'someone-else')).toBeNull();
  expect(TeamSnapshot.fromCache({ ...copy, v: 0 }, sampleUserId)).toBeNull();
});

test('downloading saves a copy; the next launch shows it, then downloads again', async () => {
  await TeamData.instance.load();
  await Promise.resolve();
  expect([...store.copies.keys()]).toEqual([sampleUserId]);

  TeamData.instance.newSession(); // closed and opened again
  const before = requests;
  const restored = await TeamData.instance.restore();
  expect(restored!.prs.length).toBe(team.prs.length);
  expect(requests).toBe(before); // restoring needs no network

  await TeamData.instance.load();
  expect(requests).toBeGreaterThan(before); // the saved copy is refreshed
});

test('concurrent loads share one request', async () => {
  await Promise.all([TeamData.instance.load(), TeamData.instance.load()]);
  expect(requests).toBe(3);
});

test('offline, the saved copy is still there', async () => {
  await store.write(sampleUserId, JSON.parse(JSON.stringify(team.toCache())));
  offline = true;
  await expect(TeamData.instance.load()).rejects.toThrow('Network request failed');
  const restored = await TeamData.instance.restore();
  expect(restored!.nameOf('okafor')).toBe('Okafor, Daniel');
});

test('signing out forgets the saved copy', async () => {
  await TeamData.instance.load();
  await TeamData.instance.clear();
  expect(store.copies.size).toBe(0);
  expect(TeamData.instance.cached).toBeNull();
});

test('alumni stay out of rivals', () => {
  const withAlum = sampleTeam(new Set(['okafor']));
  expect(withAlum.hasAlumni).toBe(true);
  const rivals = withAlum.rivalsOf('me');
  expect([...rivals.values()].some((r) => r.athleteId === 'okafor')).toBe(false);
});
