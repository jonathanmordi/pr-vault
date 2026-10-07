import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'athlete_profile_screen.dart';
import 'design_system.dart';
import 'leaderboard_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'maxes_screen.dart';
import 'onboarding.dart';
import 'prefs.dart';

Future<void> main() async {
  // Ensure Supabase is ready before rendering any widgets.
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );
  await Prefs.instance.load();
  runApp(const PRVaultApp());
}

/// Global Supabase client handle reused throughout the app.
final supabase = Supabase.instance.client;

/// Root widget that wires up the Material themes and auth gate.
class PRVaultApp extends StatelessWidget {
  const PRVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild on settings changes so the theme switches immediately.
    return PrefsScope(
      child: ListenableBuilder(
        listenable: Prefs.instance,
        builder: (context, _) {
          return MaterialApp(
            title: 'PR Vault',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.light,
              scaffoldBackgroundColor: C.bg(false),
              colorScheme: ColorScheme.light(
                primary: C.accentOf(false),
                secondary: C.accentOf(false),
                surface: C.surface(false),
                onPrimary: Colors.white,
                onSurface: C.text1(false),
              ),
              appBarTheme: AppBarTheme(
                backgroundColor: C.surface(false),
                foregroundColor: C.text1(false),
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                titleTextStyle: TextStyle(
                  color: C.text1(false),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              chipTheme: ChipThemeData(
                backgroundColor: C.surface2(false),
                selectedColor: C.accentOf(false),
                labelStyle: TextStyle(fontSize: 12, color: C.text2(false)),
                secondaryLabelStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              dividerColor: C.border(false),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              scaffoldBackgroundColor: C.bg(true),
              colorScheme: ColorScheme.dark(
                primary: C.accentOf(true),
                secondary: C.accentOf(true),
                surface: C.surface(true),
                onPrimary: Colors.white,
                onSurface: C.text1(true),
              ),
              appBarTheme: AppBarTheme(
                backgroundColor: C.surface(true),
                foregroundColor: C.text1(true),
                elevation: 0,
                surfaceTintColor: const Color.fromARGB(0, 255, 255, 255),
                titleTextStyle: TextStyle(
                  color: C.text1(true),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              chipTheme: ChipThemeData(
                backgroundColor: C.surface2(true),
                selectedColor: C.accentOf(true),
                labelStyle: TextStyle(fontSize: 12, color: C.text2(true)),
                secondaryLabelStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              dividerColor: C.border(true),
            ),
            themeMode: Prefs.instance.themeMode,
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

/// Waits for a signed-in session, then onboarding, before the main shell.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Fall back to the restored session until the stream's first event
        // arrives, so signed-in users don't see the login screen flash.
        final session = snapshot.hasData
            ? snapshot.data!.session
            : supabase.auth.currentSession;
        if (session != null) return const OnboardingGate(child: MainShell());
        return const LoginScreen();
      },
    );
  }
}

/// Hosts the tabbed experience with the floating bottom nav.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  /// Tabs are built the first time they're opened and then kept alive, so
  /// switching back is instant instead of refetching behind a spinner.
  final Set<int> _visited = {0};

  static const List<Widget> _screens = [
    LeaderboardScreen(),
    ProfileScreen(),
    MaxesScreen(),
    SettingsScreen(),
  ];

  void _select(int i) {
    if (i == _currentIndex) return;
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _currentIndex = i;
      _visited.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SheetBackdrop(
      child: Scaffold(
        backgroundColor: C.bg(dark),
        body: Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < _screens.length; i++)
              _TabPage(
                key: ValueKey(i),
                active: i == _currentIndex,
                child: _visited.contains(i) ? _screens[i] : const SizedBox(),
              ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 32,
              child: _FloatingNav(
                currentIndex: _currentIndex,
                onTap: _select,
                dark: dark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cross-fades between tabs. Hidden tabs keep their state but don't take
/// taps or run animations.
class _TabPage extends StatelessWidget {
  final bool active;
  final Widget child;

  const _TabPage({super.key, required this.active, required this.child});

  @override
  Widget build(BuildContext context) {
    // TickerMode must sit inside the fade: wrapped around it, it paused the
    // fade-out itself, leaving the old tab fully visible on top.
    return IgnorePointer(
      ignoring: !active,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: TickerMode(enabled: active, child: child),
      ),
    );
  }
}

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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VerifyEmailScreen(email: email)),
    );
  }

  Future<void> _submit() async {
    // Single handler toggles between login and registration states.
    final email = _emailCtrl.text.trim();
    setState(() => _loading = true);
    try {
      if (_isSignUp) {
        final res = await supabase.auth.signUp(
          email: email,
          password: _passCtrl.text.trim(),
          data: {'full_name': _nameCtrl.text.trim(), 'role': 'athlete'},
        );
        // With email confirmation on there's no session until the emailed
        // code is entered. Without it, AuthGate takes over straight away.
        if (res.session == null && mounted) _openVerify(email);
      } else {
        try {
          await supabase.auth.signInWithPassword(
            email: email,
            password: _passCtrl.text.trim(),
          );
        } on AuthException catch (e) {
          // Signed up but never entered the code: send a fresh one.
          if (e.code != 'email_not_confirmed') rethrow;
          await const OnboardingApi().resendSignup(email);
          if (mounted) _openVerify(email);
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

    return Scaffold(
      backgroundColor: C.bg(dark),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [C.accentOf(dark), C.accentAlt],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x4DB80C09),
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'V',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'PR Vault',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.96,
                  color: C.text1(dark),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                _isSignUp ? 'Create your account' : 'Track. Lift. Compete.',
                style: TextStyle(fontSize: 15, color: C.text3(dark)),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              if (_isSignUp) ...[
                InputField(
                  controller: _nameCtrl,
                  hint: 'Full name',
                  icon: Icons.person_outline,
                  dark: dark,
                ),
                const SizedBox(height: 12),
              ],
              InputField(
                controller: _emailCtrl,
                hint: _isSignUp ? 'School email' : 'Email',
                icon: Icons.mail_outline,
                dark: dark,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 12),
              InputField(
                controller: _passCtrl,
                hint: 'Password',
                icon: Icons.lock_outline,
                dark: dark,
                obscure: true,
              ),
              const SizedBox(height: 20),
              if (_isSignUp) ...[
                Text(
                  "Use your school email and you'll join your team "
                  'automatically. We\'ll send a code to check it.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: C.text3(dark)),
                ),
                const SizedBox(height: 16),
              ],
              PrimaryButton(
                label: _isSignUp ? 'Create Account' : 'Sign In',
                loading: _loading,
                onTap: _submit,
                dark: dark,
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => setState(() => _isSignUp = !_isSignUp),
                child: Text(
                  _isSignUp
                      ? 'Already have an account? Sign in'
                      : "Don't have an account? Sign up",
                  style: TextStyle(
                    fontSize: 13,
                    color: C.accentOf(dark),
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill-shaped tab bar. Tap a tab, or press and slide along the bar: the
/// highlight follows your finger and the tab under it opens when you let go.
class _FloatingNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool dark;

  const _FloatingNav({
    required this.currentIndex,
    required this.onTap,
    required this.dark,
  });

  @override
  State<_FloatingNav> createState() => _FloatingNavState();
}

class _FloatingNavState extends State<_FloatingNav> {
  static const _items = [
    (Icons.leaderboard_outlined, Icons.leaderboard, 'Leaderboard'),
    (Icons.person_outline, Icons.person, 'Profile'),
    (Icons.fitness_center_outlined, Icons.fitness_center, 'Maxes'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  /// Gap between the bar's edge and the highlight.
  static const _inset = 6.0;

  /// Finger position while sliding, null otherwise.
  double? _dragX;
  int? _hover;

  int _indexAt(double x, double slot) =>
      ((x - _inset) / slot).floor().clamp(0, _items.length - 1);

  void _startSlide(double x, double slot) {
    HapticFeedback.lightImpact();
    setState(() {
      _dragX = x;
      _hover = _indexAt(x, slot);
    });
  }

  void _slide(double x, double slot) {
    if (_dragX == null) return;
    final i = _indexAt(x, slot);
    if (i != _hover) HapticFeedback.selectionClick();
    setState(() {
      _dragX = x;
      _hover = i;
    });
  }

  void _endSlide() {
    final i = _hover;
    if (_dragX == null || i == null) return;
    setState(() {
      _dragX = null;
      _hover = null;
    });
    widget.onTap(i);
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final slot = (width - _inset * 2) / _items.length;
        final sliding = _dragX != null;
        final shown = _hover ?? widget.currentIndex;
        // Sliding, the pill tracks the finger; otherwise it rests on a tab.
        final left = sliding
            ? (_dragX! - slot / 2).clamp(_inset, width - _inset - slot)
            : _inset + slot * widget.currentIndex;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => widget.onTap(_indexAt(d.localPosition.dx, slot)),
          onHorizontalDragStart: (d) => _startSlide(d.localPosition.dx, slot),
          onHorizontalDragUpdate: (d) => _slide(d.localPosition.dx, slot),
          onHorizontalDragEnd: (_) => _endSlide(),
          onLongPressStart: (d) => _startSlide(d.localPosition.dx, slot),
          onLongPressMoveUpdate: (d) => _slide(d.localPosition.dx, slot),
          onLongPressEnd: (_) => _endSlide(),
          child: AnimatedScale(
            scale: sliding ? 1.03 : 1,
            duration: const Duration(milliseconds: 220),
            curve: kSpring,
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: C.border(dark), width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.4 : 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: sliding
                        ? Duration.zero
                        : const Duration(milliseconds: 380),
                    curve: Curves.easeOutBack,
                    left: left,
                    top: _inset,
                    bottom: _inset,
                    width: slot,
                    child: AnimatedScale(
                      scale: sliding ? 1.08 : 1,
                      duration: const Duration(milliseconds: 220),
                      curve: kSpring,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: C.accentSoft(dark),
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _inset),
                    child: Row(
                      children: [
                        for (var i = 0; i < _items.length; i++)
                          Expanded(
                            child: _NavItem(
                              icon: _items[i].$1,
                              activeIcon: _items[i].$2,
                              label: _items[i].$3,
                              active: shown == i,
                              dark: dark,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Icon and label for one tab. Taps are handled by the bar.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final bool dark;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? C.accentOf(dark) : C.text3(dark);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedScale(
          scale: active ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 250),
          curve: kSpring,
          child: Icon(active ? activeIcon : icon, size: 22, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: color,
          ),
        ),
      ],
    );
  }
}
