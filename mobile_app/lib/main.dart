import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'design_system.dart';
import 'leaderboard_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'maxes_screen.dart';

Future<void> main() async {
  // Ensure Supabase is ready before rendering any widgets.
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );
  runApp(const PRVaultApp());
}

/// Global Supabase client handle reused throughout the app.
final supabase = Supabase.instance.client;

/// Root widget that wires up the Material themes and auth gate.
class PRVaultApp extends StatelessWidget {
  const PRVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen for theme changes so toggling dark mode updates immediately.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'PR Vault',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: C.bg(false),
            colorScheme: ColorScheme.light(
              primary: C.accent,
              secondary: C.accent,
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
              selectedColor: C.accent,
              labelStyle: TextStyle(fontSize: 12, color: C.text2(false)),
              secondaryLabelStyle:
                  const TextStyle(color: Colors.white, fontSize: 12),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100)),
            ),
            dividerColor: C.border(false),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: C.bg(true),
            colorScheme: ColorScheme.dark(
              primary: C.accent,
              secondary: C.accent,
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
              selectedColor: C.accent,
              labelStyle: TextStyle(fontSize: 12, color: C.text2(true)),
              secondaryLabelStyle:
                  const TextStyle(color: Colors.white, fontSize: 12),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100)),
            ),
            dividerColor: C.border(true),
          ),
          themeMode: mode,
          home: const AuthGate(),
        );
      },
    );
  }
}

/// Waits for a signed-in session before showing the main shell.
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
        if (session != null) return const MainShell();
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
    return Scaffold(
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

/// Email/password auth plus optional invite code routing.
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

  Future<void> _submit() async {
    // Single handler toggles between login and registration states.
    setState(() => _loading = true);
    try {
      if (_isSignUp) {
        final res = await supabase.auth.signUp(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text.trim(),
          data: {'full_name': _nameCtrl.text.trim(), 'role': 'athlete'},
        );
        if (res.user != null && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => InviteCodeScreen(userId: res.user!.id),
            ),
          );
        }
      } else {
        await supabase.auth.signInWithPassword(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text.trim(),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
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
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [C.accent, C.accentAlt],
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
                _InputField(
                  controller: _nameCtrl,
                  hint: 'Full name',
                  icon: Icons.person_outline,
                  dark: dark,
                ),
                const SizedBox(height: 12),
              ],
              _InputField(
                controller: _emailCtrl,
                hint: 'Email',
                icon: Icons.mail_outline,
                dark: dark,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _InputField(
                controller: _passCtrl,
                hint: 'Password',
                icon: Icons.lock_outline,
                dark: dark,
                obscure: true,
              ),
              const SizedBox(height: 20),
              PressScale(
                onTap: _loading ? () {} : _submit,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [C.accent, C.accentAlt],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x4DB80C09),
                        blurRadius: 20,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _isSignUp ? 'Create Account' : 'Sign In',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
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
                    color: C.accent,
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

/// Collects the team invite code immediately after sign-up.
class InviteCodeScreen extends StatefulWidget {
  final String userId;
  const InviteCodeScreen({super.key, required this.userId});

  @override
  State<InviteCodeScreen> createState() => _InviteCodeScreenState();
}

class _InviteCodeScreenState extends State<InviteCodeScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _submitCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() => _loading = true);
    try {
      // Server validates the code and sets our team_id (see join_team in
      // backend/supabase/migrations). Returns null for an unknown code.
      final result = await supabase.rpc('join_team', params: {'p_code': code});

      if (result == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid invite code. Check with your coach.')),
          );
        }
        return;
      }

      // AuthGate will notice the new session; simply unwind the stack.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Something went wrong: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
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
              Icon(Icons.key_outlined, size: 48, color: C.accent),
              const SizedBox(height: 20),
              Text(
                'Enter invite code',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: C.text1(dark),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Ask your coach for your team\'s invite code.',
                style: TextStyle(fontSize: 15, color: C.text3(dark)),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              _InputField(
                controller: _codeCtrl,
                hint: 'Invite code',
                icon: Icons.tag,
                dark: dark,
              ),
              const SizedBox(height: 20),
              PressScale(
                onTap: _loading ? () {} : _submitCode,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [C.accent, C.accentAlt],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x4DB80C09),
                        blurRadius: 20,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Join Team',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
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

/// Decorated input used on auth and invite screens for a consistent look.
class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool dark;
  final bool obscure;
  final TextInputType? keyboardType;

  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.dark,
    this.obscure = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: C.surface(dark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.border(dark)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(icon, size: 18, color: C.text3(dark)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              style: TextStyle(fontSize: 15, color: C.text1(dark)),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: C.text3(dark), fontSize: 15),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

/// Floating nav bar that mimics an iOS-style bottom navigation.
class _FloatingNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool dark;

  const _FloatingNav({
    required this.currentIndex,
    required this.onTap,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _NavItem(
            icon: Icons.leaderboard_outlined,
            activeIcon: Icons.leaderboard,
            label: 'Leaderboard',
            active: currentIndex == 0,
            onTap: () => onTap(0),
            dark: dark,
          ),
          _NavItem(
            icon: Icons.person_outline,
            activeIcon: Icons.person,
            label: 'Profile',
            active: currentIndex == 1,
            onTap: () => onTap(1),
            dark: dark,
          ),
          _NavItem(
            icon: Icons.fitness_center_outlined,
            activeIcon: Icons.fitness_center,
            label: 'Maxes',
            active: currentIndex == 2,
            onTap: () => onTap(2),
            dark: dark,
          ),
          _NavItem(
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings,
            label: 'Settings',
            active: currentIndex == 3,
            onTap: () => onTap(3),
            dark: dark,
          ),
        ],
      ),
    );
  }
}

/// Icon + label button that updates the current tab when tapped.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool dark;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: kSpring,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active ? C.accentSoft(dark) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: active ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 250),
                curve: kSpring,
                child: Icon(
                  active ? activeIcon : icon,
                  size: 22,
                  color: active ? C.accent : C.text3(dark),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight:
                      active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? C.accent : C.text3(dark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
