import 'package:flutter/material.dart';

// ─── Theme mode notifier ──────────────────────────────────────────────────────
final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

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
  static const accent = Color(0xFFB80C09);
  static const accentAlt = Color(0xFFE8372D);

    static Color bg(bool dark) =>
      dark ? const Color(0xFF0F0F0F) : const Color(0xFFF8F7F4);

  static Color surface(bool dark) =>
      dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);

  static Color surface2(bool dark) =>
      dark ? const Color(0xFF2C2C2E) : const Color(0xFFF0EDEA);

  static Color surface3(bool dark) =>
      dark ? const Color(0xFF3A3A3C) : const Color(0xFFE8E5E2);

  static Color border(bool dark) =>
      dark ? const Color(0x1AFFFFFF) : const Color(0xFFE0DEDB);

  static Color text1(bool dark) =>
      dark ? const Color(0xFFEFEEE6) : const Color(0xFF141301);

  static Color text2(bool dark) =>
      dark ? const Color(0xFF9E9C8A) : const Color(0xFF5C5A4A);

  static Color text3(bool dark) =>
      dark ? const Color(0xFF5C5A4A) : const Color(0xFF9E9C8A);

  static Color accentSoft(bool dark) =>
      dark ? const Color(0x1AB80C09) : const Color(0xFFFDECEC);
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

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
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
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
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
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 26,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: value ? C.accent : const Color(0xFF5C5A4A),
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