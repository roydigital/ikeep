import 'package:flutter/material.dart';

/// Detects a left-edge horizontal swipe and pops the current route.
///
/// A thin (24 dp) gesture strip sits at the left screen edge. When the user
/// swipes right from this strip with sufficient velocity (> 500 dp/s) or drags
/// past 30 % of the screen width, the route is popped — mimicking the iOS-style
/// back gesture on Android.
class SwipeBackWrapper extends StatefulWidget {
  const SwipeBackWrapper({super.key, required this.child});

  final Widget child;

  @override
  State<SwipeBackWrapper> createState() => _SwipeBackWrapperState();
}

class _SwipeBackWrapperState extends State<SwipeBackWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _dragExtent = 0;
  bool _isPopping = false;

  static const double _edgeWidth = 24;
  static const double _popThreshold = 0.3;
  static const double _popVelocity = 500;
  static const Duration _snapDuration = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _snapDuration);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isPopping) return;
    setState(() {
      _dragExtent =
          (_dragExtent + details.delta.dx).clamp(0.0, double.infinity);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isPopping) return;
    final width = MediaQuery.sizeOf(context).width;
    final velocity = details.primaryVelocity ?? 0;

    if (_dragExtent > width * _popThreshold || velocity > _popVelocity) {
      _isPopping = true;
      // Animate off-screen, then pop.
      final start = _dragExtent;
      final target = width;
      _controller.addListener(() {
        if (!mounted) return;
        setState(() {
          _dragExtent = start + (target - start) * _controller.value;
        });
      });
      _controller.forward(from: 0).then((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    } else {
      _snapBack();
    }
  }

  void _snapBack() {
    final start = _dragExtent;
    late final Animation<double> anim;
    anim = Tween<double>(begin: start, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    )..addListener(() {
        if (!mounted) return;
        setState(() => _dragExtent = anim.value);
      });
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dimmed scrim behind the sliding page.
        if (_dragExtent > 0)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(
                alpha:
                    0.4 * (1 - _dragExtent / MediaQuery.sizeOf(context).width),
              ),
            ),
          ),
        // Page content — slides right with the drag.
        Transform.translate(
          offset: Offset(_dragExtent, 0),
          child: widget.child,
        ),
        // Left-edge gesture strip.
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _edgeWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
          ),
        ),
      ],
    );
  }
}
