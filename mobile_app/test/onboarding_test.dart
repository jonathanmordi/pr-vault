// Sign-up and onboarding against a fake backend: joining by school email,
// picking yourself from the roster, the invite-code fallback and the
// emailed-code screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/onboarding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeApi extends OnboardingApi {
  FakeApi({
    this.team,
    this.outcome = JoinOutcome.joined,
    this.onboarded = false,
    this.mail = 'jane@stevens.edu',
  });

  String? team;
  JoinOutcome outcome;
  bool onboarded;
  final String mail;
  final claimed = <String>[];
  final codes = <String>[];
  int resends = 0;
  int teamChecks = 0;
  bool signedOut = false;
  Object? joinError;

  @override
  String? get userId => 'me';
  @override
  String? get email => mail;

  @override
  Future<String?> teamIdOf(String userId) async {
    teamChecks++;
    return team;
  }

  @override
  Future<JoinOutcome> joinByEmail() async {
    if (joinError != null) throw joinError!;
    if (outcome == JoinOutcome.joined) team = 'stevens';
    return outcome;
  }

  @override
  Future<bool> joinByCode(String code) async {
    if (code != 'DUCKS1') return false;
    team = 'stevens';
    return true;
  }

  List<RosterEntry> roster = const [
    RosterEntry(id: 'p1', name: 'Chen, Lily', gender: 'F'),
    RosterEntry(id: 'p2', name: 'Mordi, Jonathan', gender: 'M'),
    RosterEntry(id: 'p3', name: 'Okafor, Daniel', gender: 'M'),
  ];

  @override
  Future<List<RosterEntry>> unclaimedRoster() async => roster;

  @override
  Future<void> claim(String profileId) async => claimed.add(profileId);

  @override
  Future<void> verifySignup(String email, String code) async {
    codes.add(code);
    if (code != '123456') throw const AuthException('Token has expired or is invalid');
  }

  @override
  Future<void> resendSignup(String email) async => resends++;

  @override
  Future<void> signOut() async => signedOut = true;

  TeamInfo? myTeamInfo = const TeamInfo(name: 'Stevens Ducks', division: 'D3');

  @override
  Future<TeamInfo?> myTeam() async => myTeamInfo;

  int deletes = 0;
  bool signedOutLocally = false;
  Object? deleteError;

  @override
  Future<void> deleteAccount() async {
    if (deleteError != null) throw deleteError!;
    deletes++;
  }

  @override
  Future<void> signOutLocally() async => signedOutLocally = true;

  @override
  Future<bool> wasOnboarded(String userId) async => onboarded;

  @override
  Future<void> markOnboarded(String userId) async => onboarded = true;
}

Widget _gate(FakeApi api) => MaterialApp(
      home: OnboardingGate(api: api, child: const Text('MAIN SHELL')),
    );

void main() {
  testWidgets('returning users go straight in without a team check', (tester) async {
    final api = FakeApi(onboarded: true);
    await tester.pumpWidget(_gate(api));
    await tester.pumpAndSettle();
    expect(find.text('MAIN SHELL'), findsOneWidget);
    expect(api.teamChecks, 0);
  });

  testWidgets('users already on a team go straight in and are remembered', (tester) async {
    final api = FakeApi(team: 'stevens');
    await tester.pumpWidget(_gate(api));
    await tester.pumpAndSettle();
    expect(find.text('MAIN SHELL'), findsOneWidget);
    expect(api.onboarded, isTrue);
  });

  testWidgets('new users join by email, then pick themselves from the roster', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(_gate(api));
    await tester.pumpAndSettle();
    expect(find.text('Which one is you?'), findsOneWidget);
    expect(find.text('Lily Chen'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'mor');
    await tester.pump();
    expect(find.text('Lily Chen'), findsNothing);
    expect(find.text('Jonathan Mordi'), findsOneWidget);

    await tester.tap(find.text('Jonathan Mordi'));
    await tester.pumpAndSettle();
    expect(find.text('Are you Jonathan Mordi?'), findsOneWidget);
    await tester.tap(find.text("Yes, that's me"));
    await tester.pumpAndSettle();

    expect(api.claimed, ['p2']);
    expect(find.text('MAIN SHELL'), findsOneWidget);
    expect(api.onboarded, isTrue);
  });

  testWidgets('"Not me" keeps you on the roster', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(_gate(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lily Chen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not me'));
    await tester.pumpAndSettle();
    expect(api.claimed, isEmpty);
    expect(find.text('Which one is you?'), findsOneWidget);
  });

  testWidgets('skipping the roster still lets you in', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(_gate(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'm not on TFRRS yet"));
    await tester.pumpAndSettle();
    expect(api.claimed, isEmpty);
    expect(find.text('MAIN SHELL'), findsOneWidget);
  });

  testWidgets('an unknown school offers the invite code, which leads to the roster', (tester) async {
    final api = FakeApi(outcome: JoinOutcome.noTeamForDomain, mail: 'x@gmail.com');
    await tester.pumpWidget(_gate(api));
    await tester.pumpAndSettle();
    expect(find.text("PR Vault isn't at gmail.com yet"), findsOneWidget);

    await tester.tap(find.text('Use an invite code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Join Team'));
    await tester.pumpAndSettle();
    expect(find.text("That code doesn't match a team."), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ducks1');
    await tester.tap(find.text('Join Team'));
    await tester.pumpAndSettle();
    expect(find.text('Which one is you?'), findsOneWidget);
  });

  testWidgets('an unverified email explains why and offers a way out', (tester) async {
    final api = FakeApi(outcome: JoinOutcome.unverified);
    await tester.pumpWidget(_gate(api));
    await tester.pumpAndSettle();
    expect(find.text("We couldn't confirm your email"), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    expect(api.signedOut, isTrue);
  });

  testWidgets('a server error says so, not "check your connection"', (tester) async {
    final api = FakeApi()
      ..joinError = const PostgrestException(
          message: 'Could not find the function public.join_team_by_email', code: 'PGRST202');
    await tester.pumpWidget(_gate(api));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't finish setting up your account"), findsOneWidget);
    expect(find.text("Couldn't reach PR Vault"), findsNothing);

    // Once the server is fixed, trying again carries on.
    api.joinError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Which one is you?'), findsOneWidget);
  });

  testWidgets('no connection says to check the connection', (tester) async {
    final api = FakeApi()..joinError = Exception('SocketException: Failed host lookup');
    await tester.pumpWidget(_gate(api));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't reach PR Vault"), findsOneWidget);
  });

  group('VerifyEmailScreen', () {
    Future<FakeApi> open(WidgetTester tester) async {
      final api = FakeApi();
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => VerifyEmailScreen(email: 'jane@stevens.edu', api: api),
            )),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('a wrong code shows an error and clears the field', (tester) async {
      final api = await open(tester);
      await tester.enterText(find.byType(TextField), '000000');
      await tester.pump();
      expect(api.codes, ['000000']);
      expect(find.textContaining("That code didn't work"), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('the right code verifies on the last digit and closes', (tester) async {
      final api = await open(tester);
      await tester.enterText(find.byType(TextField), '12345');
      await tester.pump();
      expect(api.codes, isEmpty);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();
      expect(api.codes, ['123456']);
      expect(find.byType(VerifyEmailScreen), findsNothing);
    });

    testWidgets('a new code can be sent after a minute', (tester) async {
      final api = await open(tester);
      expect(find.text('Send a new code in 60s'), findsOneWidget);
      await tester.tap(find.textContaining('Send a new code'));
      expect(api.resends, 0);

      await tester.pump(const Duration(seconds: 61));
      await tester.tap(find.text('Send a new code'));
      await tester.pump();
      expect(api.resends, 1);
      expect(find.text('Send a new code in 60s'), findsOneWidget);
    });
  });
}
