import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'athlete_profile_screen.dart';
import 'design_system.dart';
import 'pr_stats.dart';
import 'prefs.dart';
import 'team_data.dart';

/// Tracks which PR alerts the user has already seen so the bell can show an
/// unread count. Seen keys are stored per user in SharedPreferences.
class ActivityFeed {
  ActivityFeed._() {
    // Notification settings change what's in the feed, so recount.
    Prefs.instance.addListener(() {
      final snap = TeamData.instance.cached;
      if (snap != null) refresh(snap);
    });
  }
  static final instance = ActivityFeed._();

  static const feedSize = 100;

  final unread = ValueNotifier<int>(0);

  static List<PrEvent> _recent(TeamSnapshot snap) =>
      snap.prEvents.take(feedSize).toList();

  /// The recent PRs the user's notification settings let through.
  static List<PrEvent> itemsOf(TeamSnapshot snap) {
    final p = Prefs.instance;
    final me = snap.userId;
    final rivals = me == null ? const <String, Rival>{} : snap.rivalsOf(me);
    return _recent(snap).where((e) {
      if (p.alertRecords && e.schoolRecord) return true;
      if (e.athleteId == me) return p.alertMine;
      if (rivals[eventKey(e.event, e.season)]?.athleteId == e.athleteId) {
        return p.alertRivals;
      }
      return p.alertTeam;
    }).toList();
  }

  String _prefsKey(TeamSnapshot snap) => 'activity_seen_v1:${snap.userId}';

  Future<Set<String>?> _loadSeen(TeamSnapshot snap) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_prefsKey(snap))?.toSet();
    } catch (_) {
      return null;
    }
  }

  /// Recounts unread alerts. On first run everything already in the feed
  /// counts as seen, so nobody opens the app to a badge of 100.
  Future<void> refresh(TeamSnapshot snap) async {
    final seen = await _loadSeen(snap);
    if (seen == null) {
      await markAllSeen(snap);
      return;
    }
    unread.value = itemsOf(snap).where((e) => !seen.contains(e.key)).length;
  }

  /// Marks the whole feed as read and returns the keys that were unread.
  Future<Set<String>> markAllSeen(TeamSnapshot snap) async {
    // Hidden alerts count as seen too, so turning a filter back on doesn't
    // bring back old PRs as unread.
    final keys = _recent(snap).map((e) => e.key).toList();
    final seen = await _loadSeen(snap) ?? keys.toSet();
    final fresh = keys.where((k) => !seen.contains(k)).toSet();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey(snap), keys);
    } catch (_) {}
    unread.value = 0;
    return fresh;
  }
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  TeamSnapshot? _snap;
  Map<String, Rival> _myRivals = {};
  Set<String> _fresh = {};
  String _filter = 'All';
  bool _loading = true;
  String? _error;

  String? get _myId => TeamData.instance.currentUserId();

  @override
  void initState() {
    super.initState();
    final cached = TeamData.instance.cached;
    if (cached != null) _apply(cached, const {});
    _load();
  }

  void _apply(TeamSnapshot snap, Set<String> fresh) {
    _snap = snap;
    _myRivals = _myId == null ? {} : snap.rivalsOf(_myId!);
    _fresh = {..._fresh, ...fresh};
    _loading = false;
    _error = null;
  }

  Future<void> _load({bool force = false}) async {
    try {
      final snap = await TeamData.instance.load(force: force);
      final fresh = await ActivityFeed.instance.markAllSeen(snap);
      if (!mounted) return;
      setState(() => _apply(snap, fresh));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load activity. Pull down to try again.";
      });
    }
  }

  bool _isRival(PrEvent p) =>
      _myRivals[eventKey(p.event, p.season)]?.athleteId == p.athleteId;

  List<PrEvent> get _items {
    final all = ActivityFeed.itemsOf(_snap!);
    switch (_filter) {
      case 'Rivals':
        return all.where(_isRival).toList();
      case 'You':
        return all.where((p) => p.athleteId == _myId).toList();
      default:
        return all;
    }
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

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return SheetBackdrop(
      child: Scaffold(
        backgroundColor: C.bg(dark),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WashHeader(
                dark: dark,
                padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 12, 20, 0),
                child: Row(
                  children: [
                    PressScale(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: C.surface2(dark),
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          size: 16,
                          color: C.text2(dark),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Activity',
                      style: pageTitleStyle(dark),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ChipRow(
                height: 40,
                chips: [
                  for (final f in const ['All', 'Rivals', 'You'])
                    AppChip(
                      label: f,
                      selected: f == _filter,
                      dark: dark,
                      onTap: () => setState(() => _filter = f),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 0.5, color: C.border(dark)),
              Expanded(child: _buildBody(dark)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool dark) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: C.accentOf(dark),
          strokeWidth: 2,
        ),
      );
    }
    return RefreshIndicator(
      color: C.accentOf(dark),
      onRefresh: () {
        HapticFeedback.lightImpact();
        return _load(force: true);
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: KeyedSubtree(key: ValueKey(_filter), child: _buildList(dark)),
      ),
    );
  }

  Widget _buildList(bool dark) {
    const physics = AlwaysScrollableScrollPhysics(
      parent: BouncingScrollPhysics(),
    );

    if (_snap == null || _error != null) {
      return _message(
        dark,
        physics,
        Icons.cloud_off_outlined,
        _error ?? "Couldn't load activity.",
      );
    }

    final items = _items;
    if (items.isEmpty) {
      final linked =
          _myId != null && _snap!.prs.any((p) => p['athlete_id'] == _myId);
      final text = switch (_filter) {
        'Rivals' when !linked => 'Link your TFRRS profile to get rivals.',
        'Rivals' => 'No PRs from your rivals yet.',
        'You' when !linked => 'Link your TFRRS profile to see your PRs.',
        'You' => "You haven't set a PR yet. Soon.",
        _ => 'No PRs yet.',
      };
      return _message(dark, physics, Icons.notifications_none, text);
    }

    // Interleave month headers with the items.
    final rows = <Object>[];
    String? month;
    for (final p in items) {
      final m = _monthLabel(p.date);
      if (m != month) {
        rows.add(m);
        month = m;
      }
      rows.add(p);
    }

    return ListView.builder(
      physics: physics,
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final row = rows[i];
        if (row is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
            child: Text(row, style: SectionTitle.style(dark).copyWith(fontSize: 17)),
          );
        }
        final p = row as PrEvent;
        return _ActivityRow(
          pr: p,
          name: _snap!.nameOf(p.athleteId),
          gender: _snap!.genderOf(p.athleteId),
          isMine: p.athleteId == _myId,
          isRival: _isRival(p),
          isNew: _fresh.contains(p.key),
          dark: dark,
          onTap: () => _openAthlete(p.athleteId),
        );
      },
    );
  }

  Widget _message(
    bool dark,
    ScrollPhysics physics,
    IconData icon,
    String text,
  ) {
    return ListView(
      physics: physics,
      children: [
        const SizedBox(height: 110),
        EmptyState(icon: icon, title: text, dark: dark),
      ],
    );
  }

  String _monthLabel(DateTime d) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }
}

class _ActivityRow extends StatelessWidget {
  final PrEvent pr;
  final String name;
  final String gender;
  final bool isMine;
  final bool isRival;
  final bool isNew;
  final bool dark;
  final VoidCallback onTap;

  const _ActivityRow({
    required this.pr,
    required this.name,
    required this.gender,
    required this.isMine,
    required this.isRival,
    required this.isNew,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final prefs = Prefs.of(context);
    final sign = isFieldEvent(pr.event) ? '+' : '−';
    final detail = [
      seasonLabel(pr.season),
      prefs.mark(pr.event, pr.display, pr.value),
      '$sign${prefs.gap(pr.event, pr.gap)} (${pr.improvementPct.toStringAsFixed(1)}%)',
      if (pr.meetName.isNotEmpty) pr.meetName,
    ].join(' · ');

    return PressScale(
      pressedScale: 0.98,
      onTap: onTap,
      child: Container(
        color: isNew ? C.accentSoft(dark) : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InitialsAvatar(name: name, gender: gender, dark: dark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: isMine ? 'You' : formatName(name),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: " PR'd in ${pr.event}"),
                      ],
                    ),
                    style: TextStyle(fontSize: 14, color: C.text1(dark)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: C.text3(dark)),
                  ),
                  if (isRival || pr.schoolRecord) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (isRival) _tag('RIVAL', filled: true),
                        if (pr.schoolRecord) _tag('🏆 SCHOOL RECORD'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatShortMeetDate(pr.date),
                  style: TextStyle(fontSize: 11, color: C.text3(dark)),
                ),
                const SizedBox(height: 4),
                Text(
                  '+${pr.points} pts',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: C.accentOf(dark),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String text, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? C.accentOf(dark) : C.accentSoft(dark),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: filled ? Colors.white : C.accentOf(dark),
        ),
      ),
    );
  }
}
