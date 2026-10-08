// Sign-in and sign-up. A red hero shows what the app does (a track, a few
// cards like the ones inside), with the form on a card below it.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'design_system.dart';
import 'onboarding.dart';

final _supabase = Supabase.instance.client;

/// Email/password sign-in, and sign-up with a school email that's verified
/// with an emailed code.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _loading = false;
  bool _isSignUp = false;

  void _openVerify(String email) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => VerifyEmailScreen(email: email)));
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    setState(() => _loading = true);
    try {
      if (_isSignUp) {
        final res = await _supabase.auth.signUp(
          email: email,
          password: _passCtrl.text.trim(),
          data: {'full_name': _nameCtrl.text.trim()},
        );
        // With email confirmation on there's no session until the emailed
        // code is entered. Without it, AuthGate takes over straight away.
        if (res.session == null && mounted) _openVerify(email);
      } else {
        try {
          await _supabase.auth.signInWithPassword(email: email, password: _passCtrl.text.trim());
        } on AuthException catch (e) {
          // Signed up but never entered the code: send a fresh one.
          if (e.code != 'email_not_confirmed') rethrow;
          await const OnboardingApi().resendSignup(email);
          if (mounted) _openVerify(email);
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // So the logo is there from the first frame instead of popping in.
    precacheImage(const AssetImage(AppIcon.asset), context);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: C.bg(dark),
        body: Stack(
          children: [
            Positioned.fill(child: TrackBackdrop(dark: dark)),
            Column(
              children: [
                Expanded(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                      child: _HeroContent(signUp: _isSignUp),
                    ),
                  ),
                ),
                _form(dark),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _form(bool dark) {
    return Container(
      decoration: BoxDecoration(
        color: C.bg(dark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: SafeArea(
        top: false,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentToggle(
                  options: const ['Sign In', 'Sign Up'],
                  value: _isSignUp ? 'Sign Up' : 'Sign In',
                  dark: dark,
                  height: 40,
                  fontSize: 14,
                  onChanged: (v) => setState(() => _isSignUp = v == 'Sign Up'),
                ),
              ),
              const SizedBox(height: 16),
              if (_isSignUp) ...[
                InputField(controller: _nameCtrl, hint: 'Full name', icon: Icons.person_outline, dark: dark),
                const SizedBox(height: 10),
              ],
              InputField(
                controller: _emailCtrl,
                hint: _isSignUp ? 'School email' : 'Email',
                icon: Icons.mail_outline,
                dark: dark,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 10),
              InputField(controller: _passCtrl, hint: 'Password', icon: Icons.lock_outline, dark: dark, obscure: true),
              if (_isSignUp) ...[
                const SizedBox(height: 12),
                Text(
                  "Use your school email and you'll join your team automatically. "
                  "We'll send a code to check it.",
                  style: TextStyle(fontSize: 13, height: 1.4, color: C.text3(dark)),
                ),
              ],
              const SizedBox(height: 16),
              PrimaryButton(
                label: _isSignUp ? 'Create Account' : 'Sign In',
                loading: _loading,
                onTap: _submit,
                dark: dark,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Hero ─────────────────────────────────────────────────────────────────────

/// The logo, a few cards like the app's own, and the pitch. Drops the cards,
/// then the pitch, as the keyboard or the sign-up fields take the room.
class _HeroContent extends StatelessWidget {
  final bool signUp;

  const _HeroContent({required this.signUp});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      final showPitch = h >= 200;
      final showHeadline = h >= 130;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandMark(),
          Expanded(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: h >= 380 ? 1 : 0,
              child: h >= 380 ? const _PreviewCards() : const SizedBox.shrink(),
            ),
          ),
          if (showHeadline)
            Text(
              signUp ? 'Join your\nteam.' : 'Every PR.\nOne vault.',
              style: const TextStyle(
                fontSize: 42,
                height: 1.02,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.6,
                color: Colors.white,
              ),
            ),
          if (showPitch) ...[
            const SizedBox(height: 10),
            Text(
              signUp
                  ? 'Your TFRRS results come with you. Rankings, rivals and lifts, all in one place.'
                  : 'Your TFRRS results, team rankings, rivals and lifts, all in one place.',
              style: TextStyle(fontSize: 15, height: 1.4, color: Colors.white.withValues(alpha: 0.78)),
            ),
          ],
        ],
      );
    });
  }
}

/// Three tilted cards that gently float: a new PR, a national rank and a
/// trend, like the cards inside the app.
class _PreviewCards extends StatefulWidget {
  const _PreviewCards();

  @override
  State<_PreviewCards> createState() => _PreviewCardsState();
}

class _PreviewCardsState extends State<_PreviewCards> with SingleTickerProviderStateMixin {
  late final _float = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _float.stop();
    } else if (!_float.isAnimating) {
      _float.repeat();
    }
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;
      // Shrink the cards on shorter screens instead of overlapping them.
      final scale = (h / 300).clamp(0.75, 1.0);
      final cards = [
        (Offset(0, h * 0.06), -0.08, 0.0, const _PreviewCard.pr()),
        (Offset(w * 0.46, h * 0.30), 0.06, 0.33, const _PreviewCard.rank()),
        (Offset(w * 0.10, h * 0.58), -0.03, 0.66, const _PreviewCard.trend()),
      ];
      return AnimatedBuilder(
        animation: _float,
        builder: (context, _) => Stack(
          clipBehavior: Clip.none,
          children: [
            for (final (i, (at, tilt, phase, card)) in cards.indexed)
              Positioned(
                left: at.dx,
                top: at.dy + 6 * math.sin(2 * math.pi * (_float.value + phase)),
                child: FadeSlideIn(
                  delay: Duration(milliseconds: 120 + 110 * i),
                  child: Transform.rotate(
                    angle: tilt,
                    child: Transform.scale(scale: scale, alignment: Alignment.topLeft, child: card),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _PreviewCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool solid;

  const _PreviewCard.pr()
      : icon = Icons.bolt_rounded,
        label = 'NEW PR',
        value = '6.91m',
        detail = 'Long jump · +0.12m',
        solid = true;

  const _PreviewCard.rank()
      : icon = Icons.military_tech_rounded,
        label = 'NATIONALS',
        value = '#12 in D3',
        detail = 'Inside the cut',
        solid = false;

  const _PreviewCard.trend()
      : icon = Icons.trending_up_rounded,
        label = 'TRENDING',
        value = '+2.6%',
        detail = 'Better in 3 of 4 meets',
        solid = false;

  @override
  Widget build(BuildContext context) {
    final accent = C.accentOf(false);
    final ink = solid ? const Color(0xFF111114) : Colors.white;
    final soft = solid ? const Color(0xFF6E6E76) : Colors.white.withValues(alpha: 0.75);
    return Container(
      width: 168,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: solid ? Colors.white : Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: solid ? null : Border.all(color: Colors.white.withValues(alpha: 0.22), width: 0.8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: solid ? accent : Colors.white),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: solid ? accent : Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.05, color: ink)),
          const SizedBox(height: 3),
          Text(detail, style: TextStyle(fontSize: 12.5, color: soft)),
        ],
      ),
    );
  }
}
