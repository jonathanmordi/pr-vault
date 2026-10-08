// The team's data saved on the phone: shown at once on the next launch and
// when offline, refreshed in the background, and forgotten on sign-out.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/athlete_profile_screen.dart';
import 'package:mobile_app/leaderboard_screen.dart';
import 'package:mobile_app/prefs.dart';
import 'package:mobile_app/team_cache.dart';
import 'package:mobile_app/team_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/sample_team.dart';

void main() {
  final team = sampleTeam();
  var offline = false;
  var requests = 0;
  late MemoryTeamCacheStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test',
      httpClient: MockClient((req) async {
        requests++;
        if (offline) throw http.ClientException('offline', req.url);
        // One page of each table, then an empty page.
        final from = int.tryParse(req.url.queryParameters['offset'] ?? '0') ?? 0;
        final athlete = req.url.queryParameters['athlete_id']?.replaceFirst('eq.', '');
        List<Map<String, dynamic>> only(List<Map<String, dynamic>> rows) =>
            athlete == null ? rows : rows.where((r) => r['athlete_id'] == athlete).toList();
        final rows = from > 0
            ? const []
            : switch (req.url.pathSegments.last) {
                'track_prs' => only(team.prs),
                'meet_appearances' => only(team.appearances),
                'school_records' => team.records,
                _ => const [],
              };
        return http.Response(jsonEncode(rows), 200,
            request: req, headers: {'content-type': 'application/json'});
      }),
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false, autoRefreshToken: false),
    );
    TeamData.instance.currentUserId = () => sampleUserId;
  });

  setUp(() {
    offline = false;
    requests = 0;
    store = MemoryTeamCacheStore();
    TeamData.instance.store = store;
    TeamData.instance.newSession();
  });

  test('a saved copy reads back the same, but not for someone else or an older app', () {
    final copy = jsonDecode(jsonEncode(team.toCache())) as Map<String, dynamic>;
    final back = TeamSnapshot.fromCache(copy, sampleUserId)!;
    expect(back.prs.length, team.prs.length);
    expect(back.appearances.length, team.appearances.length);
    expect(back.nameOf('okafor'), 'Okafor, Daniel');
    expect(back.prEvents.length, team.prEvents.length);

    expect(TeamSnapshot.fromCache(copy, 'someone-else'), isNull);
    expect(TeamSnapshot.fromCache({...copy, 'v': 0}, sampleUserId), isNull);
  });

  test('downloading saves a copy; the next launch shows it, then downloads again', () async {
    await TeamData.instance.load();
    expect(store.copies.keys, [sampleUserId]);

    TeamData.instance.newSession(); // closed and opened again
    final before = requests;
    final restored = await TeamData.instance.restore();
    expect(restored!.prs.length, team.prs.length);
    expect(requests, before, reason: 'restoring needs no network');

    await TeamData.instance.load();
    expect(requests, greaterThan(before), reason: 'the saved copy is refreshed');
  });

  test('signing out forgets the saved copy', () async {
    await TeamData.instance.load();
    await TeamData.instance.clear();
    expect(store.copies, isEmpty);
    expect(TeamData.instance.cached, isNull);
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('offline, the leaderboard shows the saved copy instead of an error', (tester) async {
    phone(tester);
    await store.write(sampleUserId, jsonDecode(jsonEncode(team.toCache())) as Map<String, dynamic>);
    offline = true;
    await tester.pumpWidget(PrefsScope(child: const MaterialApp(home: LeaderboardScreen())));
    await tester.pumpAndSettle();
    // The saved copy shows straight away...
    expect(find.text('Daniel Okafor'), findsWidgets);
    expect(find.textContaining("Couldn't load the leaderboard"), findsNothing);

    // ...and once the client gives up retrying, a note says it's offline.
    await tester.pump(const Duration(minutes: 1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("Couldn't refresh. Check your connection."), findsOneWidget);
    expect(find.text('Daniel Okafor'), findsWidgets);
    await tester.pump(const Duration(seconds: 10)); // let the note time out
  });

  testWidgets('offline, a profile shows from the saved copy instead of an error', (tester) async {
    phone(tester);
    await store.write(sampleUserId, jsonDecode(jsonEncode(team.toCache())) as Map<String, dynamic>);
    offline = true;
    await tester.pumpWidget(PrefsScope(
      child: const MaterialApp(
        home: AthleteProfileScreen(athleteId: 'me', athleteName: 'Mordi, Jonathan', gender: 'M'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('14.10m'), findsWidgets);
    expect(find.text("Couldn't load this profile."), findsNothing);
    await tester.pump(const Duration(minutes: 1)); // the client's retries
  });
}
