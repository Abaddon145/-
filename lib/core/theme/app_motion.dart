import 'package:flutter/material.dart';

abstract final class AppMotion {
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  static Duration duration(BuildContext context, [int milliseconds = 220]) =>
      reduced(context) ? Duration.zero : Duration(milliseconds: milliseconds);
  static AnimationStyle sheet(BuildContext context) => reduced(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: Duration(milliseconds: 260),
          reverseDuration: Duration(milliseconds: 180),
        );
}

/// A bounded touch response. Listener leaves the child's gesture/semantics intact.
class PressFeedback extends StatefulWidget {
  const PressFeedback({super.key, required this.child});
  final Widget child;
  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  int? _pointer;
  Offset? _origin;
  bool _pressed = false;
  void _release() {
    _pointer = null;
    _origin = null;
    if (_pressed && mounted) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (_pointer != null) return;
      _pointer = event.pointer;
      _origin = event.position;
      setState(() => _pressed = true);
    },
    onPointerMove: (event) {
      if (event.pointer == _pointer &&
          _origin != null &&
          (event.position - _origin!).distance > 8) {
        _release();
      }
    },
    onPointerUp: (event) {
      if (event.pointer == _pointer) _release();
    },
    onPointerCancel: (event) {
      if (event.pointer == _pointer) _release();
    },
    child: AnimatedScale(
      scale: _pressed && !AppMotion.reduced(context) ? .982 : 1,
      duration: AppMotion.duration(context, 120),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}

/// No repeating shimmer or offscreen controller; animates only a changed value.
class SmoothProgress extends StatelessWidget {
  const SmoothProgress({super.key, required this.value});
  final double value;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.clamp(0, 1)),
    duration: AppMotion.duration(context, 300),
    curve: Curves.easeOutCubic,
    builder: (context, value, _) => LinearProgressIndicator(value: value),
  );
}

/// A single local fade/scale; never slides one route over another.
class RevealContent extends StatelessWidget {
  const RevealContent({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: AppMotion.reduced(context) ? 1 : 0, end: 1),
    duration: AppMotion.duration(context),
    curve: Curves.easeOutCubic,
    child: RepaintBoundary(child: child),
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.scale(scale: .985 + .015 * value, child: child),
    ),
  );
}
