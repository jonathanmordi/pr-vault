// Settings: the team row, and deleting your account (a confirmation that
// says what goes and what stays, then the deletion and a sign-out).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'onboarding_test.dart' show FakeApi;

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

  Future<FakeApi> openSheet(WidgetTester tester, {Object? error}) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final api = FakeApi()..deleteError = error;
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Delete account'), 200);
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsOneWidget);
    expect(find.textContaining('lifting maxes are deleted'), findsOneWidget);
    expect(find.textContaining('TFRRS results stay'), findsOneWidget);
    return api;
  }

  testWidgets('cancelling keeps the account', (tester) async {
    final api = await openSheet(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.deletes, 0);
    expect(api.signedOutLocally, isFalse);
    expect(find.text('Delete your account?'), findsNothing);
  });

  testWidgets('confirming deletes the account and signs out', (tester) async {
    final api = await openSheet(tester);
    await tester.tap(find.widgetWithText(GestureDetector, 'Delete account').last);
    await tester.pumpAndSettle();
    expect(api.deletes, 1);
    expect(api.signedOutLocally, isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failed delete says so and stays signed in', (tester) async {
    final api = await openSheet(tester, error: Exception('offline'));
    await tester.tap(find.widgetWithText(GestureDetector, 'Delete account').last);
    await tester.pumpAndSettle();
    expect(api.signedOutLocally, isFalse);
    expect(find.text("Couldn't delete your account. Try again."), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the team row shows your team and division', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(api: FakeApi())));
    await tester.pumpAndSettle();
    expect(find.text('Stevens Ducks'), findsOneWidget);
    expect(find.text('Team · NCAA D3'), findsOneWidget);
    expect(find.text('My Team'), findsNothing);
  });

  testWidgets('without a team it says so', (tester) async {
    final api = FakeApi()..myTeamInfo = null;
    // The row remembers the last team per account; use a different one.
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(api: _OtherUser(api))));
    await tester.pumpAndSettle();
    expect(find.text('No team yet'), findsOneWidget);
  });
}

class _OtherUser extends FakeApi {
  _OtherUser(FakeApi base) {
    myTeamInfo = base.myTeamInfo;
  }

  @override
  String? get userId => 'someone-else';
}
