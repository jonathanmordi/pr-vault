import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'design_system.dart';

final supabase = Supabase.instance.client;

// ─── Event categories with subcategories ─────────────────────────────────────

const _eventGroups = <String, List<String>?>{
  'All': null,
  'Sprints': ['55 Meters', '60 Meters', '100 Meters', '200 Meters', '300 Meters', '400 Meters'],
  'Mid': ['500 Meters', '600 Meters', '800 Meters', '1000 Meters', '1500 Meters', 'Mile', '3000 Meters', '5000 Meters', '10,000 Meters', '3000 Steeplechase'],
  'Hurdles': ['55 Hurdles', '60 Hurdles', '110 Hurdles', '100 Hurdles', '400 Hurdles'],
  'Jumps': ['High Jump', 'Long Jump', 'Triple Jump', 'Pole Vault'],
  'Throws': ['Shot Put', 'Discus', 'Hammer', 'Javelin', 'Weight Throw'],
};

const _fieldEvents = ['High Jump', 'Long Jump', 'Triple Jump', 'Pole Vault', 'Shot Put', 'Discus', 'Hammer', 'Javelin', 'Weight Throw'];

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _grouped = [];
  Map<String, List<double>> _sparklines = {};
  bool _loading = true;
  bool _initialLoad = true;

  String _group = 'All';
  String? _subEvent; // specific event within a group
  String _tab = 'heat';
  String _search = '';
  String _gender = 'All';
  final _searchCtrl = TextEditingController();

  late final AnimationController _heatBarCtrl;
  late final Animation<double> _heatBarAnim;

  @override
  void initState() {
    super.initState();
    _heatBarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _heatBarAnim = CurvedAnimation(parent: _heatBarCtrl, curve: kSpring);
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text));
    _load();
  }

  @override
  void dispose() {
    _heatBarCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final raw = await supabase
        .from('track_prs')
        .select(
            'event, best_display, best_mark_meters, best_time_seconds, improvement_delta_pct, athlete_id, profiles(full_name, gender)')
        .order('improvement_delta_pct', ascending: false);

    final data = List<Map<String, dynamic>>.from(raw);

    // Build sparklines from meet_appearances
    final appearances = await supabase
        .from('meet_appearances')
        .select('athlete_id, event, time_seconds, mark_meters, meet_date');

    final Map<String, List<double>> sparklines = {};
    for (final a in List<Map<String, dynamic>>.from(appearances)) {
      final id = a['athlete_id'] as String;
      final event = a['event'] as String? ?? '';
      final val = (a['time_seconds'] as num?)?.toDouble() ??
          (a['mark_meters'] as num?)?.toDouble();
      if (val != null && val > 0) {
        // Key by athlete_id + event so sparklines are per-event
        final key = '${id}_$event';
        sparklines.putIfAbsent(key, () => []).add(val);
      }
    }

    final Map<String, Map<String, dynamic>> best = {};
    for (final e in data) {
      final id = e['athlete_id'] as String;
      final d = (e['improvement_delta_pct'] ?? 0.0) as num;
      if (!best.containsKey(id) ||
          d > (best[id]!['improvement_delta_pct'] as num)) {
        best[id] = e;
      }
    }
    final grouped = best.values.toList()
  ..sort((a, b) => (b['improvement_delta_pct'] as num? ?? 0)
      .compareTo(a['improvement_delta_pct'] as num? ?? 0));

    setState(() {
      _entries = data;
      _grouped = grouped;
      _sparklines = sparklines;
      _loading = false;
    });

    _heatBarCtrl.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) setState(() => _initialLoad = false);
  }

  List<Map<String, dynamic>> get _filtered {
    List<Map<String, dynamic>> list;

    if (_subEvent != null) {
      list = _entries.where((e) => e['event'] == _subEvent).toList();
    } else if (_group == 'All') {
      list = List.from(_grouped);
    } else {
      list = _entries
          .where((e) => (_eventGroups[_group] ?? []).contains(e['event']))
          .toList();
    }

    if (_gender != 'All') {
      list = list.where((e) {
        final g = e['profiles']?['gender'] ?? 'M';
        return g == _gender;
      }).toList();
    }

    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((e) {
        final name =
            (e['profiles']?['full_name'] ?? '').toString().toLowerCase();
        final ev = (e['event'] ?? '').toString().toLowerCase();
        return name.contains(q) || ev.contains(q);
      }).toList();
    }

    if (_tab == 'heat') {
      list.sort((a, b) => (b['improvement_delta_pct'] as num? ?? 0)
          .compareTo(a['improvement_delta_pct'] as num? ?? 0));
    } else {
      list.sort((a, b) {
        final af = _fieldEvents.contains(a['event']);
        final bf = _fieldEvents.contains(b['event']);
        if (af && bf) {
          return (b['best_mark_meters'] as num? ?? 0)
              .compareTo(a['best_mark_meters'] as num? ?? 0);
        } else if (!af && !bf) {
          return (a['best_time_seconds'] as num? ?? 9999)
              .compareTo(b['best_time_seconds'] as num? ?? 9999);
        }
        return 0;
      });
    }
    return list;
  }

  double get _maxDelta => _entries.fold(0.0, (m, e) {
        final d = (e['improvement_delta_pct'] as num? ?? 0).toDouble();
        return d > m ? d : m;
      });

  void _openDetail(Map<String, dynamic> entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _AthleteDetailSheet(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final list = _filtered;

    return Scaffold(
      backgroundColor: C.bg(dark),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(dark),
            _buildChips(dark),
            if (_group != 'All' && _eventGroups[_group] != null)
              _buildSubChips(dark),
            Container(height: 0.5, color: C.border(dark)),
            Expanded(child: _buildList(dark, list)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeSlideIn(
            delay: const Duration(milliseconds: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PR Vault',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.96,
                    color: C.text1(dark),
                  ),
                ),
                Row(
                  children: [
                    PressScale(
                      onTap: _load,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.refresh,
                            size: 20, color: C.text2(dark)),
                      ),
                    ), 
                    const SizedBox(width: 4),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [C.accent, C.accentAlt],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x4DE8372D),
                            blurRadius: 16,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'V',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFEEECE9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: Icon(Icons.search,
                        size: 16, color: C.text3(dark)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: TextStyle(
                          fontSize: 15, color: C.text1(dark)),
                      decoration: InputDecoration(
                        hintText: 'Search athletes or events…',
                        hintStyle: TextStyle(
                            color: C.text3(dark), fontSize: 15),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: _searchCtrl.clear,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.close,
                            size: 16, color: C.text3(dark)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Tabs + gender
          FadeSlideIn(
            delay: const Duration(milliseconds: 120),
            child: Row(
              children: [
                _TabBtn(
                  label: 'Heat Map',
                  active: _tab == 'heat',
                  onTap: () {
                    setState(() => _tab = 'heat');
                    _heatBarCtrl.forward(from: 0);
                  },
                ),
                const SizedBox(width: 28),
                _TabBtn(
                  label: 'PR Rankings',
                  active: _tab == 'rankings',
                  onTap: () => setState(() => _tab = 'rankings'),
                ),
                const Spacer(),
                _GenderToggle(
                  gender: _gender,
                  dark: dark,
                  onChanged: (g) => setState(() => _gender = g),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildChips(bool dark) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: _eventGroups.keys.map((g) {
          final sel = g == _group;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PressScale(
              pressedScale: 0.96,
              onTap: () {
                setState(() {
                  _group = g;
                  _subEvent = null;
                });
                if (_tab == 'heat') _heatBarCtrl.forward(from: 0);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: kSpring,
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? C.accent : C.surface2(dark),
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: sel
                      ? const [
                          BoxShadow(
                            color: Color(0x4DE8372D),
                            blurRadius: 12,
                            offset: Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  g,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        sel ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: -0.1,
                    color: sel ? Colors.white : C.text2(dark),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSubChips(bool dark) {
    final events = _eventGroups[_group] ?? [];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _subEvent = null),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: _subEvent == null
                      ? C.text2(dark)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                      color: _subEvent == null
                          ? Colors.transparent
                          : C.border(dark)),
                ),
                child: Text(
                  'All ${_group}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _subEvent == null
                        ? (dark ? C.bg(dark) : Colors.white)
                        : C.text3(dark),
                  ),
                ),
              ),
            ),
          ),
          ...events.map((ev) {
            final sel = _subEvent == ev;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _subEvent = ev),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: sel ? C.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                        color: sel ? C.accent : C.border(dark)),
                  ),
                  child: Text(
                    ev.replaceAll(' Meters', '').replaceAll(' Hurdles', 'H'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : C.text2(dark),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildList(bool dark, List<Map<String, dynamic>> list) {
    if (_loading) {
      return const Center(
          child:
              CircularProgressIndicator(color: C.accent, strokeWidth: 2));
    }
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 40, color: C.text3(dark)),
            const SizedBox(height: 12),
            Text('No results found',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: C.text3(dark))),
          ],
        ),
      );
    }

    final maxDelta = _maxDelta;
    final showPodium = _tab == 'heat' &&
      _group == 'All' &&
      _subEvent == null &&
      list.length >= 3;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: list.length + (list.length >= 3 ? 1 : 0),
      itemBuilder: (_, i) {
        // Insert podium at top
        if (showPodium && i == 0) {
          return _PodiumCard(
            entries: list
            .where((e) => (e['improvement_delta_pct'] as num? ?? 0) > 0.01)
            .take(3)
            .toList(),
            dark: dark,
            onTap: _openDetail,
          );
        }
        final actualIndex = showPodium ? i - 1 : i;
        if(actualIndex < 0 || actualIndex >= list.length){
          return const SizedBox.shrink();
        }
        final entry = list[actualIndex];
        final id = entry['athlete_id'] as String? ?? actualIndex.toString();
        final delay = _initialLoad
            ? Duration(milliseconds: 200 + actualIndex * 40)
            : Duration.zero;
        final event = entry['event'] ?? '';
        final sparkData = _sparklines['${id}_$event'] ?? [];

        return FadeSlideIn(
          key: ValueKey('lb-$id-${entry['event']}'),
          delay: delay,
          child: _LeaderboardRow(
            entry: entry,
            index: actualIndex,
            tab: _tab,
            maxDelta: maxDelta,
            heatAnim: _heatBarAnim,
            dark: dark,
            sparkData: sparkData,
            onTap: () => _openDetail(entry),
          ),
        );
      },
    );
  }
}

// ─── Podium card ──────────────────────────────────────────────────────────────

class _PodiumCard extends StatelessWidget {
  final List<Map<String, dynamic>> entries;
  final bool dark;
  final Function(Map<String, dynamic>) onTap;

  const _PodiumCard({
    required this.entries,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: GlassCard(
        forceDark: dark,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_fire_department,
                      size: 14, color: C.accent),
                  const SizedBox(width: 6),
                  Text(
                    'TOP IMPROVERS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: C.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: entries.asMap().entries.map((e) {
                  final idx = e.key;
                  final entry = e.value;
                  final name =
                      formatName(entry['profiles']?['full_name'] ?? 'Unknown');
                  final delta =
                      (entry['improvement_delta_pct'] ?? 0.0) as num;
                  final event = entry['event'] ?? '';
                  final gender =
                      entry['profiles']?['gender'] ?? 'M';

                  final parts = name.toString().split(' ');
                  final initials = parts.length >= 2
                      ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
                      : name.toString().isNotEmpty
                          ? name.toString()[0].toUpperCase()
                          : '?';

                  final medals = ['🥇', '🥈', '🥉'];
                  final sizes = [52.0, 44.0, 44.0];

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onTap(entry),
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: sizes[idx],
                                height: sizes[idx],
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: gender == 'F'
                                        ? const [
                                            Color(0xFFD4537E),
                                            Color(0xFFED93B1)
                                          ]
                                        : idx == 0
                                            ? const [
                                                C.accent,
                                                C.accentAlt
                                              ]
                                            : [
                                                C.surface2(dark),
                                                C.surface3(dark)
                                              ],
                                  ),
                                  boxShadow: idx == 0
                                      ? const [
                                          BoxShadow(
                                            color: Color(0x4DE8372D),
                                            blurRadius: 16,
                                            offset: Offset(0, 4),
                                          )
                                        ]
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  initials,
                                  style: TextStyle(
                                    fontSize: idx == 0 ? 18 : 14,
                                    fontWeight: FontWeight.w800,
                                    color: idx == 0 || gender == 'F'
                                        ? Colors.white
                                        : C.text2(dark),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: -6,
                                right: -6,
                                child: Text(medals[idx],
                                    style:
                                        const TextStyle(fontSize: 16)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            parts.isNotEmpty ? parts[0] : name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: C.text1(dark),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            event,
                            style: TextStyle(
                                fontSize: 10, color: C.text3(dark)),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: C.accentSoft(dark),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              '+${delta.toStringAsFixed(2)}%',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: C.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sparkline painter ────────────────────────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final bool isField;
  final Color color;

  const _SparklinePainter({
    required this.data,
    required this.isField,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final recent = data.length > 8 ? data.sublist(data.length - 8) : data;
    final minV = recent.reduce((a, b) => a < b ? a : b);
    final maxV = recent.reduce((a, b) => a > b ? a : b);
    if (maxV == minV) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (var i = 0; i < recent.length; i++) {
      final x = (i / (recent.length - 1)) * size.width;
      // For track: lower is better (invert). For field: higher is better.
      final norm = isField
          ? (recent[i] - minV) / (maxV - minV)
          : 1 - (recent[i] - minV) / (maxV - minV);
      final y = size.height - norm * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.data != data || old.color != color;
}

// ─── Gender toggle ────────────────────────────────────────────────────────────

class _GenderToggle extends StatelessWidget {
  final String gender;
  final bool dark;
  final ValueChanged<String> onChanged;

  const _GenderToggle({
    required this.gender,
    required this.dark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: C.surface2(dark),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['All', 'M', 'F'].map((v) {
          final active = gender == v;
          return GestureDetector(
            onTap: () => onChanged(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? C.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                v,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : C.text3(dark),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Tab button ───────────────────────────────────────────────────────────────

class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabBtn(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: active ? C.text1(dark) : C.text2(dark),
            ),
            child: Text(label),
          ),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: kSpring,
            height: 2,
            width: active ? 44.0 : 0.0,
            decoration: BoxDecoration(
              color: C.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Leaderboard row ──────────────────────────────────────────────────────────

class _LeaderboardRow extends StatefulWidget {
  final Map<String, dynamic> entry;
  final int index;
  final String tab;
  final double maxDelta;
  final Animation<double> heatAnim;
  final bool dark;
  final List<double> sparkData;
  final VoidCallback onTap;

  const _LeaderboardRow({
    required this.entry,
    required this.index,
    required this.tab,
    required this.maxDelta,
    required this.heatAnim,
    required this.dark,
    required this.sparkData,
    required this.onTap,
  });

  @override
  State<_LeaderboardRow> createState() => _LeaderboardRowState();
}

class _LeaderboardRowState extends State<_LeaderboardRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final dark = widget.dark;
    final name = formatName(e['profiles']?['full_name'] ?? 'Unknown');
    final event = e['event'] ?? '';
    final delta = (e['improvement_delta_pct'] ?? 0.0) as num;
    final gender = e['profiles']?['gender'] ?? 'M';
    final isField = _fieldEvents.contains(event);

    final parts = name.toString().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : name.toString().isNotEmpty
            ? name.toString()[0].toUpperCase()
            : '?';

    final isFirst = widget.index == 0;
    final isTop3 = widget.index < 3;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _pressed ? C.accentSoft(dark) : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            // Rank
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isFirst
                    ? C.accent
                    : isTop3
                        ? C.accentSoft(dark)
                        : C.surface2(dark),
                boxShadow: isFirst
                    ? const [
                        BoxShadow(
                          color: Color(0x4DE8372D),
                          blurRadius: 12,
                          offset: Offset(0, 2),
                        )
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                '${widget.index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isFirst
                      ? Colors.white
                      : isTop3
                          ? C.accent
                          : C.text2(dark),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: gender == 'F'
                    ? const Color(0xFFFDE8F0)
                    : C.surface2(dark),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: gender == 'F'
                      ? const Color(0xFFD4537E)
                      : C.text2(dark),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15,
                      color: C.text1(dark),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: C.text3(dark),
                    ),
                  ),
                  if (widget.tab == 'heat' &&
                      widget.maxDelta > 0 &&
                      delta > 0) ...[
                    const SizedBox(height: 6),
                    AnimatedBuilder(
                      animation: widget.heatAnim,
                      builder: (_, child) => ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          height: 4,
                          color: C.surface3(dark),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor:
                                (delta.toDouble() / widget.maxDelta)
                                        .clamp(0.0, 1.0) *
                                    widget.heatAnim.value,
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [C.accent, C.accentAlt],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Sparkline
            if (widget.sparkData.length >= 2)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 40,
                  height: 24,
                  child: CustomPaint(
                    painter: _SparklinePainter(
                      data: widget.sparkData,
                      isField: isField,
                      color: delta > 0
                          ? C.accent.withValues(alpha: 0.7)
                          : C.text3(dark),
                    ),
                  ),
                ),
              ),

            // Trailing value
            if (widget.tab == 'heat')
              delta > 0
                  ? _DeltaBadge(delta: delta, dark: dark)
                  : Text('—',
                      style: TextStyle(color: C.text3(dark)))
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    e['best_display'] ?? '—',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: C.accent,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (delta > 0)
                    Text(
                      '+${delta.toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontSize: 10, color: C.text3(dark)),
                    ),
                ],
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 14, color: C.text3(dark)),
          ],
        ),
      ),
    );
  }
}

// ─── Delta badge ──────────────────────────────────────────────────────────────

class _DeltaBadge extends StatelessWidget {
  final num delta;
  final bool dark;

  const _DeltaBadge({required this.delta, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: C.accentSoft(dark),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_upward, size: 9, color: C.accent),
          const SizedBox(width: 2),
          Text(
            '${delta.toStringAsFixed(2)}%',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: C.accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Athlete detail bottom sheet ──────────────────────────────────────────────

class _AthleteDetailSheet extends StatefulWidget {
  final Map<String, dynamic> entry;

  const _AthleteDetailSheet({required this.entry});

  @override
  State<_AthleteDetailSheet> createState() => _AthleteDetailSheetState();
}

class _AthleteDetailSheetState extends State<_AthleteDetailSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slideAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..forward();
    _slideAnim = CurvedAnimation(parent: _ctrl, curve: kSpring);
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: kSpring));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final e = widget.entry;
    final name = formatName(e['profiles']?['full_name'] ?? 'Unknown');
    final event = e['event'] ?? '';
    final bestDisplay = e['best_display'] ?? '—';
    final delta = (e['improvement_delta_pct'] ?? 0.0) as num;
    final gender = e['profiles']?['gender'] ?? 'M';

    final parts = name.toString().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : name.toString().isNotEmpty
            ? name.toString()[0].toUpperCase()
            : '?';

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Transform.scale(
        scale: _scaleAnim.value,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(_slideAnim),
          child: child,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: C.surface(dark),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 40,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: C.text3(dark),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: gender == 'F'
                                  ? const [
                                      Color(0xFFD4537E),
                                      Color(0xFFED93B1)
                                    ]
                                  : const [C.accent, C.accentAlt],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: gender == 'F'
                                    ? const Color(0x59D4537E)
                                    : const Color(0x59E8372D),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                  color: C.text1(dark),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                children: [
                                  _Badge(event, dark),
                                  _Badge(
                                      gender == 'F' ? 'Women' : 'Men',
                                      dark),
                                ],
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: C.surface2(dark),
                            ),
                            child: Icon(Icons.close,
                                size: 14, color: C.text2(dark)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Personal Best',
                            value: bestDisplay,
                            accent: true,
                            dark: dark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            label: 'Event',
                            value: event,
                            dark: dark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            label: 'Improvement',
                            value: delta > 0
                                ? '+${delta.toStringAsFixed(2)}%'
                                : '—',
                            accent: delta > 0,
                            dark: dark,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String text;
  final bool dark;

  const _Badge(this.text, this.dark);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: C.surface2(dark),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: C.text2(dark),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;
  final bool dark;

  const _StatCard({
    required this.label,
    required this.value,
    this.accent = false,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      forceDark: dark,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
                color: C.text3(dark),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: accent ? C.accent : C.text1(dark),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}