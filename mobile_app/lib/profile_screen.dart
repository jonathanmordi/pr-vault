import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  bool _linked = false; // whether auth user is linked to a TFRRS profile

  // For the linking search flow
  bool _showSearch = false;
  List<Map<String, dynamic>> _searchResults = [];
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  bool _linking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    // First: check if this auth user has a profile row
    try {
      final profile =
          await supabase.from('profiles').select().eq('id', uid).maybeSingle();

      if (profile != null) {
        // Auth user has a profile — check if it has PRs
        final prs = await supabase
            .from('track_prs')
            .select()
            .eq('athlete_id', uid)
            .order('event');

        setState(() {
          _profile = Map<String, dynamic>.from(profile);
          _prs = List<Map<String, dynamic>>.from(prs);
          _linked = _prs.isNotEmpty;
          _showSearch = _prs.isEmpty;
          _loading = false;
        });
        return;
      }
    } catch (_) {}

    // No profile row for auth user — create a basic one
    final email = supabase.auth.currentUser?.email ?? '';
    final meta = supabase.auth.currentUser?.userMetadata;
    final name = meta?['full_name'] ?? email.split('@')[0];

    try {
      // Get team_id (for now, use the first team)
      final teamResult = await supabase.from('teams').select('id').limit(1);
      final teamId = (teamResult as List).isNotEmpty ? teamResult[0]['id'] : null;

      await supabase.from('profiles').insert({
        'id': uid,
        'full_name': name,
        'team_id': teamId,
        'role': 'athlete',
      });

      setState(() {
        _profile = {
          'id': uid,
          'full_name': name,
          'team_id': teamId,
          'role': 'athlete',
        };
        _prs = [];
        _linked = false;
        _showSearch = true;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _profile = {'full_name': name, 'role': 'athlete'};
        _prs = [];
        _linked = false;
        _showSearch = true;
        _loading = false;
      });
    }
  }

  Future<void> _searchAthletes(String query) async {
    if (query.length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);

    try {
      // Search scraper-created profiles that have TFRRS data
      final results = await supabase
          .from('profiles')
          .select('id, full_name, tfrrs_athlete_id')
          .not('tfrrs_athlete_id', 'is', null)
          .ilike('full_name', '%$query%')
          .limit(10);

      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(results);
        _searching = false;
      });
    } catch (_) {
      setState(() => _searching = false);
    }
  }

  Future<void> _linkProfile(Map<String, dynamic> tfrrsProfile) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _linking = true);
    final oldId = tfrrsProfile['id'] as String;
    final tfrrsId = tfrrsProfile['tfrrs_athlete_id'] as String?;

    try {
      // Update all track_prs to point to auth user's ID
      await supabase
          .from('track_prs')
          .update({'athlete_id': uid})
          .eq('athlete_id', oldId);

      // Update all meet_appearances to point to auth user's ID
      await supabase
          .from('meet_appearances')
          .update({'athlete_id': uid})
          .eq('athlete_id', oldId);

      // Update the auth user's profile with TFRRS info
      await supabase.from('profiles').update({
        'tfrrs_athlete_id': tfrrsId,
        'full_name': tfrrsProfile['full_name'],
      }).eq('id', uid);

      // Delete the old scraper-created profile
      await supabase.from('profiles').delete().eq('id', oldId);

      // Reload everything
      await _load();
    } catch (e) {
      setState(() => _linking = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to link profile: $e'),
            backgroundColor: C.accent,
          ),
        );
      }
    }
  }

  String _initials(String name) {
    final formatted = formatName(name);
    final parts = formatted.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return formatted.isNotEmpty ? formatted[0].toUpperCase() : '?';
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
                        style: TextStyle(color: C.text3(dark))))
                : ListView(
                    padding: const EdgeInsets.only(bottom: 104),
                    children: [
                      // ── Title
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 0),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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

                      // ── Profile card
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 80),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: GlassCard(
                            forceDark: dark,
                            padding: const EdgeInsets.all(24),
                            child: Row(
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [C.accent, C.accentAlt],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0x59E8372D),
                                        blurRadius: 20,
                                        offset: Offset(0, 4),
                                      )
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _initials(
                                        _profile!['full_name'] ?? 'U'),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        formatName(
                                            _profile!['full_name'] ?? 'Unknown'),
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.4,
                                          color: C.text1(dark),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _profile!['role'] == 'coach'
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
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Link TFRRS profile (if not linked)
                      if (_showSearch && !_linked) ...[
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 120),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: _buildLinkSection(dark),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Stats grid (only if linked)
                      if (_linked) ...[
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 160),
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 20),
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
                                  icon: Icons.emoji_events_outlined,
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
                                  icon: Icons.track_changes_outlined,
                                  dark: dark,
                                ),
                                _statCard(
                                  label: 'Season',
                                  value: '2025',
                                  icon: Icons.calendar_today_outlined,
                                  dark: dark,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // ── PR list
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 240),
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PERSONAL RECORDS',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: C.text3(dark),
                                    letterSpacing: 0.06 * 13,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _prs.isEmpty
                                    ? GlassCard(
                                        forceDark: dark,
                                        padding: const EdgeInsets.all(24),
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
                                              final pr = entry.value;
                                              final last =
                                                  i == _prs.length - 1;
                                              final delta =
                                                  (pr['improvement_delta_pct']
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
                    ],
                  ),
      ),
    );
  }

  Widget _buildLinkSection(bool dark) {
    return GlassCard(
      forceDark: dark,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link, size: 16, color: C.accent),
              const SizedBox(width: 8),
              Text(
                'LINK YOUR TFRRS PROFILE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: C.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Find your name to connect your race results and PRs.',
            style: TextStyle(fontSize: 13, color: C.text3(dark)),
          ),
          const SizedBox(height: 14),

          // Search field
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF2C2C2E) : const Color(0xFFEEECE9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: Icon(Icons.search, size: 16, color: C.text3(dark)),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: TextStyle(fontSize: 15, color: C.text1(dark)),
                    decoration: InputDecoration(
                      hintText: 'Search by name…',
                      hintStyle:
                          TextStyle(color: C.text3(dark), fontSize: 15),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: _searchAthletes,
                  ),
                ),
                if (_searchCtrl.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() => _searchResults = []);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child:
                          Icon(Icons.close, size: 16, color: C.text3(dark)),
                    ),
                  ),
              ],
            ),
          ),

          // Search results
          if (_searching)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: C.accent, strokeWidth: 2),
                ),
              ),
            ),

          if (_linking)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: Column(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: C.accent, strokeWidth: 2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Linking your profile…',
                      style: TextStyle(fontSize: 13, color: C.text3(dark)),
                    ),
                  ],
                ),
              ),
            ),

          if (!_searching && !_linking && _searchResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...(_searchResults.map((result) {
              final name = formatName(result['full_name'] ?? 'Unknown');
              final tfrrsId = result['tfrrs_athlete_id'] ?? '';
              return InkWell(
                onTap: () => _confirmLink(result, dark),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: C.surface2(dark),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _initials(result['full_name'] ?? ''),
                          style: TextStyle(
                            fontSize: 12,
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
                              name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: C.text1(dark),
                              ),
                            ),
                            Text(
                              'TFRRS #$tfrrsId',
                              style: TextStyle(
                                  fontSize: 11, color: C.text3(dark)),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 16, color: C.text3(dark)),
                    ],
                  ),
                ),
              );
            })),
          ],

          if (!_searching &&
              !_linking &&
              _searchResults.isEmpty &&
              _searchCtrl.text.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: Text(
                  'No athletes found',
                  style: TextStyle(fontSize: 13, color: C.text3(dark)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _confirmLink(Map<String, dynamic> tfrrsProfile, bool dark) {
    final name = formatName(tfrrsProfile['full_name'] ?? 'Unknown');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface(dark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Link to $name?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: C.text1(dark),
          ),
        ),
        content: Text(
          'This will connect your account to this athlete\'s TFRRS data, including all PRs and meet results.',
          style: TextStyle(fontSize: 14, color: C.text2(dark)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: C.text3(dark))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _linkProfile(tfrrsProfile);
            },
            child: const Text('Link',
                style: TextStyle(
                    color: C.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
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
              child: Icon(icon, size: 18, color: C.text2(dark)),
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

// ─── PR row ─────────────────────────────────────────────────────────────────

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
                bottom: BorderSide(color: C.border(dark), width: 0.5),
              ),
            ),
      child: Row(
        children: [
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
                  pr['set_at_meet'] ?? 'Season best',
                  style: TextStyle(fontSize: 11, color: C.text3(dark)),
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
                  style: TextStyle(fontSize: 11, color: C.text3(dark)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}