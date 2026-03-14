import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final profile = await supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();

    final prs = await supabase
        .from('track_prs')
        .select()
        .eq('athlete_id', userId)
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
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFB80C09)))
          : _profile == null
              ? const Center(child: Text('Profile not found'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Athlete card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF141301)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? const Color(0x18FFFFFF)
                                : const Color(0xFFE0DEDB),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFB80C09),
                              ),
                              child: Center(
                                child: Text(
                                  _initials(
                                      _profile!['full_name'] ?? 'Unknown'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _profile!['full_name'] ?? 'Unknown',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? const Color(0xFFE5E7E6)
                                        : const Color(0xFF141301),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _profile!['role'] == 'coach'
                                      ? 'Coach'
                                      : 'Athlete',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF888888),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // PR section
                      Text(
                        'Personal Records',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFF888888)
                              : const Color(0xFF888888),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _prs.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF141301)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0x18FFFFFF)
                                      : const Color(0xFFE0DEDB),
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'No PRs yet',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF888888)),
                                ),
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF141301)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0x18FFFFFF)
                                      : const Color(0xFFE0DEDB),
                                ),
                              ),
                              child: Column(
                                children: _prs
                                    .asMap()
                                    .entries
                                    .map((entry) {
                                  final i = entry.key;
                                  final pr = entry.value;
                                  final isLast = i == _prs.length - 1;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      border: isLast
                                          ? null
                                          : Border(
                                              bottom: BorderSide(
                                                color: isDark
                                                    ? const Color(0x0FFFFFFF)
                                                    : const Color(0xFFEEECEA),
                                              ),
                                            ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          pr['event'] ?? '',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: isDark
                                                ? const Color(0xFFE5E7E6)
                                                : const Color(0xFF141301),
                                          ),
                                        ),
                                        Text(
                                          pr['best_display'] ?? '—',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFB80C09),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                    ],
                  ),
                ),
    );
  }
}