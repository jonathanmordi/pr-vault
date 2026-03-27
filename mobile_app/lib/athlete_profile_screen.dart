import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'design_system.dart';

final _supabase = Supabase.instance.client;

const _fieldEvents = [
  'High Jump', 'Long Jump', 'Triple Jump', 'Pole Vault',
  'Shot Put', 'Discus', 'Hammer', 'Javelin', 'Weight Throw',
];

class AthleteProfileScreen extends StatefulWidget {
  final String athleteId;
  final String athleteName;
  final String gender;
  final bool showBackButton;

  const AthleteProfileScreen({
    super.key,
    required this.athleteId,
    required this.athleteName,
    required this.gender,
    this.showBackButton = true,
  });

  @override
  State<AthleteProfileScreen> createState() => _AthleteProfileScreenState();
}

class _AthleteProfileScreenState extends State<AthleteProfileScreen> {
  List<Map<String, dynamic>> _prs = [];
  List<Map<String, dynamic>> _appearances = [];
  bool _loading = true;
  String? _selectedEvent;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prs = await _supabase
        .from('track_prs')
        .select()
        .eq('athlete_id', widget.athleteId)
        .order('event');

    final appearances = await _supabase
        .from('meet_appearances')
        .select()
        .eq('athlete_id', widget.athleteId)
        .order('meet_date', ascending: true);

    setState(() {
      _prs = List<Map<String, dynamic>>.from(prs);
      _appearances = List<Map<String, dynamic>>.from(appearances);
      _loading = false;
      if (_prs.isNotEmpty) {
        _selectedEvent = _prs.first['event'];
      }
    });
  }

  String _initials(String name) {
    final formatted = formatName(name);
    final parts = formatted.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return formatted.isNotEmpty ? formatted[0].toUpperCase() : '?';
  }

  double get _bestImprovement => _prs.fold(0.0, (m, pr) {
        final d = (pr['improvement_delta_pct'] as num? ?? 0.0).toDouble();
        return d > m ? d : m;
      });

  List<ChartPoint> _chartPointsForEvent(String event) {
    final data = _appearances
        .where((a) => a['event'] == event && a['meet_date'] != null)
        .toList();

    final isField = _fieldEvents.contains(event);
    final points = <ChartPoint>[];

    for (final a in data) {
      final v = isField
          ? (a['mark_meters'] as num?)?.toDouble()
          : (a['time_seconds'] as num?)?.toDouble();
      if (v != null && v > 0) {
        points.add(ChartPoint(
          value: v,
          display: a['display_value'] ?? '—',
          meetName: a['meet_name'] ?? 'Unknown',
          date: a['meet_date'] ?? '',
        ));
      }
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = formatName(widget.athleteName);
    final isFemale = widget.gender == 'F';

    return Scaffold(
      backgroundColor: C.bg(dark),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: C.accent, strokeWidth: 2))
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  backgroundColor: C.bg(dark),
                  elevation: 0,
                  pinned: true,
                  leading: widget.showBackButton
                      ? GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Center(
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: C.surface2(dark),
                              ),
                              child: Icon(Icons.arrow_back, size: 16, color: C.text2(dark)),
                            ),
                          ),
                        )
                      : const SizedBox(width: 0),
                  automaticallyImplyLeading: false,
                  title: Text(
                    name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: C.text1(dark),
                    ),
                  ),
                  centerTitle: true,
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),

                        // Header card
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 0),
                          child: GlassCard(
                            forceDark: dark,
                            padding: const EdgeInsets.all(24),
                            child: Row(
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: isFemale
                                          ? const [Color(0xFFD4537E), Color(0xFFED93B1)]
                                          : const [C.accent, C.accentAlt],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isFemale
                                            ? const Color(0x59D4537E)
                                            : const Color(0x59E8372D),
                                        blurRadius: 20,
                                        offset: const Offset(0, 4),
                                      )
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _initials(widget.athleteName),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                          _pill('${_prs.length} PRs', C.accentSoft(dark), C.accent),
                                          _pill(isFemale ? 'Women' : 'Men', C.surface2(dark), C.text2(dark)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Stats row
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 60),
                          child: Row(
                            children: [
                              Expanded(
                                child: _miniStat(
                                  label: 'PRs',
                                  value: '${_prs.length}',
                                  icon: Icons.emoji_events_outlined,
                                  dark: dark,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _miniStat(
                                  label: 'Best Imp.',
                                  value: _bestImprovement > 0
                                      ? '+${_bestImprovement.toStringAsFixed(1)}%'
                                      : '—',
                                  icon: Icons.trending_up,
                                  dark: dark,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _miniStat(
                                  label: 'Meets',
                                  value: '${_appearances.map((a) => a['meet_name']).toSet().length}',
                                  icon: Icons.calendar_today_outlined,
                                  dark: dark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Trend chart
                        if (_prs.isNotEmpty) ...[
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 120),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PROGRESSION',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: C.text3(dark),
                                    letterSpacing: 0.06 * 13,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 36,
                                  child: ListView(
                                    scrollDirection: Axis.horizontal,
                                    children: _prs.map((pr) {
                                      final event = pr['event'] as String;
                                      final sel = event == _selectedEvent;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: GestureDetector(
                                          onTap: () => setState(() => _selectedEvent = event),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: sel ? C.accent : C.surface2(dark),
                                              borderRadius: BorderRadius.circular(100),
                                            ),
                                            child: Text(
                                              event,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: sel ? Colors.white : C.text2(dark),
                                              ),
                                            ),
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
                                    child: InteractiveTrendChart(
                                      points: _chartPointsForEvent(_selectedEvent!),
                                      isField: _fieldEvents.contains(_selectedEvent),
                                      dark: dark,
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PERSONAL RECORDS',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: C.text3(dark),
                                  letterSpacing: 0.06 * 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              GlassCard(
                                forceDark: dark,
                                child: Column(
                                  children: _prs.asMap().entries.map((entry) {
                                    final i = entry.key;
                                    final pr = entry.value;
                                    final isLast = i == _prs.length - 1;
                                    final delta = (pr['improvement_delta_pct'] as num? ?? 0.0);
                                    return _PRRow(pr: pr, isLast: isLast, delta: delta, dark: dark);
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Meet history
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 240),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'MEET HISTORY',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: C.text3(dark),
                                  letterSpacing: 0.06 * 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildMeetHistory(dark),
                            ],
                          ),
                        ),
                        const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ),
              ],
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
      return GlassCard(
        forceDark: dark,
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('No meet history', style: TextStyle(fontSize: 13, color: C.text3(dark))),
        ),
      );
    }

    return Column(
      children: sortedMeets.take(10).map((meet) {
        final results = byMeet[meet]!;
        final date = meetDates[meet] ?? '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            forceDark: dark,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        meet,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.text1(dark)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_formatDateLabel(date), style: TextStyle(fontSize: 12, color: C.text3(dark))),
                  ],
                ),
                const SizedBox(height: 10),
                ...results.map((r) {
                  final event = r['event'] ?? '';
                  final display = r['display_value'] ?? '—';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: Text(event, style: TextStyle(fontSize: 12, color: C.text2(dark))),
                        ),
                        Text(display, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.text1(dark))),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatDateLabel(String date) {
    if (date.isEmpty) return '';
    try {
      final parts = date.split('-');
      final months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return "${months[int.parse(parts[1])]} '${parts[0].substring(2)}";
    } catch (_) {
      return date;
    }
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _miniStat({required String label, required String value, required IconData icon, required bool dark}) {
    return GlassCard(
      forceDark: dark,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Icon(icon, size: 16, color: C.text3(dark)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: C.text1(dark))),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: C.text3(dark))),
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
          child: Text('Not enough data to chart', style: TextStyle(fontSize: 13, color: C.text3(dark))),
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
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: C.accent, letterSpacing: -1),
            ),
            const SizedBox(width: 8),
            Text('PR', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.text3(dark))),
            const Spacer(),
            Text('${points.length} results', style: TextStyle(fontSize: 12, color: C.text3(dark))),
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

              return GestureDetector(
                onLongPressStart: (d) => _updateActive(d.localPosition.dx, positions),
                onLongPressMoveUpdate: (d) => _updateActive(d.localPosition.dx, positions),
                onLongPressEnd: (_) => setState(() => _activeIndex = null),
                onPanStart: (d) => _updateActive(d.localPosition.dx, positions),
                onPanUpdate: (d) => _updateActive(d.localPosition.dx, positions),
                onPanEnd: (_) => setState(() => _activeIndex = null),
                child: Stack(
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
                      ),
                    ),
                    if (_activeIndex != null && _activeIndex! < points.length)
                      _buildCallout(positions[_activeIndex!], points[_activeIndex!], chartWidth, dark),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatShortDate(points.first.date), style: TextStyle(fontSize: 10, color: C.text3(dark))),
            Text(
              'Touch and hold to explore',
              style: TextStyle(fontSize: 10, color: C.text3(dark).withValues(alpha: 0.6)),
            ),
            Text(_formatShortDate(points.last.date), style: TextStyle(fontSize: 10, color: C.text3(dark))),
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
      setState(() => _activeIndex = closest);
    }
  }

  Widget _buildCallout(Offset pos, ChartPoint point, double chartWidth, bool dark) {
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.text1(dark)),
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
          // Tail — flush with bottom of card
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
      final months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return "${months[int.parse(parts[1])]} '${parts[0].substring(2)}";
    } catch (_) {
      return date;
    }
  }

  String _formatFullDate(String date) {
    if (date.isEmpty) return '';
    try {
      final parts = date.split('-');
      final months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[int.parse(parts[1])]} ${int.parse(parts[2])}, ${parts[0]}';
    } catch (_) {
      return date;
    }
  }
}

// ─── Tail painter — triangle flush with card bottom ─────────────────────────

class _TailPainter extends CustomPainter {
  final double tailLeft;
  final Color fillColor;
  final Color borderColor;

  _TailPainter({required this.tailLeft, required this.fillColor, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(tailLeft, 0)
      ..lineTo(tailLeft + 6, size.height)
      ..lineTo(tailLeft + 12, 0);

    // Fill the triangle
    canvas.drawPath(path, Paint()..color = fillColor);

    // Draw border on left and right edges
    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(tailLeft, 0), Offset(tailLeft + 6, size.height), borderPaint);
    canvas.drawLine(Offset(tailLeft + 6, size.height), Offset(tailLeft + 12, 0), borderPaint);

    // Paint over the card's bottom border where the tail connects
    canvas.drawLine(
      Offset(tailLeft + 0.5, 0),
      Offset(tailLeft + 11.5, 0),
      Paint()..color = fillColor..strokeWidth = 1.5,
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

  _TrendLinePainter({
    required this.positions,
    required this.values,
    required this.prValue,
    required this.isField,
    required this.dark,
    this.activeIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.length < 2) return;

    // PR dashed line
    final prIdx = values.indexOf(prValue);
    if (prIdx >= 0) {
      final prY = positions[prIdx].dy;
      final dp = Paint()
        ..color = C.accent.withValues(alpha: 0.3)
        ..strokeWidth = 1;
      const dw = 6.0;
      const ds = 4.0;
      var sx = 0.0;
      while (sx < size.width) {
        canvas.drawLine(Offset(sx, prY), Offset((sx + dw).clamp(0, size.width), prY), dp);
        sx += dw + ds;
      }
    }

    // Gradient fill
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
          colors: [C.accent.withValues(alpha: 0.12), C.accent.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Line
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
        ..color = C.accent
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    // Dots
    for (var i = 0; i < positions.length; i++) {
      final isPR = values[i] == prValue;
      final isActive = i == activeIndex;

      if (isActive) {
        canvas.drawLine(
          Offset(positions[i].dx, 0),
          Offset(positions[i].dx, size.height),
          Paint()
            ..color = (dark ? Colors.white : Colors.black).withValues(alpha: 0.12)
            ..strokeWidth = 0.5,
        );
      }

      final r = isActive ? 6.0 : isPR ? 5.0 : 3.0;
      final a = isActive || isPR ? 1.0 : 0.5;

      canvas.drawCircle(positions[i], r, Paint()..color = C.accent.withValues(alpha: a));

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

  @override
  bool shouldRepaint(_TrendLinePainter old) => old.activeIndex != activeIndex;
}

// ─── PR Row ─────────────────────────────────────────────────────────────────

class _PRRow extends StatelessWidget {
  final Map<String, dynamic> pr;
  final bool isLast;
  final num delta;
  final bool dark;

  const _PRRow({required this.pr, required this.isLast, required this.delta, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: isLast
          ? null
          : BoxDecoration(border: Border(bottom: BorderSide(color: C.border(dark), width: 0.5))),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: C.surface2(dark), borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Icon(Icons.emoji_events_outlined, size: 18, color: C.text2(dark)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pr['event'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.text1(dark))),
                Text(pr['set_at_meet'] ?? 'Season best', style: TextStyle(fontSize: 11, color: C.text3(dark))),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(pr['best_display'] ?? '—', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.accent, letterSpacing: -0.5)),
              if (delta > 0)
                Text('+${delta.toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, color: C.text3(dark))),
            ],
          ),
        ],
      ),
    );
  }
}