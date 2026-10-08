import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'activity_screen.dart';
import 'design_system.dart';
import 'athlete_profile_screen.dart';
import 'pr_stats.dart';
import 'prefs.dart';
import 'team_data.dart';

// ─── Event categories with subcategories ─────────────────────────────────────

const _eventGroups = <String, List<String>?>{
  'All': null,
  'Sprints': ['55 Meters', '60 Meters', '100 Meters', '200 Meters', '300 Meters', '400 Meters'],
  'Mid': ['500 Meters', '600 Meters', '800 Meters', '1000 Meters', '1500 Meters', 'Mile', '3000 Meters', '5000 Meters', '10,000 Meters', '3000 Steeplechase'],
  'Hurdles': ['55 Hurdles', '60 Hurdles', '110 Hurdles', '100 Hurdles', '400 Hurdles'],
  'Jumps': ['High Jump', 'Long Jump', 'Triple Jump', 'Pole Vault'],
  'Throws': ['Shot Put', 'Discus', 'Hammer', 'Javelin', 'Weight Throw'],
};

// Always scrollable so pull-to-refresh works on short lists too.
const _listPhysics =
    AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics());

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with TickerProviderStateMixin {
  TeamSnapshot? _snap;
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _grouped = [];
  Map<String, List<double>> _sparklines = {};
  double _maxDelta = 0;
  bool _loading = true;
  bool _initialLoad = true;
  String? _error;

  String _group = 'All';
  String? _subEvent; // specific event within a group
  String _tab = 'heat';
  String _search = '';
  String _gender = 'All';
  TrendWindow? _window; // null = the snapshot's current season
  bool _trendByPoints = false;
  /// PR Rankings: include alumni (everyone who's competed for the team).
  bool _allTime = false;
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
    _searchCtrl.addListener(() {
      if (_search != _searchCtrl.text) {
        setState(() => _search = _searchCtrl.text);
      }
    });
    final cached = TeamData.instance.cached;
    if (cached != null) {
      _apply(cached);
      _heatBarCtrl.forward();
    }
    _load();
  }

  @override
  void dispose() {
    _heatBarCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    final hadData = _snap != null;
    try {
      final snap = await TeamData.instance.load(force: force);
      if (!mounted) return;
      setState(() => _apply(snap));
      ActivityFeed.instance.refresh(snap);
      if (!hadData || force) _heatBarCtrl.forward(from: 0);
      if (_initialLoad) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) setState(() => _initialLoad = false);
      }
    } catch (_) {
      if (!mounted) return;
      if (_snap != null) {
        // Keep showing what we have; just say the refresh failed.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't refresh. Check your connection.")),
        );
      } else {
        setState(() {
          _loading = false;
          _error = "Couldn't load the leaderboard. Pull down to try again.";
        });
      }
    }
  }

  Future<void> _refresh() {
    HapticFeedback.lightImpact();
    return _load(force: true);
  }

  void _apply(TeamSnapshot snap) {
    final data = List<Map<String, dynamic>>.from(snap.prs)
      ..sort((a, b) => (b['improvement_delta_pct'] as num? ?? 0)
          .compareTo(a['improvement_delta_pct'] as num? ?? 0));

    // Sparklines per athlete + event. Appearances arrive oldest first.
    final Map<String, List<double>> sparklines = {};
    for (final a in snap.appearances) {
      final val = (a['time_seconds'] as num?)?.toDouble() ??
          (a['mark_meters'] as num?)?.toDouble();
      if (val != null && val > 0) {
        final key = '${a['athlete_id']}_${a['event'] ?? ''}';
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

    _snap = snap;
    _entries = data;
    _grouped = grouped;
    _sparklines = sparklines;
    _maxDelta = data.fold(0.0, (m, e) {
      final d = (e['improvement_delta_pct'] as num? ?? 0).toDouble();
      return d > m ? d : m;
    });
    _loading = false;
    _error = null;
    if (_window != null && !snap.windows.contains(_window)) _window = null;
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

    // Alumni only show on PR Rankings' all-time view; Heat Map is about now.
    final snap = _snap;
    if (snap != null && !(_tab == 'rankings' && _allTime)) {
      list = list.where((e) => snap.isCurrent(e['athlete_id'] as String)).toList();
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
        final af = isFieldEvent(a['event'] ?? '');
        final bf = isFieldEvent(b['event'] ?? '');
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

  void _openDetail(Map<String, dynamic> entry) {
    final event = entry['event'] as String? ?? '';
    showAthleteSheet(
      context,
      athleteId: entry['athlete_id'] ?? '',
      athleteName: entry['profiles']?['full_name'] ?? 'Unknown',
      gender: entry['profiles']?['gender'] ?? 'M',
      focus: ProfileFocus(
        event: event,
        display: entry['best_display'],
        meters: entry['best_mark_meters'],
        improvementPct:
            (entry['improvement_delta_pct'] as num? ?? 0).toDouble(),
      ),
    );
  }

  void _openAthlete(String athleteId) {
    final snap = _snap!;
    showAthleteSheet(
      context,
      athleteId: athleteId,
      athleteName: snap.nameOf(athleteId),
      gender: snap.genderOf(athleteId),
    );
  }

  void _openActivity() {
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ActivityScreen()),
    );
  }

  void _setTab(String tab) {
    if (tab == _tab) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = tab);
    if (tab == 'heat') _heatBarCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final showSubChips = _group != 'All' && _eventGroups[_group] != null;
    final showTrendControls = _tab == 'trending' && _snap != null;
    final showRosterControls = _tab == 'rankings' && (_snap?.hasAlumni ?? false);

    return Scaffold(
      backgroundColor: C.bg(dark),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(dark),
            _buildChips(dark),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: kSpring,
              alignment: Alignment.topCenter,
              child: showSubChips
                  ? _buildSubChips(dark)
                  : const SizedBox(width: double.infinity),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: kSpring,
              alignment: Alignment.topCenter,
              child: showTrendControls
                  ? _buildTrendControls(dark)
                  : const SizedBox(width: double.infinity),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: kSpring,
              alignment: Alignment.topCenter,
              child: showRosterControls
                  ? _buildRosterControls(dark)
                  : const SizedBox(width: double.infinity),
            ),
            Container(height: 0.5, color: C.border(dark)),
            Expanded(child: _buildBody(dark)),
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
                    _BellButton(dark: dark, onTap: _openActivity),
                    const SizedBox(width: 4),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [C.accentOf(dark), C.accentAlt],
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

          // Search + gender
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: C.field(dark),
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
                            textInputAction: TextInputAction.search,
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
                const SizedBox(width: 8),
                SegmentToggle(
                  options: const ['All', 'M', 'F'],
                  value: _gender,
                  dark: dark,
                  onChanged: (g) => setState(() => _gender = g),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tabs (shrink rather than overflow at large text sizes)
          FadeSlideIn(
            delay: const Duration(milliseconds: 120),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  _TabBtn(
                    label: 'Heat Map',
                    active: _tab == 'heat',
                    onTap: () => _setTab('heat'),
                  ),
                  const SizedBox(width: 24),
                  _TabBtn(
                    label: 'PR Rankings',
                    active: _tab == 'rankings',
                    onTap: () => _setTab('rankings'),
                  ),
                  const SizedBox(width: 24),
                  _TabBtn(
                    label: 'Trending',
                    active: _tab == 'trending',
                    onTap: () => _setTab('trending'),
                  ),
                ],
              ),
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
                if (sel) return;
                HapticFeedback.selectionClick();
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
                  color: sel ? C.accentOf(dark) : C.surface2(dark),
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
              onTap: () {
                if (_subEvent == null) return;
                HapticFeedback.selectionClick();
                setState(() => _subEvent = null);
              },
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
                  'All $_group',
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
              child: _OutlineChip(
                label: ev.replaceAll(' Meters', '').replaceAll(' Hurdles', 'H'),
                selected: sel,
                dark: dark,
                onTap: () => setState(() => _subEvent = ev),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Current roster vs. all-time (with alumni), on PR Rankings.
  Widget _buildRosterControls(bool dark) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(
                _allTime ? 'Everyone who has competed for the team' : 'Current roster',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: C.text3(dark)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: SegmentToggle(
              options: const ['Current', 'All-time'],
              value: _allTime ? 'All-time' : 'Current',
              dark: dark,
              onChanged: (v) => setState(() => _allTime = v == 'All-time'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendControls(bool dark) {
    final snap = _snap!;
    final current = _window ?? snap.currentSeason;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            // Fade the chips out before the toggle instead of cutting them.
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.85, 1],
              ).createShader(rect),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 6, 24, 6),
                children: snap.windows.map((w) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _OutlineChip(
                      label: w.label,
                      selected: w == current,
                      dark: dark,
                      onTap: () => setState(() => _window = w),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: SegmentToggle(
              options: const ['PRs', 'Points'],
              value: _trendByPoints ? 'Points' : 'PRs',
              dark: dark,
              onChanged: (v) => setState(() => _trendByPoints = v == 'Points'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool dark) {
    if (_loading) return const _SkeletonRows();

    final Widget content;
    if (_snap == null) {
      content = _message(dark, Icons.cloud_off_outlined,
          _error ?? "Couldn't load the leaderboard.");
    } else if (_tab == 'trending') {
      content = _buildTrending(dark);
    } else {
      content = _buildList(dark, _filtered);
    }

    return RefreshIndicator(
      color: C.accentOf(dark),
      onRefresh: _refresh,
      // Cross-fade when the filters change instead of snapping.
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: KeyedSubtree(
          key: ValueKey(
              '$_tab|$_group|$_subEvent|$_gender|${_window?.id}|$_trendByPoints|$_allTime'),
          child: content,
        ),
      ),
    );
  }

  Widget _message(bool dark, IconData icon, String text) {
    return ListView(
      physics: _listPhysics,
      children: [
        const SizedBox(height: 100),
        Icon(icon, size: 40, color: C.text3(dark)),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: C.text3(dark)),
          ),
        ),
      ],
    );
  }

  Widget _buildList(bool dark, List<Map<String, dynamic>> list) {
    if (list.isEmpty) return _message(dark, Icons.search, 'No results found');

    final podium = _tab == 'heat' && _group == 'All' && _subEvent == null
        ? list
            .where((e) => (e['improvement_delta_pct'] as num? ?? 0) > 0.01)
            .take(3)
            .toList()
        : const <Map<String, dynamic>>[];
    final showPodium = podium.isNotEmpty;

    return ListView.builder(
      physics: _listPhysics,
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: list.length + (showPodium ? 1 : 0),
      itemBuilder: (_, i) {
        // Insert podium at top
        if (showPodium && i == 0) {
          return _PodiumCard(
            entries: podium,
            dark: dark,
            onTap: _openDetail,
          );
        }
        final actualIndex = showPodium ? i - 1 : i;
        final entry = list[actualIndex];
        final id = entry['athlete_id'] as String? ?? actualIndex.toString();
        final event = entry['event'] ?? '';
        final sparkData = _sparklines['${id}_$event'] ?? [];

        return FadeSlideIn(
          key: ValueKey('lb-$id-$event'),
          // Stagger only the first screenful of the first load.
          animate: _initialLoad && actualIndex < 12,
          delay: Duration(milliseconds: 200 + actualIndex * 40),
          child: _LeaderboardRow(
            entry: entry,
            index: actualIndex,
            tab: _tab,
            maxDelta: _maxDelta,
            heatAnim: _heatBarAnim,
            dark: dark,
            sparkData: sparkData,
            onTap: () => _openDetail(entry),
          ),
        );
      },
    );
  }

  Widget _buildTrending(bool dark) {
    final snap = _snap!;
    final window = _window ?? snap.currentSeason;
    final events =
        _subEvent != null ? {_subEvent!} : _eventGroups[_group]?.toSet();
    final q = _search.toLowerCase();

    final prs = snap.prEvents.where((p) {
      if (!window.contains(p.date)) return false;
      if (events != null && !events.contains(p.event)) return false;
      if (_gender != 'All' && snap.genderOf(p.athleteId) != _gender) {
        return false;
      }
      if (q.isNotEmpty &&
          !snap.nameOf(p.athleteId).toLowerCase().contains(q) &&
          !p.event.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    });
    final rows = trendingAthletes(prs, byPoints: _trendByPoints);

    if (rows.isEmpty) {
      final when = window == TrendWindow.allTime
          ? ''
          : window.isSeason
              ? ' in the ${window.label} season'
              : ' in the last 30 days';
      return _message(
          dark, Icons.local_fire_department_outlined, 'No PRs$when yet.');
    }

    return ListView.builder(
      physics: _listPhysics,
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final row = rows[i];
        return _TrendingRow(
          key: ValueKey('tr-${row.athleteId}'),
          trend: row,
          index: i,
          name: snap.nameOf(row.athleteId),
          gender: snap.genderOf(row.athleteId),
          byPoints: _trendByPoints,
          dark: dark,
          onTap: () => _openAthlete(row.athleteId),
        );
      },
    );
  }
}

// ─── Bell with unread badge ───────────────────────────────────────────────────

class _BellButton extends StatelessWidget {
  final bool dark;
  final VoidCallback onTap;

  const _BellButton({required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final showBadge = Prefs.of(context).showBadge;
    return PressScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: ValueListenableBuilder<int>(
          valueListenable: ActivityFeed.instance.unread,
          builder: (_, count, _) {
            final unread = showBadge ? count : 0;
            return Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                unread > 0
                    ? Icons.notifications
                    : Icons.notifications_none,
                size: 22,
                color: C.text2(dark),
              ),
              Positioned(
                top: -4,
                right: -6,
                child: AnimatedScale(
                  scale: unread > 0 ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  child: Container(
                    height: 17,
                    constraints: const BoxConstraints(minWidth: 17),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: C.accentOf(dark),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: C.bg(dark), width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
          },
        ),
      ),
    );
  }
}

// ─── Loading skeleton ─────────────────────────────────────────────────────────

class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows();

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8),
        itemCount: 8,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              const SkeletonBox(width: 30, height: 30, radius: 15),
              const SizedBox(width: 12),
              const SkeletonBox(width: 40, height: 40, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 110.0 + (i % 3) * 30, height: 12),
                    const SizedBox(height: 6),
                    const SkeletonBox(width: 70, height: 10),
                  ],
                ),
              ),
              const SkeletonBox(width: 56, height: 22, radius: 11),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Trending row ─────────────────────────────────────────────────────────────

class _TrendingRow extends StatelessWidget {
  final AthleteTrend trend;
  final int index;
  final String name;
  final String gender;
  final bool byPoints;
  final bool dark;
  final VoidCallback onTap;

  const _TrendingRow({
    super.key,
    required this.trend,
    required this.index,
    required this.name,
    required this.gender,
    required this.byPoints,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final events = trend.events;
    final eventText = events.length <= 2
        ? events.join(', ')
        : '${events.take(2).join(', ')} +${events.length - 2}';
    final prs = '${trend.prCount} PR${trend.prCount == 1 ? '' : 's'}';

    return PressScale(
      pressedScale: 0.98,
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            _RankBadge(index: index, dark: dark),
            const SizedBox(width: 12),
            InitialsAvatar(name: name, gender: gender, dark: dark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatName(name),
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
                    '$eventText · last ${formatShortMeetDate(trend.lastPr)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: C.text3(dark),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  byPoints ? '${trend.points} pts' : prs,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: C.accentOf(dark),
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  byPoints ? prs : '${trend.points} pts',
                  style: TextStyle(fontSize: 10, color: C.text3(dark)),
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

// ─── Rank badge ───────────────────────────────────────────────────────────────

class _RankBadge extends StatelessWidget {
  final int index;
  final bool dark;

  const _RankBadge({required this.index, required this.dark});

  @override
  Widget build(BuildContext context) {
    final isFirst = index == 0;
    final isTop3 = index < 3;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isFirst
            ? C.accentOf(dark)
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
        '${index + 1}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isFirst
              ? Colors.white
              : isTop3
                  ? C.accentOf(dark)
                  : C.text2(dark),
        ),
      ),
    );
  }
}

// ─── Outline chip ─────────────────────────────────────────────────────────────

class _OutlineChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  const _OutlineChip({
    required this.label,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (selected) return;
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? C.accentOf(dark) : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: selected ? C.accentOf(dark) : C.border(dark)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : C.text2(dark),
          ),
        ),
      ),
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
                  Icon(Icons.local_fire_department,
                      size: 14, color: C.accentOf(dark)),
                  const SizedBox(width: 6),
                  Text(
                    'TOP IMPROVERS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: C.accentOf(dark),
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
                                            ? [
                                                C.accentOf(dark),
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
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: C.accentOf(dark),
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
              color: C.accentOf(dark),
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
    final isField = isFieldEvent(event);
    final alum = e['profiles']?['on_roster'] == false;

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
            _RankBadge(index: widget.index, dark: dark),
            const SizedBox(width: 12),
            InitialsAvatar(
              name: e['profiles']?['full_name'] ?? 'Unknown',
              gender: gender,
              dark: dark,
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
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
                      ),
                      if (alum) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: C.surface2(dark),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            'ALUM',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: C.text3(dark),
                            ),
                          ),
                        ),
                      ],
                    ],
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
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [C.accentOf(dark), C.accentAlt],
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
                          ? C.accentOf(dark).withValues(alpha: 0.7)
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
                    Prefs.of(context).mark(event, e['best_display'], e['best_mark_meters']),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: C.accentOf(dark),
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
          Icon(Icons.arrow_upward, size: 9, color: C.accentOf(dark)),
          const SizedBox(width: 2),
          Text(
            '${delta.toStringAsFixed(2)}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: C.accentOf(dark),
            ),
          ),
        ],
      ),
    );
  }
}
