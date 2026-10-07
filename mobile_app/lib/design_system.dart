import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Spring curve ─────────────────────────────────────────────────────────────
const kSpring = SpringCurve();

class SpringCurve extends Curve {
  const SpringCurve();
  @override
  double transform(double t) {
    return 1 - (1 - t) * (1 - t) * (1 - t);
  }
}

// ─── Color system ─────────────────────────────────────────────────────────────
class C {
  static const accentAlt = Color(0xFFE8372D);

  /// Brand red. Dark mode uses the brighter red so it doesn't go muddy on
  /// dark cards.
  static Color accentOf(bool dark) => dark ? accentAlt : const Color(0xFFC8140F);

  // Neutral greys; the old olive-tinted ones made both themes look muddy.
  static Color bg(bool dark) =>
      dark ? const Color(0xFF000000) : const Color(0xFFF2F2F5);

  static Color surface(bool dark) =>
      dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);

  static Color surface2(bool dark) =>
      dark ? const Color(0xFF2C2C2E) : const Color(0xFFEEEEF1);

  static Color surface3(bool dark) =>
      dark ? const Color(0xFF3A3A3C) : const Color(0xFFE4E4E8);

  /// Bottom sheets. Lifted off black in dark mode so the sheet's edge shows
  /// against the dimmed screen behind it.
  static Color sheet(bool dark) =>
      dark ? const Color(0xFF111113) : const Color(0xFFF2F2F5);

  /// Search and text field fill, sitting directly on [bg].
  static Color field(bool dark) =>
      dark ? const Color(0xFF1C1C1E) : const Color(0xFFE4E4E9);

  static Color border(bool dark) =>
      dark ? const Color(0x1FFFFFFF) : const Color(0xFFE2E2E7);

  static Color text1(bool dark) =>
      dark ? const Color(0xFFF5F5F7) : const Color(0xFF111114);

  static Color text2(bool dark) =>
      dark ? const Color(0xFFAEAEB2) : const Color(0xFF4E4E57);

  static Color text3(bool dark) =>
      dark ? const Color(0xFF8E8E93) : const Color(0xFF75757F);

  static Color accentSoft(bool dark) =>
      dark ? const Color(0x29E8372D) : const Color(0xFFFCE9E8);
}

// ─── Glass card ───────────────────────────────────────────────────────────────
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool forceDark;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.forceDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = forceDark ||
        Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: C.surface(dark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.border(dark), width: 0.5),
      ),
      child: child,
    );
  }
}

// ─── Fade + slide in animation ────────────────────────────────────────────────
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;

  /// When false the child shows immediately. Read once on first build, so
  /// list rows that scroll into view later don't replay the entrance.
  final bool animate;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.animate = true,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: widget.animate ? 0 : 1,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    if (widget.animate) {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ─── Skeleton loading placeholders ────────────────────────────────────────────
/// Gently pulses its child; wrap a group of [SkeletonBox]es so they share
/// one animation.
class SkeletonPulse extends StatefulWidget {
  final Widget child;

  const SkeletonPulse({super.key, required this.child});

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(begin: 0.45, end: 1)
      .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}

class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: C.surface2(dark),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ─── Initials avatar ──────────────────────────────────────────────────────────
class InitialsAvatar extends StatelessWidget {
  final String name;
  final String gender;
  final bool dark;
  final double size;

  const InitialsAvatar({
    super.key,
    required this.name,
    required this.gender,
    required this.dark,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final female = gender == 'F';
    // A muted pink in dark mode; the light-mode pink glares on black.
    final bg = female
        ? (dark ? const Color(0x33D4537E) : const Color(0xFFFDE8F0))
        : C.surface2(dark);
    final fg = female
        ? (dark ? const Color(0xFFED93B1) : const Color(0xFFD4537E))
        : C.text2(dark);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      alignment: Alignment.center,
      child: Text(
        initialsFor(name),
        style: TextStyle(
          fontSize: size * 0.33,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

// ─── Press scale ──────────────────────────────────────────────────────────────
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double pressedScale;

  const PressScale({
    super.key,
    required this.child,
    required this.onTap,
    this.pressedScale = 0.97,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: widget.pressedScale)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

// ─── Segment toggle ───────────────────────────────────────────────────────────

/// Pick-one pill control. Tap a segment, or press and slide: the thumb
/// follows your finger and the segment under it is picked when you let go.
class SegmentToggle extends StatefulWidget {
  final List<String> options;
  final String value;
  final bool dark;
  final ValueChanged<String> onChanged;

  const SegmentToggle({
    super.key,
    required this.options,
    required this.value,
    required this.dark,
    required this.onChanged,
  });

  @override
  State<SegmentToggle> createState() => _SegmentToggleState();
}

class _SegmentToggleState extends State<SegmentToggle> {
  final _track = GlobalKey();

  /// Thumb position from 0 (first segment) to 1 (last) while sliding.
  double? _slide;
  int? _hover;

  int get _n => widget.options.length;

  double get _width => _track.currentContext?.size?.width ?? 1;

  int _indexAt(double x) => (x / _width * _n).floor().clamp(0, _n - 1);

  double _fractionAt(double x) {
    if (_n < 2) return 0;
    final segment = _width / _n;
    return ((x - segment / 2) / (_width - segment)).clamp(0.0, 1.0);
  }

  void _pick(int i) {
    if (widget.options[i] == widget.value) return;
    widget.onChanged(widget.options[i]);
  }

  void _startSlide(double x) {
    HapticFeedback.lightImpact();
    setState(() {
      _slide = _fractionAt(x);
      _hover = _indexAt(x);
    });
  }

  void _moveSlide(double x) {
    if (_slide == null) return;
    final i = _indexAt(x);
    if (i != _hover) HapticFeedback.selectionClick();
    setState(() {
      _slide = _fractionAt(x);
      _hover = i;
    });
  }

  void _endSlide() {
    final i = _hover;
    if (_slide == null || i == null) return;
    setState(() {
      _slide = null;
      _hover = null;
    });
    _pick(i);
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final n = _n;
    final index = widget.options.indexOf(widget.value).clamp(0, n - 1);
    final sliding = _slide != null;
    final shown = _hover ?? index;
    final at = _slide ?? (n > 1 ? index / (n - 1) : 0.5);

    return Container(
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: C.surface2(dark),
        borderRadius: BorderRadius.circular(100),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final i = _indexAt(d.localPosition.dx);
          if (widget.options[i] == widget.value) return;
          HapticFeedback.selectionClick();
          _pick(i);
        },
        onHorizontalDragStart: (d) => _startSlide(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => _moveSlide(d.localPosition.dx),
        onHorizontalDragEnd: (_) => _endSlide(),
        onLongPressStart: (d) => _startSlide(d.localPosition.dx),
        onLongPressMoveUpdate: (d) => _moveSlide(d.localPosition.dx),
        onLongPressEnd: (_) => _endSlide(),
        // Every segment is as wide as the widest label, so 'All' doesn't get
        // more room than 'M' or 'F'.
        child: IntrinsicWidth(
          key: _track,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: AnimatedAlign(
                  duration: sliding
                      ? Duration.zero
                      : const Duration(milliseconds: 320),
                  curve: Curves.easeOutBack,
                  alignment: Alignment(-1 + 2 * at, 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / n,
                    child: AnimatedScale(
                      scale: sliding ? 1.12 : 1,
                      duration: const Duration(milliseconds: 200),
                      curve: kSpring,
                      child: Container(
                        decoration: BoxDecoration(
                          color: C.accentOf(dark),
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: shown == i ? Colors.white : C.text3(dark),
                            ),
                            child: Text(widget.options[i]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Input field ──────────────────────────────────────────────────────────────

/// Rounded text field with a leading icon, used on the sign-in and
/// onboarding screens.
class InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool dark;
  final bool obscure;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;

  const InputField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    required this.dark,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: C.surface(dark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.border(dark)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(icon, size: 18, color: C.text3(dark)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              autofillHints: autofillHints,
              onChanged: onChanged,
              style: TextStyle(fontSize: 15, color: C.text1(dark)),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: C.text3(dark), fontSize: 15),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

// ─── Primary button ───────────────────────────────────────────────────────────

/// Full-width red gradient button. Shows a spinner and ignores taps while
/// [loading].
class PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  final bool dark;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.dark,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: loading ? () {} : onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [C.accentOf(dark), C.accentAlt]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(color: Color(0x4DB80C09), blurRadius: 20, offset: Offset(0, 6)),
          ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
        ),
      ),
    );
  }
}

// ─── Custom toggle ────────────────────────────────────────────────────────────
class CustomToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const CustomToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 26,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: value ? C.accentOf(dark) : C.surface3(dark),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment:
              value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String formatName(String raw) {
  if (raw.contains(',')) {
    final parts = raw.split(',');
    if (parts.length >= 2) {
      return '${parts[1].trim()} ${parts[0].trim()}';
    }
  }
  return raw;
}

/// "Smith, John" → "JS". Falls back to "?" for an empty name.
String initialsFor(String raw) {
  final parts =
      formatName(raw).split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  return parts.isNotEmpty ? parts[0][0].toUpperCase() : '?';
}

/// "2026-05-03" → "May 3".
String formatShortMeetDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
      'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[d.month - 1]} ${d.day}';
}