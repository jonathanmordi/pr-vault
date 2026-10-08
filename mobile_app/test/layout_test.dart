// Renders the leaderboard (every tab) and the activity feed with a fake team
// at phone sizes. Any RenderFlex overflow or exception fails the test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/activity_screen.dart';
import 'package:mobile_app/design_system.dart';
import 'package:mobile_app/leaderboard_screen.dart';
import 'package:mobile_app/team_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/sample_team.dart';

const _sizes = {'iPhone SE': Size(375, 667), 'iPhone 17': Size(402, 874)};

Widget _app(Widget home) => MaterialApp(
  theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: C.bg(false)),
  home: home,
);

void main() {
  setUpAll(loadRealFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TeamData.instance.currentUserId = () => sampleUserId;
    TeamData.instance.seed(sampleTeam());
  });

  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  for (final MapEntry(key: device, value: size) in _sizes.entries) {
    testWidgets('leaderboard tabs lay out on $device', (tester) async {
      setSize(tester, size);
      await tester.pumpWidget(_app(const LeaderboardScreen()));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Top Improvers'), findsOneWidget);

      await tester.tap(find.text('PR Rankings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trending'));
      await tester.pumpAndSettle();
      // Offseason: defaults to the latest season that has PRs.
      expect(find.text('2025–26'), findsOneWidget);
      expect(find.text('Jonathan Mordi'), findsOneWidget);

      await tester.tap(find.text('Points'));
      await tester.pumpAndSettle();

      // Sub-chips and trend controls on screen together.
      await tester.tap(find.text('Jumps'));
      await tester.pumpAndSettle();
      expect(find.text('All Jumps'), findsOneWidget);
      expect(find.text('Lily Chen'), findsNothing);
    });

    testWidgets('activity feed lays out on $device', (tester) async {
      setSize(tester, size);
      await tester.pumpWidget(_app(const ActivityScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining("PR'd in"), findsWidgets);

      await tester.tap(find.text('Rivals'));
      await tester.pumpAndSettle();
      expect(find.text('RIVAL'), findsWidgets);

      await tester.tap(find.text('You'));
      await tester.pumpAndSettle();
      expect(find.textContaining("PR'd in"), findsWidgets);
    });
  }

  Future<void> openBoard(WidgetTester tester) async {
    setSize(tester, _sizes['iPhone 17']!);
    await tester.pumpWidget(_app(const LeaderboardScreen()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Daniel Okafor'), findsWidgets);
  }

  final gender = find.byKey(const ValueKey('gender'));

  testWidgets('the gender switch shows only the current choice until tapped', (tester) async {
    await openBoard(tester);
    expect(find.descendant(of: gender, matching: find.text('All')), findsOneWidget);
    expect(find.text('M'), findsNothing);
    expect(find.text('F'), findsNothing);

    await tester.tap(gender);
    await tester.pumpAndSettle();
    expect(find.text('M'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);

    await tester.tap(find.text('F'));
    await tester.pumpAndSettle();
    expect(find.text('Daniel Okafor'), findsNothing);
    expect(find.text('Lily Chen'), findsWidgets);
    // Folded back up, showing the new choice.
    expect(find.text('M'), findsNothing);
    expect(find.descendant(of: gender, matching: find.text('F')), findsOneWidget);
  });

  testWidgets('tapping elsewhere folds the gender switch without changing it', (tester) async {
    await openBoard(tester);
    await tester.tap(gender);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 700));
    await tester.pumpAndSettle();
    expect(find.text('M'), findsNothing);
    expect(find.text('Daniel Okafor'), findsWidgets);
  });

  testWidgets('pressing and sliding down the gender switch picks where you let go', (tester) async {
    await openBoard(tester);
    final top = tester.getCenter(gender);
    final gesture = await tester.startGesture(top);
    await tester.pump(const Duration(milliseconds: 600)); // a long press opens it
    await tester.pumpAndSettle();
    await gesture.moveTo(tester.getCenter(find.text('M')));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('F')));
    await tester.pump();
    // Nothing filters until the finger lifts.
    expect(find.text('Daniel Okafor'), findsWidgets);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Daniel Okafor'), findsNothing);
    expect(find.text('Lily Chen'), findsWidgets);
  });
}
