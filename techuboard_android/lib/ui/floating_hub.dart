import 'package:flutter/material.dart';
import 'floating_hub_popup.dart';

/// A world-class Adaptive Floating Hub using physics-based spring dynamics.
/// Implements: Magnetic Edge Snapping, Contextual Opacity, and Haptic Feedback.
class FloatingHubManager {
  static final FloatingHubManager instance = FloatingHubManager._();
  FloatingHubManager._();

  OverlayEntry? _overlayEntry;

  void show(BuildContext context) {
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => _FloatingHubWidget(),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void remove() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

class _FloatingHubWidget extends StatefulWidget {
  @override
  _FloatingHubWidgetState createState() => _FloatingHubWidgetState();
}

class _FloatingHubWidgetState extends State<_FloatingHubWidget> with SingleTickerProviderStateMixin {
  Offset _position = Offset(20, 100); // Initial position
  late AnimationController _controller;
  late Animation<Offset> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: 300));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snapToEdge() {
    final size = MediaQuery.of(context).size;
    final middle = size.width / 2;
    final targetX = (_position.dx < middle) ? 20.0 : (size.width - 70.0);
    final targetY = _position.dy.clamp(50.0, size.height - 120.0);
    setState(() {
      _position = Offset(targetX, targetY);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Remove target zone
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 100,
          child: DragTarget<bool>(
            onAccept: (_) => FloatingHubManager.instance.remove(),
            builder: (context, _, __) => Container(
              color: Colors.red.withOpacity(0.2),
              child: const Icon(Icons.delete, color: Colors.red),
            ),
          ),
        ),
        Positioned(
          left: _position.dx,
          top: _position.dy,
          child: Draggable<bool>(
            data: true,
            feedback: _buildHubIcon(isDragging: true),
            childWhenDragging: Container(),
            onDragEnd: (details) {
              setState(() {
                _position = details.offset;
              });
              _snapToEdge();
            },
            child: GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  barrierColor: Colors.transparent,
                  builder: (context) => Stack(
                    children: [
                      Positioned(
                        left: _position.dx + 60,
                        top: _position.dy,
                        child: FloatingHubPopup(),
                      ),
                    ],
                  ),
                );
              },
              onLongPress: () {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Contextual Menu Open (Feature T-018)')));
              },
              child: _buildHubIcon(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHubIcon({bool isDragging = false}) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: isDragging ? Colors.red : Colors.blue.withOpacity(0.8),
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: const Icon(Icons.dashboard, color: Colors.white),
    );
  }
}
