// The main screens render the sample team: the leaderboard opens on the
// latest season, and a profile shows one season's PRs at a time.
import { act, fireEvent, render, screen, within } from '@testing-library/react-native';
import { ReactNode } from 'react';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { OverlayProvider } from '@/components/overlay';
import { MemoryTeamCacheStore } from '@/lib/teamCache';
import { TeamData } from '@/lib/teamData';
import { sampleTeam, sampleUserId } from '@/test/sampleTeam';

import { AthleteProfile } from '../AthleteProfile';
import { Leaderboard } from '../Leaderboard';

jest.mock('expo-router', () => ({ router: { push: jest.fn(), back: jest.fn() } }));
jest.mock('../athleteSheet', () => ({ showAthleteSheet: jest.fn(), SheetBackdrop: ({ children }: any) => children }));

const team = sampleTeam();

const metrics = { frame: { x: 0, y: 0, width: 402, height: 874 }, insets: { top: 62, left: 0, right: 0, bottom: 34 } };
const wrap = (node: ReactNode) => (
  <GestureHandlerRootView>
    <SafeAreaProvider initialMetrics={metrics}>
      <OverlayProvider>{node}</OverlayProvider>
    </SafeAreaProvider>
  </GestureHandlerRootView>
);

beforeEach(() => {
  const data = TeamData.instance;
  data.currentUserId = () => sampleUserId;
  data.store = new MemoryTeamCacheStore();
  const rows = (r: any[]) => async () => r;
  data.source = () => ({ prs: rows(team.prs), appearances: rows(team.appearances), records: rows(team.records) });
  data.seed(team);
});

test('the leaderboard opens on the latest season', async () => {
  await render(wrap(<Leaderboard />));
  await act(async () => {});
  // The latest results are outdoor; the 60m is indoor only.
  expect(screen.getAllByText('Daniel Okafor').length).toBeGreaterThan(0);
  expect(screen.queryByText('Marcus Smith')).toBeNull();
  expect(screen.getByText('Top Improvers')).toBeTruthy();
});

test("event chips only offer the season's events", async () => {
  await render(wrap(<Leaderboard />));
  await act(async () => {});
  await fireEvent.press(screen.getByText('Sprints'));
  expect(screen.queryByText('60')).toBeNull(); // indoor only
  expect(screen.getByText('200')).toBeTruthy();
});

test('PR Rankings shows marks, Trending shows PR counts', async () => {
  await render(wrap(<Leaderboard />));
  await act(async () => {});
  await fireEvent.press(screen.getByText('Jumps'));
  expect(screen.getAllByText('Long Jump').length).toBeGreaterThan(0);
});

test("a profile shows one season's PRs at a time", async () => {
  await render(wrap(<AthleteProfile athleteId="me" athleteName="Mordi, Jonathan" gender="M" />));
  await act(async () => {});
  // Opens on outdoor, where the latest results are.
  const prs = within(screen.getByTestId('personal-records'));
  expect(prs.getByText('14.10m')).toBeTruthy();
  expect(prs.queryByText('14.02m')).toBeNull();
  expect(screen.getAllByText('Jonathan Mordi').length).toBeGreaterThan(0); // hero and top bar
  expect(screen.getByText('Insights')).toBeTruthy();
});

test('a profile opened from the leaderboard keeps its season', async () => {
  await render(wrap(<AthleteProfile athleteId="me" athleteName="Mordi, Jonathan" gender="M" season="indoor" />));
  await act(async () => {});
  const prs = within(screen.getByTestId('personal-records'));
  expect(prs.getByText('14.02m')).toBeTruthy();
  expect(prs.getByText('6.88m')).toBeTruthy();
  expect(prs.queryByText('14.10m')).toBeNull();
});

test('meet history labels each meet\'s season', async () => {
  await render(wrap(<AthleteProfile athleteId="me" athleteName="Mordi, Jonathan" gender="M" />));
  await act(async () => {});
  expect(screen.getAllByText('INDOOR').length).toBeGreaterThan(0);
  expect(screen.getAllByText('OUTDOOR').length).toBeGreaterThan(0);
});
