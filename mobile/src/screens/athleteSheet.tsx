// The floating profile card: opens at the bottom of the screen; dragging it
// up docks it into a full-height card over the receding screen; dragging it
// down dismisses it.

import { BottomSheetBackdrop, BottomSheetModal, BottomSheetScrollView } from '@gorhom/bottom-sheet';
import { ReactNode, useEffect, useRef } from 'react';
import { PixelRatio, View, useWindowDimensions } from 'react-native';
import Animated, {
  Extrapolation,
  interpolate,
  makeMutable,
  useAnimatedReaction,
  useAnimatedStyle,
  useSharedValue,
} from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { haptic } from '@/lib/haptics';
import { Observable, useObservable } from '@/lib/store';
import { C, useDark } from '@/theme/colors';

import { AthleteProfile, ProfileFocus } from './AthleteProfile';

export type SheetRequest = {
  athleteId: string;
  athleteName: string;
  gender: string;
  focus?: ProfileFocus;
  season?: string;
};

const request = new Observable<(SheetRequest & { key: number }) | null>(null);

/**
 * How far a profile sheet has risen over the screen that opened it: 0 at
 * card height (or with no sheet open), 1 fully up. Screens wrapped in
 * SheetBackdrop shrink back as it rises.
 */
export const sheetDepth = makeMutable(0);

/** Opens a profile as a floating card at the bottom of the screen. */
export function showAthleteSheet(r: SheetRequest) {
  haptic.selection();
  request.value = { ...r, key: Date.now() };
}

/** Recedes [children] behind a rising profile sheet, like iOS card sheets. */
export function SheetBackdrop({ children }: { children: ReactNode }) {
  const style = useAnimatedStyle(() => ({
    flex: 1,
    transform: [{ scale: 1 - 0.07 * sheetDepth.value }],
    borderRadius: 18 * sheetDepth.value,
    overflow: sheetDepth.value > 0 ? 'hidden' : 'visible',
  }));
  return (
    <View style={{ flex: 1, backgroundColor: '#000' }}>
      <Animated.View style={style}>{children}</Animated.View>
    </View>
  );
}

// Card shape at its two resting points.
const cardMargin = 8;
const cardRadius = 36;
const dockedRadius = 16;

/** Hosts the sheet; mounted once at the root, under BottomSheetModalProvider. */
export function AthleteSheetHost() {
  const dark = useDark();
  const current = useObservable(request);
  const modal = useRef<BottomSheetModal>(null);
  const insets = useSafeAreaInsets();
  const { height: screenH } = useWindowDimensions();
  const index = useSharedValue(-1);
  const scrollY = useSharedValue(0);

  useEffect(() => {
    if (current) {
      scrollY.value = 0;
      modal.current?.present();
    }
  }, [current, scrollY]);

  // Docked, the card stops just under the status bar so the receding screen
  // shows above it.
  const max = screenH - insets.top - cardMargin;
  // Tall enough for the header, the focus row and the swipe-up hint, clear
  // of the home indicator; taller with bigger text.
  const textGrowth = Math.max(0, Math.min(1, PixelRatio.getFontScale() - 1));
  const bottomRoom = Math.max(16, insets.bottom - 4);
  const peek = Math.min(306 + textGrowth * 90 + cardMargin + bottomRoom, max - 0.05 * screenH);

  // 0 at the peek height, 1 at full screen.
  const progress = useSharedValue(0);
  useAnimatedReaction(
    () => index.value,
    (i) => {
      progress.value = interpolate(i, [0, 1], [0, 1], Extrapolation.CLAMP);
      // The screen behind springs back as the sheet slides away.
      sheetDepth.value = i < 0 ? Math.max(0, progress.value * (1 + i)) : progress.value;
    },
  );

  const card = useAnimatedStyle(() => {
    const p = progress.value;
    return {
      flex: 1,
      marginHorizontal: cardMargin * (1 - p),
      marginBottom: cardMargin * (1 - p),
      borderTopLeftRadius: cardRadius + (dockedRadius - cardRadius) * p,
      borderTopRightRadius: cardRadius + (dockedRadius - cardRadius) * p,
      borderBottomLeftRadius: cardRadius * (1 - p),
      borderBottomRightRadius: cardRadius * (1 - p),
    };
  });

  return (
    <BottomSheetModal
      ref={modal}
      snapPoints={[peek, max]}
      index={0}
      enableDynamicSizing={false}
      enablePanDownToClose
      animatedIndex={index}
      handleComponent={null}
      backgroundStyle={{ backgroundColor: 'transparent' }}
      style={{ boxShadow: `0 -2px 24px rgba(0, 0, 0, ${dark ? 0.5 : 0.18})` }}
      backdropComponent={(props) => (
        <BottomSheetBackdrop {...props} appearsOnIndex={0} disappearsOnIndex={-1} opacity={0.4} pressBehavior="close" />
      )}
      onChange={(i) => {
        if (i === 1) haptic.light();
      }}
      onDismiss={() => {
        sheetDepth.value = 0;
        request.value = null;
      }}
    >
      <Animated.View
        style={[
          { overflow: 'hidden', backgroundColor: C.sheet(dark), borderWidth: 0.5, borderColor: C.border(dark) },
          card,
        ]}
      >
        {current && (
          <AthleteProfile
            key={current.key}
            athleteId={current.athleteId}
            athleteName={current.athleteName}
            gender={current.gender}
            focus={current.focus}
            season={current.season}
            showBackButton={false}
            scrollY={scrollY}
            sheet={{ progress, expand: () => modal.current?.snapToIndex(1) }}
            renderScroll={(content) => (
              <BottomSheetScrollView
                onScroll={(e) => (scrollY.value = e.nativeEvent.contentOffset.y)}
                showsVerticalScrollIndicator={false}
              >
                {content}
              </BottomSheetScrollView>
            )}
          />
        )}
      </Animated.View>
    </BottomSheetModal>
  );
}
