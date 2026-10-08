# PR Vault app

The Flutter app (iOS and Android). See the [main README](../README.md) for
what it does and how the pieces fit together.

## Running

```bash
flutter pub get
flutter run          # needs lib/app_config.dart, see the main README
flutter test
flutter analyze
```

## Where things are

- `lib/main.dart`: startup, the auth gate and the tab bar.
- `lib/onboarding.dart`: joining a team by school email (or invite code)
  and claiming your TFRRS profile; then `lib/intro.dart`, shown once.
- `lib/team_data.dart`: one load of the team's PRs and results shared by
  every screen, with `lib/team_cache*.dart` saving a copy on the phone.
- `lib/pr_stats.dart` and `lib/insights.dart`: the pure-Dart logic (seasons,
  PR detection, trends, rivals, ranks, insights), unit tested without a
  backend.
- `lib/design_system.dart`: colors, shared components and animations.

Widget tests use a fake team (`test/support/sample_team.dart`) and serve
Supabase responses with `MockClient`, so they run offline.
