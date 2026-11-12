import { SheetBackdrop } from '@/screens/athleteSheet';
import { Leaderboard } from '@/screens/Leaderboard';

// The leaderboard opens profile cards, so it recedes behind them.
export default function LeaderboardTab() {
  return (
    <SheetBackdrop>
      <Leaderboard />
    </SheetBackdrop>
  );
}
