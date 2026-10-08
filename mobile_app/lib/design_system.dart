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

// ─── Drop toggle ──────────────────────────────────────────────────────────────

/// A pick-one switch folded down to its current choice. Tap it and the
/// other choices drop down below it, in the same sliding-pill style as
/// [SegmentToggle]; tap one, or press and slide down and let go on one.
/// Tapping anywhere else folds it back up.
class DropToggle extends StatefulWidget {
  final List<String> options;
  final String value;
  final bool dark;
  final ValueChanged<String> onChanged;
  final double width;
  final double height;

  const DropToggle({
    super.key,
    required this.options,
    required this.value,
    required this.dark,
    required this.onChanged,
    this.width = 64,
    this.height = 42,
  });

  @override
  State<DropToggle> createState() => _DropToggleState();
}

class _DropToggleState extends State<DropToggle> with SingleTickerProviderStateMixin {
  static const _pad = 3.0;

  final _link = LayerLink();
  final _portal = OverlayPortalController();
  late final _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 220),
  );

  /// The thumb's row while a finger slides it, null otherwise.
  double? _slide;

  /// A row just picked, shown until the parent passes the new value.
  int? _picked;

  double get _row => widget.height - 2 * _pad;
  int get _n => widget.options.length;
  int get _index => widget.options.indexOf(widget.value).clamp(0, _n - 1);

  @override
  void didUpdateWidget(DropToggle old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _picked = null;
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  void _show() {
    if (!_portal.isShowing) setState(_portal.show);
    _open.animateTo(1, curve: Curves.easeOutCubic);
  }

  Future<void> _hide() async {
    await _open.animateBack(0, curve: Curves.easeInCubic);
    if (mounted && _open.value == 0 && _portal.isShowing) setState(_portal.hide);
  }

  int _rowAt(double dy) => ((dy - _pad) / _row).floor().clamp(0, _n - 1);

  void _slideTo(double dy) {
    final at = ((dy - _pad - _row / 2) / _row).clamp(0.0, _n - 1.0);
    final before = _slide?.round();
    if (before != null && before != at.round()) HapticFeedback.selectionClick();
    setState(() => _slide = at);
  }

  void _startSlide(double dy) {
    HapticFeedback.lightImpact();
    _show();
    _slideTo(dy);
  }

  void _endSlide() {
    final at = _slide;
    if (at == null) return;
    setState(() => _slide = null);
    _pick(at.round());
  }

  void _pick(int i) {
    if (i != _index) {
      HapticFeedback.selectionClick();
      setState(() => _picked = i);
      widget.onChanged(widget.options[i]);
    }
    // Let the thumb reach the row before folding up.
    Future.delayed(const Duration(milliseconds: 140), () {
      if (mounted) _hide();
    });
  }

  /// The control at openness [t]: 0 shows only the current choice, 1 all.
  Widget _body(double t) {
    final dark = widget.dark;
    final selected = _picked ?? _index;
    final thumb = _slide ?? selected.toDouble();
    final hover = _slide?.round() ?? selected;
    final row = _row;
    return Container(
      width: widget.width,
      height: widget.height + (_n - 1) * row * t,
      decoration: BoxDecoration(
        color: C.surface2(dark),
        borderRadius: BorderRadius.circular(widget.height / 2),
        boxShadow: [
          if (t > 0)
            BoxShadow(
              color: Colors.black.withValues(alpha: (dark ? 0.5 : 0.16) * t),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: Stack(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: thumb),
            duration: _slide != null ? Duration.zero : const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            builder: (context, at, _) => Positioned(
              left: _pad,
              right: _pad,
              top: _pad + row * at * t,
              height: row,
              child: AnimatedScale(
                scale: _slide != null ? 1.08 : 1,
                duration: const Duration(milliseconds: 200),
                curve: kSpring,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: C.accentOf(dark),
                    borderRadius: BorderRadius.circular(row / 2),
                  ),
                ),
              ),
            ),
          ),
          for (var i = 0; i < _n; i++)
            if (t > 0 || i == selected)
              Positioned(
                left: _pad,
                right: _pad,
                top: _pad + row * i * t,
                height: row,
                child: Opacity(
                  opacity: i == selected ? 1 : t,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 150),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: i == hover ? Colors.white : C.text2(dark),
                          ),
                          child: Text(widget.options[i]),
                        ),
                        // The fold-down hint, only while closed.
                        if (i == selected && t < 1)
                          ClipRect(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              widthFactor: 1 - t,
                              child: Opacity(
                                opacity: 1 - t,
                                child: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _hide,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              child: Align(
                alignment: Alignment.topLeft,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _pick(_rowAt(d.localPosition.dy)),
                  onVerticalDragStart: (d) => _startSlide(d.localPosition.dy),
                  onVerticalDragUpdate: (d) => _slideTo(d.localPosition.dy),
                  onVerticalDragEnd: (_) => _endSlide(),
                  onLongPressStart: (d) => _startSlide(d.localPosition.dy),
                  onLongPressMoveUpdate: (d) => _slideTo(d.localPosition.dy),
                  onLongPressEnd: (_) => _endSlide(),
                  child: AnimatedBuilder(
                    animation: _open,
                    builder: (context, _) => _body(_open.value),
                  ),
                ),
              ),
            ),
          ],
        ),
        // While open, the copy in the overlay stands in for this one.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            _show();
          },
          onVerticalDragStart: (d) => _startSlide(d.localPosition.dy),
          onVerticalDragUpdate: (d) => _slideTo(d.localPosition.dy),
          onVerticalDragEnd: (_) => _endSlide(),
          onLongPressStart: (d) => _startSlide(d.localPosition.dy),
          onLongPressMoveUpdate: (d) => _slideTo(d.localPosition.dy),
          onLongPressEnd: (_) => _endSlide(),
          child: AnimatedBuilder(
            animation: _open,
            builder: (context, _) => Opacity(
              opacity: _open.value == 0 && !_portal.isShowing ? 1 : 0,
              child: SizedBox(width: widget.width, height: widget.height, child: _body(0)),
            ),
          ),
        ),
      ),
    );
  }
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