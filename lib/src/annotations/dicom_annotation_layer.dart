import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/viewport_controller.dart';
import 'annotation_controller.dart';
import 'annotation_model.dart';
import 'annotation_painter.dart';
import 'annotation_style.dart';
import 'annotation_transform.dart';

/// Interactive Flutter Widget overlaying a DICOM viewport to draw, select, manipulate,
/// and edit GSPS-compatible clinical annotations.
class DicomAnnotationLayer extends StatefulWidget {
  final ViewportController viewportController;
  final AnnotationController annotationController;
  final EdgeInsets inset;
  final AnnotationStyle style;

  const DicomAnnotationLayer({
    super.key,
    required this.viewportController,
    required this.annotationController,
    this.inset = const EdgeInsets.all(4.0),
    this.style = const AnnotationStyle(),
  });

  @override
  State<DicomAnnotationLayer> createState() => _DicomAnnotationLayerState();
}

class _DicomAnnotationLayerState extends State<DicomAnnotationLayer> {
  // Focus node for keyboard navigation & Delete/Backspace handling
  final FocusNode _layerFocusNode = FocusNode();

  // Active gesture tracking
  Offset? _drawStartPoint;
  AnnotationHandle? _activeHandle;
  DicomAnnotation? _draggingAnnotation;
  Offset? _dragLastPoint;
  bool _isDraggingEmptySpace = false;

  // Double-click / double-tap tracking for reset view
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;

  // Multi-step drawing state for Angle and Polyline
  List<Offset> _multiStepPoints = [];

  // Inline text editing state
  TextAnnotation? _editingTextAnnotation;
  final TextEditingController _textEditingController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.viewportController.addListener(_onRebuildNeeded);
    widget.annotationController.addListener(_onRebuildNeeded);
  }

  @override
  void didUpdateWidget(covariant DicomAnnotationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewportController != widget.viewportController) {
      oldWidget.viewportController.removeListener(_onRebuildNeeded);
      widget.viewportController.addListener(_onRebuildNeeded);
    }
    if (oldWidget.annotationController != widget.annotationController) {
      oldWidget.annotationController.removeListener(_onRebuildNeeded);
      widget.annotationController.addListener(_onRebuildNeeded);
    }
  }

  @override
  void dispose() {
    widget.viewportController.removeListener(_onRebuildNeeded);
    widget.annotationController.removeListener(_onRebuildNeeded);
    _textEditingController.dispose();
    _textFocusNode.dispose();
    _layerFocusNode.dispose();
    super.dispose();
  }

  void _onRebuildNeeded() {
    if (mounted) setState(() {});
  }

  ViewportCoordinateTransform? _getTransform(Size size) {
    final frame = widget.viewportController.currentFrame;
    if (frame == null || size.isEmpty) return null;
    return ViewportCoordinateTransform(
      viewportSize: size,
      imageWidth: frame.width,
      imageHeight: frame.height,
      zoom: widget.viewportController.zoom,
      panOffset: widget.viewportController.panOffset,
      inset: widget.inset,
    );
  }

  void _startEditingText(TextAnnotation annotation) {
    setState(() {
      _editingTextAnnotation = annotation;
      _textEditingController.text = annotation.text;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _textFocusNode.requestFocus();
        _textEditingController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _textEditingController.text.length,
        );
      }
    });
  }

  void _commitTextEditing() {
    if (_editingTextAnnotation != null) {
      final updated = _editingTextAnnotation!.copyWith(
        text: _textEditingController.text.trim().isEmpty
            ? 'Annotation'
            : _textEditingController.text,
      );
      widget.annotationController.updateAnnotation(updated);
      setState(() {
        _editingTextAnnotation = null;
      });
    }
  }

  void _onPointerDown(PointerDownEvent event, ViewportCoordinateTransform transform) {
    _layerFocusNode.requestFocus();
    final imagePt = transform.viewportToImage(event.localPosition);
    final tool = widget.annotationController.activeTool;

    // Dismiss any active text editor on click outside
    if (_editingTextAnnotation != null) {
      _commitTextEditing();
      return;
    }

    if (tool == AnnotationTool.none) return;

    // Filter out Secondary (right) and Middle (wheel) mouse buttons from drawing/selecting
    if (event.kind == ui.PointerDeviceKind.mouse) {
      if ((event.buttons & kSecondaryMouseButton) != 0 ||
          (event.buttons & kMiddleMouseButton) != 0) {
        return;
      }
    }

    // Double-click Left Button on empty space: Reset View
    if (event.buttons == kPrimaryMouseButton) {
      final now = DateTime.now();
      if (_lastTapTime != null &&
          _lastTapPosition != null &&
          now.difference(_lastTapTime!).inMilliseconds < 300 &&
          (event.localPosition - _lastTapPosition!).distance < 10) {
        widget.viewportController.resetView();
        _lastTapTime = null;
        _lastTapPosition = null;
        return;
      }
      _lastTapTime = now;
      _lastTapPosition = event.localPosition;
    }

    // 1. ALWAYS check if an active handle of selected annotation was clicked (prioritize grabbing handles!)
    final selected = widget.annotationController.selectedAnnotation;
    if (selected != null) {
      final handles = selected.getHandles();
      for (final h in handles) {
        final handleScreen = transform.imageToViewport(h.point);
        if ((event.localPosition - handleScreen).distance <=
            widget.style.handleRadius + 8.0) {
          _activeHandle = h;
          _dragLastPoint = imagePt;
          return;
        }
      }
    }

    if (tool == AnnotationTool.select) {
      // 2. Check if an existing visible annotation was hit
      final visibleList = widget.annotationController.visibleAnnotations;
      const hitTolerancePixels = 8.0;
      final imageTolerance = transform.viewportDistanceToImage(hitTolerancePixels);

      for (int i = visibleList.length - 1; i >= 0; i--) {
        final ann = visibleList[i];
        if (ann.hitTest(imagePt, imageTolerance)) {
          widget.annotationController.selectAnnotation(ann);
          _draggingAnnotation = ann;
          _dragLastPoint = imagePt;

          // Double tap or click on text annotation enables inline editing
          if (ann is TextAnnotation) {
            _startEditingText(ann);
          }
          return;
        }
      }

      // 3. Clicked empty space: clear selection and allow window/level adjustment
      widget.annotationController.selectAnnotation(null);
      _isDraggingEmptySpace = true;
      return;
    }

    // Drawing tools
    final clampedPt = transform.clampImagePoint(imagePt);
    _drawStartPoint = clampedPt;

    if (tool == AnnotationTool.caliper) {
      final draft = CaliperAnnotation(
        id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
        start: clampedPt,
        end: clampedPt,
        creatorName: widget.annotationController.activeCreator,
      );
      widget.annotationController.setDraftAnnotation(draft);
    } else if (tool == AnnotationTool.circle) {
      final draft = CircleAnnotation(
        id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
        center: clampedPt,
        radius: 1.0,
        creatorName: widget.annotationController.activeCreator,
      );
      widget.annotationController.setDraftAnnotation(draft);
    } else if (tool == AnnotationTool.ellipse) {
      final draft = EllipseAnnotation(
        id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
        center: clampedPt,
        radiusX: 1.0,
        radiusY: 1.0,
        rotation: 0.0,
        creatorName: widget.annotationController.activeCreator,
      );
      widget.annotationController.setDraftAnnotation(draft);
    } else if (tool == AnnotationTool.angle) {
      _multiStepPoints.add(clampedPt);
      if (_multiStepPoints.length == 1) {
        // Vertex defined
        final draft = AngleAnnotation(
          id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
          p1: clampedPt,
          vertex: clampedPt,
          p2: clampedPt,
          creatorName: widget.annotationController.activeCreator,
        );
        widget.annotationController.setDraftAnnotation(draft);
      } else if (_multiStepPoints.length == 2) {
        // P1 defined
      } else if (_multiStepPoints.length >= 3) {
        // P2 defined, commit angle
        final ann = AngleAnnotation(
          id: 'angle_${DateTime.now().millisecondsSinceEpoch}',
          p1: _multiStepPoints[0],
          vertex: _multiStepPoints[1],
          p2: _multiStepPoints[2],
          creatorName: widget.annotationController.activeCreator,
        );
        _multiStepPoints.clear();
        widget.annotationController.setDraftAnnotation(null);
        widget.annotationController.addAnnotation(ann);
        widget.annotationController.setActiveTool(AnnotationTool.select);
      }
    } else if (tool == AnnotationTool.polyline) {
      if (_multiStepPoints.isNotEmpty) {
        // Double-click or click on last vertex finishes polyline
        if ((clampedPt - _multiStepPoints.last).distance <= 3.0) {
          finishPolyline();
          return;
        }
        // Click near starting vertex closes polyline
        if (_multiStepPoints.length >= 3) {
          final distToStart = (clampedPt - _multiStepPoints.first).distance;
          final screenDist = transform.imageDistanceToViewport(distToStart);
          if (screenDist <= 16.0 || distToStart <= 12.0) {
            finishPolyline(close: true);
            return;
          }
        }
      }
      _multiStepPoints.add(clampedPt);
      final draft = PolylineAnnotation(
        id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
        points: List.from(_multiStepPoints),
        creatorName: widget.annotationController.activeCreator,
      );
      widget.annotationController.setDraftAnnotation(draft);
    } else if (tool == AnnotationTool.text) {
      final textAnn = TextAnnotation(
        id: 'text_${DateTime.now().millisecondsSinceEpoch}',
        anchor: clampedPt,
        text: 'Note',
        creatorName: widget.annotationController.activeCreator,
      );
      widget.annotationController.addAnnotation(textAnn);
      widget.annotationController.setActiveTool(AnnotationTool.select);
      _startEditingText(textAnn);
    }
  }

  void _onPointerMove(PointerMoveEvent event, ViewportCoordinateTransform transform) {
    if (event.delta == Offset.zero) return;

    if (event.kind == ui.PointerDeviceKind.mouse) {
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      final isCtrlOrCmd = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;

      // 1. Zoom: Right Mouse Click Drag OR Shift + Left Click Drag
      final isRightDrag = (event.buttons & kSecondaryMouseButton) != 0;
      final isShiftLeftDrag =
          ((event.buttons & kPrimaryMouseButton) != 0) && isShift;
      if (isRightDrag || isShiftLeftDrag) {
        final zoomDelta = -event.delta.dy * 0.01;
        widget.viewportController.adjustZoom(zoomDelta);
        return;
      }

      // 2. Pan: Middle Mouse Drag OR Ctrl/Cmd + Left Click Drag
      final isMiddleDrag = (event.buttons & kMiddleMouseButton) != 0;
      final isCtrlLeftDrag =
          ((event.buttons & kPrimaryMouseButton) != 0) && isCtrlOrCmd;
      if (isMiddleDrag || isCtrlLeftDrag) {
        widget.viewportController.adjustPan(event.delta);
        return;
      }
    }

    // 3. Empty-space Drag in Select mode: Window / Level
    if (_isDraggingEmptySpace && (event.buttons & kPrimaryMouseButton) != 0) {
      final deltaWidth = event.delta.dx * 2.0;
      final deltaCenter = event.delta.dy * 2.0;
      widget.viewportController.adjustWindowLevel(deltaCenter, deltaWidth);
      return;
    }

    final imagePt = transform.viewportToImage(event.localPosition);
    final clampedPt = transform.clampImagePoint(imagePt);
    final tool = widget.annotationController.activeTool;

    // Prioritize dragging active handle across all tools
    if (_activeHandle != null) {
      final selected = widget.annotationController.selectedAnnotation;
      if (selected != null) {
        final updated = selected.updateHandle(_activeHandle!.id, clampedPt);
        widget.annotationController.updateAnnotation(updated);
      }
      return;
    }

    if (tool == AnnotationTool.select) {
      if (_draggingAnnotation != null && _dragLastPoint != null) {
        final delta = imagePt - _dragLastPoint!;
        final box = _draggingAnnotation!.geometricBounds;
        final imgW = transform.imageWidth.toDouble();
        final imgH = transform.imageHeight.toDouble();

        double clampedDx = delta.dx;
        double clampedDy = delta.dy;

        if (box.width <= imgW) {
          if (box.left + clampedDx < 0.0) {
            clampedDx = -box.left;
          } else if (box.right + clampedDx > imgW) {
            clampedDx = imgW - box.right;
          }
        }

        if (box.height <= imgH) {
          if (box.top + clampedDy < 0.0) {
            clampedDy = -box.top;
          } else if (box.bottom + clampedDy > imgH) {
            clampedDy = imgH - box.bottom;
          }
        }

        final clampedDelta = Offset(clampedDx, clampedDy);
        if (clampedDelta != Offset.zero) {
          final updated = _draggingAnnotation!.translate(clampedDelta);
          widget.annotationController.updateAnnotation(updated);
          _draggingAnnotation = updated;
          _dragLastPoint = _dragLastPoint! + clampedDelta;
        }
      }
      return;
    }

    // Dynamic preview while drawing
    if (tool == AnnotationTool.caliper && _drawStartPoint != null) {
      final draft = CaliperAnnotation(
        id: 'draft_caliper',
        start: _drawStartPoint!,
        end: clampedPt,
        creatorName: widget.annotationController.activeCreator,
      );
      widget.annotationController.setDraftAnnotation(draft);
    } else if (tool == AnnotationTool.circle && _drawStartPoint != null) {
      final r = (_drawStartPoint! - clampedPt).distance;
      final draft = CircleAnnotation(
        id: 'draft_circle',
        center: _drawStartPoint!,
        radius: math.max(r, 2.0),
        creatorName: widget.annotationController.activeCreator,
      );
      widget.annotationController.setDraftAnnotation(draft);
    } else if (tool == AnnotationTool.ellipse && _drawStartPoint != null) {
      final rX = (clampedPt.dx - _drawStartPoint!.dx).abs();
      final rY = (clampedPt.dy - _drawStartPoint!.dy).abs();
      final draft = EllipseAnnotation(
        id: 'draft_ellipse',
        center: _drawStartPoint!,
        radiusX: math.max(rX, 3.0),
        radiusY: math.max(rY, 3.0),
        rotation: 0.0,
        creatorName: widget.annotationController.activeCreator,
      );
      widget.annotationController.setDraftAnnotation(draft);
    } else if (tool == AnnotationTool.angle && _multiStepPoints.isNotEmpty) {
      if (_multiStepPoints.length == 1) {
        final draft = AngleAnnotation(
          id: 'draft_angle',
          p1: clampedPt,
          vertex: _multiStepPoints[0],
          p2: clampedPt,
          creatorName: widget.annotationController.activeCreator,
        );
        widget.annotationController.setDraftAnnotation(draft);
      } else if (_multiStepPoints.length == 2) {
        final draft = AngleAnnotation(
          id: 'draft_angle',
          p1: _multiStepPoints[0],
          vertex: _multiStepPoints[1],
          p2: clampedPt,
          creatorName: widget.annotationController.activeCreator,
        );
        widget.annotationController.setDraftAnnotation(draft);
      }
    } else if (tool == AnnotationTool.polyline && _multiStepPoints.isNotEmpty) {
      final previewPoints = List<Offset>.from(_multiStepPoints)..add(clampedPt);
      final draft = PolylineAnnotation(
        id: 'draft_polyline',
        points: previewPoints,
        creatorName: widget.annotationController.activeCreator,
      );
      widget.annotationController.setDraftAnnotation(draft);
    }
  }

  void _onPointerUp(PointerUpEvent event, ViewportCoordinateTransform transform) {
    if (_isDraggingEmptySpace) {
      _isDraggingEmptySpace = false;
      return;
    }

    final imagePt =
        transform.clampImagePoint(transform.viewportToImage(event.localPosition));
    final tool = widget.annotationController.activeTool;

    if (_activeHandle != null) {
      _activeHandle = null;
      _draggingAnnotation = null;
      _dragLastPoint = null;
      return;
    }

    if (tool == AnnotationTool.select) {
      _draggingAnnotation = null;
      _dragLastPoint = null;
      return;
    }

    if (tool == AnnotationTool.caliper && _drawStartPoint != null) {
      if ((imagePt - _drawStartPoint!).distance >= 3.0) {
        final ann = CaliperAnnotation(
          id: 'caliper_${DateTime.now().millisecondsSinceEpoch}',
          start: _drawStartPoint!,
          end: imagePt,
          creatorName: widget.annotationController.activeCreator,
        );
        widget.annotationController.addAnnotation(ann);
        widget.annotationController.setActiveTool(AnnotationTool.select);
      }
      _drawStartPoint = null;
      widget.annotationController.setDraftAnnotation(null);
    } else if (tool == AnnotationTool.circle && _drawStartPoint != null) {
      final r = (imagePt - _drawStartPoint!).distance;
      if (r >= 3.0) {
        final ann = CircleAnnotation(
          id: 'circle_${DateTime.now().millisecondsSinceEpoch}',
          center: _drawStartPoint!,
          radius: r,
          creatorName: widget.annotationController.activeCreator,
        );
        widget.annotationController.addAnnotation(ann);
        widget.annotationController.setActiveTool(AnnotationTool.select);
      }
      _drawStartPoint = null;
      widget.annotationController.setDraftAnnotation(null);
    } else if (tool == AnnotationTool.ellipse && _drawStartPoint != null) {
      final rX = (imagePt.dx - _drawStartPoint!.dx).abs();
      final rY = (imagePt.dy - _drawStartPoint!.dy).abs();
      if (rX >= 3.0 || rY >= 3.0) {
        final ann = EllipseAnnotation(
          id: 'ellipse_${DateTime.now().millisecondsSinceEpoch}',
          center: _drawStartPoint!,
          radiusX: math.max(rX, 6.0),
          radiusY: math.max(rY, 6.0),
          rotation: 0.0,
          creatorName: widget.annotationController.activeCreator,
        );
        widget.annotationController.addAnnotation(ann);
        widget.annotationController.setActiveTool(AnnotationTool.select);
      }
      _drawStartPoint = null;
      widget.annotationController.setDraftAnnotation(null);
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activeHandle = null;
    _draggingAnnotation = null;
    _dragLastPoint = null;
    _drawStartPoint = null;
    _isDraggingEmptySpace = false;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    // Forward mouse wheel scrolling to slice step navigation
    if (event is PointerScrollEvent) {
      if (event.scrollDelta.dy.abs() >= 10.0) {
        final direction = event.scrollDelta.dy > 0 ? 1 : -1;
        widget.viewportController.onSliceStep?.call(direction);
      }
    }
  }

  /// Finishes active multi-step polyline.
  void finishPolyline({bool close = false}) {
    if (_multiStepPoints.length >= 2) {
      final ann = PolylineAnnotation(
        id: 'polyline_${DateTime.now().millisecondsSinceEpoch}',
        points: List.from(_multiStepPoints),
        isClosed: close,
        creatorName: widget.annotationController.activeCreator,
      );
      widget.annotationController.addAnnotation(ann);
      widget.annotationController.setActiveTool(AnnotationTool.select);
    }
    _multiStepPoints.clear();
    widget.annotationController.setDraftAnnotation(null);
  }

  /// Handles keyboard shortcuts (Delete / Backspace to remove, Escape to cancel, Enter to finish).
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        if (_editingTextAnnotation != null) {
          return KeyEventResult.ignored;
        }
        if (widget.annotationController.hasDeletable) {
          widget.annotationController.deleteSelected();
          return KeyEventResult.handled;
        }
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_editingTextAnnotation != null) {
          _commitTextEditing();
          return KeyEventResult.handled;
        }
        if (_multiStepPoints.isNotEmpty) {
          _multiStepPoints.clear();
          widget.annotationController.setDraftAnnotation(null);
          setState(() {});
          return KeyEventResult.handled;
        }
        widget.annotationController.selectAnnotation(null);
        widget.annotationController.setActiveTool(AnnotationTool.select);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (widget.annotationController.activeTool == AnnotationTool.polyline &&
            _multiStepPoints.length >= 2) {
          finishPolyline();
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final transform = _getTransform(size);

        if (transform == null) {
          return const SizedBox.expand();
        }

        final isInteractive =
            widget.annotationController.activeTool != AnnotationTool.none;

        return ClipRect(
          clipBehavior: Clip.hardEdge,
          child: IgnorePointer(
            ignoring: !isInteractive,
            child: Focus(
              focusNode: _layerFocusNode,
              autofocus: isInteractive,
              onKeyEvent: isInteractive ? _handleKeyEvent : null,
              child: Listener(
                behavior: isInteractive
                    ? HitTestBehavior.opaque
                    : HitTestBehavior.translucent,
                onPointerDown: isInteractive ? (e) => _onPointerDown(e, transform) : null,
                onPointerMove: isInteractive ? (e) => _onPointerMove(e, transform) : null,
                onPointerUp: isInteractive ? (e) => _onPointerUp(e, transform) : null,
                onPointerCancel: isInteractive ? _onPointerCancel : null,
                onPointerSignal: isInteractive ? _onPointerSignal : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: AnnotationPainter(
                        annotations: widget.annotationController.visibleAnnotations,
                        selectedAnnotation:
                            widget.annotationController.selectedAnnotation,
                        draftAnnotation: widget.annotationController.draftAnnotation,
                        transform: transform,
                        pixelSpacing: widget.viewportController.pixelSpacing,
                        style: widget.style,
                      ),
                    ),
                    if (_editingTextAnnotation != null)
                      _buildInlineTextEditor(transform),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInlineTextEditor(ViewportCoordinateTransform transform) {
    final screenAnchor = transform.imageToViewport(_editingTextAnnotation!.anchor);
    return Positioned(
      left: screenAnchor.dx,
      top: screenAnchor.dy,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xE61E1E1E),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: widget.style.primaryColor, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black87,
                blurRadius: 4,
                offset: Offset(1, 1),
              ),
            ],
          ),
          child: TextField(
            controller: _textEditingController,
            focusNode: _textFocusNode,
            style: widget.style.textStyle.copyWith(fontWeight: FontWeight.normal),
            cursorColor: widget.style.primaryColor,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              border: InputBorder.none,
            ),
            onSubmitted: (_) => _commitTextEditing(),
            onTapOutside: (_) => _commitTextEditing(),
          ),
        ),
      ),
    );
  }
}
