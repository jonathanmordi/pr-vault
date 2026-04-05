import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'design_system.dart';
import 'package:flutter/services.dart';

final _supabase = Supabase.instance.client;

const _liftTypes = ['Squat', 'Bench Press', 'Power Clean', 'Deadlift'];

class MaxesScreen extends StatefulWidget {
  const MaxesScreen({super.key});

  @override
  State<MaxesScreen> createState() => _MaxesScreenState();
}

class _MaxesScreenState extends State<MaxesScreen> {
  String _selectedLift = 'Squat';
  List<Map<String, dynamic>> _leaderboard = [];
  bool _loading = true;
  String? _myId;
  String? _myTeamId;
  int? _deletingIndex;

  @override
  void initState() {
    super.initState();
    _myId = _supabase.auth.currentUser?.id;
    _loadTeamAndMaxes();
  }

  Future<void> _loadTeamAndMaxes() async {
    try {
      final profile = await _supabase
          .from('profiles')
          .select('team_id')
          .eq('id', _myId!)
          .single();
      _myTeamId = profile['team_id'] as String?;
    } catch (_) {}
    await _loadMaxes();
  }

  Future<void> _loadMaxes() async {
    setState(() => _loading = true);
    try {
      final data = await _supabase
          .from('lifting_maxes')
          .select('weight_lbs, athlete_id, profiles!inner(full_name)')
          .eq('lift_type', _selectedLift)
          .eq('team_id', _myTeamId ?? '')
          .order('weight_lbs', ascending: false);

      setState(() {
        _leaderboard = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _showEntrySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MaxEntrySheet(
        teamId: _myTeamId ?? '',
        athleteId: _myId ?? '',
        onSaved: () {
          _loadMaxes();
        },
      ),
    );
  }

void _confirmDelete(Map<String, dynamic> entry, int index) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final liftType = _selectedLift; // capture before async
    
    HapticFeedback.mediumImpact();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: C.surface(dark),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: C.border(dark), width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: C.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline, color: C.accent, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              'Delete $liftType max?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: C.text1(dark)),
            ),
            const SizedBox(height: 6),
            Text(
              '${entry['weight_lbs']} lbs will be removed',
              style: TextStyle(fontSize: 14, color: C.text3(dark)),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: C.surface2(dark),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text('Cancel', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.text2(dark))),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(context);
                      HapticFeedback.heavyImpact();
                      
                      setState(() => _deletingIndex = index);
                      await Future.delayed(const Duration(milliseconds: 300));
                      
                      try {
                        await _supabase
                            .from('lifting_maxes')
                            .delete()
                            .eq('athlete_id', _myId!)
                            .eq('lift_type', liftType);
                      } catch (e) {
                        print('Delete error: $e');
                      }
                      
                      setState(() => _deletingIndex = null);
                      await _loadMaxes();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: C.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text('Delete', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: C.bg(dark),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Maxes',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: C.text1(dark),
                      ),
                    ),
                  ),
                  PressScale(
                    onTap: _showEntrySheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [C.accent, C.accentAlt],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 16, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Log Max',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Lift type chips ──
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical : 3),
                itemCount: _liftTypes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final lift = _liftTypes[i];
                  final selected = lift == _selectedLift;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedLift = lift);
                      _loadMaxes();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? C.accent : C.surface2(dark),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        lift,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : C.text2(dark),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // ── Leaderboard ──
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: C.accent))
                  : _leaderboard.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fitness_center,
                                  size: 48, color: C.text3(dark)),
                              const SizedBox(height: 12),
                              Text(
                                'No $_selectedLift maxes yet',
                                style: TextStyle(
                                    fontSize: 15, color: C.text3(dark)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap "Log Max" to be the first',
                                style: TextStyle(
                                    fontSize: 13, color: C.text3(dark)),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          color: C.accent,
                          onRefresh: _loadMaxes,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                                20, 0, 20, 120),
                            itemCount: _leaderboard.length,
                            itemBuilder: (context, i) {
                              final entry = _leaderboard[i];
                              final name = formatName(
                                  entry['profiles']?['full_name'] ?? '—');
                              final weight = entry['weight_lbs'] as int;
                              final isMe = entry['athlete_id'] == _myId;
                              final rank = i + 1;

                              final isDeleting = _deletingIndex == i;
                              return FadeSlideIn(
                                delay: Duration(milliseconds: i * 40),
                                child: AnimatedSlide(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInBack,
                                  offset: isDeleting ? const Offset(1.0, 0) : Offset.zero,
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 250),
                                    opacity: isDeleting ? 0.0 : 1.0,
                                    child: GestureDetector(
                                      onLongPress: isMe ? () {
                                        _confirmDelete(entry, i);
                                      } : null,
                                      child: _MaxRow(
                                        rank: rank,
                                        name: name,
                                        weight: weight,
                                        isMe: isMe,
                                        dark: dark,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Leaderboard row ──────────────────────────────────────────────────────────

class _MaxRow extends StatelessWidget {
  final int rank;
  final String name;
  final int weight;
  final bool isMe;
  final bool dark;

  const _MaxRow({
    required this.rank,
    required this.name,
    required this.weight,
    required this.isMe,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isMe ? C.accentSoft(dark) : C.surface(dark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe ? C.accent.withValues(alpha: 0.3) : C.border(dark),
          width: isMe ? 1 : 0.5,
        ),
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 32,
            child: Text(
              rank <= 3
                  ? ['🥇', '🥈', '🥉'][rank - 1]
                  : '#$rank',
              style: TextStyle(
                fontSize: rank <= 3 ? 18 : 14,
                fontWeight: FontWeight.w700,
                color: rank <= 3 ? null : C.text3(dark),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                color: isMe ? C.accent : C.text1(dark),
              ),
            ),
          ),

          // Weight
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: rank <= 3
                  ? C.accent.withValues(alpha: 0.1)
                  : C.surface2(dark),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$weight lbs',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: rank <= 3 ? C.accent : C.text1(dark),
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Entry bottom sheet ───────────────────────────────────────────────────────

class _MaxEntrySheet extends StatefulWidget {
  final String teamId;
  final String athleteId;
  final VoidCallback onSaved;

  const _MaxEntrySheet({
    required this.teamId,
    required this.athleteId,
    required this.onSaved,
  });

  @override
  State<_MaxEntrySheet> createState() => _MaxEntrySheetState();
}

class _MaxEntrySheetState extends State<_MaxEntrySheet> {
  String _lift = 'Squat';
  final _weightCtrl = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    final weight = int.tryParse(_weightCtrl.text.trim());
    if (weight == null || weight <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid weight')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _supabase.from('lifting_maxes').upsert(
        {
          'athlete_id': widget.athleteId,
          'team_id': widget.teamId,
          'lift_type': _lift,
          'weight_lbs': weight,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'athlete_id,lift_type',
      );

      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      decoration: BoxDecoration(
        color: C.surface(dark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: C.text3(dark),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'Log a Max',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: C.text1(dark),
            ),
          ),
          const SizedBox(height: 20),

          // Lift type selector
          Text(
            'Lift',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: C.text2(dark),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _liftTypes.map((lift) {
              final selected = lift == _lift;
              return GestureDetector(
                onTap: () => setState(() => _lift = lift),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? C.accent : C.surface2(dark),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    lift,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : C.text2(dark),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Weight input
          Text(
            'Weight (lbs)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: C.text2(dark),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: C.surface2(dark),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.border(dark)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(Icons.fitness_center, size: 18, color: C.text3(dark)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _weightCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: C.text1(dark),
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g. 315',
                      hintStyle:
                          TextStyle(color: C.text3(dark), fontSize: 15),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                Text(
                  'lbs',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: C.text3(dark),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Save button
          PressScale(
            onTap: _saving ? () {} : _save,
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
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Save',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}