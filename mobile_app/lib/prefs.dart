import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pr_stats.dart';

enum FieldUnits { metric, imperial }

enum LiftUnits { lbs, kg }

/// Settings picked in the Settings tab, saved across launches.
///
/// Widgets read them with [Prefs.of], which rebuilds them on change, so
/// switching units in Settings updates every tab.
class Prefs extends ChangeNotifier {
  Prefs._();
  static final instance = Prefs._();

  ThemeMode themeMode = ThemeMode.system;
  FieldUnits fieldUnits = FieldUnits.metric;
  LiftUnits liftUnits = LiftUnits.lbs;

  // Which PRs show in the Activity feed and count toward the bell.
  bool alertMine = true;
  bool alertRivals = true;
  bool alertTeam = true;
  bool alertRecords = true;
  bool showBadge = true;

  bool get imperial => fieldUnits == FieldUnits.imperial;

  static Prefs of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PrefsScope>()?.notifier ??
      instance;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      themeMode = ThemeMode.values.asNameMap()[p.getString('theme_mode')] ??
          ThemeMode.system;
      fieldUnits =
          FieldUnits.values.asNameMap()[p.getString('field_units')] ??
              FieldUnits.metric;
      liftUnits = LiftUnits.values.asNameMap()[p.getString('lift_units')] ??
          LiftUnits.lbs;
      alertMine = p.getBool('alert_mine') ?? true;
      alertRivals = p.getBool('alert_rivals') ?? true;
      alertTeam = p.getBool('alert_team') ?? true;
      alertRecords = p.getBool('alert_records') ?? true;
      showBadge = p.getBool('show_badge') ?? true;
      notifyListeners();
    } catch (_) {
      // Defaults are fine if storage is unavailable.
    }
  }

  /// Applies [change], rebuilds listeners and saves.
  void update(void Function(Prefs p) change) {
    change(this);
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await Future.wait([
        p.setString('theme_mode', themeMode.name),
        p.setString('field_units', fieldUnits.name),
        p.setString('lift_units', liftUnits.name),
        p.setBool('alert_mine', alertMine),
        p.setBool('alert_rivals', alertRivals),
        p.setBool('alert_team', alertTeam),
        p.setBool('alert_records', alertRecords),
        p.setBool('show_badge', showBadge),
      ]);
    } catch (_) {}
  }

  // ─── Formatting ────────────────────────────────────────────────────────────

  /// A field mark in the chosen units; track times are left as scraped.
  String mark(String event, String? display, num? meters) => markDisplay(
      event, display ?? '—', meters?.toDouble(),
      imperial: imperial);

  String gap(String event, double gap) =>
      formatGap(event, gap, imperial: imperial);

  /// A stored weight in the chosen units, e.g. "225 lbs" or "102.5 kg".
  String weight(num lbs) {
    if (liftUnits == LiftUnits.lbs) return '${lbs.round()} lbs';
    final kg = (lbs * kLbToKg * 2).round() / 2;
    return '${kg == kg.truncate() ? kg.toInt() : kg} kg';
  }

  String get weightUnit => liftUnits == LiftUnits.kg ? 'kg' : 'lbs';

  /// Converts a weight typed in the chosen units to whole pounds for storage.
  int toLbs(num entered) => liftUnits == LiftUnits.kg
      ? (entered / kLbToKg).round()
      : entered.round();
}

const kLbToKg = 0.45359237;

/// Makes [Prefs] available to [Prefs.of] below it.
class PrefsScope extends InheritedNotifier<Prefs> {
  PrefsScope({super.key, required super.child})
      : super(notifier: Prefs.instance);
}
