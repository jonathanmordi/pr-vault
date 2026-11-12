import { useSession } from '@/lib/session';
import { MainShell } from '@/screens/MainShell';
import { OnboardingGate } from '@/screens/Onboarding';

export default function Home() {
  const session = useSession();
  // A new gate per user, so signing in as someone else checks their team.
  return (
    <OnboardingGate key={session?.user.id}>
      <MainShell />
    </OnboardingGate>
  );
}
