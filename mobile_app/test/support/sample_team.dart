// A small fake team for widget tests: realistic TFRRS-style names, a long
// name and meet names to stress layouts, and two seasons of results.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mobile_app/pr_stats.dart';
import 'package:mobile_app/team_data.dart';

const sampleUserId = 'me';

class _Series {
  final String athleteId;
  final String name;
  final String gender;
  final String event;
  final List<(String, double)> results;
  const _Series(this.athleteId, this.name, this.gender, this.event, this.results);
}

const _series = [
  _Series('me', 'Mordi, Jonathan', 'M', 'Triple Jump', [
    ('2025-01-18', 13.41), ('2025-02-22', 13.62), ('2025-12-06', 13.55),
    ('2026-01-24', 13.88), ('2026-02-28', 14.02), ('2026-04-18', 14.10),
  ]),
  _Series('me', 'Mordi, Jonathan', 'M', 'Long Jump', [
    ('2025-12-06', 6.71), ('2026-02-07', 6.88), ('2026-05-02', 6.93),
  ]),
  _Series('okafor', 'Okafor, Daniel', 'M', 'Triple Jump', [
    ('2025-12-06', 13.80), ('2026-01-24', 14.05), ('2026-03-28', 14.22),
  ]),
  _Series('okafor', 'Okafor, Daniel', 'M', 'Long Jump', [
    ('2025-12-06', 6.80), ('2026-02-07', 6.95),
  ]),
  _Series('bv', 'Bartholomew-Vanderbilt, Alexander Maximilian', 'M', '400 Meters', [
    ('2025-12-13', 51.20), ('2026-01-31', 50.42), ('2026-02-21', 49.87),
    ('2026-04-25', 49.31),
  ]),
  _Series('smith', 'Smith, Marcus', 'M', '60 Meters', [
    ('2025-12-13', 7.12), ('2026-01-31', 7.01), ('2026-02-21', 6.98),
  ]),
  _Series('chen', 'Chen, Lily', 'F', '400 Meters', [
    ('2025-12-13', 59.80), ('2026-02-21', 58.40), ('2026-04-25', 57.95),
  ]),
  _Series('chen', 'Chen, Lily', 'F', '200 Meters', [
    ('2026-03-28', 26.10), ('2026-04-25', 25.62),
  ]),
  _Series('rivera', 'Rivera, Sofia', 'F', 'Long Jump', [
    ('2025-12-06', 5.40), ('2026-02-07', 5.62), ('2026-05-02', 5.71),
  ]),
  _Series('nguyen', 'Nguyen, Ava', 'F', 'Mile', [
    ('2025-12-13', 312.4), ('2026-02-21', 305.9),
  ]),
];

const _meets = [
  'Fastrack National Invitational at the Ocean Breeze Athletic Complex',
  'MAC Indoor Championships',
  'Stevens Duck Classic',
];

String _display(String event, double v) {
  if (isFieldEvent(event)) return '${v.toStringAsFixed(2)}m';
  if (v >= 60) {
    final m = v ~/ 60;
    return '$m:${(v - m * 60).toStringAsFixed(2).padLeft(5, '0')}';
  }
  return v.toStringAsFixed(2);
}

/// [alumni] lists athlete ids that have left the roster.
TeamSnapshot sampleTeam({Set<String> alumni = const {}}) {
  final appearances = <Map<String, dynamic>>[];
  final prs = <Map<String, dynamic>>[];
  for (final s in _series) {
    final field = isFieldEvent(s.event);
    var i = 0;
    for (final (date, v) in s.results) {
      appearances.add({
        'athlete_id': s.athleteId,
        'event': s.event,
        'time_seconds': field ? null : v,
        'mark_meters': field ? v : null,
        'display_value': _display(s.event, v),
        'meet_name': _meets[i++ % _meets.length],
        'meet_date': date,
      });
    }
    final values = s.results.map((r) => r.$2).toList();
    final best = field
        ? values.reduce((a, b) => a > b ? a : b)
        : values.reduce((a, b) => a < b ? a : b);
    final prev = values.length > 1 ? values[values.length - 2] : best;
    prs.add({
      'athlete_id': s.athleteId,
      'event': s.event,
      'best_time_seconds': field ? null : best,
      'best_mark_meters': field ? best : null,
      'best_display': _display(s.event, best),
      'improvement_delta_pct': (best - prev).abs() / prev * 100,
      'set_on': s.results.last.$1,
      'set_at_meet': _meets.first,
      'profiles': {
        'full_name': s.name,
        'gender': s.gender,
        'on_roster': !alumni.contains(s.athleteId),
        'class_year': 'JR-3',
      },
    });
  }
  appearances.sort((a, b) =>
      (a['meet_date'] as String).compareTo(b['meet_date'] as String));
  return TeamSnapshot(
    userId: sampleUserId,
    prs: prs,
    appearances: appearances,
    records: [
      {
        'event': '400 Meters',
        'gender': 'M',
        'season': 'outdoor',
        'record_mark_seconds': 49.31,
        'record_mark_meters': null,
      },
    ],
  );
}

/// Loads Roboto and Material Icons from the Flutter SDK so text is measured
/// with real glyphs instead of the test font's 1em squares.
Future<void> loadRealFonts() async {
  // The test runner lives at <flutter>/bin/cache/artifacts/engine/...
  final exe = Platform.resolvedExecutable;
  final cache = exe.indexOf('/bin/cache/');
  final root = Platform.environment['FLUTTER_ROOT'] ??
      (cache >= 0 ? exe.substring(0, cache) : null);
  if (root == null) return;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('$dir/$f');
      if (file.existsSync()) {
        loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      }
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}
