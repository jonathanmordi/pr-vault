import 'package:flutter/material.dart';     
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'design_system.dart';

final supabase = Supabase.instance.client;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _prs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final profile =
        await supabase.from('profiles').select().eq('id', uid).single();
    final prs = await supabase
        .from('track_prs')
        .select()
        .eq('athlete_id', uid)
        .order('event');

    setState(() {
      _profile = Map<String, dynamic>.from(profile);
      _prs = List<Map<String, dynamic>>.from(prs);
      _loading = false;
    });
  }

  String _initials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  double get _bestImprovement => _prs.fold(0.0, (m, pr) {
        final d = (pr['improvement_delta_pct'] as num? ?? 0.0).toDouble();
        return d > m ? d : m;
      });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: C.bg(dark),
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                    color: C.accent, strokeWidth: 2))
            : _profile == null
                ? Center(
                    child: Text('Profile not found',
                        style:
                            TextStyle(color: C.text3(dark))))
                : ListView(
                    padding:
                        const EdgeInsets.only(bottom: 104),
                    children: [
                      // ── Title ──────────────────────────────────
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 0),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                              20, 16, 20, 0),
                          child: Text(
                            'My Profile',
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

                      // ── Profile card ────────────────────────────
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 80),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20),
                          child: GlassCard(
                            forceDark: dark,
                            padding: const EdgeInsets.all(24),
                            child: Row(
                              children: [
                                // Gradient avatar
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration:
                                      const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        C.accent,
                                        C.accentAlt
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Color(0x59E8372D),
                                        blurRadius: 20,
                                        offset: Offset(0, 4),
                                      )
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _initials(
                                        _profile!['full_name'] ??
                                            'U'),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _profile!['full_name'] ??
                                          'Unknown',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight:
                                            FontWeight.w700,
                                        letterSpacing: -0.4,
                                        color: C.text1(dark),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _profile!['role'] ==
                                              'coach'
                                          ? 'Coach'
                                          : 'Athlete',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: C.text3(dark),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        _pill(
                                          '${_prs.length} PRs',
                                          C.accentSoft(dark),
                                          C.accent,
                                        ),
                                        const SizedBox(width: 8),
                                        _pill(
                                          'Track',
                                          C.surface2(dark),
                                          C.text2(dark),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Stats grid ──────────────────────────────
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 160),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20),
                          child: GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics:
                                const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.55,
                            children: [
                              _statCard(
                                label: 'Total PRs',
                                value: '${_prs.length}',
                                icon:
                                    Icons.emoji_events_outlined,
                                dark: dark,
                              ),
                              _statCard(
                                label: 'Best Imp.',
                                value: _bestImprovement > 0
                                    ? '+${_bestImprovement.toStringAsFixed(2)}%'
                                    : '—',
                                icon: Icons.trending_up,
                                dark: dark,
                              ),
                              _statCard(
                                label: 'Events',
                                value:
                                    '${_prs.map((p) => p['event']).toSet().length}',
                                icon:
                                    Icons.track_changes_outlined,
                                dark: dark,
                              ),
                              _statCard(
                                label: 'Season',
                                value: '2025',
                                icon:
                                    Icons.calendar_today_outlined,
                                dark: dark,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── PR list ─────────────────────────────────
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 240),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PERSONAL RECORDS',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: C.text3(dark),
                                  letterSpacing:
                                      0.06 * 13, // 0.06em @ 13px
                                ),
                              ),
                              const SizedBox(height: 12),
                              _prs.isEmpty
                                  ? GlassCard(
                                      forceDark: dark,
                                      padding: const EdgeInsets
                                          .all(24),
                                      child: Center(
                                        child: Text(
                                          'No PRs yet',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: C.text3(dark),
                                          ),
                                        ),
                                      ),
                                    )
                                  : GlassCard(
                                      forceDark: dark,
                                      child: Column(
                                        children:
                                            _prs.asMap().entries.map(
                                          (entry) {
                                            final i = entry.key;
                                            final pr =
                                                entry.value;
                                            final last = i ==
                                                _prs.length - 1;
                                            final delta = (pr['improvement_delta_pct']
                                                    as num? ??
                                                0.0);
                                            return _PRRow(
                                              pr: pr,
                                              isLast: last,
                                              delta: delta,
                                              dark: dark,
                                            );
                                          },
                                        ).toList(),
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

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(100)),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required bool dark,
  }) {
    return GlassCard(
      forceDark: dark,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: C.surface2(dark),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Icon(icon, size: 18, color: C.text2(dark)),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: C.text1(dark),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: C.text3(dark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── PR row ───────────────────────────────────────────────────────────────────

class _PRRow extends StatelessWidget {
  final Map<String, dynamic> pr;
  final bool isLast;
  final num delta;
  final bool dark;

  const _PRRow({
    required this.pr,
    required this.isLast,
    required this.delta,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: C.border(dark), width: 0.5),
              ),
            ),
      child: Row(
        children: [
          // Icon box with event abbreviation
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: C.surface2(dark),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              pr['event'] ?? '',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: C.text2(dark),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pr['event'] ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: C.text1(dark),
                  ),
                ),
                Text(
                  'Season best',
                  style: TextStyle(
                      fontSize: 11, color: C.text3(dark)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                pr['best_display'] ?? '—',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: C.accent,
                  letterSpacing: -0.5,
                ),
              ),
              if (delta > 0)
                Text(
                  '+${delta.toStringAsFixed(1)}%',
                  style: TextStyle(
                      fontSize: 11, color: C.text3(dark)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
