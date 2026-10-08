import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'design_system.dart';
import 'athlete_profile_screen.dart';
import 'team_data.dart';

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
  bool _linked = false;

  // Linking search flow
  bool _showSearch = false;
  List<Map<String, dynamic>> _searchResults = [];
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  bool _linking = false;
  Timer? _searchDebounce;
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Waits for a pause in typing instead of querying on every keystroke.
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    setState(() {}); // show/hide the clear button
    _searchDebounce = Timer(
      const Duration(milliseconds: 250),
      () => _searchAthletes(query),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final profile =
          await supabase.from('profiles').select().eq('id', uid).maybeSingle();

      if (profile != null) {
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

    final email = supabase.auth.currentUser?.email ?? '';
    final meta = supabase.auth.currentUser?.userMetadata;
    final name = meta?['full_name'] ?? email.split('@')[0];

    try {
      // New profiles start teamless; team_id is only ever set by join_team.
      await supabase.from('profiles').insert({
        'id': uid,
        'full_name': name,
        'role': 'athlete',
      });

      setState(() {
        _profile = {'id': uid, 'full_name': name, 'team_id': null, 'role': 'athlete'};
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
    // Responses can arrive out of order; only the latest search may win.
    final seq = ++_searchSeq;
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);

    try {
      final results = await supabase
          .from('profiles')
          .select('id, full_name, gender, tfrrs_athlete_id')
          .not('tfrrs_athlete_id', 'is', null)
          .ilike('full_name', '%$query%')
          .limit(10);

      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(results);
        _searching = false;
      });
    } catch (_) {
      if (!mounted || seq != _searchSeq) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _linkProfile(Map<String, dynamic> tfrrsProfile) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _linking = true);
    final oldId = tfrrsProfile['id'] as String;

    try {
      // Moves the scraped profile's PRs and meet history onto our account in
      // one server-side transaction (see claim_tfrrs_profile).
      await supabase.rpc('claim_tfrrs_profile', params: {'p_profile_id': oldId});

      // Our results just moved to a new athlete id; drop the stale cache.
      TeamData.instance.load(force: true).ignore();
      await _load();
    } catch (e) {
      setState(() => _linking = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to link profile: $e'), backgroundColor: C.accentOf(Theme.of(context).brightness == Brightness.dark)),
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

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        backgroundColor: C.bg(dark),
        body: Center(child: CircularProgressIndicator(color: C.accentOf(dark), strokeWidth: 2)),
      );
    }

    // If linked with PRs, show the full athlete profile screen directly
    if (_linked && _profile != null) {
      final uid = supabase.auth.currentUser?.id ?? '';
      return AthleteProfileScreen(
        athleteId: uid,
        athleteName: _profile!['full_name'] ?? 'Unknown',
        gender: _profile!['gender'] ?? 'M',
        showBackButton: false,
      );
    }

    // Otherwise show the linking flow
    final name = _profile?['full_name'] as String? ?? 'Unknown';
    return Scaffold(
      backgroundColor: C.bg(dark),
      body: _profile == null
          ? Center(child: EmptyState(icon: Icons.person_off_outlined, title: 'Profile not found', dark: dark))
          : ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                WashHeader(
                  dark: dark,
                  padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('My Profile', style: pageTitleStyle(dark)),
                      const SizedBox(height: 24),
                      FadeSlideIn(
                        child: Row(
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [C.accentAlt, C.accentOf(false)],
                                ),
                                boxShadow: [
                                  BoxShadow(color: C.accentOf(dark).withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8)),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _initials(name),
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    formatName(name),
                                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: C.text1(dark)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _profile!['role'] == 'coach' ? 'Coach' : 'Athlete · not linked to TFRRS yet',
                                    style: TextStyle(fontSize: 14, color: C.text2(dark)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showSearch && !_linked)
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 80),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildLinkSection(dark),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildLinkSection(bool dark) {
    final query = _searchCtrl.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('Link your TFRRS profile', dark: dark),
        const SizedBox(height: 6),
        Text(
          'Find your name to bring in your race results and PRs.',
          style: TextStyle(fontSize: 14, height: 1.4, color: C.text2(dark)),
        ),
        const SizedBox(height: 16),
        InputField(
          controller: _searchCtrl,
          hint: 'Search by name',
          icon: Icons.search,
          dark: dark,
          onChanged: _onSearchChanged,
          onClear: () {
            _searchDebounce?.cancel();
            _searchSeq++; // drop any search still in flight
            setState(() {
              _searchResults = [];
              _searching = false;
            });
          },
        ),
        const SizedBox(height: 16),
        if (_searching || _linking)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: C.accentOf(dark), strokeWidth: 2)),
                if (_linking) ...[
                  const SizedBox(height: 10),
                  Text('Linking your profile…', style: TextStyle(fontSize: 14, color: C.text2(dark))),
                ],
              ],
            ),
          )
        else if (_searchResults.isNotEmpty)
          GlassCard(
            forceDark: dark,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _searchResults.length; i++) ...[
                  if (i > 0) Divider(height: 0.5, thickness: 0.5, indent: 68, color: C.border(dark)),
                  _resultRow(_searchResults[i], dark),
                ],
              ],
            ),
          )
        else if (query.length >= 2)
          EmptyState(icon: Icons.search_off_rounded, title: 'No athletes found', message: 'Try your last name.', dark: dark),
      ],
    );
  }

  Widget _resultRow(Map<String, dynamic> result, bool dark) {
    final raw = result['full_name'] as String? ?? '';
    return PressScale(
      pressedScale: 0.98,
      onTap: () => _confirmLink(result),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            InitialsAvatar(name: raw, gender: result['gender'] as String? ?? 'M', dark: dark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatName(raw), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.text1(dark))),
                  Text('TFRRS #${result['tfrrs_athlete_id'] ?? ''}', style: TextStyle(fontSize: 13, color: C.text3(dark))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLink(Map<String, dynamic> tfrrsProfile) async {
    final name = formatName(tfrrsProfile['full_name'] ?? 'Unknown');
    final confirmed = await confirmAction(
      context,
      title: 'Are you $name?',
      message: "Their PRs, meets and rankings from TFRRS will move onto your account.",
      confirmLabel: "Yes, that's me",
      cancelLabel: 'Not me',
    );
    if (confirmed && mounted) _linkProfile(tfrrsProfile);
  }

}