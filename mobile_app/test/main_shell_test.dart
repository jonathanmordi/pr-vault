// The tab shell keeps every visited tab alive and cross-fades between them.
// Regression: the old tab's fade-out was paused along with its other
// animations, so leaving Settings left it fully visible on top.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/design_system.dart';
import 'package:mobile_app/leaderboard_screen.dart';
import 'package:mobile_app/main.dart';
import 'package:mobile_app/maxes_screen.dart';
import 'package:mobile_app/settings_screen.dart';
import 'package:mobile_app/team_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  testWidgets('only the selected tab is visible after switching',
      (tester) async {
    TeamData.instance.currentUserId = () => sampleUserId;
    TeamData.instance.seed(sampleTeam());

    await tester.pumpWidget(ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (_, mode, _) => MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: mode,
        home: const MainShell(),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));

    double opacityOf(Type screen) => tester
        .widget<FadeTransition>(find
            .ancestor(
                of: find.byType(screen), matching: find.byType(FadeTransition))
            .first)
        .opacity
        .value;

    // One frame to start the cross-fade, then let it finish.
    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> open(String tab) async {
      await tester.tap(find.text(tab).last);
      await settle();
    }

    await open('Settings');
    expect(opacityOf(SettingsScreen), 1);
    expect(opacityOf(LeaderboardScreen), 0);

    // Flip the theme while on Settings, as in the original report.
    await tester.tap(find.byType(CustomToggle));
    await settle();

    await open('Leaderboard');
    expect(opacityOf(LeaderboardScreen), 1);
    expect(opacityOf(SettingsScreen), 0);

    await open('Maxes');
    expect(opacityOf(MaxesScreen), 1);
    expect(opacityOf(LeaderboardScreen), 0);
    expect(opacityOf(SettingsScreen), 0);

    themeModeNotifier.value = ThemeMode.system;
  });
}
