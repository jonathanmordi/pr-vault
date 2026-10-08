import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'design_system.dart';
import 'prefs.dart';
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
  // Every lift for the team, so switching lifts is instant.
  List<Map<String, dynamic>> _allMaxes = [];
  bool _loading = true;
  bool _animateRows = true;
  String? _myId;
  String? _myTeamId;
  int? _deletingIndex;

  List<Map<String, dynamic>> get _leaderboard =>
      _allMaxes.where((m) => m['lift_type'] == _selectedLift).toList();

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
    try {
      var query = _supabase
          .from('lifting_maxes')
          .select('weight_lbs, lift_type, athlete_id, profiles!inner(full_name, gender)');
      if (_myTeamId != null) query = query.eq('team_id', _myTeamId!);
      final data = await query.order('weight_lbs', ascending: false);
      if (!mounted) return;
      setState(() {
        _allMaxes = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
    // Only the first screenful of the first load gets the entrance stagger.
    WidgetsBinding.instance.addPostFrameCallback((_) => _animateRows = false);
  }

  void _selectLift(String lift) {
    if (lift == _selectedLift) return;
    setState(() => _selectedLift = lift);
  }

  void _showEntrySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MaxEntrySheet(
        teamId: _myTeamId ?? '',
        athleteId: _myId ?? '',
        initialLift: _selectedLift,
        onSaved: () {
          _loadMaxes();
        },
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> entry, int index) async {
    final liftType = _selectedLift; // capture before async
    HapticFeedback.mediumImpact();
    final sure = await confirmAction(
      context,
      title: 'Delete $liftType max?',
      message: '${Prefs.of(context).weight(entry['weight_lbs'] as num)} will be removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!sure || !mounted) return;

    HapticFeedback.heavyImpact();
    setState(() => _deletingIndex = index);
    await Future.delayed(const Duration(milliseconds: 300));
    try {
      await _supabase.from('lifting_maxes').delete().eq('athlete_id', _myId!).eq('lift_type', liftType);
    } catch (e) {
      debugPrint('Delete error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't delete that max. Try again.")),
        );
      }
    }
    if (!mounted) return;
    setState(() => _deletingIndex = null);
    await _loadMaxes();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: C.bg(dark),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            WashHeader(
              dark: dark,
              padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Maxes',
                      style: pageTitleStyle(dark),
                    ),
                  ),
                  PressScale(
                    onTap: _showEntrySheet,
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.only(left: 12, right: 16),
                      decoration: BoxDecoration(
                        color: C.accentOf(dark),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: 18, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Log Max',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
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
            ChipRow(
              height: 44,
              chips: [
                for (final lift in _liftTypes)
                  AppChip(
                    label: lift,
                    selected: lift == _selectedLift,
                    dark: dark,
                    onTap: () => _selectLift(lift),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // ── Leaderboard ──
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(color: C.accentOf(dark)))
                  : RefreshIndicator(
                      color: C.accentOf(dark),
                      onRefresh: () {
                        HapticFeedback.lightImpact();
                        return _loadMaxes();
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.topCenter,
                          children: [...previous, ?current],
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(_selectedLift),
                          child: _buildList(dark),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(bool dark) {
    const physics =
        AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics());
    final leaderboard = _leaderboard;

    if (leaderboard.isEmpty) {
      // Scrollable so pull-to-refresh still works with nothing logged.
      return ListView(
        physics: physics,
        children: [
          const SizedBox(height: 110),
          EmptyState(
            icon: Icons.fitness_center_rounded,
            title: 'No $_selectedLift maxes yet',
            message: 'Log yours to start the board.',
            actionLabel: 'Log Max',
            onAction: _showEntrySheet,
            dark: dark,
          ),
        ],
      );
    }

    return ListView.builder(
      physics: physics,
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: leaderboard.length,
      itemBuilder: (context, i) {
        final entry = leaderboard[i];
        final name = formatName(
            entry['profiles']?['full_name'] ?? '—');
        final weight = entry['weight_lbs'] as int;
        final isMe = entry['athlete_id'] == _myId;
        final rank = i + 1;

        final isDeleting = _deletingIndex == i;
        return FadeSlideIn(
          animate: _animateRows && i < 12,
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
                  rawName: entry['profiles']?['full_name'] ?? '',
                  gender: entry['profiles']?['gender'] ?? 'M',
                  weight: weight,
                  isMe: isMe,
                  dark: dark,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Leaderboard row ──────────────────────────────────────────────────────────

class _MaxRow extends StatelessWidget {
  final int rank;
  final String name;
  final String rawName;
  final String gender;
  final int weight;
  final bool isMe;
  final bool dark;

  const _MaxRow({
    required this.rank,
    required this.name,
    required this.rawName,
    required this.gender,
    required this.weight,
    required this.isMe,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isMe ? C.accentSoft(dark) : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: rank <= 3 ? C.accentOf(dark) : C.text3(dark),
              ),
            ),
          ),
          const SizedBox(width: 12),
          InitialsAvatar(name: rawName, gender: gender, dark: dark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.15, color: C.text1(dark)),
                ),
                if (isMe)
                  Text('You · hold to delete', style: TextStyle(fontSize: 12, color: C.text3(dark))),
              ],
            ),
          ),
          Text(
            Prefs.of(context).weight(weight),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: rank <= 3 ? C.accentOf(dark) : C.text1(dark),
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
  final String initialLift;
  final VoidCallback onSaved;

  const _MaxEntrySheet({
    required this.teamId,
    required this.athleteId,
    required this.initialLift,
    required this.onSaved,
  });

  @override
  State<_MaxEntrySheet> createState() => _MaxEntrySheetState();
}

class _MaxEntrySheetState extends State<_MaxEntrySheet> {
  late String _lift = widget.initialLift;
  final _weightCtrl = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    final entered = num.tryParse(_weightCtrl.text.trim());
    final weight = entered == null ? null : Prefs.instance.toLbs(entered);
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
    final prefs = Prefs.of(context);

    // A floating card above the keyboard, like the other sheets.
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, MediaQuery.of(context).viewInsets.bottom + 10),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
          decoration: cardDecoration(dark, radius: 32, color: C.sheet(dark)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Log a Max',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: C.text1(dark)),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final lift in _liftTypes)
                    AppChip(
                      label: lift,
                      selected: lift == _lift,
                      dark: dark,
                      small: true,
                      onTap: () => setState(() => _lift = lift),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                height: 72,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(color: C.field(dark), borderRadius: BorderRadius.circular(18)),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        autofocus: true,
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: C.text1(dark)),
                        decoration: InputDecoration(
                          hintText: prefs.liftUnits == LiftUnits.kg ? '140' : '315',
                          hintStyle: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: C.text3(dark).withValues(alpha: 0.5)),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    Text(
                      prefs.weightUnit,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: C.text3(dark)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              PrimaryButton(label: 'Save', loading: _saving, onTap: _save, dark: dark),
            ],
          ),
        ),
      ),
    );
  }
}