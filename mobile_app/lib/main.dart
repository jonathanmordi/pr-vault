import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'leaderboard_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  runApp(const PRVaultApp());
}

final supabase = Supabase.instance.client;

class PRVaultApp extends StatelessWidget {
  const PRVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PR Vault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8F7F4),
        colorScheme: ColorScheme.light(
          primary: const Color(0xFFB80C09),
          secondary: const Color(0xFFB80C09),
          surface: const Color(0xFFFFFFFF),
          onPrimary: Colors.white,
          onSurface: const Color(0xFF141301),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFFFF),
          foregroundColor: Color(0xFF141301),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: Color(0xFF141301),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Color(0xFFB80C09),
          unselectedLabelColor: Color(0xFF888888),
          indicatorColor: Color(0xFFB80C09),
          indicatorSize: TabBarIndicatorSize.label,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFF0EDEA),
          selectedColor: const Color(0xFFB80C09),
          labelStyle: const TextStyle(fontSize: 12),
          secondaryLabelStyle: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFFFFFFFF),
          selectedItemColor: Color(0xFFB80C09),
          unselectedItemColor: Color(0xFF888888),
          elevation: 0,
          type: BottomNavigationBarType.fixed,
        ),
        dividerColor: const Color(0xFFEEECEA),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1C1B08),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFB80C09),
          secondary: const Color(0xFFB80C09),
          surface: const Color(0xFF141301),
          onPrimary: Colors.white,
          onSurface: const Color(0xFFE5E7E6),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF141301),
          foregroundColor: Color(0xFFE5E7E6),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: Color(0xFFE5E7E6),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Color(0xFFB80C09),
          unselectedLabelColor: Color(0xFF555555),
          indicatorColor: Color(0xFFB80C09),
          indicatorSize: TabBarIndicatorSize.label,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0x14FFFFFF),
          selectedColor: const Color(0xFFB80C09),
          labelStyle: const TextStyle(
            color: Color(0xFF888888),
            fontSize: 12,
          ),
          secondaryLabelStyle: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF141301),
          selectedItemColor: Color(0xFFB80C09),
          unselectedItemColor: Color(0xFF555555),
          elevation: 0,
          type: BottomNavigationBarType.fixed,
        ),
        dividerColor: const Color(0x0FFFFFFF),
      ),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final session = snapshot.data!.session;
          if (session != null) {
            return const MainShell();
          }
        }
        return const LoginScreen();
      },
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    LeaderboardScreen(),
    ProfileScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark
                  ? const Color(0x18FFFFFF)
                  : const Color(0xFFE0DEDB),
              width: 0.5,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.leaderboard_outlined),
              activeIcon: Icon(Icons.leaderboard),
              label: 'Leaderboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo placeholder
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB80C09),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text(
                      'V',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'PR Vault',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'Track. Lift. Compete.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF888888),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email_outlined, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark
                          ? const Color(0x18FFFFFF)
                          : const Color(0xFFE0DEDB),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark
                          ? const Color(0x18FFFFFF)
                          : const Color(0xFFE0DEDB),
                    ),
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark
                          ? const Color(0x18FFFFFF)
                          : const Color(0xFFE0DEDB),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark
                          ? const Color(0x18FFFFFF)
                          : const Color(0xFFE0DEDB),
                    ),
                  ),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _signIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB80C09),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
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
                          'Sign In',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Don't have an invite? Contact your coach.",
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF888888),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}