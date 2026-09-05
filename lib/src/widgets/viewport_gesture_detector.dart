import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'viewport_controller.dart';

/// Multimodal gesture detector for clinical viewports supporting:
/// - Desktop mouse: Left-drag for W/L, Right-drag or Shift+Left-drag for Zoom,
///   Middle-drag or Ctrl/Cmd+Left-drag for Pan, Wheel for slice stack scroll, Double-click for Reset.
/// - Mobile touch: 1-finger drag for W/L, 2-finger drag for Pan, 2-finger pinch for Zoom, Double-tap for Reset.
class ViewportGestureDetector extends StatefulWidget {
  final ViewportController controller;
  final Widget child;

  /// Sensitivity multiplier for Window Width / Center adjustments.
  final double windowLevelSensitivity;

  /// Sensitivity multiplier for dynamic zoom adjustments.
  final double zoomSensitivity;

  const ViewportGestureDetector({
    super.key,
    required this.controller,
    required this.child,
    this.windowLevelSensitivity = 2.0,
    this.zoomSensitivity = 0.01,
  });

  @override
  State<ViewportGestureDetector> createState() => _ViewportGestureDetectorState();
}

class _ViewportGestureDetectorState extends State<ViewportGestureDetector> {
  // Multi-touch tracking
  final Map<int, Offset> _touchPointers = {};
  double? _lastPinchDistance;
  Offset? _lastCentroid;

  // Double-tap / double-click tracking
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;

  // Track if a multi-touch gesture just finished to debounce 1-finger drag resumption
  DateTime? _multiTouchEndTime;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      onPointerSignal: _onPointerSignal,
      child: widget.child,
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == ui.PointerDeviceKind.mouse) {
      _handleMouseDown(event);
    } else {
      _touchPointers[event.pointer] = event.localPosition;
      if (_touchPointers.length == 2) {
        final points = _touchPointers.values.toList();
        _lastCentroid = (points[0] + points[1]) / 2.0;
        _lastPinchDistance = (points[0] - points[1]).distance;
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.kind == ui.PointerDeviceKind.mouse) {
      _handleMouseMove(event);
    } else {
      _touchPointers[event.pointer] = event.localPosition;
      _handleTouchMove(event);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.kind == ui.PointerDeviceKind.mouse) {
      _handleMouseUp(event);
    } else {
      _handleTouchUp(event);
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _touchPointers.remove(event.pointer);
    if (_touchPointers.length < 2) {
      _lastPinchDistance = null;
      _lastCentroid = null;
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      // Mouse wheel / trackpad scroll for stack navigation
      if (event.scrollDelta.dy > 0) {
        widget.controller.stepSlice(1); // Next slice
      } else if (event.scrollDelta.dy < 0) {
        widget.controller.stepSlice(-1); // Previous slice
      }
    }
  }

  // --- Desktop Mouse Handling ---

  void _handleMouseDown(PointerDownEvent event) {
    final now = DateTime.now();
    if (event.buttons == kPrimaryMouseButton) {
      if (_lastTapTime != null &&
          _lastTapPosition != null &&
          now.difference(_lastTapTime!).inMilliseconds < 300 &&
          (event.localPosition - _lastTapPosition!).distance < 10) {
        // Double-click Left Button: Reset View
        widget.controller.resetView();
        _lastTapTime = null;
        _lastTapPosition = null;
        return;
      }
      _lastTapTime = now;
      _lastTapPosition = event.localPosition;
    }
  }

  void _handleMouseMove(PointerMoveEvent event) {
    if (event.delta == Offset.zero) return;

    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isCtrlOrCmd = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;

    // 1. Zoom: Right Mouse Click Drag OR Shift + Left Click Drag
    final isRightDrag = (event.buttons & kSecondaryMouseButton) != 0;
    final isShiftLeftDrag = ((event.buttons & kPrimaryMouseButton) != 0) && isShift;

    if (isRightDrag || isShiftLeftDrag) {
      // Drag Up (negative dy) -> Zoom In (positive zoom delta)
      final zoomDelta = -event.delta.dy * widget.zoomSensitivity;
      widget.controller.adjustZoom(zoomDelta);
      return;
    }

    // 2. Pan: Middle Mouse Drag OR Ctrl/Cmd + Left Click Drag
    final isMiddleDrag = (event.buttons & kMiddleMouseButton) != 0;
    final isCtrlLeftDrag = ((event.buttons & kPrimaryMouseButton) != 0) && isCtrlOrCmd;

    if (isMiddleDrag || isCtrlLeftDrag) {
      widget.controller.adjustPan(event.delta);
      return;
    }

    // 3. Window / Level: Primary Left Click Drag without modifiers
    if ((event.buttons & kPrimaryMouseButton) != 0) {
      final deltaWidth = event.delta.dx * widget.windowLevelSensitivity;
      // Drag Up (negative dy) -> Increase Brightness (decrease Window Center)
      final deltaCenter = event.delta.dy * widget.windowLevelSensitivity;
      widget.controller.adjustWindowLevel(deltaCenter, deltaWidth);
    }
  }

  void _handleMouseUp(PointerUpEvent event) {
    // Mouse up cleanup if needed
  }

  // --- Mobile Touch Handling ---

  void _handleTouchMove(PointerMoveEvent event) {
    if (event.delta == Offset.zero) return;

    // Debounce: If multi-touch just ended in the last 200ms, suppress 1-finger moves
    if (_multiTouchEndTime != null &&
        DateTime.now().difference(_multiTouchEndTime!).inMilliseconds < 200) {
      return;
    }

    if (_touchPointers.length == 1) {
      // 1 Finger: Window / Level
      final deltaWidth = event.delta.dx * widget.windowLevelSensitivity;
      // Drag Up -> Increase Brightness (decrease Center)
      final deltaCenter = event.delta.dy * widget.windowLevelSensitivity;
      widget.controller.adjustWindowLevel(deltaCenter, deltaWidth);
    } else if (_touchPointers.length >= 2) {
      // 2 Fingers: Combined Pan and Pinch Zoom
      final points = _touchPointers.values.toList();
      final currentCentroid = (points[0] + points[1]) / 2.0;
      final currentDistance = (points[0] - points[1]).distance;

      if (_lastCentroid != null) {
        final panDelta = currentCentroid - _lastCentroid!;
        widget.controller.adjustPan(panDelta);
      }

      if (_lastPinchDistance != null && _lastPinchDistance! > 10.0) {
        final distanceDelta = currentDistance - _lastPinchDistance!;
        final zoomDelta = distanceDelta * widget.zoomSensitivity;
        widget.controller.adjustZoom(zoomDelta);
      }

      _lastCentroid = currentCentroid;
      _lastPinchDistance = currentDistance;
    }
  }

  void _handleTouchUp(PointerUpEvent event) {
    final now = DateTime.now();

    if (_touchPointers.length == 1) {
      // Check for single-finger double tap to reset view
      if (_lastTapTime != null &&
          _lastTapPosition != null &&
          now.difference(_lastTapTime!).inMilliseconds < 300 &&
          (event.localPosition - _lastTapPosition!).distance < 20) {
        widget.controller.resetView();
        _lastTapTime = null;
        _lastTapPosition = null;
      } else {
        _lastTapTime = now;
        _lastTapPosition = event.localPosition;
      }
    } else if (_touchPointers.length >= 2) {
      _multiTouchEndTime = now;
    }

    _touchPointers.remove(event.pointer);
    if (_touchPointers.length < 2) {
      _lastPinchDistance = null;
      _lastCentroid = null;
    }
  }
}

