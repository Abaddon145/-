import 'package:flutter/material.dart';

/// Left-edge swipe that pops a pushed route without sliding the page underneath.
/// Tab roots are left alone because their navigator cannot pop.
class IosEdgeBack extends StatefulWidget {
  const IosEdgeBack({super.key, required this.child});
  final Widget child;

  @override
  State<IosEdgeBack> createState() => _IosEdgeBackState();
}

class _IosEdgeBackState extends State<IosEdgeBack> {
  int? _pointer;
  double _dx = 0;
  double _dy = 0;

  void _reset() {
    _pointer = null;
    _dx = 0;
    _dy = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.iOS) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.localPosition.dx <= 28) {
          _pointer = event.pointer;
          _dx = 0;
          _dy = 0;
        } else {
          _reset();
        }
      },
      onPointerMove: (event) {
        if (event.pointer != _pointer) return;
        _dx += event.delta.dx;
        _dy += event.delta.dy;
      },
      onPointerUp: (event) {
        if (event.pointer == _pointer && _dx > 72 && _dx > _dy.abs() * 1.4) {
          final navigator = Navigator.of(context);
          if (navigator.canPop()) navigator.maybePop();
        }
        _reset();
      },
      onPointerCancel: (event) {
        if (event.pointer == _pointer) _reset();
      },
      child: widget.child,
    );
  }
}
