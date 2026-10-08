// The how-it-works intro: once after sign-up, replayable from Settings; and
// the one-time tip on the leaderboard's filter pill.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/design_system.dart';
import 'package:mobile_app/intro.dart';
import 'package:mobile_app/onboarding.dart';
import 'package:mobile_app/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'onboarding_test.dart' show FakeApi;

/// The intro's backdrop never stops moving, so step time instead of
/// waiting for it to settle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false, autoRefreshToken: false),
    );
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Widget gate(FakeApi api) => MaterialApp(home: OnboardingGate(api: api, child: const Text('MAIN SHELL')));

  testWidgets('new users see the intro after picking their profile, once', (tester) async {
    phone(tester);
    final api = FakeApi()..introSeen = false;
    await tester.pumpWidget(gate(api));
    await settle(tester);
    // Pick yourself from the roster.
    await tester.tap(find.text('Lily Chen'));
    await settle(tester);
    await tester.tap(find.text("Yes, that's me"));
    await settle(tester);

    expect(find.text('Your results, automatically'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(find.text('MAIN SHELL'), findsOneWidget);
    expect(api.introSeen, isTrue);
  });

  testWidgets('people who signed up before the intro see it once', (tester) async {
    phone(tester);
    final api = FakeApi(onboarded: true)..introSeen = false;
    await tester.pumpWidget(gate(api));
    await settle(tester);
    expect(find.text('Your results, automatically'), findsOneWidget);
  });

  testWidgets('Next walks through the four pages, then Let\'s go finishes', (tester) async {
    phone(tester);
    var done = 0;
    await tester.pumpWidget(MaterialApp(home: IntroScreen(onDone: () => done++)));
    await settle(tester);
    for (final title in ['Your team, ranked', 'Tap anyone', 'Stay in the loop']) {
      await tester.tap(find.text('Next'));
      await settle(tester);
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Next'), findsNothing);
    await tester.tap(find.text("Let's go"));
    await settle(tester);
    expect(done, 1);
  });

  testWidgets('the leaderboard demo is live: switching season changes the marks', (tester) async {
    phone(tester);
    await tester.pumpWidget(MaterialApp(home: IntroScreen(onDone: () {})));
    await settle(tester);
    await tester.tap(find.text('Next'));
    await settle(tester);
    await tester.tap(find.text('Rankings'));
    await settle(tester);
    expect(find.text('7.21m'), findsOneWidget); // outdoor
    await tester.tap(find.text('Outdoor · All'));
    await settle(tester);
    await tester.tap(find.text('Indoor'));
    await settle(tester);
    expect(find.text('7.04m'), findsOneWidget);
    expect(find.text('7.21m'), findsNothing);
  });

  testWidgets('Settings can replay the intro', (tester) async {
    phone(tester);
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(api: FakeApi())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('How PR Vault works'), 200);
    await tester.tap(find.text('How PR Vault works'));
    await settle(tester);
    expect(find.text('Your results, automatically'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(find.text('How PR Vault works'), findsOneWidget);
  });

  testWidgets('a tip shows the first time only, and a tap anywhere dismisses it', (tester) async {
    Widget screen() => MaterialApp(
          home: Scaffold(
            body: Center(
              child: OneTimeTip(
                id: 'test_tip',
                message: 'Tap to switch season or gender',
                child: TextButton(onPressed: () {}, child: const Text('pill')),
              ),
            ),
          ),
        );
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('Tap to switch season or gender'), findsOneWidget);

    // It doesn't swallow the tap.
    await tester.tap(find.text('pill'));
    await tester.pumpAndSettle();
    expect(find.text('Tap to switch season or gender'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('Tap to switch season or gender'), findsNothing);
  });
}
