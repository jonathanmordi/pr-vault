// How PR Vault works: four pages shown once after sign-up, and again from
// Settings. Each page has a small live demo built from the app's own pieces,
// so it shows the real thing instead of a screenshot.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_system.dart';

class IntroScreen extends StatefulWidget {
  final VoidCallback onDone;

  const IntroScreen({super.key, required this.onDone});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  static const _count = 4;
  final _pages = PageController();
  int _page = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // So the logo is there from the first frame instead of popping in.
    precacheImage(const AssetImage(AppIcon.asset), context);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_page == _count - 1) return widget.onDone();
    _pages.nextPage(duration: const Duration(milliseconds: 460), curve: kFluid);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final last = _page == _count - 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: C.bg(dark),
        body: Stack(
          children: [
            Positioned.fill(child: TrackBackdrop(dark: dark)),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 12, 0),
                    child: Row(
                      children: [
                        const BrandMark(),
                        const Spacer(),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: last ? 0 : 1,
                          child: IgnorePointer(
                            ignoring: last,
                            child: TextButton(
                              onPressed: widget.onDone,
                              child: Text('Skip',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(alpha: 0.8))),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pages,
                      onPageChanged: (i) {
                        HapticFeedback.selectionClick();
                        setState(() => _page = i);
                      },
                      children: [
                        _IntroPage(
                          demo: _ResultsDemo(active: _page == 0),
                          title: 'Your results, automatically',
                          body: 'PR Vault pulls every result from TFRRS each night, so a meet '
                              'shows up by the next morning. Indoor and outdoor PRs are kept separate.',
                        ),
                        _IntroPage(
                          demo: _BoardDemo(dark: dark),
                          title: 'Your team, ranked',
                          body: "Heat Map shows who's improving most, PR Rankings the best marks, "
                              "Trending who's PR'ing most. Tap the pill to switch season or gender. Try it.",
                        ),
                        _IntroPage(
                          demo: _TapDemo(active: _page == 2, dark: dark),
                          title: 'Tap anyone',
                          body: 'Their card pops up. Drag it up for the full profile: insights, '
                              'progression and rivals. Swipe down to close.',
                        ),
                        _IntroPage(
                          demo: _LoopDemo(active: _page == 3),
                          title: 'Stay in the loop',
                          body: "The bell shows your teammates' PRs. Rivals are the teammates closest "
                              'to you in each event, and Maxes is where you log your lifts.',
                        ),
                      ],
                    ),
                  ),
                  _Dots(count: _count, page: _page),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                    child: _WhiteButton(label: last ? "Let's go" : 'Next', onTap: _next),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  final Widget demo;
  final String title;
  final String body;

  const _IntroPage({required this.demo, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Demos are drawn at one size and scaled down to fit small phones.
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                // Scaled as a whole if large text makes a demo outgrow its box.
                child: SizedBox(
                  width: 320,
                  height: 330,
                  child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: demo)),
                ),
              ),
            ),
          ),
          Text(
            title,
            style: const TextStyle(
                fontSize: 32, height: 1.05, fontWeight: FontWeight.w900, letterSpacing: -1.1, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(body, style: TextStyle(fontSize: 15.5, height: 1.42, color: Colors.white.withValues(alpha: 0.82))),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int page;

  const _Dots({required this.count, required this.page});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: kFluid,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == page ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i == page ? 1 : 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

class _WhiteButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _WhiteButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        height: 54,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(label,
              key: ValueKey(label),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.accentOf(false))),
        ),
      ),
    );
  }
}

/// A card like the sign-in screen's: solid white, or glassy on the red.
class _GlassCard extends StatelessWidget {
  final Widget child;
  final bool solid;

  const _GlassCard({required this.child, this.solid = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: solid ? Colors.white : Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: solid ? null : Border.all(color: Colors.white.withValues(alpha: 0.22), width: 0.8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 22, offset: const Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }
}

TextStyle _label(Color color) =>
    TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: color);

/// Replays its children's entrance whenever the page comes into view.
class _Entrance extends StatelessWidget {
  final bool active;
  final List<Widget> children;

  const _Entrance({required this.active, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey(active),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++)
          FadeSlideIn(delay: Duration(milliseconds: 120 + 150 * i), child: children[i]),
      ],
    );
  }
}

// ─── 1. Results arrive on their own ────────────────────────────────────────────

class _ResultsDemo extends StatelessWidget {
  final bool active;

  const _ResultsDemo({required this.active});

  @override
  Widget build(BuildContext context) {
    final soft = Colors.white.withValues(alpha: 0.75);
    final accent = C.accentOf(false);
    return _Entrance(
      active: active,
      children: [
        _GlassCard(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                child: Text('TFRRS', style: _label(Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('MAC Outdoor Championships',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text('Long Jump · 6.91m', style: TextStyle(fontSize: 13, color: soft)),
                  ],
                ),
              ),
            ],
          ),
        ),
        _SyncLine(active: active),
        _GlassCard(
          solid: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.bolt_rounded, size: 16, color: accent),
                const SizedBox(width: 4),
                Text('NEW PR', style: _label(accent)),
              ]),
              const SizedBox(height: 6),
              const Text('6.91m',
                  style: TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1, color: Color(0xFF111114))),
              const Text('Outdoor long jump · +0.12m',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6E6E76))),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SeasonChip(label: 'Indoor', mark: '6.73m', solid: false),
            const SizedBox(width: 10),
            _SeasonChip(label: 'Outdoor', mark: '6.91m', solid: true),
          ],
        ),
      ],
    );
  }
}

class _SeasonChip extends StatelessWidget {
  final String label;
  final String mark;
  final bool solid;

  const _SeasonChip({required this.label, required this.mark, required this.solid});

  @override
  Widget build(BuildContext context) {
    final ink = solid ? C.accentOf(false) : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: solid ? Colors.white : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '$label  ', style: TextStyle(fontSize: 13, color: ink.withValues(alpha: 0.8))),
        TextSpan(text: mark, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
      ])),
    );
  }
}

/// A dotted line with a dot travelling down it: the nightly sync.
class _SyncLine extends StatefulWidget {
  final bool active;

  const _SyncLine({required this.active});

  @override
  State<_SyncLine> createState() => _SyncLineState();
}

class _SyncLineState extends State<_SyncLine> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  void _sync() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_SyncLine old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 10,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(size: const Size(10, 50), painter: _SyncPainter(_c.value)),
            ),
          ),
          const SizedBox(width: 10),
          Text('every night',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

class _SyncPainter extends CustomPainter {
  final double t;

  const _SyncPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final dots = Paint()..color = Colors.white.withValues(alpha: 0.35);
    for (var y = 4.0; y < size.height; y += 8) {
      canvas.drawCircle(Offset(size.width / 2, y), 1.5, dots);
    }
    final y = 4 + (size.height - 8) * Curves.easeInOut.transform(t);
    canvas.drawCircle(Offset(size.width / 2, y), 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SyncPainter old) => old.t != t;
}

// ─── 2. The leaderboard, live ─────────────────────────────────────────────────

class _Sample {
  final String name;
  final String gender;
  final Map<String, (String, double)> marks; // season → (display, value)
  final Map<String, double> gains; // season → % improvement
  final Map<String, int> prCounts; // season → PRs

  const _Sample(this.name, this.gender, this.marks, this.gains, this.prCounts);
}

const _samples = [
  _Sample('Maya Brooks', 'F', {'Indoor': ('5.88m', 5.88), 'Outdoor': ('6.02m', 6.02)},
      {'Indoor': 3.1, 'Outdoor': 4.6}, {'Indoor': 2, 'Outdoor': 4}),
  _Sample('Jordan Ellis', 'M', {'Indoor': ('7.04m', 7.04), 'Outdoor': ('7.21m', 7.21)},
      {'Indoor': 5.2, 'Outdoor': 1.8}, {'Indoor': 4, 'Outdoor': 2}),
  _Sample('Sam Okoro', 'M', {'Indoor': ('6.73m', 6.73), 'Outdoor': ('6.91m', 6.91)},
      {'Indoor': 2.4, 'Outdoor': 3.9}, {'Indoor': 3, 'Outdoor': 3}),
  _Sample('Ava Morales', 'F', {'Indoor': ('5.61m', 5.61), 'Outdoor': ('5.70m', 5.70)},
      {'Indoor': 6.0, 'Outdoor': 2.2}, {'Indoor': 5, 'Outdoor': 1}),
];

class _BoardDemo extends StatefulWidget {
  final bool dark;

  const _BoardDemo({required this.dark});

  @override
  State<_BoardDemo> createState() => _BoardDemoState();
}

class _BoardDemoState extends State<_BoardDemo> {
  static const _tabs = ['Heat', 'Rankings', 'Trending'];
  static const _rowH = 50.0;
  String _tab = 'Heat';
  String _season = 'Outdoor';
  String _gender = 'All';

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final shown = _samples.where((s) => _gender == 'All' || s.gender == _gender).toList();
    double metric(_Sample s) => switch (_tab) {
          'Heat' => s.gains[_season]!,
          'Rankings' => s.marks[_season]!.$2,
          _ => s.prCounts[_season]!.toDouble(),
        };
    shown.sort((a, b) => metric(b).compareTo(metric(a)));

    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: C.bg(dark),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 14))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentToggle(
              options: _tabs,
              value: _tab,
              dark: dark,
              height: 34,
              fontSize: 12.5,
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text('Long Jump',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: C.text1(dark))),
              ),
              const SizedBox(width: 8),
              FilterPill(
                dark: dark,
                height: 36,
                groups: [
                  FilterGroup(
                      options: const ['Indoor', 'Outdoor'],
                      value: _season,
                      onChanged: (s) => setState(() => _season = s)),
                  FilterGroup(
                      options: const ['All', 'M', 'F'], value: _gender, onChanged: (g) => setState(() => _gender = g)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Rows glide to their new places when the order changes.
          AnimatedContainer(
            duration: const Duration(milliseconds: 380),
            curve: kFluid,
            height: _rowH * shown.length,
            child: Stack(
              children: [
                for (final s in _samples)
                  AnimatedPositioned(
                    key: ValueKey(s.name),
                    duration: const Duration(milliseconds: 460),
                    curve: kFluid,
                    left: 0,
                    right: 0,
                    top: _rowH * math.max(0, shown.indexOf(s)),
                    height: _rowH,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: shown.contains(s) ? 1 : 0,
                      child: _row(s, shown.indexOf(s), dark),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(_Sample s, int place, bool dark) {
    final value = switch (_tab) {
      'Heat' => '+${s.gains[_season]!.toStringAsFixed(1)}%',
      'Rankings' => s.marks[_season]!.$1,
      _ => '${s.prCounts[_season]} PRs',
    };
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Text('${place + 1}',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: place < 3 ? C.accentOf(dark) : C.text3(dark))),
        ),
        InitialsAvatar(name: s.name, gender: s.gender, dark: dark, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Text(s.name,
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: C.text1(dark))),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(value,
              key: ValueKey(value),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: C.accentOf(dark))),
        ),
      ],
    );
  }
}

// ─── 3. Tap anyone: a looping demo of the profile card ─────────────────────────

class _TapDemo extends StatefulWidget {
  final bool active;
  final bool dark;

  const _TapDemo({required this.active, required this.dark});

  @override
  State<_TapDemo> createState() => _TapDemoState();
}

class _TapDemoState extends State<_TapDemo> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 6400));

  void _sync() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_TapDemo old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _c.value = 0;
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // 0 → 1 over [a, b] of the loop, shaped by [curve].
  double _phase(double a, double b, [Curve curve = Curves.easeInOutCubic]) =>
      curve.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    const w = 210.0, h = 320.0;
    final dark = widget.dark;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // The card: hidden → peek (tap) → full (drag up) → gone (swipe down).
        final peek = _phase(0.20, 0.32, kFluid);
        final full = _phase(0.42, 0.56, kFluid);
        final gone = _phase(0.78, 0.88);
        final top = h - (h * 0.42) * peek - (h * 0.42 - 18) * full + (h + 20) * gone;
        // The finger: to the row, tap, to the card, drag up, swipe down.
        final toRow = _phase(0.04, 0.16);
        final toCard = _phase(0.34, 0.42);
        final drag = _phase(0.42, 0.56, kFluid);
        final swipe = _phase(0.76, 0.88);
        final pressed = (_c.value > 0.16 && _c.value < 0.20) || (_c.value > 0.40 && _c.value < 0.57) ||
            (_c.value > 0.74 && _c.value < 0.88);
        var finger = Offset.lerp(const Offset(w * 0.8, h * 0.95), const Offset(w * 0.55, 108), toRow)!;
        finger = Offset.lerp(finger, Offset(w * 0.5, h - h * 0.42 + 14), toCard)!;
        finger = Offset(finger.dx, finger.dy - (h * 0.42 - 32) * drag);
        finger = Offset(finger.dx, finger.dy + (h * 0.5) * swipe);
        final fingerOpacity = _c.value < 0.02 || _c.value > 0.92 ? 0.0 : 1.0;
        final tapped = _c.value > 0.16 && _c.value < 0.86;

        return Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: C.bg(dark),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 3),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 30, offset: const Offset(0, 14)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(27),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // The leaderboard underneath.
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Leaderboard',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: C.text1(dark))),
                      const SizedBox(height: 14),
                      for (final (i, name) in ['Jordan Ellis', 'Sam Okoro', 'Maya Brooks', 'Ava Morales'].indexed)
                        Container(
                          height: 40,
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: i == 1 && tapped ? C.surface2(dark) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              InitialsAvatar(name: name, gender: i >= 2 ? 'F' : 'M', dark: dark, size: 26),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(name,
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.text1(dark))),
                              ),
                              Text(['7.21m', '6.91m', '6.02m', '5.70m'][i],
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: C.accentOf(dark))),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Dims as the card rises.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(color: Colors.black.withValues(alpha: 0.35 * peek * (1 - gone))),
                  ),
                ),
                // The profile card.
                Positioned(
                  left: 6 * (1 - full),
                  right: 6 * (1 - full),
                  top: top,
                  height: h,
                  child: Container(
                    decoration: BoxDecoration(
                      color: C.sheet(dark),
                      borderRadius: BorderRadius.circular(22 - 8 * full),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 30,
                            height: 4,
                            decoration: BoxDecoration(
                                color: C.text3(dark).withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [C.accentAlt, C.accentOf(false)]),
                              ),
                              alignment: Alignment.center,
                              child: const Text('SO',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text('Sam Okoro',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: C.text1(dark))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('PERSONAL BEST', style: _label(C.text3(dark))),
                        Text('6.91m',
                            style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: C.accentOf(dark))),
                        const SizedBox(height: 10),
                        // More shows as the card opens up.
                        Opacity(
                          opacity: full,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                    color: C.surface(dark), borderRadius: BorderRadius.circular(12)),
                                child: Row(
                                  children: [
                                    Icon(Icons.trending_up_rounded, size: 16, color: C.accentOf(dark)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text('Outdoor long jump is trending up',
                                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: C.text1(dark))),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 60,
                                width: double.infinity,
                                child: CustomPaint(painter: _MiniChartPainter(C.accentOf(dark))),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // The finger.
                Positioned(
                  left: finger.dx - 18,
                  top: finger.dy - 18,
                  child: Opacity(
                    opacity: fingerOpacity,
                    child: AnimatedScale(
                      scale: pressed ? 0.82 : 1,
                      duration: const Duration(milliseconds: 140),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.55),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10)],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MiniChartPainter extends CustomPainter {
  final Color color;

  const _MiniChartPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const ys = [0.85, 0.6, 0.7, 0.4, 0.45, 0.15];
    final path = Path();
    for (var i = 0; i < ys.length; i++) {
      final p = Offset(size.width * i / (ys.length - 1), size.height * ys[i]);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(Offset(size.width, size.height * ys.last), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MiniChartPainter old) => old.color != color;
}

// ─── 4. Activity, rivals and maxes ─────────────────────────────────────────────

class _LoopDemo extends StatelessWidget {
  final bool active;

  const _LoopDemo({required this.active});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF111114);
    const soft = Color(0xFF6E6E76);
    final accent = C.accentOf(false);
    return _Entrance(
      active: active,
      children: [
        _GlassCard(
          solid: true,
          child: Row(
            children: [
              _RingingBell(active: active),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'Maya Brooks', style: TextStyle(fontWeight: FontWeight.w800)),
                        TextSpan(text: " PR'd in 400 Meters"),
                      ]),
                      style: TextStyle(fontSize: 13.5, color: ink),
                    ),
                    Text('Outdoor · 58.40 · −0.62s', style: TextStyle(fontSize: 12, color: soft)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('RIVAL', style: _label(Colors.white.withValues(alpha: 0.85))),
              const SizedBox(height: 4),
              const Text('0.12m behind Jordan Ellis',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: Colors.white)),
              Text('Closest teammate in the outdoor triple jump',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _GlassCard(
          solid: true,
          child: Row(
            children: [
              Icon(Icons.fitness_center_rounded, size: 20, color: accent),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Squat', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
              ),
              const Text('315 lbs', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(100)),
                child: Text('+10', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: accent)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The bell with an unread badge, giving a little ring now and then.
class _RingingBell extends StatefulWidget {
  final bool active;

  const _RingingBell({required this.active});

  @override
  State<_RingingBell> createState() => _RingingBellState();
}

class _RingingBellState extends State<_RingingBell> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  void _sync() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_RingingBell old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = C.accentOf(false);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // A quick shake in the first quarter of each cycle, then still.
        final t = (_c.value / 0.25).clamp(0.0, 1.0);
        final angle = t >= 1 ? 0.0 : math.sin(t * math.pi * 6) * 0.35 * (1 - t);
        return Transform.rotate(angle: angle, alignment: Alignment.topCenter, child: child);
      },
      child: SizedBox(
        width: 34,
        height: 34,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(child: Icon(Icons.notifications_rounded, size: 26, color: accent)),
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 17,
                height: 17,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                alignment: Alignment.center,
                child: const Text('3', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
