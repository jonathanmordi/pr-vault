import { useLocalSearchParams } from 'expo-router';

import { AthleteProfile } from '@/screens/AthleteProfile';
import { SheetBackdrop } from '@/screens/athleteSheet';

/** A teammate's full profile, pushed from a rival row. */
export default function AthletePage() {
  const { id, name, gender } = useLocalSearchParams<{ id: string; name?: string; gender?: string }>();
  return (
    <SheetBackdrop>
      <AthleteProfile athleteId={id} athleteName={name ?? 'Unknown'} gender={gender ?? 'M'} />
    </SheetBackdrop>
  );
}
