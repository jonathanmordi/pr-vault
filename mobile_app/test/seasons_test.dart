// Indoor and outdoor are separate seasons: the leaderboard and profiles show
// one at a time, opening on the season of the latest results.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/athlete_profile_screen.dart';
import 'package:mobile_app/leaderboard_screen.dart';
import 'package:mobile_app/prefs.dart';
import 'package:mobile_app/team_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/sample_team.dart';

void main() {
  final team = sampleTeam();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // Profiles load their own rows; serve the sample team's.
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test',
      httpClient: MockClient((req) async {
        final athlete = req.url.queryParameters['athlete_id']?.replaceFirst('eq.', '');
        final rows = switch (req.url.pathSegments.last) {
          'track_prs' => team.prs.where((r) => r['athlete_id'] == athlete).toList(),
          'meet_appearances' => team.appearances.where((r) => r['athlete_id'] == athlete).toList(),
          _ => const [],
        };
        return http.Response(jsonEncode(rows), 200,
            request: req, headers: {'content-type': 'application/json'});
      }),
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false, autoRefreshToken: false),
    );
    TeamData.instance.currentUserId = () => sampleUserId;
  });

  setUp(() => TeamData.instance.seed(team));

  Widget app(Widget home) => PrefsScope(child: MaterialApp(home: home));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('the leaderboard opens on the latest season and switches', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const LeaderboardScreen()));
    await tester.pumpAndSettle();

    // The latest results are outdoor; the 60m is indoor only.
    final season = find.byKey(const ValueKey('season'));
    expect(find.descendant(of: season, matching: find.text('Outdoor')), findsOneWidget);
    expect(find.text('Marcus Smith'), findsNothing);

    await tester.tap(season);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Indoor'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: season, matching: find.text('Indoor')), findsOneWidget);
    expect(find.text('Marcus Smith'), findsWidgets);
  });

  testWidgets('event chips only offer the season\'s events', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const LeaderboardScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sprints'));
    await tester.pumpAndSettle();
    expect(find.text('60'), findsNothing); // outdoor
    expect(find.text('200'), findsOneWidget);
  });

  testWidgets('a profile shows one season\'s PRs at a time', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const AthleteProfileScreen(
        athleteId: 'me', athleteName: 'Mordi, Jonathan', gender: 'M')));
    await tester.pumpAndSettle();

    // Opens on outdoor, where the latest results are.
    expect(find.byKey(const ValueKey('profile-season')), findsOneWidget);
    expect(find.text('14.10m'), findsWidgets);
    expect(find.text('14.02m'), findsNothing);

    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('profile-season')), matching: find.text('Indoor')));
    await tester.pumpAndSettle();
    expect(find.text('14.02m'), findsWidgets);
    expect(find.text('6.88m'), findsWidgets);
    expect(find.text('14.10m'), findsNothing);
  });

  testWidgets('a profile opened from the leaderboard keeps its season', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const AthleteProfileScreen(
        athleteId: 'me', athleteName: 'Mordi, Jonathan', gender: 'M', season: 'indoor')));
    await tester.pumpAndSettle();
    expect(find.text('14.02m'), findsWidgets);
    expect(find.text('14.10m'), findsNothing);
  });

  testWidgets('meet history labels each meet\'s season', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const AthleteProfileScreen(
        athleteId: 'me', athleteName: 'Mordi, Jonathan', gender: 'M')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('INDOOR').first, 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('INDOOR'), findsWidgets);
    expect(find.text('OUTDOOR'), findsWidgets);
  });
}
