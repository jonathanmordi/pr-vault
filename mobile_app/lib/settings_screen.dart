import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'design_system.dart';
import 'intro.dart';
import 'onboarding.dart';
import 'prefs.dart';

final supabase = Supabase.instance.client;

const _themeLabels = {
  ThemeMode.system: 'Auto',
  ThemeMode.light: 'Light',
  ThemeMode.dark: 'Dark',
};

class SettingsScreen extends StatelessWidget {
  final OnboardingApi api;

  const SettingsScreen({super.key, this.api = const OnboardingApi()});

  String _alertsSummary(Prefs p) {
    final on = [p.alertMine, p.alertRivals, p.alertTeam];
    if (on.every((x) => x)) return 'All PRs';
    if (!on.any((x) => x)) return p.alertRecords ? 'School records only' : 'Off';
    return [
      if (p.alertMine) 'You',
      if (p.alertRivals) 'Rivals',
      if (p.alertTeam) 'Teammates',
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final user = supabase.auth.currentUser;
    final prefs = Prefs.of(context);

    return Scaffold(
      backgroundColor: C.bg(dark),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 104),
          children: [
            // ── Title ─────────────────────────────────────────
            WashHeader(
              dark: dark,
              padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 20, 24),
              child: FadeSlideIn(
                child: Text('Settings', style: pageTitleStyle(dark)),
              ),
            ),

            // ── Account ────────────────────────────────────────
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader('Account', dark),
                  _Group(
                    dark: dark,
                    children: [
                      _SettingsRow(
                        icon: Icons.mail_outline,
                        title: user?.email ?? 'Not signed in',
                        subtitle: 'Email address',
                        dark: dark,
                        divider: true,
                      ),
                      _TeamRow(api: api, dark: dark),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Preferences ────────────────────────────────────
            FadeSlideIn(
              delay: const Duration(milliseconds: 160),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader('Preferences', dark),
                  _Group(
                    dark: dark,
                    children: [
                      _SettingsRow(
                        icon: dark
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        title: 'Appearance',
                        subtitle: prefs.themeMode == ThemeMode.system
                            ? 'Matches your phone'
                            : _themeLabels[prefs.themeMode],
                        dark: dark,
                        divider: true,
                        below: SizedBox(
                          width: double.infinity,
                          child: SegmentToggle(
                            options: _themeLabels.values.toList(),
                            value: _themeLabels[prefs.themeMode]!,
                            dark: dark,
                            onChanged: (label) => prefs.update((p) =>
                                p.themeMode = _themeLabels.entries
                                    .firstWhere((e) => e.value == label)
                                    .key),
                          ),
                        ),
                      ),
                      _SettingsRow(
                        icon: Icons.notifications_outlined,
                        title: 'Notifications',
                        subtitle: _alertsSummary(prefs),
                        dark: dark,
                        divider: true,
                        trailing: _Chevron(dark),
                        onTap: () => _push(context, const NotificationSettingsScreen()),
                      ),
                      _SettingsRow(
                        icon: Icons.straighten_outlined,
                        title: 'Units',
                        subtitle:
                            '${prefs.imperial ? 'Feet & inches' : 'Meters'} · ${prefs.weightUnit}',
                        dark: dark,
                        divider: true,
                        trailing: _Chevron(dark),
                        onTap: () => _push(context, const UnitsSettingsScreen()),
                      ),
                      _SettingsRow(
                        icon: Icons.auto_stories_outlined,
                        title: 'How PR Vault works',
                        subtitle: 'The quick tour',
                        dark: dark,
                        trailing: _Chevron(dark),
                        onTap: () => _push(context, IntroScreen(onDone: () => Navigator.of(context).pop())),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Sign out ───────────────────────────────────────
            FadeSlideIn(
              delay: const Duration(milliseconds: 240),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: PressScale(
                  onTap: () async {
                    if (await confirmAction(
                      context,
                      title: 'Sign out?',
                      message: "You'll need your email and password to sign back in.",
                      confirmLabel: 'Sign Out',
                    )) {
                      await api.signOut();
                    }
                  },
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: cardDecoration(dark, radius: 16),
                    child: Text(
                      'Sign Out',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.accentOf(dark)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => _confirmDelete(context, api),
                child: Text(
                  'Delete account',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: C.text3(dark)),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Version footer ─────────────────────────────────
            FadeSlideIn(
              delay: const Duration(milliseconds: 320),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      'PR Vault v1.0.0',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: C.text3(dark),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Built for athletes, by athletes.',
                      style: TextStyle(
                        fontSize: 11,
                        color: C.text3(dark).withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmDelete(BuildContext context, OnboardingApi api) async {
  HapticFeedback.mediumImpact();
  final dark = Theme.of(context).brightness == Brightness.dark;
  final confirmed = await confirmAction(
    context,
    title: 'Delete your account?',
    body: _DeletePoints(dark: dark),
    confirmLabel: 'Delete account',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  final sure = await confirmAction(
    context,
    title: 'Are you sure?',
    message: "Your account will be deleted. This can't be undone.",
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!sure || !context.mounted) return;

  // Block the screen while deleting; the sign-out afterwards swaps the
  // whole app back to the sign-in screen.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
  );
  try {
    await api.deleteAccount();
    if (context.mounted) Navigator.of(context).pop();
    await api.signOutLocally();
  } catch (_) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't delete your account. Try again.")),
    );
  }
}

/// Says exactly what deleting removes and what stays before it happens.
class _DeletePoints extends StatelessWidget {
  final bool dark;

  const _DeletePoints({required this.dark});

  @override
  Widget build(BuildContext context) {
    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: C.surface2(dark), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: C.text2(dark)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(text, style: TextStyle(fontSize: 14, height: 1.4, color: C.text2(dark))),
                ),
              ),
            ],
          ),
        );

    return Column(
      children: [
        point(Icons.person_off_outlined, 'Your login and lifting maxes are deleted.'),
        point(Icons.emoji_events_outlined,
            "Your TFRRS results stay on your team's leaderboards, since "
            "they're public. If you come back, you can link them again."),
        point(Icons.warning_amber_rounded, "This can't be undone."),
      ],
    );
  }
}

void _push(BuildContext context, Widget screen) {
  HapticFeedback.selectionClick();
  Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
}

/// The user's team. Loaded once per account and remembered, so switching
/// tabs doesn't flash a placeholder.
class _TeamRow extends StatefulWidget {
  final OnboardingApi api;
  final bool dark;

  const _TeamRow({required this.api, required this.dark});

  @override
  State<_TeamRow> createState() => _TeamRowState();
}

class _TeamRowState extends State<_TeamRow> {
  static String? _cachedFor;
  static TeamInfo? _cached;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loading = _cachedFor != widget.api.userId;
    _load();
  }

  Future<void> _load() async {
    final uid = widget.api.userId;
    try {
      final team = await widget.api.myTeam();
      _cachedFor = uid;
      _cached = team;
    } catch (_) {
      // Keep whatever we showed last.
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final team = _cachedFor == widget.api.userId ? _cached : null;
    return _SettingsRow(
      icon: Icons.school_outlined,
      title: team?.name ?? (_loading ? 'Loading team…' : 'No team yet'),
      subtitle: ['Team', ?team?.divisionLabel].join(' · '),
      dark: widget.dark,
    );
  }
}

// ─── Notifications ────────────────────────────────────────────────────────────

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final prefs = Prefs.of(context);

    _SettingsRow toggle({
      required IconData icon,
      required String title,
      required String subtitle,
      required bool value,
      required void Function(Prefs p, bool v) set,
      bool divider = true,
    }) =>
        _SettingsRow(
          icon: icon,
          title: title,
          subtitle: subtitle,
          dark: dark,
          divider: divider,
          onTap: () => prefs.update((p) => set(p, !value)),
          trailing: CustomToggle(
            value: value,
            onChanged: (v) => prefs.update((p) => set(p, v)),
          ),
        );

    return _SubScreen(
      title: 'Notifications',
      children: [
        _SectionHeader('Show in Activity', dark),
        _Group(
          dark: dark,
          children: [
            toggle(
              icon: Icons.person_outline,
              title: 'Your PRs',
              subtitle: 'Every time you set a new best',
              value: prefs.alertMine,
              set: (p, v) => p.alertMine = v,
            ),
            toggle(
              icon: Icons.compare_arrows_rounded,
              title: "Rivals' PRs",
              subtitle: 'Your closest teammate in each event',
              value: prefs.alertRivals,
              set: (p, v) => p.alertRivals = v,
            ),
            toggle(
              icon: Icons.groups_outlined,
              title: "Teammates' PRs",
              subtitle: 'Everyone else on the team',
              value: prefs.alertTeam,
              set: (p, v) => p.alertTeam = v,
            ),
            toggle(
              icon: Icons.emoji_events_outlined,
              title: 'School records',
              subtitle: 'Always shown, even with teammates off',
              value: prefs.alertRecords,
              set: (p, v) => p.alertRecords = v,
              divider: false,
            ),
          ],
        ),
        const SizedBox(height: 28),
        _SectionHeader('Bell', dark),
        _Group(
          dark: dark,
          children: [
            toggle(
              icon: Icons.notifications_active_outlined,
              title: 'Unread badge',
              subtitle: 'Count new PRs on the bell',
              value: prefs.showBadge,
              set: (p, v) => p.showBadge = v,
              divider: false,
            ),
          ],
        ),
        _Footnote(
          'New PRs show up in Activity after the nightly TFRRS sync. '
          'Lock screen notifications need a paid Apple Developer account.',
          dark,
        ),
      ],
    );
  }
}

// ─── Units ────────────────────────────────────────────────────────────────────

class UnitsSettingsScreen extends StatelessWidget {
  const UnitsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final prefs = Prefs.of(context);

    return _SubScreen(
      title: 'Units',
      children: [
        _SectionHeader('Field Events', dark),
        _Group(
          dark: dark,
          children: [
            _ChoiceRow(
              title: 'Meters',
              example: '6.22m',
              selected: !prefs.imperial,
              dark: dark,
              divider: true,
              onTap: () => prefs.update((p) => p.fieldUnits = FieldUnits.metric),
            ),
            _ChoiceRow(
              title: 'Feet & inches',
              example: "20' 4.75\"",
              selected: prefs.imperial,
              dark: dark,
              onTap: () => prefs.update((p) => p.fieldUnits = FieldUnits.imperial),
            ),
          ],
        ),
        _Footnote(
          'Converted from the meter mark and rounded down to the quarter '
          'inch, like NCAA conversions. Times and multi-event points '
          "don't change.",
          dark,
        ),
        const SizedBox(height: 28),
        _SectionHeader('Lifting', dark),
        _Group(
          dark: dark,
          children: [
            _ChoiceRow(
              title: 'Pounds',
              example: '225 lbs',
              selected: prefs.liftUnits == LiftUnits.lbs,
              dark: dark,
              divider: true,
              onTap: () => prefs.update((p) => p.liftUnits = LiftUnits.lbs),
            ),
            _ChoiceRow(
              title: 'Kilograms',
              example: '102 kg',
              selected: prefs.liftUnits == LiftUnits.kg,
              dark: dark,
              onTap: () => prefs.update((p) => p.liftUnits = LiftUnits.kg),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Shared pieces ────────────────────────────────────────────────────────────

/// A pushed settings page with a back button and large title.
class _SubScreen extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SubScreen({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: C.bg(dark),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 104),
          children: [
            WashHeader(
              dark: dark,
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: PressScale(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: C.surface2(dark),
                    ),
                    child: Icon(Icons.arrow_back, size: 16, color: C.text2(dark)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Text(
                title,
                style: pageTitleStyle(dark),
              ),
            ),
                ],
              ),
            ),
            FadeSlideIn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final bool dark;
  final List<Widget> children;

  const _Group({required this.dark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassCard(
        forceDark: dark,
        // Clip so the pressed-row highlight keeps the card's corners.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(children: children),
        ),
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  final String text;
  final bool dark;

  const _Footnote(this.text, this.dark);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 10, 36, 0),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, height: 1.4, color: C.text3(dark)),
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  final bool dark;

  const _Chevron(this.dark);

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.chevron_right, size: 18, color: C.text3(dark));
}

/// One option in a pick-one list, with a live example of the format.
class _ChoiceRow extends StatelessWidget {
  final String title;
  final String example;
  final bool selected;
  final bool dark;
  final bool divider;
  final VoidCallback onTap;

  const _ChoiceRow({
    required this.title,
    required this.example,
    required this.selected,
    required this.dark,
    this.divider = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (selected) return;
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 15),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: C.text1(dark),
                    ),
                  ),
                ),
                Text(
                  example,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected ? C.accentOf(dark) : C.text3(dark),
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: kSpring,
                  child: Icon(Icons.check_rounded, size: 20, color: C.accentOf(dark)),
                ),
              ],
            ),
          ),
        ),
        if (divider)
          Container(
            height: 0.5,
            color: C.border(dark),
            margin: const EdgeInsets.only(left: 20),
          ),
      ],
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  final bool dark;

  const _SectionHeader(this.text, this.dark);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: SectionTitle(text, dark: dark),
    );
  }
}

// ─── Settings row ─────────────────────────────────────────────────────────────

class _SettingsRow extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool dark;
  final bool divider;
  final Widget? trailing;

  /// Full-width control under the title, for ones too wide to trail.
  final Widget? below;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.dark,
    this.divider = false,
    this.trailing,
    this.below,
    this.onTap,
  });

  @override
  State<_SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<_SettingsRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tappable = widget.onTap != null;
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: tappable ? (_) => setState(() => _pressed = true) : null,
          onTapUp: tappable ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: tappable ? () => setState(() => _pressed = false) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            color: _pressed ? C.surface2(widget.dark) : Colors.transparent,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              crossAxisAlignment: widget.below != null
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                // Icon tile
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: C.accentSoft(widget.dark),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(widget.icon, size: 17, color: C.accentOf(widget.dark)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: C.text1(widget.dark),
                        ),
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          style: TextStyle(fontSize: 12, color: C.text3(widget.dark)),
                        ),
                      if (widget.below != null) ...[
                        const SizedBox(height: 12),
                        widget.below!,
                      ],
                    ],
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 8),
                  widget.trailing!,
                ],
              ],
            ),
          ),
        ),
        if (widget.divider)
          Container(
            height: 0.5,
            color: C.border(widget.dark),
            margin: const EdgeInsets.only(left: 66),
          ),
      ],
    );
  }
}
