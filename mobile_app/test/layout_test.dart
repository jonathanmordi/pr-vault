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

const _sizes = {
  'iPhone SE': Size(375, 667),
  'iPhone 17': Size(402, 874),
};

Widget _app(Widget home) => MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: C.bg(false),
      ),
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
      expect(find.text('TOP IMPROVERS'), findsOneWidget);

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
}
