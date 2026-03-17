import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'design_system.dart';

final supabase = Supabase.instance.client;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final user = supabase.auth.currentUser;

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        final darkOn = mode == ThemeMode.dark ||
            (mode == ThemeMode.system && dark);

        return Scaffold(
          backgroundColor: C.bg(dark),
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 104),
              children: [
                // ── Title ─────────────────────────────────────────
                FadeSlideIn(
                  delay: const Duration(milliseconds: 0),
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.96,
                        color: C.text1(dark),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Account ────────────────────────────────────────
                FadeSlideIn(
                  delay: const Duration(milliseconds: 80),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader('Account', dark),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20),
                        child: GlassCard(
                          forceDark: dark,
                          child: Column(
                            children: [
                              _SettingsRow(
                                icon: Icons.mail_outline,
                                title:
                                    user?.email ?? 'Not signed in',
                                subtitle: 'Email address',
                                dark: dark,
                                divider: true,
                              ),
                              _SettingsRow(
                                icon: Icons.school_outlined,
                                title: 'My Team',
                                subtitle: 'Team',
                                dark: dark,
                              ),
                            ],
                          ),
                        ),
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
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20),
                        child: GlassCard(
                          forceDark: dark,
                          child: Column(
                            children: [
                              _SettingsRow(
                                icon: darkOn
                                    ? Icons.dark_mode_outlined
                                    : Icons.light_mode_outlined,
                                title: 'Dark Mode',
                                subtitle: 'Appearance',
                                dark: dark,
                                divider: true,
                                trailing: CustomToggle(
                                  value: darkOn,
                                  onChanged: (val) {
                                    themeModeNotifier.value = val
                                        ? ThemeMode.dark
                                        : ThemeMode.light;
                                  },
                                ),
                              ),
                              _SettingsRow(
                                icon: Icons.notifications_outlined,
                                title: 'Notifications',
                                subtitle: 'PR alerts & updates',
                                dark: dark,
                                divider: true,
                                trailing: Icon(Icons.chevron_right,
                                    size: 16, color: C.text3(dark)),
                              ),
                              _SettingsRow(
                                icon: Icons.straighten_outlined,
                                title: 'Units',
                                subtitle: 'Metric',
                                dark: dark,
                                trailing: Icon(Icons.chevron_right,
                                    size: 16, color: C.text3(dark)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Sign out ───────────────────────────────────────
                FadeSlideIn(
                  delay: const Duration(milliseconds: 240),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20),
                    child: GlassCard(
                      forceDark: dark,
                      child: PressScale(
                        onTap: () => supabase.auth.signOut(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.logout,
                                  size: 16, color: C.accent),
                              SizedBox(width: 8),
                              Text(
                                'Sign Out',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: C.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

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
                            color: C.text3(dark)
                                .withValues(alpha: 0.5),
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
      },
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
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: C.text3(dark),
          letterSpacing: 0.06 * 13, // 0.06em @ 13px
        ),
      ),
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

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.dark,
    this.divider = false,
    this.trailing,
  });

  @override
  State<_SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<_SettingsRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTapDown: (_) => setState(() => _hover = true),
          onTapUp: (_) => setState(() => _hover = false),
          onTapCancel: () => setState(() => _hover = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            color: _hover ? C.accentSoft(widget.dark) : Colors.transparent,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              children: [
                // Icon box
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: C.surface2(widget.dark),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon,
                      size: 18, color: C.text2(widget.dark)),
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
                          style: TextStyle(
                              fontSize: 12,
                              color: C.text3(widget.dark)),
                        ),
                    ],
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        ),
        if (widget.divider)
          Container(
            height: 0.5,
            color: C.border(widget.dark),
            margin: const EdgeInsets.only(left: 64),
          ),
      ],
    );
  }
}
