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

  const AthleteProfileScreen({
    super.key,
    required this.athleteId,
    required this.athleteName,
    required this.gender,
  });

  @override
  State<AthleteProfileScreen> createState() => _AthleteProfileScreenState();
}

class _AthleteProfileScreenState extends State<AthleteProfileScreen> {
  List<Map<String, dynamic>> _prs = [];
  List<Map<String, dynamic>> _appearances = [];
  bool _loading = true;
  String? _selectedEvent; // for trend chart filtering

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

  List<Map<String, dynamic>> _appearancesForEvent(String event) {
    return _appearances
        .where((a) => a['event'] == event && a['meet_date'] != null)
        .toList();
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
                // ── App bar
                SliverAppBar(
                  backgroundColor: C.bg(dark),
                  elevation: 0,
                  pinned: true,
                  leading: GestureDetector(
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
                  ),
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

                        // ── Header card
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
                                          _pill(
                                            '${_prs.length} PRs',
                                            C.accentSoft(dark),
                                            C.accent,
                                          ),
                                          _pill(
                                            isFemale ? 'Women' : 'Men',
                                            C.surface2(dark),
                                            C.text2(dark),
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
                        const SizedBox(height: 16),

                        // ── Stats row
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

                        // ── Trend chart section
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
                                // Event selector chips
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
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 8),
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
                                // Chart
                                if (_selectedEvent != null)
                                  GlassCard(
                                    forceDark: dark,
                                    padding: const EdgeInsets.all(20),
                                    child: _buildTrendChart(dark),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],

                        // ── Personal Records list
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
                                    final delta =
                                        (pr['improvement_delta_pct'] as num? ?? 0.0);
                                    return _PRRow(
                                      pr: pr,
                                      isLast: isLast,
                                      delta: delta,
                                      dark: dark,
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        // ── Meet history
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
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTrendChart(bool dark) {
    final data = _appearancesForEvent(_selectedEvent!);
    final isField = _fieldEvents.contains(_selectedEvent);

    if (data.length < 2) {
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

    // Get values
    final values = data.map((a) {
      final v = isField
          ? (a['mark_meters'] as num?)?.toDouble()
          : (a['time_seconds'] as num?)?.toDouble();
      return v ?? 0.0;
    }).where((v) => v > 0).toList();

    final dates = data
        .where((a) {
          final v = isField
              ? (a['mark_meters'] as num?)?.toDouble()
              : (a['time_seconds'] as num?)?.toDouble();
          return v != null && v > 0;
        })
        .map((a) => a['meet_date'] as String? ?? '')
        .toList();

    if (values.length < 2) {
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

    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);

    // PR line (best value)
    final prValue = isField ? maxV : minV;

    // Format display value
    String formatVal(double v) {
      if (isField) return '${v.toStringAsFixed(2)}m';
      if (v >= 60) {
        final m = v ~/ 60;
        final s = (v % 60).toStringAsFixed(2);
        return '$m:${s.padLeft(5, '0')}';
      }
      return v.toStringAsFixed(2);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // PR display
        Row(
          children: [
            Text(
              formatVal(prValue),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: C.accent,
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
              '${values.length} results',
              style: TextStyle(fontSize: 12, color: C.text3(dark)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Chart
        SizedBox(
          height: 140,
          child: CustomPaint(
            size: const Size(double.infinity, 140),
            painter: _TrendChartPainter(
              values: values,
              dates: dates,
              isField: isField,
              prValue: prValue,
              dark: dark,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Date labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDateLabel(dates.first),
              style: TextStyle(fontSize: 10, color: C.text3(dark)),
            ),
            Text(
              _formatDateLabel(dates.last),
              style: TextStyle(fontSize: 10, color: C.text3(dark)),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDateLabel(String date) {
    if (date.isEmpty) return '';
    try {
      final parts = date.split('-');
      final months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final month = months[int.parse(parts[1])];
      final year = parts[0].substring(2); // "2025" → "25"
      return "$month '$year";
    } catch (_) {
      return date;
    }
  }

  Widget _buildMeetHistory(bool dark) {
    // Group appearances by meet
    final Map<String, List<Map<String, dynamic>>> byMeet = {};
    final Map<String, String> meetDates = {};

    for (final a in _appearances) {
      final meet = a['meet_name'] as String? ?? 'Unknown Meet';
      final date = a['meet_date'] as String? ?? '';
      byMeet.putIfAbsent(meet, () => []).add(a);
      meetDates[meet] = date;
    }

    // Sort meets by date descending (most recent first)
    final sortedMeets = byMeet.keys.toList()
      ..sort((a, b) => (meetDates[b] ?? '').compareTo(meetDates[a] ?? ''));

    if (sortedMeets.isEmpty) {
      return GlassCard(
        forceDark: dark,
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'No meet history',
            style: TextStyle(fontSize: 13, color: C.text3(dark)),
          ),
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
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: C.text1(dark),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDateLabel(date),
                      style: TextStyle(fontSize: 12, color: C.text3(dark)),
                    ),
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
                          child: Text(
                            event,
                            style: TextStyle(
                              fontSize: 12,
                              color: C.text2(dark),
                            ),
                          ),
                        ),
                        Text(
                          display,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: C.text1(dark),
                          ),
                        ),
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

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(100)),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _miniStat({
    required String label,
    required String value,
    required IconData icon,
    required bool dark,
  }) {
    return GlassCard(
      forceDark: dark,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Icon(icon, size: 16, color: C.text3(dark)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: C.text1(dark),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: C.text3(dark)),
          ),
        ],
      ),
    );
  }
}

// ─── Trend chart painter ────────────────────────────────────────────────────

class _TrendChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> dates;
  final bool isField;
  final double prValue;
  final bool dark;

  _TrendChartPainter({
    required this.values,
    required this.dates,
    required this.isField,
    required this.prValue,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = maxV - minV;
    if (range == 0) return;

    final padding = 8.0;
    final chartWidth = size.width - padding * 2;
    final chartHeight = size.height - padding * 2;

    // PR reference line
    final prNorm = isField
        ? (prValue - minV) / range
        : 1 - (prValue - minV) / range;
    final prY = padding + chartHeight - prNorm * chartHeight;

    final prPaint = Paint()
      ..color = C.accent.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Draw dashed PR line
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    var startX = padding;
    while (startX < size.width - padding) {
      canvas.drawLine(
        Offset(startX, prY),
        Offset((startX + dashWidth).clamp(0, size.width - padding), prY),
        prPaint,
      );
      startX += dashWidth + dashSpace;
    }

    // Line path
    final linePaint = Paint()
      ..color = C.accent
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Gradient fill
    final fillPath = Path();
    final linePath = Path();

    for (var i = 0; i < values.length; i++) {
      final x = padding + (i / (values.length - 1)) * chartWidth;
      final norm = isField
          ? (values[i] - minV) / range
          : 1 - (values[i] - minV) / range;
      final y = padding + chartHeight - norm * chartHeight;

      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Close fill path
    fillPath.lineTo(padding + chartWidth, size.height);
    fillPath.close();

    // Draw gradient fill
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          C.accent.withValues(alpha: 0.15),
          C.accent.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);

    // Draw dots
    for (var i = 0; i < values.length; i++) {
      final x = padding + (i / (values.length - 1)) * chartWidth;
      final norm = isField
          ? (values[i] - minV) / range
          : 1 - (values[i] - minV) / range;
      final y = padding + chartHeight - norm * chartHeight;

      // Is this the PR value?
      final isPR = values[i] == prValue;

      canvas.drawCircle(
        Offset(x, y),
        isPR ? 5 : 3,
        Paint()..color = isPR ? C.accent : C.accent.withValues(alpha: 0.6),
      );

      if (isPR) {
        canvas.drawCircle(
          Offset(x, y),
          5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TrendChartPainter old) => true;
}

// ─── PR Row ─────────────────────────────────────────────────────────────────

class _PRRow extends StatelessWidget {
  final Map<String, dynamic> pr;
  final bool isLast;
  final num delta;
  final bool dark;

  const _PRRow({
    required this.pr,
    required this.isLast,
    required this.delta,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: C.border(dark), width: 0.5),
              ),
            ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: C.surface2(dark),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.emoji_events_outlined,
              size: 18,
              color: C.text2(dark),
            ),
          ),
          const SizedBox(width: 12),
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
                pr['best_display'] ?? '—',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: C.accent,
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
    );
  }
}