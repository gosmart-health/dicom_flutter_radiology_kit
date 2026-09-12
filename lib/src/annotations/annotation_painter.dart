import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../imaging/pixel_spacing.dart';
import 'annotation_model.dart';
import 'annotation_style.dart';
import 'annotation_transform.dart';

/// CustomPainter that renders clinical annotations, measurements, high-contrast shadows,
/// and interactive manipulation handles synchronized with image coordinates.
class AnnotationPainter extends CustomPainter {
  final List<DicomAnnotation> annotations;
  final DicomAnnotation? selectedAnnotation;
  final DicomAnnotation? draftAnnotation;
  final ViewportCoordinateTransform transform;
  final PixelSpacing? pixelSpacing;
  final AnnotationStyle style;

  AnnotationPainter({
    required this.annotations,
    this.selectedAnnotation,
    this.draftAnnotation,
    required this.transform,
    this.pixelSpacing,
    this.style = const AnnotationStyle(),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (transform.viewportSize.isEmpty) return;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // Render all saved annotations
    for (final ann in annotations) {
      if (!ann.isVisible) continue;
      _drawAnnotation(canvas, ann);
    }

    // Render active draft annotation if present
    if (draftAnnotation != null && draftAnnotation!.isVisible) {
      _drawAnnotation(canvas, draftAnnotation!);
    }

    // Render interactive handles for selected annotation
    if (selectedAnnotation != null && selectedAnnotation!.isVisible) {
      _drawHandles(canvas, selectedAnnotation!);
    }

    canvas.restore();
  }

  void _drawAnnotation(Canvas canvas, DicomAnnotation ann) {
    if (ann is CaliperAnnotation) {
      _drawCaliper(canvas, ann);
    } else if (ann is AngleAnnotation) {
      _drawAngle(canvas, ann);
    } else if (ann is PolylineAnnotation) {
      _drawPolyline(canvas, ann);
    } else if (ann is CircleAnnotation) {
      _drawCircle(canvas, ann);
    } else if (ann is EllipseAnnotation) {
      _drawEllipse(canvas, ann);
    } else if (ann is TextAnnotation) {
      _drawText(canvas, ann);
    }
  }

  void _drawCaliper(Canvas canvas, CaliperAnnotation ann) {
    final start = transform.imageToViewport(ann.start);
    final end = transform.imageToViewport(ann.end);

    // Cross-tick vectors
    final diff = end - start;
    final length = diff.distance;
    final normal = length > 0
        ? Offset(-diff.dy / length, diff.dx / length) * 7.0
        : const Offset(0, 7.0);

    // 1. Draw cross-ticks
    final t1Start = start - normal;
    final t1End = start + normal;
    final t2Start = end - normal;
    final t2End = end + normal;

    // Shadow pass
    canvas.drawLine(t1Start, t1End, style.shadowLinePaint);
    canvas.drawLine(t2Start, t2End, style.shadowLinePaint);
    canvas.drawLine(start, end, style.shadowLinePaint);

    // Foreground pass
    canvas.drawLine(t1Start, t1End, style.foregroundLinePaint);
    canvas.drawLine(t2Start, t2End, style.foregroundLinePaint);
    canvas.drawLine(start, end, style.foregroundLinePaint);

    // 2. Draw distance label
    final label = ann.formatDistance(pixelSpacing: pixelSpacing);
    final mid = Offset((start.dx + end.dx) / 2.0, (start.dy + end.dy) / 2.0);
    final labelPos = mid + (normal * 1.8);
    _drawTextBadge(canvas, label, labelPos);
  }

  void _drawAngle(Canvas canvas, AngleAnnotation ann) {
    final p1 = transform.imageToViewport(ann.p1);
    final vertex = transform.imageToViewport(ann.vertex);
    final p2 = transform.imageToViewport(ann.p2);

    // Shadow pass
    canvas.drawLine(vertex, p1, style.shadowLinePaint);
    canvas.drawLine(vertex, p2, style.shadowLinePaint);

    // Foreground pass
    canvas.drawLine(vertex, p1, style.foregroundLinePaint);
    canvas.drawLine(vertex, p2, style.foregroundLinePaint);

    // Draw angle arc
    final v1 = p1 - vertex;
    final v2 = p2 - vertex;
    if (v1.distance > 0 && v2.distance > 0) {
      final a1 = math.atan2(v1.dy, v1.dx);
      final a2 = math.atan2(v2.dy, v2.dx);
      double sweep = a2 - a1;
      if (sweep > math.pi) sweep -= 2 * math.pi;
      if (sweep < -math.pi) sweep += 2 * math.pi;

      const arcRadius = 22.0;
      final arcRect = Rect.fromCircle(center: vertex, radius: arcRadius);
      canvas.drawArc(arcRect, a1, sweep, false, style.shadowLinePaint);
      canvas.drawArc(arcRect, a1, sweep, false, style.foregroundLinePaint);
    }

    // Draw angle label
    final label = ann.formatAngle();
    final midArm = vertex + ((v1 / (v1.distance > 0 ? v1.distance : 1) +
                v2 / (v2.distance > 0 ? v2.distance : 1)) *
            18.0);
    _drawTextBadge(canvas, label, midArm);
  }

  void _drawPolyline(Canvas canvas, PolylineAnnotation ann) {
    if (ann.polylinePoints.length < 2) return;
    final path = Path();
    final first = transform.imageToViewport(ann.polylinePoints.first);
    path.moveTo(first.dx, first.dy);

    for (int i = 1; i < ann.polylinePoints.length; i++) {
      final p = transform.imageToViewport(ann.polylinePoints[i]);
      path.lineTo(p.dx, p.dy);
    }

    if (ann.isClosedOrClosureDetected && ann.polylinePoints.length > 2) {
      path.close();
    }

    canvas.drawPath(path, style.shadowLinePaint);
    canvas.drawPath(path, style.foregroundLinePaint);

    if (ann.isClosedOrClosureDetected) {
      final areaStr = ann.formatArea(pixelSpacing: pixelSpacing);
      if (areaStr != null) {
        final badgeText = ann.label != null && ann.label!.isNotEmpty
            ? '${ann.label}\n$areaStr'
            : areaStr;
        final screenCentroid = transform.imageToViewport(ann.centroid);
        _drawTextBadge(canvas, badgeText, screenCentroid);
      }
    }
  }

  void _drawCircle(Canvas canvas, CircleAnnotation ann) {
    final c = transform.imageToViewport(ann.center);
    final r = transform.imageDistanceToViewport(ann.radius);

    canvas.drawCircle(c, r, style.shadowLinePaint);
    canvas.drawCircle(c, r, style.foregroundLinePaint);

    final areaStr = ann.formatArea(pixelSpacing: pixelSpacing);
    final badgeText = ann.label != null && ann.label!.isNotEmpty
        ? '${ann.label}\n$areaStr'
        : areaStr;
    _drawTextBadge(canvas, badgeText, Offset(c.dx, c.dy - r - 14.0));
  }

  void _drawEllipse(Canvas canvas, EllipseAnnotation ann) {
    final c = transform.imageToViewport(ann.center);
    final rX = transform.imageDistanceToViewport(ann.radiusX);
    final rY = transform.imageDistanceToViewport(ann.radiusY);

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(ann.rotation);

    final rect = Rect.fromCenter(center: Offset.zero, width: rX * 2, height: rY * 2);
    canvas.drawOval(rect, style.shadowLinePaint);
    canvas.drawOval(rect, style.foregroundLinePaint);

    canvas.restore();

    final areaStr = ann.formatArea(pixelSpacing: pixelSpacing);
    final badgeText = ann.label != null && ann.label!.isNotEmpty
        ? '${ann.label}\n$areaStr'
        : areaStr;
    _drawTextBadge(canvas, badgeText, Offset(c.dx, c.dy - math.max(rX, rY) - 14.0));
  }

  void _drawText(Canvas canvas, TextAnnotation ann) {
    final a = transform.imageToViewport(ann.anchor);
    _drawTextBadge(canvas, ann.text, a, isAnchorPoint: true);
  }

  void _drawHandles(Canvas canvas, DicomAnnotation ann) {
    final handles = ann.getHandles();

    // If ellipse, draw rotation stem line
    if (ann is EllipseAnnotation) {
      final endScreen = transform.imageToViewport(ann.majorEnd);
      final rotScreen = transform.imageToViewport(ann.rotationHandlePoint);
      canvas.drawLine(endScreen, rotScreen, style.shadowLinePaint);
      canvas.drawLine(endScreen, rotScreen, style.foregroundLinePaint);
    }

    final handleBorderPaint = Paint()
      ..color = style.handleBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.handleBorderWidth
      ..isAntiAlias = true;

    final handleFillPaint = Paint()
      ..color = style.handleFillColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (final h in handles) {
      final screenPos = transform.imageToViewport(h.point);

      if (h.type == HandleType.rotation) {
        // Rotation handle is a circle with distinct fill (e.g. green or cyan accent or white center)
        final rotFill = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawCircle(screenPos, style.handleRadius + 1.5, style.shadowLinePaint);
        canvas.drawCircle(screenPos, style.handleRadius + 1.5, rotFill);
        canvas.drawCircle(screenPos, style.handleRadius + 1.5, handleBorderPaint);
      } else if (h.type == HandleType.center) {
        // Center handle is a crosshair
        const crossSize = 5.0;
        canvas.drawLine(
          screenPos - const Offset(crossSize, 0),
          screenPos + const Offset(crossSize, 0),
          style.shadowLinePaint,
        );
        canvas.drawLine(
          screenPos - const Offset(0, crossSize),
          screenPos + const Offset(0, crossSize),
          style.shadowLinePaint,
        );
        canvas.drawLine(
          screenPos - const Offset(crossSize, 0),
          screenPos + const Offset(crossSize, 0),
          style.foregroundLinePaint,
        );
        canvas.drawLine(
          screenPos - const Offset(0, crossSize),
          screenPos + const Offset(0, crossSize),
          style.foregroundLinePaint,
        );
      } else {
        // Square or circular pull handle
        final rect = Rect.fromCircle(center: screenPos, radius: style.handleRadius);
        canvas.drawRect(rect.inflate(1.0), Paint()..color = Colors.black);
        canvas.drawRect(rect, handleFillPaint);
        canvas.drawRect(rect, handleBorderPaint);
      }
    }
  }

  void _drawTextBadge(
    Canvas canvas,
    String text,
    Offset position, {
    bool isAnchorPoint = false,
  }) {
    if (text.isEmpty) return;

    final textSpan = TextSpan(text: text, style: style.textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = Rect.fromLTWH(
      position.dx - (isAnchorPoint ? 0 : textPainter.width / 2.0) - 4.0,
      position.dy - (isAnchorPoint ? 0 : textPainter.height / 2.0) - 2.0,
      textPainter.width + 8.0,
      textPainter.height + 4.0,
    );

    // Draw dark rounded background chip for maximum contrast
    final rrect = RRect.fromRectAndRadius(bgRect, const Radius.circular(4.0));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = style.textBackgroundColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0x66000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    final textOffset = Offset(
      position.dx - (isAnchorPoint ? 0 : textPainter.width / 2.0),
      position.dy - (isAnchorPoint ? 0 : textPainter.height / 2.0),
    );

    textPainter.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter oldDelegate) {
    return true; // Dynamic annotations and transforms repaint on frame/gesture changes
  }
}

