// The profile sheet opens as a floating card, docks just under the status
// bar when dragged up (the screen behind receding), and closes when dragged
// down past the card.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/athlete_profile_screen.dart';
import 'package:mobile_app/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/sample_team.dart';

/// A screen with an "open" button that opens [name]'s sheet. The button sits
/// inside a SafeArea like the real callers, which hides the status bar inset
/// from its context.
Widget _host({
  required String name,
  ProfileFocus? focus,
  bool dark = false,
}) {
  return PrefsScope(
    child: MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAthleteSheet(
                  context,
                  athleteId: 'a1',
                  athleteName: name,
                  gender: 'F',
                  focus: focus,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void _setPhone(WidgetTester tester, Size size, {required double top}) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = FakeViewPadding(top: top * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    await loadRealFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test',
      authOptions: const FlutterAuthClientOptions(
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );
  });

  double profileTop(WidgetTester tester) =>
      tester.getTopLeft(find.byType(AthleteProfileScreen)).dy;

  for (final dark in [false, true]) {
    testWidgets('drag the card up to full screen and down to close '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      const size = Size(430, 932); // iPhone 15 Pro Max
      _setPhone(tester, size, top: 59);
      await tester.pumpWidget(_host(
        name: 'Chen, Lily',
        dark: dark,
        focus: const ProfileFocus(
          event: 'Weight Throw',
          display: '15.20m',
          meters: 15.2,
          improvementPct: 3.25,
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Card: the tapped result and the hint fit above the home indicator.
      expect(find.text('PERSONAL BEST'), findsOneWidget);
      expect(find.text('15.20m'), findsOneWidget);
      final hint = find.text('Swipe up for full profile');
      expect(tester.getBottomLeft(hint).dy, lessThan(size.height - 34));
      final peekTop = profileTop(tester);
      expect(peekTop, greaterThan(size.height * 0.5));
      expect(sheetDepth.value, 0);

      // Tapping the hint docks the card just under the status bar, and the
      // screen behind recedes.
      await tester.tap(hint);
      await tester.pumpAndSettle();
      expect(profileTop(tester), closeTo(59 + 8, 1));
      expect(sheetDepth.value, closeTo(1, 0.01));

      // Dragging down from the top rests on the card again...
      await tester.drag(find.text('PERSONAL BEST'), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(profileTop(tester), closeTo(peekTop, 1));
      expect(sheetDepth.value, closeTo(0, 0.01));

      // ...and dragging the card down closes it.
      await tester.drag(find.text('PERSONAL BEST'), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(find.byType(AthleteProfileScreen), findsNothing);
      expect(sheetDepth.value, 0);
    });
  }

  testWidgets('dragging the card up opens the full profile', (tester) async {
    _setPhone(tester, const Size(402, 874), top: 62);
    await tester.pumpWidget(_host(name: 'Lily Chen'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.fling(
        find.text('Lily Chen').first, const Offset(0, -500), 1500);
    await tester.pumpAndSettle();
    expect(profileTop(tester), closeTo(62 + 8, 1));

    // Closing from the top lets the screen behind spring back.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(sheetDepth.value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(sheetDepth.value, 0);
  });
}
