import { router } from 'expo-router';

import { Intro } from '@/screens/Intro';

/** The how-it-works intro, replayed from Settings. */
export default function Tour() {
  return <Intro onDone={() => router.back()} />;
}
