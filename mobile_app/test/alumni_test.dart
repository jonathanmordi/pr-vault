// Alumni: athletes who've dropped off the current TFRRS roster keep their
// results but leave rivals and the current leaderboards, and show up
// separately when picking yourself at sign-up.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/athlete_profile_screen.dart';
import 'package:mobile_app/leaderboard_screen.dart';
import 'package:mobile_app/onboarding.dart';
import 'package:mobile_app/pr_stats.dart';
import 'package:mobile_app/team_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'onboarding_test.dart' show FakeApi;
import 'support/sample_team.dart';

void main() {
  setUpAll(() async {
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

  test('class years read as words', () {
    expect(classYearLabel('FR-1'), 'Freshman');
    expect(classYearLabel('SO-2'), 'Sophomore');
    expect(classYearLabel('JR-3'), 'Junior');
    expect(classYearLabel('SR-4'), 'Senior');
    expect(classYearLabel('GR-5'), 'Grad student');
    expect(classYearLabel(' '), isNull);
    expect(classYearLabel(null), isNull);
  });

  group('TeamSnapshot', () {
    test('everyone is current until the scraper says otherwise', () {
      final snap = sampleTeam();
      expect(snap.isCurrent('okafor'), isTrue);
      expect(snap.hasAlumni, isFalse);
      expect(snap.classYearOf('okafor'), 'JR-3');
    });

    test('alumni are no one\'s rival', () {
      expect(sampleTeam().rivalsOf('me')['Triple Jump']?.athleteId, 'okafor');
      final snap = sampleTeam(alumni: {'okafor'});
      expect(snap.isCurrent('okafor'), isFalse);
      expect(snap.hasAlumni, isTrue);
      expect(snap.rivalsOf('me'), isEmpty);
      // An alum still sees current teammates as rivals.
      expect(sampleTeam(alumni: {'me'}).rivalsOf('me')['Triple Jump']?.athleteId, 'okafor');
    });
  });

  group('leaderboard', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TeamData.instance.currentUserId = () => sampleUserId;
    });

    Future<void> pumpBoard(WidgetTester tester, Set<String> alumni) async {
      tester.view.physicalSize = const Size(402, 874) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      TeamData.instance.seed(sampleTeam(alumni: alumni));
      await tester.pumpWidget(const MaterialApp(home: LeaderboardScreen()));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Okafor');
      await tester.pumpAndSettle();
    }

    testWidgets('alumni only appear on PR Rankings, all-time', (tester) async {
      await pumpBoard(tester, {'okafor'});
      expect(find.text('Daniel Okafor'), findsNothing); // Heat Map

      await tester.tap(find.text('PR Rankings'));
      await tester.pumpAndSettle();
      expect(find.text('Current roster'), findsOneWidget);
      expect(find.text('Daniel Okafor'), findsNothing);

      await tester.tap(find.text('All-time'));
      await tester.pumpAndSettle();
      expect(find.text('Daniel Okafor'), findsWidgets);
      expect(find.text('ALUM'), findsWidgets);
    });

    testWidgets('no switch when nobody has left', (tester) async {
      await pumpBoard(tester, const {});
      expect(find.text('Daniel Okafor'), findsWidgets);
      await tester.tap(find.text('PR Rankings'));
      await tester.pumpAndSettle();
      expect(find.text('Current roster'), findsNothing);
      expect(find.text('ALUM'), findsNothing);
    });
  });

  testWidgets('picking yourself lists the current roster, then alumni', (tester) async {
    final api = FakeApi()
      ..roster = const [
        RosterEntry(id: 'p1', name: 'Chen, Lily', gender: 'F', classYear: 'SO-2'),
        RosterEntry(id: 'p2', name: 'Johnson, James', gender: 'M', onRoster: false, classYear: 'SR-4'),
        RosterEntry(id: 'p3', name: 'Okafor, Daniel', gender: 'M', classYear: 'FR-1'),
      ];
    await tester.pumpWidget(MaterialApp(home: OnboardingGate(api: api, child: const Text('MAIN'))));
    await tester.pumpAndSettle();

    expect(find.text('Sophomore'), findsOneWidget);
    expect(find.text('Freshman'), findsOneWidget);
    expect(find.text('Alumni'), findsOneWidget);
    final alumniTop = tester.getTopLeft(find.text('Alumni')).dy;
    expect(tester.getTopLeft(find.text('James Johnson')).dy, greaterThan(alumniTop));
    expect(tester.getTopLeft(find.text('Daniel Okafor')).dy, lessThan(alumniTop));

    // Searching keeps the split.
    await tester.enterText(find.byType(TextField), 'j');
    await tester.pumpAndSettle();
    expect(find.text('James Johnson'), findsOneWidget);
    expect(find.text('Alumni'), findsOneWidget);

    await tester.tap(find.text('James Johnson'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Yes, that's me"));
    await tester.pumpAndSettle();
    expect(api.claimed, ['p2']);
  });

  testWidgets('profiles show the class year, or Alum once they have left', (tester) async {
    TeamData.instance.currentUserId = () => sampleUserId;
    TeamData.instance.seed(sampleTeam(alumni: {'chen'}));

    Future<void> open(String id, String name, String gender) async {
      await tester.pumpWidget(MaterialApp(
        home: AthleteProfileScreen(key: UniqueKey(), athleteId: id, athleteName: name, gender: gender),
      ));
      await tester.pumpAndSettle();
    }

    await open('okafor', 'Okafor, Daniel', 'M');
    expect(find.text('Junior · Men'), findsOneWidget);
    expect(find.textContaining('Alum'), findsNothing);

    await open('chen', 'Chen, Lily', 'F');
    expect(find.textContaining('Junior'), findsNothing);
    expect(find.textContaining('Alum'), findsOneWidget);
  });
}
