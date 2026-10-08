import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Spring curve ─────────────────────────────────────────────────────────────
const kSpring = SpringCurve();

class SpringCurve extends Curve {
  const SpringCurve();
  @override
  double transform(double t) {
    return 1 - (1 - t) * (1 - t) * (1 - t);
  }
}

/// A damped spring's motion as a curve: a quick start and a soft settle
/// with a slight overshoot, like iOS. [damping] below 1 overshoots.
class SpringPhysicsCurve extends Curve {
  final double damping;

  const SpringPhysicsCurve({this.damping = 0.72});

  @override
  double transformInternal(double t) {
    // Fast enough to settle within the curve's duration.
    const w = 9.0;
    final wd = w * math.sqrt(1 - damping * damping);
    return 1 -
        math.exp(-damping * w * t) *
            (math.cos(wd * t) + damping * w / wd * math.sin(wd * t));
  }
}

const kFluid = SpringPhysicsCurve();

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

// ─── Cards ────────────────────────────────────────────────────────────────────

/// Card surface: a soft shadow in light mode, a faint outline in dark mode,
/// where shadows don't show on black.
BoxDecoration cardDecoration(bool dark, {double radius = 20, Color? color}) => BoxDecoration(
      color: color ?? C.surface(dark),
      borderRadius: BorderRadius.circular(radius),
      border: dark ? Border.all(color: C.border(dark), width: 0.5) : null,
      boxShadow: dark
          ? null
          : const [
              BoxShadow(color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 6)),
              BoxShadow(color: Color(0x08000000), blurRadius: 3, offset: Offset(0, 1)),
            ],
    );

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
      decoration: cardDecoration(dark),
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

  /// 30 for compact switches; 40 for a screen's main tabs.
  final double height;
  final double fontSize;

  const SegmentToggle({
    super.key,
    required this.options,
    required this.value,
    required this.dark,
    required this.onChanged,
    this.height = 30,
    this.fontSize = 12,
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
      height: widget.height,
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
                              fontSize: widget.fontSize,
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

// ─── Type ─────────────────────────────────────────────────────────────────────

/// Big page title ("PR Vault", "Settings").
TextStyle pageTitleStyle(bool dark) => TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.1,
      color: C.text1(dark),
    );

/// How strongly [topWash] starts.
double washAlpha(bool dark) => dark ? 0.20 : 0.09;

/// The soft team-color wash at the top of a page, fading into the page.
BoxDecoration topWash(bool dark) => BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          C.accentOf(dark).withValues(alpha: washAlpha(dark)),
          C.accentOf(dark).withValues(alpha: 0),
        ],
      ),
    );

/// A page header on the [topWash]. The wash's top color also extends far
/// above it, so pulling a page down past the top shows more of it instead
/// of the plain page color. [base] is the color behind the page.
class WashHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool dark;
  final Color? base;

  const WashHeader({
    super.key,
    required this.child,
    required this.dark,
    this.padding = EdgeInsets.zero,
    this.base,
  });

  @override
  Widget build(BuildContext context) {
    final top = Color.alphaBlend(
      C.accentOf(dark).withValues(alpha: washAlpha(dark)),
      base ?? C.bg(dark),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: -1000,
          height: 1000,
          child: ColoredBox(color: top),
        ),
        // Full width even when the content is narrow (a lone title).
        SizedBox(
          width: double.infinity,
          child: Container(decoration: topWash(dark), padding: padding, child: child),
        ),
      ],
    );
  }
}

// ─── Section title ────────────────────────────────────────────────────────────

/// Bold row title ("Personal Records"), with an optional trailing widget.
class SectionTitle extends StatelessWidget {
  final String text;
  final bool dark;
  final Widget? trailing;

  const SectionTitle(this.text, {super.key, required this.dark, this.trailing});

  static TextStyle style(bool dark) => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: C.text1(dark),
      );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(text, style: style(dark))),
        ?trailing,
      ],
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

  /// Shows a clear button while there's text; called after clearing.
  final VoidCallback? onClear;

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
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: C.field(dark),
        borderRadius: BorderRadius.circular(16),
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
          if (onClear != null)
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => controller.text.isEmpty
                  ? const SizedBox(width: 16)
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        controller.clear();
                        onClear!();
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
                        child: Icon(Icons.cancel, size: 18, color: C.text3(dark)),
                      ),
                    ),
            )
          else
            const SizedBox(width: 16),
        ],
      ),
    );
  }
}

// ─── Primary button ───────────────────────────────────────────────────────────

enum ButtonTone {
  /// Team red, for the main action.
  accent,

  /// Black in light mode, white in dark: a strong neutral action.
  ink,

  /// Soft fill, for secondary actions like Cancel.
  soft,
}

/// Full-width rounded button. Shows a spinner and ignores taps while
/// [loading].
class PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  final bool dark;
  final ButtonTone tone;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.dark,
    this.loading = false,
    this.tone = ButtonTone.accent,
  });

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color ink) = switch (tone) {
      ButtonTone.accent => (C.accentOf(dark), Colors.white),
      ButtonTone.ink => (C.text1(dark), dark ? Colors.black : Colors.white),
      ButtonTone.soft => (C.surface2(dark), C.text1(dark)),
    };
    return PressScale(
      onTap: loading ? () {} : onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(16),
          boxShadow: tone == ButtonTone.accent
              ? [BoxShadow(color: fill.withValues(alpha: 0.22), blurRadius: 14, offset: const Offset(0, 4))]
              : null,
        ),
        child: Center(
          child: loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: ink, strokeWidth: 2),
                )
              : Text(label, style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

// ─── Chips ────────────────────────────────────────────────────────────────────

/// Filter chip. Selected is solid ink (black in light mode, white in dark),
/// so the team red stays free for highlights.
class AppChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;
  final bool small;

  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.dark,
    required this.onTap,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      pressedScale: 0.96,
      onTap: () {
        if (selected) return;
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: kSpring,
        height: small ? 32 : 36,
        padding: EdgeInsets.symmetric(horizontal: small ? 13 : 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? C.text1(dark) : C.surface2(dark),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: small ? 12.5 : 13.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            color: selected ? (dark ? Colors.black : Colors.white) : C.text2(dark),
          ),
        ),
      ),
    );
  }
}

/// A horizontal row of [AppChip]s that scrolls edge to edge.
class ChipRow extends StatelessWidget {
  final List<Widget> chips;
  final double height;

  const ChipRow({super.key, required this.chips, this.height = 52});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Center(child: chips[i]),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

/// Centered icon, title and message for empty lists and errors, with an
/// optional action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool dark;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.dark,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(shape: BoxShape.circle, color: C.surface2(dark)),
            child: Icon(icon, size: 28, color: C.text2(dark)),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: C.text1(dark)),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: C.text3(dark)),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            PressScale(
              onTap: onAction!,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                decoration: BoxDecoration(color: C.text1(dark), borderRadius: BorderRadius.circular(100)),
                child: Text(
                  actionLabel!,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: dark ? Colors.black : Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Confirm dialog ───────────────────────────────────────────────────────────

/// "Are you sure?" as a card that rises from the bottom, with the action and
/// Cancel as big buttons. True if confirmed.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? message,
  Widget? body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    // Size to the card, not the default 9/16 of the screen.
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (context) => SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
          decoration: cardDecoration(dark, radius: 32, color: C.sheet(dark)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: C.text1(dark))),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message, style: TextStyle(fontSize: 15, height: 1.4, color: C.text2(dark))),
              ],
              if (body != null) ...[
                const SizedBox(height: 16),
                body,
              ],
              const SizedBox(height: 22),
              PrimaryButton(
                label: confirmLabel,
                dark: dark,
                tone: destructive ? ButtonTone.accent : ButtonTone.ink,
                onTap: () => Navigator.pop(context, true),
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                label: cancelLabel,
                dark: dark,
                tone: ButtonTone.soft,
                onTap: () => Navigator.pop(context, false),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return confirmed ?? false;
}

// ─── Filter pill ──────────────────────────────────────────────────────────────

/// One column of a [FilterPill]: pick one of [options].
class FilterGroup {
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;

  const FilterGroup({
    required this.options,
    required this.value,
    required this.onChanged,
  });
}

/// Filters folded into one pill that reads like "Outdoor · All". Tap it and
/// it springs open downward into a column per filter, the highlight
/// splitting into one per column. Tap a choice, or press and slide down and
/// let go on one; it folds back up shortly after a pick, or when you tap
/// anywhere else.
class FilterPill extends StatefulWidget {
  final List<FilterGroup> groups;
  final bool dark;
  final double height;

  const FilterPill({
    super.key,
    required this.groups,
    required this.dark,
    this.height = 42,
  });

  @override
  State<FilterPill> createState() => _FilterPillState();
}

class _PillLayout {
  final double closedWidth;
  final double openWidth;
  final double openHeight;
  final List<double> columnWidths;

  const _PillLayout(this.closedWidth, this.openWidth, this.openHeight, this.columnWidths);
}

class _FilterPillState extends State<FilterPill> with SingleTickerProviderStateMixin {
  static const _pad = 3.0;
  static const _gap = 4.0;
  static const _labelStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);

  /// The app's text style with the label size. Set explicitly: the open
  /// panel lives in the overlay, outside the screen's text styling.
  TextStyle _style = _labelStyle;

  // Opening overshoots a touch; closing settles without a bounce.
  static const _openSpring = SpringDescription(mass: 1, stiffness: 420, damping: 32);
  static const _closeSpring = SpringDescription(mass: 1, stiffness: 520, damping: 46);

  final _link = LayerLink();
  final _portal = OverlayPortalController();
  late final _open = AnimationController.unbounded(vsync: this);
  Timer? _autoClose;
  bool _pressed = false;

  /// While a finger slides: its column and the highlight's (fractional) row.
  int? _slideColumn;
  double? _slideRow;
  bool _slideFromClosed = false;

  /// Rows just picked, shown until the parent passes the new values.
  final _picked = <int, int>{};

  double get _row => widget.height - 2 * _pad;

  @override
  void didUpdateWidget(FilterPill old) {
    super.didUpdateWidget(old);
    _picked.clear();
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    _open.dispose();
    super.dispose();
  }

  _PillLayout _layout(BuildContext context) {
    _style = (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).merge(_labelStyle);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    double width(String text) => (TextPainter(
          text: TextSpan(text: text, style: _style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout())
            .width;
    final widest = [
      for (final g in widget.groups) g.options.map(width).fold(0.0, math.max),
    ];
    final columns = [for (final w in widest) w + 28];
    final summary = widest.fold(0.0, (a, b) => a + b) +
        width(' · ') * (widget.groups.length - 1);
    final closed = 2 * _pad + 24 + summary + 18;
    var open = 2 * _pad + columns.fold(0.0, (a, b) => a + b) + _gap * (columns.length - 1);
    if (open < closed) {
      final extra = (closed - open) / columns.length;
      for (var i = 0; i < columns.length; i++) {
        columns[i] += extra;
      }
      open = closed;
    }
    final rows = widget.groups.map((g) => g.options.length).fold(1, math.max);
    return _PillLayout(closed, open, 2 * _pad + _row * rows, columns);
  }

  int _selected(int column) {
    final g = widget.groups[column];
    return _picked[column] ?? g.options.indexOf(g.value).clamp(0, g.options.length - 1);
  }

  void _show() {
    _autoClose?.cancel();
    if (!_portal.isShowing) setState(_portal.show);
    _open.animateWith(SpringSimulation(_openSpring, _open.value, 1, 0));
  }

  void _hide() {
    _autoClose?.cancel();
    _open.animateWith(SpringSimulation(_closeSpring, _open.value, 0, 0)).then((_) {
      if (!mounted || _open.value > 0.02) return;
      _open.value = 0;
      if (_portal.isShowing) setState(_portal.hide);
    });
  }

  /// The column under [dx], measured across the open layout.
  int _columnAt(double dx, _PillLayout l) {
    var x = _pad;
    for (var c = 0; c < l.columnWidths.length; c++) {
      x += l.columnWidths[c] + _gap;
      if (dx < x - _gap / 2) return c;
    }
    return l.columnWidths.length - 1;
  }

  double _rowAt(int column, double dy) {
    final last = widget.groups[column].options.length - 1.0;
    return ((dy - _pad - _row / 2) / _row).clamp(0.0, last);
  }

  void _startSlide(double dx, double dy, _PillLayout l, {required bool fromClosed}) {
    HapticFeedback.lightImpact();
    _autoClose?.cancel();
    _slideFromClosed = fromClosed;
    final column = _columnAt(dx, l);
    setState(() {
      _slideColumn = column;
      _slideRow = _rowAt(column, dy);
    });
    _show();
  }

  void _slideTo(double dy) {
    final column = _slideColumn;
    if (column == null) return;
    final at = _rowAt(column, dy);
    if (_slideRow != null && _slideRow!.round() != at.round()) {
      HapticFeedback.selectionClick();
    }
    setState(() => _slideRow = at);
  }

  /// The row a column's highlight is on: under the finger, or the choice.
  double _thumbRow(int column) =>
      _slideColumn == column ? (_slideRow ?? _selected(column).toDouble()) : _selected(column).toDouble();

  void _endSlide() {
    final column = _slideColumn;
    final at = _slideRow;
    setState(() {
      _slideColumn = null;
      _slideRow = null;
    });
    if (column != null && at != null) _pick(column, at.round());
  }

  void _pick(int column, int row) {
    final g = widget.groups[column];
    if (row != _selected(column)) {
      HapticFeedback.selectionClick();
      setState(() => _picked[column] = row);
      g.onChanged(g.options[row]);
    }
    // Fold up once the highlight has settled, unless another choice comes.
    _autoClose?.cancel();
    _autoClose = Timer(Duration(milliseconds: _slideFromClosed ? 260 : 700), _hide);
    _slideFromClosed = false;
  }

  /// The pill at openness [t]: 0 closed, 1 open (a spring, so a little past
  /// 1 while it settles). [width] grows leftward from the right edge.
  Widget _body(double t, _PillLayout l) {
    final dark = widget.dark;
    final shown = t.clamp(0.0, 1.0);
    final w = l.closedWidth + (l.openWidth - l.closedWidth) * t;
    final h = widget.height + (l.openHeight - widget.height) * t;
    final left = w - l.openWidth; // the open layout's left edge, right-aligned
    final closedThumb = Rect.fromLTWH(w - l.closedWidth + _pad, _pad, l.closedWidth - 2 * _pad, _row);

    Rect cell(int column, double row) {
      var x = left + _pad;
      for (var c = 0; c < column; c++) {
        x += l.columnWidths[c] + _gap;
      }
      return Rect.fromLTWH(x, _pad + _row * row, l.columnWidths[column], _row);
    }

    final summary = [
      for (var c = 0; c < widget.groups.length; c++) widget.groups[c].options[_selected(c)],
    ].join(' · ');

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: C.surface2(dark),
        borderRadius: BorderRadius.circular(widget.height / 2 - 3 * shown),
        boxShadow: [
          if (shown > 0)
            BoxShadow(
              color: Colors.black.withValues(alpha: (dark ? 0.5 : 0.16) * shown),
              blurRadius: 28,
              offset: Offset(0, 12 * shown),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.height / 2 - 3 * shown),
        child: Stack(
          children: [
            // One highlight per column. Closed they sit on top of each other
            // as one; opening splits them apart to their rows.
            for (var c = 0; c < widget.groups.length; c++)
              TweenAnimationBuilder<double>(
                tween: Tween(end: _thumbRow(c)),
                duration: _slideColumn == c ? Duration.zero : const Duration(milliseconds: 420),
                curve: kFluid,
                builder: (context, row, _) => Positioned.fromRect(
                  rect: Rect.lerp(closedThumb, cell(c, row), t)!,
                  child: AnimatedScale(
                    scale: _slideColumn == c ? 1.06 : 1,
                    duration: const Duration(milliseconds: 220),
                    curve: kFluid,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: C.accentOf(dark),
                        borderRadius: BorderRadius.circular(_row / 2),
                      ),
                    ),
                  ),
                ),
              ),
            // The summary fades out as the pill opens.
            if (shown < 0.4)
              Positioned.fromRect(
                rect: closedThumb,
                child: Opacity(
                  opacity: (1 - shown * 2.5).clamp(0.0, 1.0),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(summary, style: _style.copyWith(color: Colors.white)),
                        const SizedBox(width: 2),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            // The choices fade in a row at a time.
            if (shown > 0.3)
              for (var c = 0; c < widget.groups.length; c++)
                for (var r = 0; r < widget.groups[c].options.length; r++)
                  Positioned.fromRect(
                    rect: cell(c, r.toDouble()),
                    child: Builder(builder: (context) {
                      final o = ((shown - 0.35 - 0.08 * r) / 0.4).clamp(0.0, 1.0);
                      final on = _thumbRow(c).round() == r;
                      return Opacity(
                        opacity: o,
                        child: Transform.translate(
                          offset: Offset(0, (1 - o) * -6),
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 160),
                              style: _style.copyWith(color: on ? Colors.white : C.text2(dark)),
                              child: Text(widget.groups[c].options[r]),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = _layout(context);
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _hide),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.topRight,
              child: AnimatedBuilder(
                animation: _open,
                builder: (context, _) {
                  final w = l.closedWidth + (l.openWidth - l.closedWidth) * _open.value;
                  // Positions as if the panel were fully open.
                  Offset open(Offset p) => Offset(p.dx - (w - l.openWidth), p.dy);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _autoClose?.cancel(),
                    onTapUp: (d) {
                      final p = open(d.localPosition);
                      final c = _columnAt(p.dx, l);
                      final rows = widget.groups[c].options.length;
                      _pick(c, ((p.dy - _pad) / _row).floor().clamp(0, rows - 1));
                    },
                    onVerticalDragStart: (d) {
                      final p = open(d.localPosition);
                      _startSlide(p.dx, p.dy, l, fromClosed: false);
                    },
                    onVerticalDragUpdate: (d) => _slideTo(d.localPosition.dy),
                    onVerticalDragEnd: (_) => _endSlide(),
                    onLongPressStart: (d) {
                      final p = open(d.localPosition);
                      _startSlide(p.dx, p.dy, l, fromClosed: false);
                    },
                    onLongPressMoveUpdate: (d) => _slideTo(d.localPosition.dy),
                    onLongPressEnd: (_) => _endSlide(),
                    child: _body(_open.value, l),
                  );
                },
              ),
            ),
          ],
        ),
        // While open, the copy in the overlay stands in for this one.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) {
            setState(() => _pressed = false);
            HapticFeedback.selectionClick();
            _show();
          },
          onVerticalDragStart: (d) => _startSlide(
              d.localPosition.dx + l.openWidth - l.closedWidth, d.localPosition.dy, l,
              fromClosed: true),
          onVerticalDragUpdate: (d) => _slideTo(d.localPosition.dy),
          onVerticalDragEnd: (_) => _endSlide(),
          onLongPressStart: (d) => _startSlide(
              d.localPosition.dx + l.openWidth - l.closedWidth, d.localPosition.dy, l,
              fromClosed: true),
          onLongPressMoveUpdate: (d) => _slideTo(d.localPosition.dy),
          onLongPressEnd: (_) => _endSlide(),
          child: AnimatedScale(
            scale: _pressed ? 0.95 : 1,
            duration: const Duration(milliseconds: 180),
            curve: kFluid,
            child: Opacity(
              opacity: _portal.isShowing ? 0 : 1,
              child: SizedBox(width: l.closedWidth, height: widget.height, child: _body(0, l)),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bob ──────────────────────────────────────────────────────────────────────

/// Gently moves [child] up and down a few times, to hint it can be
/// dragged that way. Still when the system asks for reduced motion.
class Bob extends StatefulWidget {
  final Widget child;
  final double distance;

  const Bob({super.key, required this.child, this.distance = 3});

  @override
  State<Bob> createState() => _BobState();
}

class _BobState extends State<Bob> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.repeat(count: 3);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -widget.distance * math.sin(_c.value * math.pi * 2).abs()),
        child: child,
      ),
      child: widget.child,
    );
  }
}

// ─── One-time tip ────────────────────────────────────────────────────────────

/// A small bubble under [child] the first time it's shown, pointing at it.
/// It doesn't block touches: the first tap anywhere dismisses it for good.
class OneTimeTip extends StatefulWidget {
  /// Remembered once seen, so the tip never shows again.
  final String id;
  final String message;
  final Widget child;

  const OneTimeTip({super.key, required this.id, required this.message, required this.child});

  @override
  State<OneTimeTip> createState() => _OneTimeTipState();
}

class _OneTimeTipState extends State<OneTimeTip> with SingleTickerProviderStateMixin {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  // A beat after the screen settles, then a soft pop in.
  late final _appear = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final _intro = CurvedAnimation(parent: _appear, curve: const Interval(0.45, 1, curve: kFluid));

  String get _key => 'tip_seen:${widget.id}';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_key) ?? false) return;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(_portal.show);
    _appear.forward();
  }

  Future<void> _dismiss() async {
    if (!_portal.isShowing) return;
    await _appear.animateBack(0, duration: const Duration(milliseconds: 180));
    if (mounted) setState(_portal.hide);
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
        .merge(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dark ? Colors.black : Colors.white));
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Stack(
          children: [
            // Sees the first touch anywhere without taking it.
            Positioned.fill(
              child: Listener(behavior: HitTestBehavior.translucent, onPointerDown: (_) => _dismiss()),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 10),
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _intro,
                  builder: (context, child) => Opacity(
                    opacity: _intro.value.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.85 + 0.15 * _intro.value,
                      alignment: Alignment.topRight,
                      child: child,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 22),
                        child: CustomPaint(
                          size: const Size(16, 8),
                          painter: _TipArrowPainter(dark ? Colors.white : const Color(0xFF1C1C1E)),
                        ),
                      ),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 240),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: dark ? Colors.white : const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 18, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: Text(widget.message, style: style),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

class _TipArrowPainter extends CustomPainter {
  final Color color;
  const _TipArrowPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TipArrowPainter old) => old.color != color;
}

// ─── Brand ────────────────────────────────────────────────────────────────────

/// The app icon.
class AppIcon extends StatelessWidget {
  static const asset = 'assets/brand/icon.png';
  final double size;

  const AppIcon({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.23),
      child: Image.asset(asset, width: size, height: size, filterQuality: FilterQuality.medium),
    );
  }
}

/// The icon and "PR Vault", in white, for the red screens.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(),
        SizedBox(width: 10),
        Text(
          'PR Vault',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: Colors.white),
        ),
      ],
    );
  }
}

/// Red gradient with a running track drawn across it and a runner going
/// round the inside lane: the sign-in screen and the intro.
class TrackBackdrop extends StatefulWidget {
  final bool dark;

  const TrackBackdrop({super.key, required this.dark});

  @override
  State<TrackBackdrop> createState() => _TrackBackdropState();
}

class _TrackBackdropState extends State<TrackBackdrop> with SingleTickerProviderStateMixin {
  late final _lap = AnimationController(vsync: this, duration: const Duration(seconds: 9));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _lap.stop();
    } else if (!_lap.isAnimating) {
      _lap.repeat();
    }
  }

  @override
  void dispose() {
    _lap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.dark
        ? const [Color(0xFF6E0E0A), Color(0xFF2A0604), Color(0xFF000000)]
        : const [Color(0xFFE8372D), Color(0xFFC8140F), Color(0xFF7E0A06)];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: colors),
      ),
      child: RepaintBoundary(
        child: CustomPaint(painter: _TrackPainter(_lap), size: Size.infinite),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  final Animation<double> lap;

  _TrackPainter(this.lap) : super(repaint: lap);

  static const _lanes = 6;
  static const _laneWidth = 15.0;

  /// A running track's shape: two straights joined by semicircles.
  Path _stadium(Offset center, double straight, double radius) {
    final rect = Rect.fromCenter(center: center, width: straight + 2 * radius, height: 2 * radius);
    return Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.34);
    final straight = size.width * 0.42;
    final inner = size.width * 0.2;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.5);
    canvas.translate(-center.dx, -center.dy);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.11);
    for (var i = 0; i <= _lanes; i++) {
      canvas.drawPath(_stadium(center, straight, inner + i * _laneWidth), line);
    }

    // The runner, in lane two, with a fading trail behind.
    final lane = _stadium(center, straight, inner + 1.5 * _laneWidth);
    final metric = lane.computeMetrics().first;
    final length = metric.length;
    final at = lap.value * length;
    const dots = 24;
    const trail = 110.0;
    for (var k = dots; k > 0; k--) {
      final behind = (at - trail * k / dots) % length;
      final p = metric.getTangentForOffset(behind)?.position;
      if (p == null) continue;
      final fade = 1 - k / dots;
      canvas.drawCircle(p, 1 + 2.2 * fade, Paint()..color = Colors.white.withValues(alpha: 0.5 * fade));
    }
    final pos = metric.getTangentForOffset(at)?.position;
    if (pos != null) {
      canvas.drawCircle(pos, 9, Paint()..color = Colors.white.withValues(alpha: 0.18));
      canvas.drawCircle(pos, 4, Paint()..color = Colors.white);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.lap != lap;
}

// ─── Full-screen steps ──────────────────────────────────────────────────────

/// The backdrop for sign-in and onboarding steps: the page color under a
/// tall accent wash, with an optional back button.
class StepScaffold extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;
  final EdgeInsetsGeometry padding;

  const StepScaffold({
    super.key,
    required this.child,
    this.onBack,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: C.bg(dark),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: const Alignment(0, 0.1),
            colors: [
              C.accentOf(dark).withValues(alpha: washAlpha(dark) * 1.4),
              C.accentOf(dark).withValues(alpha: 0),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (onBack != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(alignment: Alignment.centerLeft, child: BackCircle(onTap: onBack!, dark: dark)),
                ),
              Expanded(child: Padding(padding: padding, child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round back button.
class BackCircle extends StatelessWidget {
  final VoidCallback onTap;
  final bool dark;

  const BackCircle({super.key, required this.onTap, required this.dark});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(shape: BoxShape.circle, color: C.surface(dark).withValues(alpha: 0.8)),
        alignment: Alignment.center,
        child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: C.text1(dark)),
      ),
    );
  }
}

/// A step's icon: white on an accent gradient circle with a soft glow.
class HeroIcon extends StatelessWidget {
  final IconData icon;
  final bool dark;

  const HeroIcon({super.key, required this.icon, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [C.accentAlt, C.accentOf(false)],
          ),
          boxShadow: [
            BoxShadow(color: C.accentOf(dark).withValues(alpha: 0.3), blurRadius: 28, offset: const Offset(0, 10)),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 34, color: Colors.white),
      ),
    );
  }
}

/// A step's title and explanation, centered.
class StepHeading extends StatelessWidget {
  final String title;
  final String? body;
  final bool dark;

  const StepHeading({super.key, required this.title, this.body, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.15, color: C.text1(dark)),
        ),
        if (body != null) ...[
          const SizedBox(height: 10),
          Text(body!, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.45, color: C.text2(dark))),
        ],
      ],
    );
  }
}

/// A one-time code shown as a box per digit. An invisible text field over
/// the boxes takes the typing, so paste and code autofill still work.
class CodeCells extends StatelessWidget {
  final TextEditingController controller;
  final int length;
  final ValueChanged<String> onChanged;
  final bool error;
  final bool busy;
  final bool dark;

  const CodeCells({
    super.key,
    required this.controller,
    required this.length,
    required this.onChanged,
    required this.dark,
    this.error = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = C.accentOf(dark);
    return SizedBox(
      height: 60,
      child: Stack(
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: busy ? 0.4 : 1,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final code = controller.text;
                return Row(
                  children: [
                    for (var i = 0; i < length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: C.field(dark),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              width: 1.5,
                              color: error || (!busy && i == code.length) ? accent : Colors.transparent,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            i < code.length ? code[i] : '',
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: C.text1(dark)),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          Positioned.fill(
            child: TextField(
              controller: controller,
              autofocus: true,
              readOnly: busy,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(length),
              ],
              onChanged: onChanged,
              showCursor: false,
              enableInteractiveSelection: false,
              style: const TextStyle(color: Colors.transparent, fontSize: 1),
              decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
            ),
          ),
          if (busy)
            Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: accent, strokeWidth: 2))),
        ],
      ),
    );
  }
}

/// A small text button for secondary choices under a step's main button.
class LinkButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool dark;
  final bool accent;

  const LinkButton({super.key, required this.label, required this.onTap, required this.dark, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final text = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: onTap == null ? C.text3(dark) : (accent ? C.accentOf(dark) : C.text2(dark)),
        ),
      ),
    );
    return onTap == null ? text : PressScale(onTap: onTap!, child: text);
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