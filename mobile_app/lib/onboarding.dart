import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'design_system.dart';
import 'pr_stats.dart';
import 'team_data.dart';

/// Digits in the email verification code. Matches auth.email.otp_length in
/// backend/supabase/config.toml.
const kCodeLength = 6;

enum JoinOutcome { joined, noTeamForDomain, unverified }

class TeamInfo {
  final String name;
  final String? division;

  const TeamInfo({required this.name, this.division});

  /// 'NCAA D3', 'NAIA', 'High school'.
  String? get divisionLabel => switch (division) {
        'D1' || 'D2' || 'D3' => 'NCAA $division',
        'HS' => 'High school',
        final d => d,
      };
}

class RosterEntry {
  final String id;
  final String name;
  final String gender;

  /// False for alumni, who've dropped off the current TFRRS roster.
  final bool onRoster;

  /// As TFRRS shows it, e.g. 'SR-4'.
  final String? classYear;

  const RosterEntry({
    required this.id,
    required this.name,
    required this.gender,
    this.onRoster = true,
    this.classYear,
  });
}

/// The Supabase calls sign-up and onboarding make, behind one seam so the
/// screens can be tested without a backend.
class OnboardingApi {
  const OnboardingApi();

  SupabaseClient get _db => Supabase.instance.client;

  String? get userId => _db.auth.currentUser?.id;
  String? get email => _db.auth.currentUser?.email;

  /// The signed-in user's team, or null if they aren't on one.
  Future<TeamInfo?> myTeam() async {
    final uid = userId;
    if (uid == null) return null;
    final row =
        await _db.from('profiles').select('teams(name, division)').eq('id', uid).maybeSingle();
    final team = row?['teams'] as Map<String, dynamic>?;
    if (team == null) return null;
    return TeamInfo(name: team['name'] as String, division: team['division'] as String?);
  }

  Future<String?> teamIdOf(String userId) async {
    final row = await _db.from('profiles').select('team_id').eq('id', userId).maybeSingle();
    return row?['team_id'] as String?;
  }

  /// Joins the team that uses the signed-in user's email domain (see
  /// join_team_by_email in backend/supabase/migrations).
  Future<JoinOutcome> joinByEmail() async {
    try {
      final team = await _db.rpc('join_team_by_email');
      return team == null ? JoinOutcome.noTeamForDomain : JoinOutcome.joined;
    } on PostgrestException catch (e) {
      if (e.message.contains('verify your email')) return JoinOutcome.unverified;
      rethrow;
    }
  }

  /// Joins by invite code. False if no team uses the code.
  Future<bool> joinByCode(String code) async =>
      await _db.rpc('join_team', params: {'p_code': code}) != null;

  /// Scraped TFRRS profiles on the user's team that nobody has claimed.
  Future<List<RosterEntry>> unclaimedRoster() async {
    final rows = await _db.rpc('unclaimed_roster') as List;
    return [
      for (final r in rows)
        RosterEntry(
          id: r['id'] as String,
          name: r['full_name'] as String? ?? '',
          gender: r['gender'] as String? ?? 'M',
          onRoster: r['on_roster'] as bool? ?? true,
          classYear: r['class_year'] as String?,
        ),
    ];
  }

  /// Moves a scraped profile's PRs, meets and ranks onto the user's account.
  Future<void> claim(String profileId) async {
    await _db.rpc('claim_tfrrs_profile', params: {'p_profile_id': profileId});
    TeamData.instance.load(force: true).ignore();
  }

  Future<void> verifySignup(String email, String code) =>
      _db.auth.verifyOTP(type: OtpType.signup, email: email, token: code);

  Future<void> resendSignup(String email) =>
      _db.auth.resend(type: OtpType.signup, email: email);

  Future<void> signOut() => _db.auth.signOut();

  /// Deletes the login and lifting maxes. TFRRS results stay with the team
  /// and go back on the roster (see delete_my_account in
  /// backend/supabase/migrations).
  Future<void> deleteAccount() => _db.rpc('delete_my_account');

  /// Drops the session on this phone only, for after the login was deleted.
  Future<void> signOutLocally() => _db.auth.signOut(scope: SignOutScope.local);

  /// Remembered per user so returning users skip the team check on launch.
  Future<bool> wasOnboarded(String userId) async {
    try {
      return (await SharedPreferences.getInstance()).getBool('onboarded:$userId') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markOnboarded(String userId) async {
    try {
      await (await SharedPreferences.getInstance()).setBool('onboarded:$userId', true);
    } catch (_) {}
  }
}

// ─── Gate ─────────────────────────────────────────────────────────────────────

enum _Stage { checking, claim, noTeam, unverified, offline, serverError, done }

/// Shows [child] once the signed-in user is on a team. New users join their
/// school's team through their verified school email, then pick themselves
/// from the TFRRS roster. An invite code is the fallback.
class OnboardingGate extends StatefulWidget {
  final Widget child;
  final OnboardingApi api;

  const OnboardingGate({super.key, required this.child, this.api = const OnboardingApi()});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  _Stage _stage = _Stage.checking;

  OnboardingApi get _api => widget.api;

  @override
  void initState() {
    super.initState();
    _check();
  }

  void _set(_Stage stage) {
    if (mounted) setState(() => _stage = stage);
  }

  Future<void> _check() async {
    final uid = _api.userId;
    if (uid == null) return;
    if (await _api.wasOnboarded(uid)) return _set(_Stage.done);
    _set(_Stage.checking);
    try {
      if (await _api.teamIdOf(uid) != null) return await _finish();
      _set(switch (await _api.joinByEmail()) {
        JoinOutcome.joined => _Stage.claim,
        JoinOutcome.noTeamForDomain => _Stage.noTeam,
        JoinOutcome.unverified => _Stage.unverified,
      });
    } on PostgrestException {
      // We reached the server; it's the request that failed.
      _set(_Stage.serverError);
    } catch (_) {
      _set(_Stage.offline);
    }
  }

  Future<void> _finish() async {
    final uid = _api.userId;
    if (uid != null) await _api.markOnboarded(uid);
    _set(_Stage.done);
  }

  Future<void> _useInviteCode() async {
    final joined = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => InviteCodeScreen(api: _api)),
    );
    if (joined == true) _set(_Stage.claim);
  }

  @override
  Widget build(BuildContext context) {
    final domain = (_api.email ?? '').split('@').last;
    final Widget page = switch (_stage) {
      _Stage.done => widget.child,
      _Stage.checking => const _Splash(),
      _Stage.claim => ClaimProfileScreen(api: _api, onDone: _finish),
      _Stage.noTeam => _GateMessage(
          icon: Icons.school_outlined,
          title: "PR Vault isn't at $domain yet",
          body: "Right now it's open to teams that have been set up. If your "
              'team gave you an invite code, you can use that instead.',
          action: 'Use an invite code',
          onAction: _useInviteCode,
          onSignOut: _api.signOut,
        ),
      _Stage.unverified => _GateMessage(
          icon: Icons.mark_email_unread_outlined,
          title: "We couldn't confirm your email",
          body: 'This account was created without an email code, so we '
              "can't match it to your team. Join with an invite code, or sign "
              'out and make a new account with a different school address.',
          action: 'Use an invite code',
          onAction: _useInviteCode,
          onSignOut: _api.signOut,
        ),
      _Stage.offline => _GateMessage(
          icon: Icons.cloud_off_outlined,
          title: "Couldn't reach PR Vault",
          body: 'Check your connection and try again.',
          action: 'Try again',
          onAction: _check,
          onSignOut: _api.signOut,
        ),
      _Stage.serverError => _GateMessage(
          icon: Icons.error_outline,
          title: "Couldn't finish setting up your account",
          body: "Something went wrong on PR Vault's end. Try again in a bit, "
              'or join with an invite code.',
          action: 'Try again',
          onAction: _check,
          secondary: 'Use an invite code',
          onSecondary: _useInviteCode,
          onSignOut: _api.signOut,
        ),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: KeyedSubtree(key: ValueKey(_stage), child: page),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: C.bg(dark),
      body: Center(child: CircularProgressIndicator(color: C.accentOf(dark), strokeWidth: 2)),
    );
  }
}

/// A full-screen explanation with one action and a way to sign out.
class _GateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;
  final String? secondary;
  final VoidCallback? onSecondary;
  final Future<void> Function() onSignOut;

  const _GateMessage({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
    this.secondary,
    this.onSecondary,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return StepScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          HeroIcon(icon: icon, dark: dark),
          const SizedBox(height: 28),
          StepHeading(title: title, body: body, dark: dark),
          const Spacer(),
          PrimaryButton(label: action, onTap: onAction, dark: dark),
          if (secondary != null) ...[
            const SizedBox(height: 10),
            PrimaryButton(label: secondary!, onTap: onSecondary ?? () {}, dark: dark, tone: ButtonTone.soft),
          ],
          const SizedBox(height: 4),
          LinkButton(label: 'Sign out', onTap: onSignOut, dark: dark),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ─── Verify email ─────────────────────────────────────────────────────────────

/// Collects the code emailed after sign-up. Verifying signs the user in, and
/// the screen closes so the gate behind it takes over.
class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final OnboardingApi api;

  const VerifyEmailScreen({super.key, required this.email, this.api = const OnboardingApi()});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  /// Matches auth.email.max_frequency; resending sooner is rejected.
  static const _resendWait = 60;

  final _codeCtrl = TextEditingController();
  bool _verifying = false;
  String? _error;
  int _cooldown = _resendWait;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown(); // a code was just sent
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendWait);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  void _onChanged(String code) {
    if (_error != null) setState(() => _error = null);
    if (code.length == kCodeLength) _verify(code);
  }

  Future<void> _verify(String code) async {
    if (_verifying) return;
    setState(() => _verifying = true);
    try {
      await widget.api.verifySignup(widget.email, code);
      if (mounted) Navigator.of(context).pop();
    } on AuthException {
      if (!mounted) return;
      _codeCtrl.clear();
      setState(() {
        _verifying = false;
        _error = "That code didn't work. Check the newest email, or send a new one.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = "Couldn't reach PR Vault. Check your connection and try again.";
      });
    }
  }

  Future<void> _resend() async {
    try {
      await widget.api.resendSignup(widget.email);
      if (!mounted) return;
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New code sent')));
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return StepScaffold(
      onBack: () => Navigator.of(context).pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 36),
          HeroIcon(icon: Icons.mark_email_read_outlined, dark: dark),
          const SizedBox(height: 28),
          StepHeading(
            title: 'Check your email',
            body: 'We sent a $kCodeLength-digit code to\n${widget.email}',
            dark: dark,
          ),
          const SizedBox(height: 32),
          CodeCells(
            controller: _codeCtrl,
            length: kCodeLength,
            onChanged: _onChanged,
            error: _error != null,
            busy: _verifying,
            dark: dark,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.4, color: C.accentOf(dark)),
            ),
          ],
          const SizedBox(height: 16),
          LinkButton(
            label: _cooldown > 0 ? 'Send a new code in ${_cooldown}s' : 'Send a new code',
            onTap: _cooldown > 0 ? null : _resend,
            dark: dark,
            accent: true,
          ),
        ],
      ),
    );
  }
}

// ─── Which one is you? ────────────────────────────────────────────────────────

/// Last onboarding step: pick your scraped TFRRS profile so your PRs and
/// meets move onto your account. Skippable; the Profile tab can link later.
class ClaimProfileScreen extends StatefulWidget {
  final OnboardingApi api;
  final VoidCallback onDone;

  const ClaimProfileScreen({super.key, required this.api, required this.onDone});

  @override
  State<ClaimProfileScreen> createState() => _ClaimProfileScreenState();
}

class _ClaimProfileScreenState extends State<ClaimProfileScreen> {
  final _searchCtrl = TextEditingController();
  List<RosterEntry>? _roster;
  bool _failed = false;
  String? _claiming;

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
    setState(() => _failed = false);
    try {
      final roster = await widget.api.unclaimedRoster();
      if (mounted) setState(() => _roster = roster);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  List<RosterEntry> get _matches {
    final q = _searchCtrl.text.trim().toLowerCase();
    final all = _roster ?? const <RosterEntry>[];
    if (q.isEmpty) return all;
    return all
        .where((r) => formatName(r.name).toLowerCase().contains(q) || r.name.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _pick(RosterEntry entry) async {
    final name = formatName(entry.name);
    final confirmed = await confirmAction(
      context,
      title: 'Are you $name?',
      message: 'Their PRs, meets and rankings from TFRRS will move onto your account.',
      confirmLabel: "Yes, that's me",
      cancelLabel: 'Not me',
    );
    if (!confirmed || !mounted) return;

    HapticFeedback.mediumImpact();
    setState(() => _claiming = entry.id);
    try {
      await widget.api.claim(entry.id);
      widget.onDone();
    } catch (_) {
      if (!mounted) return;
      setState(() => _claiming = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't link that profile. Try again.")),
      );
      _load(); // someone else may have just claimed it
    }
  }

  /// One card of names, separated by hairlines.
  Widget _group(List<RosterEntry> entries, bool dark) {
    return GlassCard(
      forceDark: dark,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) Divider(height: 0.5, thickness: 0.5, indent: 68, color: C.border(dark)),
            _row(entries[i], dark),
          ],
        ],
      ),
    );
  }

  Widget _row(RosterEntry entry, bool dark) {
    final detail = entry.onRoster ? classYearLabel(entry.classYear) : 'Alum';
    return PressScale(
      pressedScale: 0.98,
      onTap: _claiming == null ? () => _pick(entry) : () {},
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            InitialsAvatar(name: entry.name, gender: entry.gender, dark: dark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatName(entry.name),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.text1(dark)),
                  ),
                  if (detail != null)
                    Text(detail, style: TextStyle(fontSize: 13, color: C.text3(dark))),
                ],
              ),
            ),
            if (_claiming == entry.id)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(color: C.accentOf(dark), strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final matches = _matches;

    return Scaffold(
      backgroundColor: C.bg(dark),
      body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: WashHeader(
                dark: dark,
                padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 32, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Which one is you?', style: pageTitleStyle(dark)),
                    const SizedBox(height: 8),
                    Text(
                      'Pick your name from your team on TFRRS to bring in your PRs and meets.',
                      style: TextStyle(fontSize: 15, height: 1.4, color: C.text2(dark)),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverList.list(
                children: [
                  InputField(
                    controller: _searchCtrl,
                    hint: 'Search your name',
                    icon: Icons.search,
                    dark: dark,
                    onChanged: (_) => setState(() {}),
                    onClear: () => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            if (_failed)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: "Couldn't load your team",
                    actionLabel: 'Try again',
                    onAction: _load,
                    dark: dark,
                  ),
                ),
              )
            else if (_roster == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator(color: C.accentOf(dark), strokeWidth: 2)),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                // Current roster first; graduates and others who've left
                // can still find themselves under Alumni.
                sliver: SliverList.list(
                  children: [
                    if (matches.any((e) => e.onRoster)) _group(matches.where((e) => e.onRoster).toList(), dark),
                    if (matches.any((e) => !e.onRoster)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
                        child: Text('Alumni', style: SectionTitle.style(dark)),
                      ),
                      _group(matches.where((e) => !e.onRoster).toList(), dark),
                    ],
                  ],
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.paddingOf(context).bottom + 32),
                child: LinkButton(
                  label: _roster != null && matches.isEmpty
                      ? "Can't find yourself? Skip for now"
                      : "I'm not on TFRRS yet",
                  onTap: _claiming == null ? widget.onDone : null,
                  dark: dark,
                ),
              ),
            ),
          ],
        ),
    );
  }
}

// ─── Invite code ──────────────────────────────────────────────────────────────

/// Fallback for joining a team without a matching school email. Pops with
/// true once the user is on a team.
class InviteCodeScreen extends StatefulWidget {
  final OnboardingApi api;

  const InviteCodeScreen({super.key, this.api = const OnboardingApi()});

  @override
  State<InviteCodeScreen> createState() => _InviteCodeScreenState();
}

class _InviteCodeScreenState extends State<InviteCodeScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() => _loading = true);
    try {
      final joined = await widget.api.joinByCode(code);
      if (!mounted) return;
      if (joined) {
        // A lingering "doesn't match" snackbar would show on both routes
        // during the pop transition.
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("That code doesn't match a team.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Something went wrong: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return StepScaffold(
      onBack: () => Navigator.of(context).pop(false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          HeroIcon(icon: Icons.key_outlined, dark: dark),
          const SizedBox(height: 28),
          StepHeading(title: 'Enter invite code', body: 'If your team gave you a code, enter it here.', dark: dark),
          const Spacer(),
          InputField(controller: _codeCtrl, hint: 'Invite code', icon: Icons.tag, dark: dark),
          const SizedBox(height: 14),
          PrimaryButton(label: 'Join Team', loading: _loading, onTap: _submit, dark: dark),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
