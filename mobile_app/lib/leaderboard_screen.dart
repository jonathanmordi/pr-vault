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

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  TeamSnapshot? _snap;
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _grouped = [];
  Map<String, List<double>> _sparklines = {};
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

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (_search != _searchCtrl.text) {
        setState(() => _search = _searchCtrl.text);
      }
    });
    final cached = TeamData.instance.cached;
    if (cached != null) _apply(cached);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    try {
      final snap = await TeamData.instance.load(force: force);
      if (!mounted) return;
      setState(() => _apply(snap));
      ActivityFeed.instance.refresh(snap);
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

  static const _tabLabels = {
    'heat': 'Heat Map',
    'rankings': 'PR Rankings',
    'trending': 'Trending',
  };

  void _setTab(String tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
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
        top: false,
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
    return WashHeader(
      dark: dark,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeSlideIn(
            delay: const Duration(milliseconds: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('PR Vault', style: pageTitleStyle(dark)),
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
                DropToggle(
                  key: const ValueKey('gender'),
                  options: const ['All', 'M', 'F'],
                  value: _gender,
                  dark: dark,
                  onChanged: (g) => setState(() => _gender = g),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Main tabs: the same sliding pill as the other switches.
          FadeSlideIn(
            delay: const Duration(milliseconds: 120),
            child: SizedBox(
              width: double.infinity,
              child: SegmentToggle(
                options: _tabLabels.values.toList(),
                value: _tabLabels[_tab]!,
                dark: dark,
                height: 40,
                fontSize: 14,
                onChanged: (label) => _setTab(
                    _tabLabels.entries.firstWhere((e) => e.value == label).key),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildChips(bool dark) {
    return ChipRow(
      chips: [
        for (final g in _eventGroups.keys)
          AppChip(
            label: g,
            selected: g == _group,
            dark: dark,
            onTap: () => setState(() {
              _group = g;
              _subEvent = null;
            }),
          ),
      ],
    );
  }

  Widget _buildSubChips(bool dark) {
    final events = _eventGroups[_group] ?? [];
    return ChipRow(
      height: 44,
      chips: [
        AppChip(
          label: 'All $_group',
          selected: _subEvent == null,
          dark: dark,
          small: true,
          onTap: () => setState(() => _subEvent = null),
        ),
        for (final ev in events)
          AppChip(
            label: ev.replaceAll(' Meters', '').replaceAll(' Hurdles', 'H'),
            selected: _subEvent == ev,
            dark: dark,
            small: true,
            onTap: () => setState(() => _subEvent = ev),
          ),
      ],
    );
  }

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
                    child: Center(
                      child: AppChip(
                        label: w.label,
                        selected: w == current,
                        dark: dark,
                        small: true,
                        onTap: () => setState(() => _window = w),
                      ),
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
    // A list so pull-to-refresh still works on an empty or failed page.
    return ListView(
      physics: _listPhysics,
      children: [
        const SizedBox(height: 90),
        EmptyState(icon: icon, title: text, dark: dark),
      ],
    );
  }

  Widget _buildList(bool dark, List<Map<String, dynamic>> list) {
    if (list.isEmpty) return _message(dark, Icons.search, 'No results found');

    final podium = _tab == 'heat' && _group == 'All' && _subEvent == null && _search.isEmpty
        ? list
            .where((e) => (e['improvement_delta_pct'] as num? ?? 0) > 0.01)
            .take(5)
            .toList()
        : const <Map<String, dynamic>>[];
    final showPodium = podium.isNotEmpty;

    // The featured cards are the top of the ranking, so the list carries on
    // from there instead of repeating them.
    final skip = showPodium ? podium.length : 0;
    final showRestTitle = showPodium && list.length > skip;
    final header = (showPodium ? 1 : 0) + (showRestTitle ? 1 : 0);
    return ListView.builder(
      physics: _listPhysics,
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: list.length - skip + header,
      itemBuilder: (_, i) {
        if (showPodium && i == 0) {
          return _PodiumCard(
            entries: podium,
            dark: dark,
            onTap: _openDetail,
          );
        }
        if (showRestTitle && i == 1) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: SectionTitle('Everyone else', dark: dark),
          );
        }
        final actualIndex = i - header + skip;
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
                      fontSize: 15.5,
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
                      fontSize: 12.5,
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: C.accentOf(dark),
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  byPoints ? prs : '${trend.points} pts',
                  style: TextStyle(fontSize: 11.5, color: C.text3(dark)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Rank badge ───────────────────────────────────────────────────────────────

/// The row's place as a bold number; the top three in the team color.
class _RankBadge extends StatelessWidget {
  final int index;
  final bool dark;

  const _RankBadge({required this.index, required this.dark});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      child: Text(
        '${index + 1}',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: index < 3 ? C.accentOf(dark) : C.text3(dark),
        ),
      ),
    );
  }
}

// ─── Podium card ──────────────────────────────────────────────────────────────

/// Top improvers as a row of featured cards, edge to edge. #1 gets the team
/// color.
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
    final textGrowth = (MediaQuery.textScalerOf(context).scale(14) / 14 - 1).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SectionTitle('Top Improvers', dark: dark),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 190 + textGrowth * 60,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _ImproverCard(
                entry: entries[i],
                rank: i + 1,
                dark: dark,
                onTap: () => onTap(entries[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImproverCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final int rank;
  final bool dark;
  final VoidCallback onTap;

  const _ImproverCard({required this.entry, required this.rank, required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final lead = rank == 1;
    final name = formatName(entry['profiles']?['full_name'] ?? 'Unknown');
    final event = entry['event'] as String? ?? '';
    final delta = (entry['improvement_delta_pct'] ?? 0.0) as num;
    final gender = entry['profiles']?['gender'] as String? ?? 'M';
    final ink = lead ? Colors.white : C.text1(dark);
    final soft = lead ? Colors.white.withValues(alpha: 0.75) : C.text3(dark);

    return PressScale(
      onTap: onTap,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(14),
        decoration: lead
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [C.accentOf(dark), C.accentAlt],
                ),
                boxShadow: [BoxShadow(color: C.accentOf(dark).withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))],
              )
            : cardDecoration(dark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$rank',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -1, height: 1, color: lead ? Colors.white : C.accentOf(dark)),
                ),
                const Spacer(),
                InitialsAvatar(name: entry['profiles']?['full_name'] ?? '', gender: gender, dark: dark),
              ],
            ),
            const Spacer(),
            Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.2, color: ink)),
            const SizedBox(height: 2),
            Text(event, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: soft)),
            const SizedBox(height: 10),
            Text(
              '+${delta.toStringAsFixed(2)}%',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: lead ? Colors.white : C.accentOf(dark)),
            ),
          ],
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

// ─── Leaderboard row ──────────────────────────────────────────────────────────

class _LeaderboardRow extends StatefulWidget {
  final Map<String, dynamic> entry;
  final int index;
  final String tab;
  final bool dark;
  final List<double> sparkData;
  final VoidCallback onTap;

  const _LeaderboardRow({
    required this.entry,
    required this.index,
    required this.tab,
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
                            fontSize: 15.5,
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
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: C.text3(dark),
                    ),
                  ),
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
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: C.accentOf(dark),
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (delta > 0)
                    Text(
                      '+${delta.toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontSize: 11.5, color: C.text3(dark)),
                    ),
                ],
              ),
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
