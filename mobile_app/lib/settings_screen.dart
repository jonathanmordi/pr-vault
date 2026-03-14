import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          _sectionLabel('Account', isDark),
          _tile(
            icon: Icons.email_outlined,
            title: user?.email ?? 'Not signed in',
            subtitle: 'Email address',
            isDark: isDark,
          ),
          _divider(isDark),
          _tile(
            icon: Icons.logout,
            title: 'Sign Out',
            isDark: isDark,
            isDestructive: true,
            onTap: () => supabase.auth.signOut(),
          ),
          const SizedBox(height: 24),
          _sectionLabel('App', isDark),
          _tile(
            icon: Icons.info_outline,
            title: 'Version',
            subtitle: '1.0.0',
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF888888),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _divider(bool isDark) {
    return Divider(
      height: 1,
      indent: 52,
      color: isDark ? const Color(0x0FFFFFFF) : const Color(0xFFEEECEA),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool isDark,
    bool isDestructive = false,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        size: 20,
        color: isDestructive
            ? const Color(0xFFB80C09)
            : const Color(0xFF888888),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          color: isDestructive
              ? const Color(0xFFB80C09)
              : isDark
                  ? const Color(0xFFE5E7E6)
                  : const Color(0xFF141301),
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF888888)),
            )
          : null,
      onTap: onTap,
    );
  }
}