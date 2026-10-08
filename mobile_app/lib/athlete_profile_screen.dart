import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'design_system.dart';
import 'insights.dart';
import 'pr_stats.dart';
import 'prefs.dart';
import 'team_data.dart';

final _supabase = Supabase.instance.client;

/// A leaderboard result to lead the profile sheet with, so the peek has
/// something to show before the profile loads.
class ProfileFocus {
  final String event;
  final String? display;
  final num? meters;
  final double improvementPct;

  const ProfileFocus({
    required this.event,
    this.display,
    this.meters,
    this.improvementPct = 0,
  });
}

/// Connects a profile to the draggable sheet hosting it.
class ProfileSheet {
  final ScrollController scrollController;

  /// 0 at the peek height, 1 at full screen.
  final ValueListenable<double> progress;

  /// Animates the sheet up to full screen.
  final VoidCallback expand;

  const ProfileSheet({
    required this.scrollController,
    required this.progress,
    required this.expand,
  });
}

/// How far a profile sheet has risen over the screen that opened it: 0 at
/// card height (or with no sheet open), 1 fully up. Screens wrapped in
/// [SheetBackdrop] shrink back as it rises.
final sheetDepth = ValueNotifier<double>(0);

/// Recedes [child] behind a rising profile sheet, like iOS card sheets.
class SheetBackdrop extends StatelessWidget {
  final Widget child;

  const SheetBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: ValueListenableBuilder<double>(
        valueListenable: sheetDepth,
        // Repaint boundary so the transform only recomposites the screen.
        child: RepaintBoundary(child: child),
        builder: (context, t, child) => Transform.scale(
          scale: 1 - 0.07 * t,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18 * t),
            clipBehavior: t > 0 ? Clip.antiAlias : Clip.none,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Opens a profile as a floating card at the bottom of the screen. Dragging
/// it up docks it into a full-height card over the receding screen;
/// dragging it down dismisses it.
Future<void> showAthleteSheet(
  BuildContext context, {
  required String athleteId,
  required String athleteName,
  required String gender,
  ProfileFocus? focus,
  String? season,
}) {
  HapticFeedback.selectionClick();
  // Modal sheets don't see the status bar inset, and callers inside a
  // SafeArea have it zeroed out, so read it off the screen itself.
  final view = View.of(context);
  final insets = EdgeInsets.fromViewPadding(
    view.padding,
    view.devicePixelRatio,
  );
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    // A little overshoot so the card pops into place.
    sheetAnimationStyle: AnimationStyle(
      duration: const Duration(milliseconds: 420),
      curve: const Cubic(0.2, 0.9, 0.3, 1.06),
      reverseDuration: const Duration(milliseconds: 260),
    ),
    builder: (_) => _AthleteSheet(
      safeTop: insets.top,
      safeBottom: insets.bottom,
      athleteId: athleteId,
      athleteName: athleteName,
      gender: gender,
      focus: focus,
      season: season,
    ),
  );
}

class _AthleteSheet extends StatefulWidget {
  final double safeTop;
  final double safeBottom;
  final String athleteId;
  final String athleteName;
  final String gender;
  final ProfileFocus? focus;
  final String? season;

  const _AthleteSheet({
    required this.safeTop,
    required this.safeBottom,
    required this.athleteId,
    required this.athleteName,
    required this.gender,
    this.focus,
    this.season,
  });

  @override
  State<_AthleteSheet> createState() => _AthleteSheetState();
}

class _AthleteSheetState extends State<_AthleteSheet> {
  // Card shape at its two resting points.
  static const _cardMargin = 8.0;
  static const _cardRadius = 36.0;
  static const _dockedRadius = 16.0;

  final _controller = DraggableScrollableController();
  final _progress = ValueNotifier<double>(0);
  ValueNotifier<double>? _size;
  Animation<double>? _route;
  double _max = 1;
  bool _wasFull = false;

  @override
  void initState() {
    super.initState();
    _progress.addListener(_syncDepth);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Follow the route's animation too, so the screen behind springs back
    // as the sheet slides away instead of snapping once it's gone.
    final route = ModalRoute.of(context)?.animation;
    if (route != _route) {
      _route?.removeListener(_syncDepth);
      _route = route?..addListener(_syncDepth);
    }
  }

  void _syncDepth() =>
      sheetDepth.value = _progress.value * (_route?.value ?? 1);

  @override
  void dispose() {
    _route?.removeListener(_syncDepth);
    sheetDepth.value = 0;
    _controller.dispose();
    _progress.dispose();
    _size?.dispose();
    super.dispose();
  }

  void _expand() {
    HapticFeedback.selectionClick();
    _controller.animateTo(
      _max,
      duration: const Duration(milliseconds: 420),
      curve: kSpring,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final screenH = MediaQuery.sizeOf(context).height;

    // Docked, the card stops just under the status bar so the receding
    // screen shows above it.
    _max = ((screenH - widget.safeTop - _cardMargin) / screenH).clamp(0.5, 1.0);

    // Tall enough for the header card, the focus row (or stats) and the
    // swipe-up hint, clear of the home indicator; taller with bigger text.
    final textGrowth = (MediaQuery.textScalerOf(context).scale(14) / 14 - 1)
        .clamp(0.0, 1.0);
    final bottomRoom = math.max(16.0, widget.safeBottom - 4);
    final peekPx = 306 + textGrowth * 90 + _cardMargin + bottomRoom;
    final peek = (peekPx / screenH).clamp(0.25, _max - 0.05);
    final size = _size ??= ValueNotifier(peek);

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        size.value = n.extent;
        _progress.value = ((n.extent - peek) / (_max - peek)).clamp(0.0, 1.0);
        final full = n.extent > _max - 0.001;
        if (full && !_wasFull) HapticFeedback.lightImpact();
        _wasFull = full;
        return false;
      },
      child: DraggableScrollableSheet(
        controller: _controller,
        expand: false,
        initialChildSize: peek,
        // Below the card it closes rather than resting smaller.
        minChildSize: 0,
        maxChildSize: _max,
        snap: true,
        snapSizes: [peek],
        snapAnimationDuration: const Duration(milliseconds: 320),
        builder: (context, scrollController) {
          final profile = MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            child: AthleteProfileScreen(
              athleteId: widget.athleteId,
              athleteName: widget.athleteName,
              gender: widget.gender,
              focus: widget.focus,
              season: widget.season,
              sheet: ProfileSheet(
                scrollController: scrollController,
                progress: _progress,
                expand: _expand,
              ),
            ),
          );
          // Floating card at rest; docks edge to edge as it rises. Only the
          // clip changes, so the profile isn't laid out again every frame.
          return ValueListenableBuilder<double>(
            valueListenable: _progress,
            child: profile,
            builder: (context, p, child) {
              final shape = _CardShape(
                margin: _cardMargin * (1 - p),
                topRadius: _cardRadius + (_dockedRadius - _cardRadius) * p,
                bottomRadius: _cardRadius * (1 - p),
              );
              return PhysicalShape(
                clipper: shape,
                clipBehavior: Clip.antiAlias,
                color: C.sheet(dark),
                elevation: 10,
                shadowColor: Colors.black.withValues(alpha: dark ? 0.5 : 0.18),
                child: CustomPaint(
                  foregroundPainter: _CardOutline(shape, C.border(dark)),
                  child: child,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CardShape extends CustomClipper<Path> {
  final double margin;
  final double topRadius;
  final double bottomRadius;

  const _CardShape({
    required this.margin,
    required this.topRadius,
    required this.bottomRadius,
  });

  RRect rrect(Size size) => RRect.fromRectAndCorners(
    Rect.fromLTRB(margin, 0, size.width - margin, size.height - margin),
    topLeft: Radius.circular(topRadius),
    topRight: Radius.circular(topRadius),
    bottomLeft: Radius.circular(bottomRadius),
    bottomRight: Radius.circular(bottomRadius),
  );

  @override
  Path getClip(Size size) => Path()..addRRect(rrect(size));

  @override
  bool shouldReclip(_CardShape old) =>
      old.margin != margin ||
      old.topRadius != topRadius ||
      old.bottomRadius != bottomRadius;
}

/// Hairline around the card so its edge shows against the dimmed screen.
class _CardOutline extends CustomPainter {
  final _CardShape shape;
  final Color color;

  const _CardOutline(this.shape, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      shape.rrect(size).deflate(0.25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_CardOutline old) =>
      old.color != color || old.shape.shouldReclip(shape);
}

class AthleteProfileScreen extends StatefulWidget {
  final String athleteId;
  final String athleteName;
  final String gender;
  final bool showBackButton;

  /// The leaderboard result that was tapped, shown in the sheet's peek.
  final ProfileFocus? focus;

  /// The season to open on, e.g. the leaderboard's. Otherwise the season of
  /// the athlete's latest results.
  final String? season;

  /// Set when shown inside [showAthleteSheet] instead of as a page.
  final ProfileSheet? sheet;

  const AthleteProfileScreen({
    super.key,
    required this.athleteId,
    required this.athleteName,
    required this.gender,
    this.showBackButton = true,
    this.focus,
    this.season,
    this.sheet,
  });

  @override
  State<AthleteProfileScreen> createState() => _AthleteProfileScreenState();
}

class _AthleteProfileScreenState extends State<AthleteProfileScreen> {
  List<Map<String, dynamic>> _prs = [];
  List<Map<String, dynamic>> _appearances = [];
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _maxes = [];
  List<Map<String, dynamic>> _rankRows = [];
  Map<String, List<ListRank>> _ranks = {};
  TeamSnapshot? _team;
  String? _season;
  bool _loading = true;
  String? _error;
  String? _selectedEvent;
  final _pageScroll = ScrollController();

  @override
  void dispose() {
    _pageScroll.dispose();
    super.dispose();
  }

  /// The top bar's color: the wash's top color over the page, fading to the
  /// plain page color as the hero scrolls away, so there's no seam.
  static Color _barColor(bool dark, Color page, double offset) => Color.lerp(
    Color.alphaBlend(
      C.accentOf(dark).withValues(alpha: washAlpha(dark)),
      page,
    ),
    page,
    (offset / 120).clamp(0.0, 1.0),
  )!;

  /// The name in the top bar appears once the hero's name has scrolled away.
  static double _titleOpacity(double offset) =>
      ((offset - 90) / 40).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _team = TeamData.instance.cached;
    _load();
  }

  Future<void> _load() async {
    // Team data (for rivals and points) is usually cached already; it never
    // holds up the rest of the profile.
    TeamData.instance
        .load()
        .then((team) {
          if (mounted) setState(() => _team = team);
        })
        .catchError((_) {});

    // Ranks are optional: before the list_ranks migration is applied this
    // query fails, and the profile should still load. Before the cut columns
    // exist, fall back to ranks without the nationals projection.
    Future<List<Map<String, dynamic>>> ranks(String columns) => _supabase
        .from('list_ranks')
        .select(columns)
        .eq('athlete_id', widget.athleteId);
    const rankColumns =
        'event, scope, label, season, season_year, rank, list_size';
    final ranksFuture = ranks('$rankColumns, mark_display, cut_rank, cut_mark')
        .catchError((_) => ranks(rankColumns))
        .catchError((_) => const <Map<String, dynamic>>[]);

    try {
      // Independent queries, so fetch them in parallel.
      final results = await Future.wait([
        _supabase
            .from('track_prs')
            .select()
            .eq('athlete_id', widget.athleteId)
            .order('event'),
        _supabase
            .from('meet_appearances')
            .select()
            .eq('athlete_id', widget.athleteId)
            .order('meet_date', ascending: true),
        _supabase.from('school_records').select().eq('gender', widget.gender),
        _supabase
            .from('lifting_maxes')
            .select('lift_type, weight_lbs')
            .eq('athlete_id', widget.athleteId)
            .order('lift_type'),
      ]);
      final rankRows = await ranksFuture;
      final ranks = latestRanksByEvent(rankRows);
      if (!mounted) return;
      setState(() {
        _prs = results[0];
        _appearances = results[1];
        _records = results[2];
        _maxes = results[3];
        _rankRows = rankRows;
        _ranks = ranks;
        _loading = false;
        _error = null;
        final prs = _seasonPrs;
        if (prs.isNotEmpty) {
          final focusEvent = widget.focus?.event;
          _selectedEvent ??= prs.any((pr) => pr['event'] == focusEvent)
              ? focusEvent
              : prs.first['event'];
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load this profile.";
      });
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  void _openAthlete(String athleteId) {
    final team = _team!;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AthleteProfileScreen(
          athleteId: athleteId,
          athleteName: team.nameOf(athleteId),
          gender: team.genderOf(athleteId),
        ),
      ),
    );
  }

  String _initials(String name) => initialsFor(name);

  /// 'Senior' for someone on the current roster, "Alum '26" for someone who
  /// has left it (the season of their last meet), or null if unknown.
  String? get _standing {
    final team = _team;
    if (team == null) return null;
    if (team.isCurrent(widget.athleteId)) {
      return classYearLabel(team.classYearOf(widget.athleteId));
    }
    final dates = _appearances
        .map((a) => parseMeetDate(a['meet_date']))
        .whereType<DateTime>();
    if (dates.isEmpty) return 'Alum';
    final last = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    final year = (academicYearOf(last) + 1) % 100;
    return "Alum '${year.toString().padLeft(2, '0')}";
  }

  double get _bestImprovement => _prs.fold(0.0, (m, pr) {
    final d = (pr['improvement_delta_pct'] as num? ?? 0.0).toDouble();
    return d > m ? d : m;
  });

  /// Seasons this athlete has PRs in, indoor first.
  List<String> get _seasons => seasonsIn(_prs);

  /// The season shown: the one picked, else the one asked for, else that
  /// of their latest results, as long as they have PRs in it.
  String get _seasonNow {
    final seasons = _seasons;
    for (final s in [_season, widget.season, latestSeasonOf(_appearances)]) {
      if (s != null && seasons.contains(s)) return s;
    }
    return seasons.isEmpty ? 'outdoor' : seasons.first;
  }

  List<Map<String, dynamic>> get _seasonPrs {
    final season = _seasonNow;
    return _prs.where((pr) => seasonOf(pr) == season).toList();
  }

  /// The season's national and conference ranks per event.
  Map<String, List<ListRank>> get _seasonRanks {
    final season = _seasonNow;
    return latestRanksByEvent(_rankRows.where((r) => r['season'] == season));
  }

  void _setSeason(String label) {
    final season = kSeasons.firstWhere((s) => seasonLabel(s) == label);
    setState(() {
      _season = season;
      final prs = _seasonPrs;
      if (!prs.any((pr) => pr['event'] == _selectedEvent)) {
        _selectedEvent = prs.isEmpty ? null : prs.first['event'];
      }
    });
  }

  List<ChartPoint> _chartPointsForEvent(String event) {
    final season = _seasonNow;
    final data = _appearances
        .where((a) =>
            a['event'] == event &&
            a['meet_date'] != null &&
            seasonOf(a) == season)
        .toList();

    final isField = isFieldEvent(event);
    final prefs = Prefs.of(context);
    final points = <ChartPoint>[];

    for (final a in data) {
      final v = isField
          ? (a['mark_meters'] as num?)?.toDouble()
          : (a['time_seconds'] as num?)?.toDouble();
      if (v != null && v > 0) {
        points.add(
          ChartPoint(
            value: v,
            display: prefs.mark(event, a['display_value'], a['mark_meters']),
            meetName: a['meet_name'] ?? 'Unknown',
            date: a['meet_date'] ?? '',
          ),
        );
      }
    }
    return points;
  }

  /// The school record for the PR's event and season. Indoor and outdoor
  /// records are separate, and cross country has none.
  Map<String, dynamic>? _getRecordForPR(Map<String, dynamic> pr) {
    final event = pr['event'] as String? ?? '';
    final season = seasonOf(pr);
    for (final r in _records) {
      if (r['event'] == event && (r['season'] ?? 'indoor') == season) return r;
    }
    return null;
  }

  String _recordGapText(Map<String, dynamic> pr, Map<String, dynamic> record) {
    final event = pr['event'] as String? ?? '';
    final isField = isFieldEvent(event);
    final prefs = Prefs.of(context);

    if (isField) {
      final prMark = (pr['best_mark_meters'] as num?)?.toDouble() ?? 0;
      final recMark = (record['record_mark_meters'] as num?)?.toDouble() ?? 0;
      if (prMark <= 0 || recMark <= 0) return '';
      final gap = recMark - prMark;
      if (gap <= 0) return '🏆 NEW SCHOOL RECORD';
      return '${prefs.gap(event, gap)} from record (${prefs.mark(event, record['record_display'], recMark)}, ${record['holder_name']} \'${(record['year_set'] ?? 0) % 100})';
    } else {
      final prTime = (pr['best_time_seconds'] as num?)?.toDouble() ?? 0;
      final recTime =
          (record['record_mark_seconds'] as num?)?.toDouble() ?? 9999;
      if (prTime <= 0 || recTime >= 9999) return '';
      final gap = prTime - recTime;
      if (gap <= 0) return '🏆 NEW SCHOOL RECORD';
      if (gap >= 60) {
        final m = gap ~/ 60;
        final s = (gap % 60).toStringAsFixed(2);
        return '$m:${s.padLeft(5, '0')} off record (${record['record_display']}, ${record['holder_name']} \'${(record['year_set'] ?? 0) % 100})';
      }
      return '${gap.toStringAsFixed(2)}s off record (${record['record_display']}, ${record['holder_name']} \'${(record['year_set'] ?? 0) % 100})';
    }
  }

  double _recordPercentage(
    Map<String, dynamic> pr,
    Map<String, dynamic> record,
  ) {
    final isField = isFieldEvent(pr['event']);
    if (isField) {
      final prMark = (pr['best_mark_meters'] as num?)?.toDouble() ?? 0;
      final recMark = (record['record_mark_meters'] as num?)?.toDouble() ?? 1;
      if (recMark <= 0) return 0;
      return (prMark / recMark).clamp(0.0, 1.0);
    } else {
      final prTime = (pr['best_time_seconds'] as num?)?.toDouble() ?? 9999;
      final recTime = (record['record_mark_seconds'] as num?)?.toDouble() ?? 1;
      if (recTime <= 0) return 0;
      return (recTime / prTime).clamp(0.0, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = formatName(widget.athleteName);
    final isFemale = widget.gender == 'F';
    final sheet = widget.sheet;
    final focus = widget.focus;

    return Scaffold(
      backgroundColor: sheet != null ? C.sheet(dark) : C.bg(dark),
      // The header renders straight away from what the caller passed in;
      // only the sections below it wait on the network.
      body: CustomScrollView(
        controller: sheet?.scrollController ?? _pageScroll,
        slivers: [
          if (sheet != null)
            _sheetBar(dark, name, sheet)
          else
            ListenableBuilder(
              listenable: _pageScroll,
              builder: (context, _) {
                final offset = _pageScroll.hasClients
                    ? _pageScroll.offset
                    : 0.0;
                // Solid at the top so it matches the wash; frosted once the
                // page scrolls under it.
                final scrolled = (offset / 120).clamp(0.0, 1.0);
                return SliverAppBar(
                  backgroundColor: Colors.transparent,
                  flexibleSpace: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 20 * scrolled,
                        sigmaY: 20 * scrolled,
                      ),
                      child: ColoredBox(
                        color: _barColor(
                          dark,
                          C.bg(dark),
                          offset,
                        ).withValues(alpha: 1 - 0.2 * scrolled),
                        // Fill the bar; an empty ColoredBox would size to 0.
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  surfaceTintColor: Colors.transparent,
                  scrolledUnderElevation: 0,
                  elevation: 0,
                  pinned: true,
                  leading: widget.showBackButton
                      ? Center(
                          child: BackCircle(
                            onTap: () => Navigator.pop(context),
                            dark: dark,
                          ),
                        )
                      : const SizedBox(width: 0),
                  automaticallyImplyLeading: false,
                  title: Opacity(
                    opacity: _titleOpacity(offset),
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: C.text1(dark),
                      ),
                    ),
                  ),
                  centerTitle: true,
                );
              },
            ),
          SliverToBoxAdapter(child: _hero(dark, name, isFemale)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sheet != null) ...[
                    if (focus != null) _focusRow(dark, focus),
                    _sheetHint(dark, sheet),
                  ],

                  if (_loading)
                    _buildSkeleton()
                  else if (_error != null)
                    _buildError(dark)
                  else ...[
                    _insightsRail(dark),

                    // Indoor and outdoor PRs are separate; one season at a
                    // time from here down to Rivals.
                    if (_seasons.length > 1) ...[
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 100),
                        child: SizedBox(
                          width: double.infinity,
                          child: SegmentToggle(
                            key: const ValueKey('profile-season'),
                            options: [for (final s in _seasons) seasonLabel(s)],
                            value: seasonLabel(_seasonNow),
                            dark: dark,
                            height: 40,
                            fontSize: 14,
                            onChanged: _setSeason,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Trend chart
                    if (_seasonPrs.isNotEmpty) ...[
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionTitle('Progression', dark: dark),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 36,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: _seasonPrs.map((pr) {
                                  final event = pr['event'] as String;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Center(
                                      child: AppChip(
                                        label: event,
                                        selected: event == _selectedEvent,
                                        dark: dark,
                                        small: true,
                                        onTap: () => setState(() => _selectedEvent = event),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_selectedEvent != null)
                              GlassCard(
                                forceDark: dark,
                                padding: const EdgeInsets.all(20),
                                // Cross-fade and resize when switching
                                // events instead of jumping.
                                child: AnimatedSize(
                                  duration: const Duration(milliseconds: 250),
                                  curve: kSpring,
                                  alignment: Alignment.topCenter,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    layoutBuilder: (current, previous) => Stack(
                                      alignment: Alignment.topCenter,
                                      children: [...previous, ?current],
                                    ),
                                    child: InteractiveTrendChart(
                                      key: ValueKey('$_seasonNow|$_selectedEvent'),
                                      points: _chartPointsForEvent(
                                        _selectedEvent!,
                                      ),
                                      isField: isFieldEvent(_selectedEvent!),
                                      dark: dark,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],

                    // Personal Records
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 180),
                      child: _FoldableSection(
                        title: 'Personal Records',
                        subtitle: _seasons.length > 1 ? null : '${seasonLabel(_seasonNow)} bests',
                        dark: dark,
                        child: GlassCard(
                          forceDark: dark,
                          child: Column(
                            children: _seasonPrs.asMap().entries.map((entry) {
                              final i = entry.key;
                              final pr = entry.value;
                              final isLast = i == _seasonPrs.length - 1;
                              final delta =
                                  (pr['improvement_delta_pct'] as num? ?? 0.0);
                              final record = _getRecordForPR(pr);
                              final gapText = record != null
                                  ? _recordGapText(pr, record)
                                  : null;
                              final pct = record != null
                                  ? _recordPercentage(pr, record)
                                  : null;
                              return _PRRow(
                                pr: pr,
                                isLast: isLast,
                                delta: delta,
                                dark: dark,
                                recordGapText: gapText,
                                recordPct: pct,
                                ranks: _seasonRanks[pr['event']] ?? const [],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Rivals
                    if (_rivals.isNotEmpty) ...[
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 195),
                        child: _FoldableSection(
                          title: 'Rivals',
                          subtitle: 'Closest teammate PR in each event',
                          dark: dark,
                          child: GlassCard(
                            forceDark: dark,
                            child: Column(
                              children: _rivals.asMap().entries.map((entry) {
                                final rival = entry.value;
                                return _RivalRow(
                                  rival: rival,
                                  name: _team!.nameOf(rival.athleteId),
                                  gender: _team!.genderOf(rival.athleteId),
                                  isLast: entry.key == _rivals.length - 1,
                                  dark: dark,
                                  onTap: () => _openAthlete(rival.athleteId),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],

                    // Lifting Maxes
                    if (_maxes.isNotEmpty) ...[
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 210),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionTitle('Lifting Maxes', dark: dark),
                            const SizedBox(height: 12),
                            GlassCard(
                              forceDark: dark,
                              child: Column(
                                children: _maxes.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final max = entry.value;
                                  final isLast = i == _maxes.length - 1;
                                  return Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      18,
                                      14,
                                      18,
                                      14,
                                    ),
                                    decoration: isLast
                                        ? null
                                        : BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: C.border(dark),
                                                width: 0.5,
                                              ),
                                            ),
                                          ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            max['lift_type'] ?? '',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: C.text1(dark),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          Prefs.of(context).weight(
                                            max['weight_lbs'] as num? ?? 0,
                                          ),
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: C.accentOf(dark),
                                            letterSpacing: -0.5,
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
                      const SizedBox(height: 28),
                    ],

                    // Meet history
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 240),
                      child: _FoldableSection(
                        title: 'Meet History',
                        dark: dark,
                        child: _buildMeetHistory(dark),
                      ),
                    ),
                  ],
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Closest teammates this season, nearest first.
  List<Rival> get _rivals {
    final team = _team;
    if (team == null) return const [];
    final season = _seasonNow;
    return team.rivalsOf(widget.athleteId).values
        .where((r) => r.season == season)
        .toList()
      ..sort((a, b) => a.gapPct.compareTo(b.gapPct));
  }

  /// Grab handle, pinned while the sheet's content scrolls. Swiping down
  /// closes the sheet from any height.
  /// The name fades in once the header card scrolls away.
  Widget _sheetBar(bool dark, String name, ProfileSheet sheet) {
    final scroll = sheet.scrollController;
    return ListenableBuilder(
      listenable: scroll,
      builder: (context, _) => SliverAppBar(
        primary: false,
        pinned: true,
        toolbarHeight: 48,
        backgroundColor: _barColor(
          dark,
          C.sheet(dark),
          scroll.hasClients ? scroll.offset : 0,
        ),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        flexibleSpace: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: C.text3(dark).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        title: ListenableBuilder(
          listenable: scroll,
          builder: (_, _) {
            final offset = scroll.hasClients ? scroll.offset : 0.0;
            return Opacity(
              opacity: _titleOpacity(offset),
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: C.text1(dark),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// "Swipe up" affordance under the peek. Fades out as the sheet rises and
  /// opens the full profile when tapped.
  Widget _sheetHint(bool dark, ProfileSheet sheet) {
    return ValueListenableBuilder<double>(
      valueListenable: sheet.progress,
      builder: (_, t, child) =>
          Opacity(opacity: (1 - t * 3).clamp(0.0, 1.0), child: child),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: sheet.expand,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 18,
                color: C.text3(dark),
              ),
              const SizedBox(width: 4),
              Text(
                'Swipe up for full profile',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: C.text3(dark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _focusRow(bool dark, ProfileFocus f) {
    final improved = f.improvementPct > 0;
    return Row(
      children: [
        Expanded(
          child: _FocusStat(
            label: 'Personal Best',
            value: Prefs.of(context).mark(f.event, f.display, f.meters),
            accent: true,
            dark: dark,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FocusStat(label: 'Event', value: f.event, dark: dark),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FocusStat(
            label: 'Improvement',
            value: improved ? '+${f.improvementPct.toStringAsFixed(2)}%' : '—',
            accent: improved,
            dark: dark,
          ),
        ),
      ],
    );
  }

  /// PRs, best gain, meets and season points as plain numbers.
  Widget _statsRow(bool dark) {
    if (_loading) {
      return SkeletonPulse(
        child: Row(
          children: [
            for (var i = 0; i < 4; i++)
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 36, height: 20),
                    SizedBox(height: 6),
                    SkeletonBox(width: 52, height: 10),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    if (_error != null) return const SizedBox.shrink();

    Widget stat(String value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: C.text1(dark),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: C.text3(dark),
            ),
          ),
        ],
      ),
    );
    final team = _team;
    return FadeSlideIn(
      child: Row(
        children: [
          stat('${_prs.length}', 'PRs'),
          stat(
            _bestImprovement > 0
                ? '+${_bestImprovement.toStringAsFixed(1)}%'
                : '—',
            'Best gain',
          ),
          stat(
            '${_appearances.map((a) => a['meet_name']).toSet().length}',
            'Meets',
          ),
          stat(
            team == null
                ? '—'
                : '${team.pointsFor(widget.athleteId, team.currentSeason)}',
            team == null ? 'Points' : '${team.currentSeason.shortLabel} points',
          ),
        ],
      ),
    );
  }

  /// Avatar, name and details over a soft wash of the team color, then the
  /// stat strip. No card around it, so the profile opens on the athlete.
  Widget _hero(bool dark, String name, bool isFemale) {
    final details = [?_standing, isFemale ? 'Women' : 'Men'].join(' · ');
    return WashHeader(
      dark: dark,
      base: widget.sheet != null ? C.sheet(dark) : C.bg(dark),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: FadeSlideIn(
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
                      colors: isFemale
                          ? const [Color(0xFFD4537E), Color(0xFFED93B1)]
                          : [C.accentOf(dark), C.accentAlt],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isFemale
                            ? const Color(0x59D4537E)
                            : const Color(0x59E8372D),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(widget.athleteName),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          height: 1.1,
                          color: C.text1(dark),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        details,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: C.text2(dark),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _statsRow(dark),
          ],
        ),
      ),
    );
  }

  /// The strongest insights as a swipeable row of cards, edge to edge.
  Widget _insightsRail(bool dark) {
    final team = _team;
    final prefs = Prefs.of(context);
    final insights = athleteInsights(
      appearances: _appearances,
      ranks: _ranks,
      rivals: team?.rivalsOf(widget.athleteId) ?? const {},
      records: {
        for (final pr in _prs)
          if (_getRecordForPR(pr) case final r?)
            if (((isFieldEvent(pr['event'] ?? '') ? r['record_mark_meters'] : r['record_mark_seconds']) as num?)
                case final value?)
              eventKey(pr['event'] as String, seasonOf(pr)): RecordRef(
                value: value.toDouble(),
                display: r['record_display'] as String? ?? '',
                holder: r['holder_name'] as String? ?? '',
                year: (r['year_set'] as num?)?.toInt(),
              ),
      },
      nameOf: team?.nameOf,
      formatMark: (event, display, value) => prefs.mark(event, display, value),
      formatGap: prefs.gap,
      now: DateTime.now(),
    );
    if (insights.isEmpty) return const SizedBox.shrink();

    final textGrowth = (MediaQuery.textScalerOf(context).scale(14) / 14 - 1)
        .clamp(0.0, 1.0);
    return FadeSlideIn(
      delay: const Duration(milliseconds: 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle('Insights', dark: dark),
          const SizedBox(height: 12),
          SizedBox(
            height: 128 + textGrowth * 70,
            // Break out of the page padding so the row runs to the edges.
            child: OverflowBox(
              maxWidth: MediaQuery.sizeOf(context).width,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: insights.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) =>
                    _InsightCard(insight: insights[i], dark: dark),
              ),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return SkeletonPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 110, height: 12),
          const SizedBox(height: 12),
          const SkeletonBox(height: 280, radius: 16),
          const SizedBox(height: 28),
          const SkeletonBox(width: 150, height: 12),
          const SizedBox(height: 12),
          const SkeletonBox(height: 200, radius: 16),
        ],
      ),
    );
  }

  Widget _buildError(bool dark) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Center(
        child: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: _error!,
          actionLabel: 'Try again',
          onAction: _retry,
          dark: dark,
        ),
      ),
    );
  }

  Widget _buildMeetHistory(bool dark) {
    final Map<String, List<Map<String, dynamic>>> byMeet = {};
    final Map<String, String> meetDates = {};

    for (final a in _appearances) {
      final meet = a['meet_name'] as String? ?? 'Unknown Meet';
      final date = a['meet_date'] as String? ?? '';
      byMeet.putIfAbsent(meet, () => []).add(a);
      meetDates[meet] = date;
    }

    final sortedMeets = byMeet.keys.toList()
      ..sort((a, b) => (meetDates[b] ?? '').compareTo(meetDates[a] ?? ''));

    if (sortedMeets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: EmptyState(icon: Icons.event_outlined, title: 'No meets yet', dark: dark),
      );
    }

    final prefs = Prefs.of(context);
    final meets = sortedMeets.take(10).toList();
    return GlassCard(
      forceDark: dark,
      child: Column(
        children: [
          for (var i = 0; i < meets.length; i++)
            _MeetRow(
              meet: meets[i],
              season: seasonOf(byMeet[meets[i]]!.first),
              date: parseMeetDate(meetDates[meets[i]]),
              results: [
                for (final r in byMeet[meets[i]]!)
                  (
                    r['event'] as String? ?? '',
                    prefs.mark(r['event'] ?? '', r['display_value'], r['mark_meters']),
                  ),
              ],
              isLast: i == meets.length - 1,
              dark: dark,
            ),
        ],
      ),
    );
  }

}

// ─── Chart data model ───────────────────────────────────────────────────────

class ChartPoint {
  final double value;
  final String display;
  final String meetName;
  final String date;

  const ChartPoint({
    required this.value,
    required this.display,
    required this.meetName,
    required this.date,
  });
}

// ─── Interactive trend chart with touch-to-explore callout ──────────────────

class InteractiveTrendChart extends StatefulWidget {
  final List<ChartPoint> points;
  final bool isField;
  final bool dark;

  const InteractiveTrendChart({
    super.key,
    required this.points,
    required this.isField,
    required this.dark,
  });

  @override
  State<InteractiveTrendChart> createState() => _InteractiveTrendChartState();
}

class _InteractiveTrendChartState extends State<InteractiveTrendChart> {
  int? _activeIndex;

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final isField = widget.isField;
    final dark = widget.dark;

    if (points.length < 2) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'Not enough data to chart',
            style: TextStyle(fontSize: 13, color: C.text3(dark)),
          ),
        ),
      );
    }

    final values = points.map((p) => p.value).toList();
    final prValue = isField
        ? values.reduce((a, b) => a > b ? a : b)
        : values.reduce((a, b) => a < b ? a : b);
    final prPoint = points.firstWhere((p) => p.value == prValue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              prPoint.display,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: C.accentOf(dark),
                letterSpacing: -1,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'PR',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: C.text3(dark),
              ),
            ),
            const Spacer(),
            Text(
              '${points.length} results',
              style: TextStyle(fontSize: 12, color: C.text3(dark)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 210,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final chartWidth = constraints.maxWidth;
              const chartHeight = 140.0;
              const topPad = 60.0;
              const botPad = 10.0;

              final minV = values.reduce((a, b) => a < b ? a : b);
              final maxV = values.reduce((a, b) => a > b ? a : b);
              final range = maxV - minV;

              final positions = <Offset>[];
              for (var i = 0; i < points.length; i++) {
                final x = points.length == 1
                    ? chartWidth / 2
                    : (i / (points.length - 1)) * chartWidth;
                final norm = range == 0
                    ? 0.5
                    : isField
                    ? (values[i] - minV) / range
                    : 1 - (values[i] - minV) / range;
                final y = topPad + chartHeight - norm * chartHeight;
                positions.add(Offset(x, y));
              }

              // Horizontal drags scrub the chart; vertical ones still
              // scroll the page.
              return GestureDetector(
                onLongPressStart: (d) =>
                    _updateActive(d.localPosition.dx, positions),
                onLongPressMoveUpdate: (d) =>
                    _updateActive(d.localPosition.dx, positions),
                onLongPressEnd: (_) => setState(() => _activeIndex = null),
                onHorizontalDragStart: (d) =>
                    _updateActive(d.localPosition.dx, positions),
                onHorizontalDragUpdate: (d) =>
                    _updateActive(d.localPosition.dx, positions),
                onHorizontalDragEnd: (_) => setState(() => _activeIndex = null),
                onHorizontalDragCancel: () =>
                    setState(() => _activeIndex = null),
                child: TweenAnimationBuilder<double>(
                  // Draw the line in from left to right on first show.
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, progress, _) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: Size(chartWidth, topPad + chartHeight + botPad),
                        painter: _TrendLinePainter(
                          positions: positions,
                          values: values,
                          prValue: prValue,
                          isField: isField,
                          dark: dark,
                          activeIndex: _activeIndex,
                          progress: progress,
                        ),
                      ),
                      if (_activeIndex != null && _activeIndex! < points.length)
                        _buildCallout(
                          positions[_activeIndex!],
                          points[_activeIndex!],
                          chartWidth,
                          dark,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatShortDate(points.first.date),
              style: TextStyle(fontSize: 10, color: C.text3(dark)),
            ),
            // Gives way first when the text is large.
            Expanded(
              child: Text(
                'Touch and hold to explore',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: C.text3(dark).withValues(alpha: 0.6),
                ),
              ),
            ),
            Text(
              _formatShortDate(points.last.date),
              style: TextStyle(fontSize: 10, color: C.text3(dark)),
            ),
          ],
        ),
      ],
    );
  }

  void _updateActive(double dx, List<Offset> positions) {
    int closest = 0;
    double closestDist = double.infinity;
    for (var i = 0; i < positions.length; i++) {
      final dist = (positions[i].dx - dx).abs();
      if (dist < closestDist) {
        closestDist = dist;
        closest = i;
      }
    }
    if (_activeIndex != closest) {
      HapticFeedback.selectionClick();
      setState(() => _activeIndex = closest);
    }
  }

  Widget _buildCallout(
    Offset pos,
    ChartPoint point,
    double chartWidth,
    bool dark,
  ) {
    const tooltipW = 136.0;
    const tooltipH = 62.0;
    const tailH = 7.0;
    const gap = 8.0;

    double left = pos.dx - tooltipW / 2;
    if (left < 0) left = 0;
    if (left + tooltipW > chartWidth) left = chartWidth - tooltipW;

    final top = pos.dy - tooltipH - tailH - gap;
    final tailLeft = (pos.dx - left).clamp(14.0, tooltipW - 14.0) - 6;

    return Positioned(
      left: left,
      top: top,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: tooltipW,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: C.surface(dark),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: C.border(dark), width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  point.display,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: C.text1(dark),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _truncateMeet(point.meetName),
                  style: TextStyle(fontSize: 11, color: C.text2(dark)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatFullDate(point.date),
                  style: TextStyle(fontSize: 11, color: C.text3(dark)),
                ),
              ],
            ),
          ),
          SizedBox(
            width: tooltipW,
            height: tailH,
            child: CustomPaint(
              painter: _TailPainter(
                tailLeft: tailLeft,
                fillColor: C.surface(dark),
                borderColor: C.border(dark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _truncateMeet(String name) {
    return name.length > 22 ? '${name.substring(0, 20)}…' : name;
  }

  String _formatShortDate(String date) {
    if (date.isEmpty) return '';
    try {
      final parts = date.split('-');
      final months = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return "${months[int.parse(parts[1])]} '${parts[0].substring(2)}";
    } catch (_) {
      return date;
    }
  }

  String _formatFullDate(String date) {
    if (date.isEmpty) return '';
    try {
      final parts = date.split('-');
      final months = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[int.parse(parts[1])]} ${int.parse(parts[2])}, ${parts[0]}';
    } catch (_) {
      return date;
    }
  }
}

// ─── Tail painter ───────────────────────────────────────────────────────────

class _TailPainter extends CustomPainter {
  final double tailLeft;
  final Color fillColor;
  final Color borderColor;

  _TailPainter({
    required this.tailLeft,
    required this.fillColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(tailLeft, 0)
      ..lineTo(tailLeft + 6, size.height)
      ..lineTo(tailLeft + 12, 0);

    canvas.drawPath(path, Paint()..color = fillColor);

    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(tailLeft, 0),
      Offset(tailLeft + 6, size.height),
      borderPaint,
    );
    canvas.drawLine(
      Offset(tailLeft + 6, size.height),
      Offset(tailLeft + 12, 0),
      borderPaint,
    );

    canvas.drawLine(
      Offset(tailLeft + 0.5, 0),
      Offset(tailLeft + 11.5, 0),
      Paint()
        ..color = fillColor
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.tailLeft != tailLeft;
}

// ─── Chart line painter ─────────────────────────────────────────────────────

class _TrendLinePainter extends CustomPainter {
  final List<Offset> positions;
  final List<double> values;
  final double prValue;
  final bool isField;
  final bool dark;
  final int? activeIndex;

  /// 0–1 left-to-right reveal used for the draw-in animation.
  final double progress;

  _TrendLinePainter({
    required this.positions,
    required this.values,
    required this.prValue,
    required this.isField,
    required this.dark,
    this.activeIndex,
    this.progress = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.length < 2) return;

    // Pad the reveal so dots on the edges aren't clipped once it's done.
    canvas.clipRect(
      Rect.fromLTRB(-8, -8, -8 + (size.width + 16) * progress, size.height + 8),
    );

    final prIdx = values.indexOf(prValue);
    if (prIdx >= 0) {
      final prY = positions[prIdx].dy;
      final dp = Paint()
        ..color = C.accentOf(dark).withValues(alpha: 0.3)
        ..strokeWidth = 1;
      const dw = 6.0;
      const ds = 4.0;
      var sx = 0.0;
      while (sx < size.width) {
        canvas.drawLine(
          Offset(sx, prY),
          Offset((sx + dw).clamp(0, size.width), prY),
          dp,
        );
        sx += dw + ds;
      }
    }

    final fp = Path();
    for (var i = 0; i < positions.length; i++) {
      if (i == 0) {
        fp.moveTo(positions[i].dx, size.height);
        fp.lineTo(positions[i].dx, positions[i].dy);
      } else {
        fp.lineTo(positions[i].dx, positions[i].dy);
      }
    }
    fp.lineTo(positions.last.dx, size.height);
    fp.close();
    canvas.drawPath(
      fp,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            C.accentOf(dark).withValues(alpha: 0.12),
            C.accentOf(dark).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final lp = Path();
    for (var i = 0; i < positions.length; i++) {
      if (i == 0) {
        lp.moveTo(positions[i].dx, positions[i].dy);
      } else {
        lp.lineTo(positions[i].dx, positions[i].dy);
      }
    }
    canvas.drawPath(
      lp,
      Paint()
        ..color = C.accentOf(dark)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    for (var i = 0; i < positions.length; i++) {
      final isPR = values[i] == prValue;
      final isActive = i == activeIndex;

      if (isActive) {
        canvas.drawLine(
          Offset(positions[i].dx, 0),
          Offset(positions[i].dx, size.height),
          Paint()
            ..color = (dark ? Colors.white : Colors.black).withValues(
              alpha: 0.12,
            )
            ..strokeWidth = 0.5,
        );
      }

      final r = isActive
          ? 6.0
          : isPR
          ? 5.0
          : 3.0;
      final a = isActive || isPR ? 1.0 : 0.5;

      canvas.drawCircle(
        positions[i],
        r,
        Paint()..color = C.accentOf(dark).withValues(alpha: a),
      );

      if (isActive || isPR) {
        canvas.drawCircle(
          positions[i],
          r,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }
    }
  }

  // Comparing only activeIndex left the previous event's line on screen
  // after switching events, since the touch point was null both times.
  @override
  bool shouldRepaint(_TrendLinePainter old) =>
      old.activeIndex != activeIndex ||
      old.progress != progress ||
      old.dark != dark ||
      old.prValue != prValue ||
      !listEquals(old.positions, positions) ||
      !listEquals(old.values, values);
}

// ─── Foldable section ───────────────────────────────────────────────────────

/// A profile section whose header folds its content away. Starts open.
class _FoldableSection extends StatefulWidget {
  final String title;
  final String? subtitle;
  final bool dark;
  final Widget child;

  const _FoldableSection({
    required this.title,
    this.subtitle,
    required this.dark,
    required this.child,
  });

  @override
  State<_FoldableSection> createState() => _FoldableSectionState();
}

class _FoldableSectionState extends State<_FoldableSection>
    with SingleTickerProviderStateMixin {
  bool _open = true;
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );
  late final Animation<double> _reveal = CurvedAnimation(
    parent: _ctrl,
    curve: kSpring,
    reverseCurve: kSpring.flipped,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _open = !_open);
    _open ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(widget.title, style: SectionTitle.style(dark)),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0 : -0.25,
                    duration: const Duration(milliseconds: 280),
                    curve: kSpring,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: C.text3(dark),
                    ),
                  ),
                ],
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.subtitle!,
                  style: TextStyle(fontSize: 12, color: C.text3(dark)),
                ),
              ],
            ],
          ),
        ),
        SizeTransition(
          sizeFactor: _reveal,
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: _reveal,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Meet row ───────────────────────────────────────────────────────────────

/// One meet in the history: a date block, the meet, and each event's mark.
class _MeetRow extends StatelessWidget {
  final String meet;
  final String season;
  final DateTime? date;
  final List<(String, String)> results;
  final bool isLast;
  final bool dark;

  const _MeetRow({
    required this.meet,
    required this.season,
    required this.date,
    required this.results,
    required this.isLast,
    required this.dark,
  });

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    final d = date;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: isLast
          ? null
          : BoxDecoration(border: Border(bottom: BorderSide(color: C.border(dark), width: 0.5))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: d == null
                ? null
                : Column(
                    children: [
                      Text(_months[d.month - 1],
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: C.accentOf(dark))),
                      Text('${d.day}',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.1, color: C.text1(dark))),
                      Text("'${(d.year % 100).toString().padLeft(2, '0')}",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: C.text3(dark))),
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(seasonLabel(season).toUpperCase(),
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: C.text3(dark))),
                const SizedBox(height: 2),
                Text(meet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.25, color: C.text1(dark))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    for (final (event, mark) in results)
                      Text.rich(TextSpan(children: [
                        TextSpan(text: '$event  ', style: TextStyle(fontSize: 12, color: C.text3(dark))),
                        TextSpan(text: mark, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.text1(dark))),
                      ])),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Insight card ───────────────────────────────────────────────────────────

class _InsightCard extends StatelessWidget {
  final Insight insight;
  final bool dark;

  const _InsightCard({required this.insight, required this.dark});

  static const _icons = {
    InsightKind.schoolRecord: Icons.military_tech_rounded,
    InsightKind.freshPr: Icons.emoji_events_rounded,
    InsightKind.trend: Icons.trending_up_rounded,
    InsightKind.nationals: Icons.flag_rounded,
    InsightKind.seasonPace: Icons.speed_rounded,
    InsightKind.rival: Icons.compare_arrows_rounded,
    InsightKind.drought: Icons.hourglass_bottom_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 236,
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: C.accentSoft(dark),
            ),
            child: Icon(
              _icons[insight.kind],
              size: 17,
              color: C.accentOf(dark),
            ),
          ),
          const Spacer(),
          Text(
            insight.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: C.text1(dark),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            insight.detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, height: 1.3, color: C.text2(dark)),
          ),
        ],
      ),
    );
  }
}

// ─── Focus stat ─────────────────────────────────────────────────────────────

class _FocusStat extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;
  final bool dark;

  const _FocusStat({
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
            // Long event names and imperial marks shrink rather than wrap.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: accent ? C.accentOf(dark) : C.text1(dark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Rival row ──────────────────────────────────────────────────────────────

class _RivalRow extends StatelessWidget {
  final Rival rival;
  final String name;
  final String gender;
  final bool isLast;
  final bool dark;
  final VoidCallback onTap;

  const _RivalRow({
    required this.rival,
    required this.name,
    required this.gender,
    required this.isLast,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      pressedScale: 0.98,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: C.border(dark), width: 0.5)),
        ),
        child: Row(
          children: [
            InitialsAvatar(name: name, gender: gender, dark: dark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatName(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: C.text1(dark),
                    ),
                  ),
                  Text(
                    '${rival.event} · ${Prefs.of(context).mark(rival.event, rival.theirDisplay, rival.theirValue)}',
                    style: TextStyle(fontSize: 11, color: C.text3(dark)),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Prefs.of(context).gap(rival.event, rival.gap),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: rival.isAhead ? C.accentOf(dark) : C.text1(dark),
                  ),
                ),
                Text(
                  rival.isAhead ? 'to catch' : 'ahead',
                  style: TextStyle(fontSize: 10, color: C.text3(dark)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── PR Row ─────────────────────────────────────────────────────────────────

class _PRRow extends StatelessWidget {
  final Map<String, dynamic> pr;
  final bool isLast;
  final num delta;
  final bool dark;
  final String? recordGapText;
  final double? recordPct;

  /// National then conference rank from the latest ranked season.
  final List<ListRank> ranks;

  const _PRRow({
    required this.pr,
    required this.isLast,
    required this.delta,
    required this.dark,
    this.recordGapText,
    this.recordPct,
    this.ranks = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isNewRecord =
        recordGapText != null && recordGapText!.contains('NEW SCHOOL RECORD');

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: C.border(dark), width: 0.5),
              ),
            ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pr['event'] ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: C.text1(dark),
                      ),
                    ),
                    Text(
                      pr['set_at_meet'] ?? 'Season best',
                      style: TextStyle(fontSize: 11, color: C.text3(dark)),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Prefs.of(context).mark(
                      pr['event'] ?? '',
                      pr['best_display'],
                      pr['best_mark_meters'],
                    ),
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
                      style: TextStyle(fontSize: 11, color: C.text3(dark)),
                    ),
                ],
              ),
            ],
          ),
          if (ranks.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              // Wraps on narrow phones once the nationals margin is in the pill.
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final r in ranks) _rankPill(context, r),
                  Text(
                    ranks.first.seasonLabel.toLowerCase(),
                    style: TextStyle(fontSize: 10, color: C.text3(dark)),
                  ),
                ],
              ),
            ),
          ],
          if (recordGapText != null && recordGapText!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (recordPct != null && !isNewRecord)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 3,
                      child: LinearProgressIndicator(
                        value: recordPct!,
                        backgroundColor: C.surface3(dark),
                        valueColor: AlwaysStoppedAnimation(
                          recordPct! > 0.95 ? C.accentOf(dark) : C.text3(dark),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                isNewRecord
                    ? Center(
                        child: Text(
                          recordGapText!,
                          style: TextStyle(
                            fontSize: 10,
                            color: C.accentOf(dark),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : Text(
                        recordGapText!,
                        style: TextStyle(fontSize: 10, color: C.text3(dark)),
                      ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// '#19 D3 · in by 0.08m': the rank, plus where it sits against the
  /// projected nationals field on national lists.
  Widget _rankPill(BuildContext context, ListRank r) {
    final nationals = r.nationals;
    final top = nationals?.inside ?? r.rank <= 10;
    final gap = nationals?.gap;
    final gapText = gap == null ? null : Prefs.of(context).gap(r.event, gap);
    final status = switch (nationals) {
      null => null,
      NationalsStatus(inside: true) when gap != null && gap > 0 =>
        'in by $gapText',
      NationalsStatus(inside: true) => 'in',
      NationalsStatus() when gap == 0 => 'tied at the cut',
      NationalsStatus() when gapText != null => '$gapText out',
      NationalsStatus() => null,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: top ? C.accentSoft(dark) : C.surface2(dark),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        status == null
            ? '#${r.rank} ${r.label}'
            : '#${r.rank} ${r.label} · $status',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: top ? C.accentOf(dark) : C.text2(dark),
        ),
      ),
    );
  }
}
