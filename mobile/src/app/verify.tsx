import { useLocalSearchParams } from 'expo-router';

import { VerifyEmail } from '@/screens/Onboarding';

export default function Verify() {
  const { email } = useLocalSearchParams<{ email: string }>();
  return <VerifyEmail email={email ?? ''} />;
}
