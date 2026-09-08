import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../imaging/pixel_spacing.dart';

/// Enum representing supported clinical annotation types.
enum AnnotationType {
  caliper,
  angle,
  polyline,
  circle,
  ellipse,
  text,
}

/// Identifies the role of an interactive manipulation handle.
enum HandleType {
  point,
  pullX,
  pullY,
  rotation,
  center,
}

/// A draggable handle on an annotation for resizing, reshaping, or rotating.
class AnnotationHandle {
  final String id;
  final HandleType type;

  /// Location of handle in DICOM image pixel coordinates.
  final Offset point;

  /// Suggested mouse cursor when hovering/dragging this handle.
  final MouseCursor cursor;

  const AnnotationHandle({
    required this.id,
    required this.type,
    required this.point,
    this.cursor = SystemMouseCursors.grab,
  });
}

/// Abstract base class for all DICOM presentation state annotations.
/// All coordinates are strictly in DICOM image pixel space [0..width] x [0..height].
abstract class DicomAnnotation {
  final String id;
  final AnnotationType type;
  final String? label;
  final String? creatorName;
  final String? contentLabel;
  final String? contentDescription;
  final DateTime createdAt;
  final bool isVisible;

  DicomAnnotation({
    required this.id,
    required this.type,
    this.label,
    this.creatorName,
    this.contentLabel,
    this.contentDescription,
    DateTime? createdAt,
    this.isVisible = true,
  }) : createdAt = createdAt ?? DateTime.now();

  /// All defining geometric control points in DICOM image pixel coordinates.
  List<Offset> get points;

  /// Bounding box enclosing the annotation in DICOM image pixel coordinates (including handle/padding inflation).
  Rect get boundingBox;

  /// Exact bounding box of the geometric shape itself in DICOM image pixel coordinates,
  /// without extra padding for handles. Used for clamping translations to image bounds.
  Rect get geometricBounds;

  /// Generates interactive manipulation handles in image pixel coordinates.
  List<AnnotationHandle> getHandles();

  /// Moves the entire annotation by the given delta in image pixel coordinates.
  DicomAnnotation translate(Offset delta);

  /// Updates an interactive handle by its handle ID with a new image-space point.
  DicomAnnotation updateHandle(String handleId, Offset newPoint);

  /// Tests if a given image-space point hits this annotation within [tolerancePixels].
  bool hitTest(Offset imagePoint, double tolerancePixels);

  /// Copies this annotation with optional field modifications.
  DicomAnnotation copyWith({
    String? id,
    String? label,
    String? creatorName,
    String? contentLabel,
    String? contentDescription,
    DateTime? createdAt,
    bool? isVisible,
  });

  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson();
}

/// 2-point Caliper annotation measuring distance in millimeters.
class CaliperAnnotation extends DicomAnnotation {
  final Offset start;
  final Offset end;

  CaliperAnnotation({
    required super.id,
    required this.start,
    required this.end,
    super.label,
    super.creatorName,
    super.contentLabel,
    super.contentDescription,
    super.createdAt,
    super.isVisible,
  }) : super(type: AnnotationType.caliper);

  @override
  List<Offset> get points => [start, end];

  @override
  Rect get boundingBox => Rect.fromPoints(start, end).inflate(10.0);

  @override
  Rect get geometricBounds => Rect.fromPoints(start, end);

  /// Computes distance in millimeters using provided [pixelSpacing].
  /// If [pixelSpacing] is null, falls back to raw pixel distance.
  double computeDistance({PixelSpacing? pixelSpacing}) {
    final dx = (end.dx - start.dx).abs();
    final dy = (end.dy - start.dy).abs();
    if (pixelSpacing != null) {
      return pixelSpacing.distanceMm(dx, dy);
    }
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Formats distance label for display (e.g. "42.5 mm" or "85 px").
  String formatDistance({PixelSpacing? pixelSpacing}) {
    final dist = computeDistance(pixelSpacing: pixelSpacing);
    final unit = pixelSpacing != null ? 'mm' : 'px';
    return '${dist.toStringAsFixed(1)} $unit';
  }

  @override
  List<AnnotationHandle> getHandles() {
    return [
      AnnotationHandle(
        id: 'start',
        type: HandleType.point,
        point: start,
        cursor: SystemMouseCursors.precise,
      ),
      AnnotationHandle(
        id: 'end',
        type: HandleType.point,
        point: end,
        cursor: SystemMouseCursors.precise,
      ),
    ];
  }

  @override
  CaliperAnnotation translate(Offset delta) {
    return copyWith(
      start: start + delta,
      end: end + delta,
    );
  }

  @override
  CaliperAnnotation updateHandle(String handleId, Offset newPoint) {
    if (handleId == 'start') {
      return copyWith(start: newPoint);
    } else if (handleId == 'end') {
      return copyWith(end: newPoint);
    }
    return this;
  }

  @override
  bool hitTest(Offset imagePoint, double tolerancePixels) {
    return _distanceToSegment(imagePoint, start, end) <= tolerancePixels;
  }

  @override
  CaliperAnnotation copyWith({
    String? id,
    Offset? start,
    Offset? end,
    String? label,
    String? creatorName,
    String? contentLabel,
    String? contentDescription,
    DateTime? createdAt,
    bool? isVisible,
  }) {
    return CaliperAnnotation(
      id: id ?? this.id,
      start: start ?? this.start,
      end: end ?? this.end,
      label: label ?? this.label,
      creatorName: creatorName ?? this.creatorName,
      contentLabel: contentLabel ?? this.contentLabel,
      contentDescription: contentDescription ?? this.contentDescription,
      createdAt: createdAt ?? this.createdAt,
      isVisible: isVisible ?? this.isVisible,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'startX': start.dx,
        'startY': start.dy,
        'endX': end.dx,
        'endY': end.dy,
        'label': label,
        'creatorName': creatorName,
        'contentLabel': contentLabel,
        'contentDescription': contentDescription,
        'createdAt': createdAt.toIso8601String(),
        'isVisible': isVisible,
      };

  factory CaliperAnnotation.fromJson(Map<String, dynamic> json) =>
      CaliperAnnotation(
        id: json['id'] as String,
        start: Offset(
          (json['startX'] as num).toDouble(),
          (json['startY'] as num).toDouble(),
        ),
        end: Offset(
          (json['endX'] as num).toDouble(),
          (json['endY'] as num).toDouble(),
        ),
        label: json['label'] as String?,
        creatorName: json['creatorName'] as String?,
        contentLabel: json['contentLabel'] as String?,
        contentDescription: json['contentDescription'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        isVisible: json['isVisible'] as bool? ?? true,
      );
}

/// 3-point Angle measurement annotation (Arm 1 -> Vertex -> Arm 2).
class AngleAnnotation extends DicomAnnotation {
  final Offset p1;
  final Offset vertex;
  final Offset p2;

  AngleAnnotation({
    required super.id,
    required this.p1,
    required this.vertex,
    required this.p2,
    super.label,
    super.creatorName,
    super.contentLabel,
    super.contentDescription,
    super.createdAt,
    super.isVisible,
  }) : super(type: AnnotationType.angle);

  @override
  List<Offset> get points => [p1, vertex, p2];

  @override
  Rect get boundingBox {
    final xs = [p1.dx, vertex.dx, p2.dx];
    final ys = [p1.dy, vertex.dy, p2.dy];
    return Rect.fromLTRB(
      xs.reduce(math.min) - 10,
      ys.reduce(math.min) - 10,
      xs.reduce(math.max) + 10,
      ys.reduce(math.max) + 10,
    );
  }

  @override
  Rect get geometricBounds {
    final xs = [p1.dx, vertex.dx, p2.dx];
    final ys = [p1.dy, vertex.dy, p2.dy];
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }

  /// Calculates angle at vertex in degrees [0..180].
  double computeAngleDegrees() {
    final v1 = p1 - vertex;
    final v2 = p2 - vertex;
    final dot = v1.dx * v2.dx + v1.dy * v2.dy;
    final mag1 = math.sqrt(v1.dx * v1.dx + v1.dy * v1.dy);
    final mag2 = math.sqrt(v2.dx * v2.dx + v2.dy * v2.dy);
    if (mag1 == 0 || mag2 == 0) return 0.0;
    final cosTheta = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
    return math.acos(cosTheta) * (180.0 / math.pi);
  }

  /// Formats angle string (e.g. "45.0°").
  String formatAngle() {
    return '${computeAngleDegrees().toStringAsFixed(1)}°';
  }

  @override
  List<AnnotationHandle> getHandles() {
    return [
      AnnotationHandle(id: 'p1', type: HandleType.point, point: p1),
      AnnotationHandle(id: 'vertex', type: HandleType.point, point: vertex),
      AnnotationHandle(id: 'p2', type: HandleType.point, point: p2),
    ];
  }

  @override
  AngleAnnotation translate(Offset delta) {
    return copyWith(
      p1: p1 + delta,
      vertex: vertex + delta,
      p2: p2 + delta,
    );
  }

  @override
  AngleAnnotation updateHandle(String handleId, Offset newPoint) {
    if (handleId == 'p1') {
      return copyWith(p1: newPoint);
    } else if (handleId == 'vertex') {
      return copyWith(vertex: newPoint);
    } else if (handleId == 'p2') {
      return copyWith(p2: newPoint);
    }
    return this;
  }

  @override
  bool hitTest(Offset imagePoint, double tolerancePixels) {
    return _distanceToSegment(imagePoint, p1, vertex) <= tolerancePixels ||
        _distanceToSegment(imagePoint, vertex, p2) <= tolerancePixels;
  }

  @override
  AngleAnnotation copyWith({
    String? id,
    Offset? p1,
    Offset? vertex,
    Offset? p2,
    String? label,
    String? creatorName,
    String? contentLabel,
    String? contentDescription,
    DateTime? createdAt,
    bool? isVisible,
  }) {
    return AngleAnnotation(
      id: id ?? this.id,
      p1: p1 ?? this.p1,
      vertex: vertex ?? this.vertex,
      p2: p2 ?? this.p2,
      label: label ?? this.label,
      creatorName: creatorName ?? this.creatorName,
      contentLabel: contentLabel ?? this.contentLabel,
      contentDescription: contentDescription ?? this.contentDescription,
      createdAt: createdAt ?? this.createdAt,
      isVisible: isVisible ?? this.isVisible,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'p1X': p1.dx,
        'p1Y': p1.dy,
        'vertexX': vertex.dx,
        'vertexY': vertex.dy,
        'p2X': p2.dx,
        'p2Y': p2.dy,
        'label': label,
        'creatorName': creatorName,
        'contentLabel': contentLabel,
        'contentDescription': contentDescription,
        'createdAt': createdAt.toIso8601String(),
        'isVisible': isVisible,
      };

  factory AngleAnnotation.fromJson(Map<String, dynamic> json) =>
      AngleAnnotation(
        id: json['id'] as String,
        p1: Offset(
          (json['p1X'] as num).toDouble(),
          (json['p1Y'] as num).toDouble(),
        ),
        vertex: Offset(
          (json['vertexX'] as num).toDouble(),
          (json['vertexY'] as num).toDouble(),
        ),
        p2: Offset(
          (json['p2X'] as num).toDouble(),
          (json['p2Y'] as num).toDouble(),
        ),
        label: json['label'] as String?,
        creatorName: json['creatorName'] as String?,
        contentLabel: json['contentLabel'] as String?,
        contentDescription: json['contentDescription'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        isVisible: json['isVisible'] as bool? ?? true,
      );
}

/// Multi-point Polyline annotation.
class PolylineAnnotation extends DicomAnnotation {
  final List<Offset> polylinePoints;
  final bool isClosed;

  PolylineAnnotation({
    required super.id,
    required List<Offset> points,
    this.isClosed = false,
    super.label,
    super.creatorName,
    super.contentLabel,
    super.contentDescription,
    super.createdAt,
    super.isVisible,
  })  : polylinePoints = List.unmodifiable(points),
        super(type: AnnotationType.polyline);

  @override
  List<Offset> get points => polylinePoints;

  @override
  Rect get boundingBox {
    if (polylinePoints.isEmpty) return Rect.zero;
    double minX = polylinePoints.first.dx;
    double maxX = polylinePoints.first.dx;
    double minY = polylinePoints.first.dy;
    double maxY = polylinePoints.first.dy;
    for (final p in polylinePoints) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX - 10, minY - 10, maxX + 10, maxY + 10);
  }

  @override
  Rect get geometricBounds {
    if (polylinePoints.isEmpty) return Rect.zero;
    double minX = polylinePoints.first.dx;
    double maxX = polylinePoints.first.dx;
    double minY = polylinePoints.first.dy;
    double maxY = polylinePoints.first.dy;
    for (final p in polylinePoints) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  @override
  List<AnnotationHandle> getHandles() {
    return [
      for (int i = 0; i < polylinePoints.length; i++)
        AnnotationHandle(
          id: 'point_$i',
          type: HandleType.point,
          point: polylinePoints[i],
        ),
    ];
  }

  @override
  PolylineAnnotation translate(Offset delta) {
    return copyWith(
      points: polylinePoints.map((p) => p + delta).toList(),
    );
  }

  @override
  PolylineAnnotation updateHandle(String handleId, Offset newPoint) {
    if (!handleId.startsWith('point_')) return this;
    final index = int.tryParse(handleId.substring(6));
    if (index == null || index < 0 || index >= polylinePoints.length) return this;
    final updated = List<Offset>.from(polylinePoints);
    updated[index] = newPoint;
    return copyWith(points: updated);
  }

  @override
  bool hitTest(Offset imagePoint, double tolerancePixels) {
    if (polylinePoints.length < 2) return false;
    for (int i = 0; i < polylinePoints.length - 1; i++) {
      if (_distanceToSegment(imagePoint, polylinePoints[i], polylinePoints[i + 1]) <=
          tolerancePixels) {
        return true;
      }
    }
    if (isClosedOrClosureDetected && polylinePoints.length > 2) {
      if (_distanceToSegment(imagePoint, polylinePoints.last, polylinePoints.first) <=
          tolerancePixels) {
        return true;
      }
    }
    return false;
  }

  /// Whether this polyline is explicitly closed or closure is detected by proximal endpoints.
  bool get isClosedOrClosureDetected {
    if (isClosed) return true;
    if (polylinePoints.length >= 3) {
      final first = polylinePoints.first;
      final last = polylinePoints.last;
      return (last - first).distance <= 12.0;
    }
    return false;
  }

  /// Center/centroid of all vertices in this polyline.
  Offset get centroid {
    if (polylinePoints.isEmpty) return Offset.zero;
    double sumX = 0.0;
    double sumY = 0.0;
    for (final p in polylinePoints) {
      sumX += p.dx;
      sumY += p.dy;
    }
    return Offset(sumX / polylinePoints.length, sumY / polylinePoints.length);
  }

  /// Computes the enclosed area using Gauss's Shoelace formula if closed or closure is detected.
  /// Returns null if the polyline is not closed or has fewer than 3 points.
  double? computeArea({PixelSpacing? pixelSpacing}) {
    if (!isClosedOrClosureDetected || polylinePoints.length < 3) {
      return null;
    }
    double sum = 0.0;
    final n = polylinePoints.length;
    for (int i = 0; i < n; i++) {
      final current = polylinePoints[i];
      final next = polylinePoints[(i + 1) % n];
      sum += (current.dx * next.dy) - (next.dx * current.dy);
    }
    final pxArea = (sum.abs()) / 2.0;
    if (pixelSpacing != null) {
      return pxArea * (pixelSpacing.columnSpacingMm * pixelSpacing.rowSpacingMm);
    }
    return pxArea;
  }

  /// Formats the enclosed area for clinical display (e.g. "45.2 mm²" or "1.54 cm²").
  String? formatArea({PixelSpacing? pixelSpacing}) {
    final area = computeArea(pixelSpacing: pixelSpacing);
    if (area == null) return null;
    if (pixelSpacing != null) {
      if (area >= 100.0) {
        return '${(area / 100.0).toStringAsFixed(2)} cm²';
      }
      return '${area.toStringAsFixed(1)} mm²';
    }
    return '${area.toStringAsFixed(1)} px²';
  }

  @override
  PolylineAnnotation copyWith({
    String? id,
    List<Offset>? points,
    bool? isClosed,
    String? label,
    String? creatorName,
    String? contentLabel,
    String? contentDescription,
    DateTime? createdAt,
    bool? isVisible,
  }) {
    return PolylineAnnotation(
      id: id ?? this.id,
      points: points ?? polylinePoints,
      isClosed: isClosed ?? this.isClosed,
      label: label ?? this.label,
      creatorName: creatorName ?? this.creatorName,
      contentLabel: contentLabel ?? this.contentLabel,
      contentDescription: contentDescription ?? this.contentDescription,
      createdAt: createdAt ?? this.createdAt,
      isVisible: isVisible ?? this.isVisible,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'points': polylinePoints.map((p) => [p.dx, p.dy]).toList(),
        'isClosed': isClosed,
        'label': label,
        'creatorName': creatorName,
        'contentLabel': contentLabel,
        'contentDescription': contentDescription,
        'createdAt': createdAt.toIso8601String(),
        'isVisible': isVisible,
      };

  factory PolylineAnnotation.fromJson(Map<String, dynamic> json) {
    final rawPoints = (json['points'] as List)
        .map((item) => Offset(
              ((item as List)[0] as num).toDouble(),
              (item[1] as num).toDouble(),
            ))
        .toList();
    return PolylineAnnotation(
      id: json['id'] as String,
      points: rawPoints,
      isClosed: json['isClosed'] as bool? ?? false,
      label: json['label'] as String?,
      creatorName: json['creatorName'] as String?,
      contentLabel: json['contentLabel'] as String?,
      contentDescription: json['contentDescription'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      isVisible: json['isVisible'] as bool? ?? true,
    );
  }
}

/// Circle annotation compatible with DICOM GSPS CIRCLE graphic type (center + perimeter point).
class CircleAnnotation extends DicomAnnotation {
  final Offset center;
  final double radius;

  CircleAnnotation({
    required super.id,
    required this.center,
    required this.radius,
    super.label,
    super.creatorName,
    super.contentLabel,
    super.contentDescription,
    super.createdAt,
    super.isVisible,
  }) : super(type: AnnotationType.circle);

  /// Computes enclosed circle area. In mm² if [pixelSpacing] provided, else in px².
  double computeArea({PixelSpacing? pixelSpacing}) {
    final pxArea = math.pi * radius * radius;
    if (pixelSpacing != null) {
      return pxArea * (pixelSpacing.columnSpacingMm * pixelSpacing.rowSpacingMm);
    }
    return pxArea;
  }

  /// Formats circle area for clinical display.
  String formatArea({PixelSpacing? pixelSpacing}) {
    final area = computeArea(pixelSpacing: pixelSpacing);
    if (pixelSpacing != null) {
      if (area >= 100.0) {
        return '${(area / 100.0).toStringAsFixed(2)} cm²';
      }
      return '${area.toStringAsFixed(1)} mm²';
    }
    return '${area.toStringAsFixed(1)} px²';
  }

  /// Point on perimeter directly to the right of center (DICOM GSPS perimeter point).
  Offset get perimeterPoint => Offset(center.dx + radius, center.dy);

  @override
  List<Offset> get points => [center, perimeterPoint];

  @override
  Rect get boundingBox =>
      Rect.fromCircle(center: center, radius: radius).inflate(10.0);

  @override
  Rect get geometricBounds =>
      Rect.fromCircle(center: center, radius: radius);

  @override
  List<AnnotationHandle> getHandles() {
    return [
      AnnotationHandle(
        id: 'center',
        type: HandleType.center,
        point: center,
        cursor: SystemMouseCursors.move,
      ),
      AnnotationHandle(
        id: 'pull_right',
        type: HandleType.pullX,
        point: Offset(center.dx + radius, center.dy),
        cursor: SystemMouseCursors.resizeLeftRight,
      ),
      AnnotationHandle(
        id: 'pull_top',
        type: HandleType.pullY,
        point: Offset(center.dx, center.dy - radius),
        cursor: SystemMouseCursors.resizeUpDown,
      ),
      AnnotationHandle(
        id: 'pull_left',
        type: HandleType.pullX,
        point: Offset(center.dx - radius, center.dy),
        cursor: SystemMouseCursors.resizeLeftRight,
      ),
      AnnotationHandle(
        id: 'pull_bottom',
        type: HandleType.pullY,
        point: Offset(center.dx, center.dy + radius),
        cursor: SystemMouseCursors.resizeUpDown,
      ),
    ];
  }

  @override
  CircleAnnotation translate(Offset delta) {
    return copyWith(center: center + delta);
  }

  @override
  CircleAnnotation updateHandle(String handleId, Offset newPoint) {
    if (handleId == 'center') {
      return copyWith(center: newPoint);
    }
    final newRadius = (newPoint - center).distance.clamp(2.0, 10000.0);
    return copyWith(radius: newRadius);
  }

  @override
  bool hitTest(Offset imagePoint, double tolerancePixels) {
    final dist = (imagePoint - center).distance;
    return (dist - radius).abs() <= tolerancePixels;
  }

  @override
  CircleAnnotation copyWith({
    String? id,
    Offset? center,
    double? radius,
    String? label,
    String? creatorName,
    String? contentLabel,
    String? contentDescription,
    DateTime? createdAt,
    bool? isVisible,
  }) {
    return CircleAnnotation(
      id: id ?? this.id,
      center: center ?? this.center,
      radius: radius ?? this.radius,
      label: label ?? this.label,
      creatorName: creatorName ?? this.creatorName,
      contentLabel: contentLabel ?? this.contentLabel,
      contentDescription: contentDescription ?? this.contentDescription,
      createdAt: createdAt ?? this.createdAt,
      isVisible: isVisible ?? this.isVisible,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'centerX': center.dx,
        'centerY': center.dy,
        'radius': radius,
        'label': label,
        'creatorName': creatorName,
        'contentLabel': contentLabel,
        'contentDescription': contentDescription,
        'createdAt': createdAt.toIso8601String(),
        'isVisible': isVisible,
      };

  factory CircleAnnotation.fromJson(Map<String, dynamic> json) =>
      CircleAnnotation(
        id: json['id'] as String,
        center: Offset(
          (json['centerX'] as num).toDouble(),
          (json['centerY'] as num).toDouble(),
        ),
        radius: (json['radius'] as num).toDouble(),
        label: json['label'] as String?,
        creatorName: json['creatorName'] as String?,
        contentLabel: json['contentLabel'] as String?,
        contentDescription: json['contentDescription'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        isVisible: json['isVisible'] as bool? ?? true,
      );
}

/// Ellipse annotation with pull handles (major/minor axes) and rotation handle.
/// Exactly maps to DICOM GSPS ELLIPSE graphic type (4 points: 2 endpoints of first axis, 2 endpoints of second axis).
class EllipseAnnotation extends DicomAnnotation {
  final Offset center;
  final double radiusX; // Semi-major or horizontal radius
  final double radiusY; // Semi-minor or vertical radius
  final double rotation; // In radians, clockwise from positive X axis

  EllipseAnnotation({
    required super.id,
    required this.center,
    required this.radiusX,
    required this.radiusY,
    this.rotation = 0.0,
    super.label,
    super.creatorName,
    super.contentLabel,
    super.contentDescription,
    super.createdAt,
    super.isVisible,
  }) : super(type: AnnotationType.ellipse);

  /// Computes enclosed ellipse area. In mm² if [pixelSpacing] provided, else in px².
  double computeArea({PixelSpacing? pixelSpacing}) {
    final pxArea = math.pi * radiusX * radiusY;
    if (pixelSpacing != null) {
      return pxArea * (pixelSpacing.columnSpacingMm * pixelSpacing.rowSpacingMm);
    }
    return pxArea;
  }

  /// Formats ellipse area for clinical display.
  String formatArea({PixelSpacing? pixelSpacing}) {
    final area = computeArea(pixelSpacing: pixelSpacing);
    if (pixelSpacing != null) {
      if (area >= 100.0) {
        return '${(area / 100.0).toStringAsFixed(2)} cm²';
      }
      return '${area.toStringAsFixed(1)} mm²';
    }
    return '${area.toStringAsFixed(1)} px²';
  }

  /// Normalized unit vector along the major axis.
  Offset get unitX => Offset(math.cos(rotation), math.sin(rotation));

  /// Normalized unit vector along the minor axis.
  Offset get unitY => Offset(-math.sin(rotation), math.cos(rotation));

  /// Endpoints of the first axis (Major axis) in DICOM PS 3.3 ELLIPSE specification.
  Offset get majorStart => center - (unitX * radiusX);
  Offset get majorEnd => center + (unitX * radiusX);

  /// Endpoints of the second axis (Minor axis) in DICOM PS 3.3 ELLIPSE specification.
  Offset get minorStart => center - (unitY * radiusY);
  Offset get minorEnd => center + (unitY * radiusY);

  /// 4 DICOM GSPS points: [majorStart, majorEnd, minorStart, minorEnd].
  @override
  List<Offset> get points => [majorStart, majorEnd, minorStart, minorEnd];

  /// Rotation handle position extending beyond majorEnd.
  Offset get rotationHandlePoint {
    const handleDistance = 28.0;
    return majorEnd + (unitX * handleDistance);
  }

  @override
  Rect get boundingBox {
    final maxR = math.max(radiusX, radiusY) + 35.0;
    return Rect.fromCircle(center: center, radius: maxR);
  }

  @override
  Rect get geometricBounds {
    final maxR = math.max(radiusX, radiusY);
    return Rect.fromCircle(center: center, radius: maxR);
  }

  @override
  List<AnnotationHandle> getHandles() {
    return [
      AnnotationHandle(
        id: 'center',
        type: HandleType.center,
        point: center,
        cursor: SystemMouseCursors.move,
      ),
      AnnotationHandle(
        id: 'pull_major_end',
        type: HandleType.pullX,
        point: majorEnd,
        cursor: SystemMouseCursors.resizeLeftRight,
      ),
      AnnotationHandle(
        id: 'pull_major_start',
        type: HandleType.pullX,
        point: majorStart,
        cursor: SystemMouseCursors.resizeLeftRight,
      ),
      AnnotationHandle(
        id: 'pull_minor_end',
        type: HandleType.pullY,
        point: minorEnd,
        cursor: SystemMouseCursors.resizeUpDown,
      ),
      AnnotationHandle(
        id: 'pull_minor_start',
        type: HandleType.pullY,
        point: minorStart,
        cursor: SystemMouseCursors.resizeUpDown,
      ),
      AnnotationHandle(
        id: 'rotation',
        type: HandleType.rotation,
        point: rotationHandlePoint,
        cursor: SystemMouseCursors.grab,
      ),
    ];
  }

  @override
  EllipseAnnotation translate(Offset delta) {
    return copyWith(center: center + delta);
  }

  @override
  EllipseAnnotation updateHandle(String handleId, Offset newPoint) {
    if (handleId == 'center') {
      return copyWith(center: newPoint);
    }
    if (handleId == 'rotation') {
      final diff = newPoint - center;
      final newAngle = math.atan2(diff.dy, diff.dx);
      return copyWith(rotation: newAngle);
    }
    if (handleId == 'pull_major_end' || handleId == 'pull_major_start') {
      final diff = newPoint - center;
      // Project diff onto unitX
      final projectedR = (diff.dx * unitX.dx + diff.dy * unitX.dy).abs();
      return copyWith(radiusX: projectedR.clamp(3.0, 10000.0));
    }
    if (handleId == 'pull_minor_end' || handleId == 'pull_minor_start') {
      final diff = newPoint - center;
      // Project diff onto unitY
      final projectedR = (diff.dx * unitY.dx + diff.dy * unitY.dy).abs();
      return copyWith(radiusY: projectedR.clamp(3.0, 10000.0));
    }
    return this;
  }

  @override
  bool hitTest(Offset imagePoint, double tolerancePixels) {
    final diff = imagePoint - center;
    // Rotate back to unrotated ellipse frame
    final cosA = math.cos(-rotation);
    final sinA = math.sin(-rotation);
    final localX = diff.dx * cosA - diff.dy * sinA;
    final localY = diff.dx * sinA + diff.dy * cosA;

    final normVal = (localX * localX) / (radiusX * radiusX) +
        (localY * localY) / (radiusY * radiusY);

    final outerTol = 1.0 + (tolerancePixels / math.min(radiusX, radiusY));
    final innerTol = math.max(0.0, 1.0 - (tolerancePixels / math.min(radiusX, radiusY)));

    return normVal >= (innerTol * innerTol) && normVal <= (outerTol * outerTol);
  }

  @override
  EllipseAnnotation copyWith({
    String? id,
    Offset? center,
    double? radiusX,
    double? radiusY,
    double? rotation,
    String? label,
    String? creatorName,
    String? contentLabel,
    String? contentDescription,
    DateTime? createdAt,
    bool? isVisible,
  }) {
    return EllipseAnnotation(
      id: id ?? this.id,
      center: center ?? this.center,
      radiusX: radiusX ?? this.radiusX,
      radiusY: radiusY ?? this.radiusY,
      rotation: rotation ?? this.rotation,
      label: label ?? this.label,
      creatorName: creatorName ?? this.creatorName,
      contentLabel: contentLabel ?? this.contentLabel,
      contentDescription: contentDescription ?? this.contentDescription,
      createdAt: createdAt ?? this.createdAt,
      isVisible: isVisible ?? this.isVisible,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'centerX': center.dx,
        'centerY': center.dy,
        'radiusX': radiusX,
        'radiusY': radiusY,
        'rotation': rotation,
        'label': label,
        'creatorName': creatorName,
        'contentLabel': contentLabel,
        'contentDescription': contentDescription,
        'createdAt': createdAt.toIso8601String(),
        'isVisible': isVisible,
      };

  factory EllipseAnnotation.fromJson(Map<String, dynamic> json) =>
      EllipseAnnotation(
        id: json['id'] as String,
        center: Offset(
          (json['centerX'] as num).toDouble(),
          (json['centerY'] as num).toDouble(),
        ),
        radiusX: (json['radiusX'] as num).toDouble(),
        radiusY: (json['radiusY'] as num).toDouble(),
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
        label: json['label'] as String?,
        creatorName: json['creatorName'] as String?,
        contentLabel: json['contentLabel'] as String?,
        contentDescription: json['contentDescription'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        isVisible: json['isVisible'] as bool? ?? true,
      );
}

/// Text annotation with an anchor point and editable text string.
/// Compatible with DICOM GSPS Text Object Module (0070,0008).
class TextAnnotation extends DicomAnnotation {
  final Offset anchor;
  final String text;
  final Size? boxSize;

  TextAnnotation({
    required super.id,
    required this.anchor,
    required this.text,
    this.boxSize,
    super.label,
    super.creatorName,
    super.contentLabel,
    super.contentDescription,
    super.createdAt,
    super.isVisible,
  }) : super(type: AnnotationType.text);

  @override
  List<Offset> get points => [anchor];

  @override
  Rect get boundingBox {
    final w = boxSize?.width ?? (text.length * 9.0 + 16.0).clamp(60.0, 300.0);
    final h = boxSize?.height ?? 26.0;
    return Rect.fromLTWH(anchor.dx, anchor.dy, w, h);
  }

  @override
  Rect get geometricBounds => boundingBox;

  @override
  List<AnnotationHandle> getHandles() {
    return [
      AnnotationHandle(
        id: 'anchor',
        type: HandleType.center,
        point: anchor,
        cursor: SystemMouseCursors.move,
      ),
    ];
  }

  @override
  TextAnnotation translate(Offset delta) {
    return copyWith(anchor: anchor + delta);
  }

  @override
  TextAnnotation updateHandle(String handleId, Offset newPoint) {
    if (handleId == 'anchor') {
      return copyWith(anchor: newPoint);
    }
    return this;
  }

  @override
  bool hitTest(Offset imagePoint, double tolerancePixels) {
    return boundingBox.inflate(tolerancePixels).contains(imagePoint);
  }

  @override
  TextAnnotation copyWith({
    String? id,
    Offset? anchor,
    String? text,
    Size? boxSize,
    String? label,
    String? creatorName,
    String? contentLabel,
    String? contentDescription,
    DateTime? createdAt,
    bool? isVisible,
  }) {
    return TextAnnotation(
      id: id ?? this.id,
      anchor: anchor ?? this.anchor,
      text: text ?? this.text,
      boxSize: boxSize ?? this.boxSize,
      label: label ?? this.label,
      creatorName: creatorName ?? this.creatorName,
      contentLabel: contentLabel ?? this.contentLabel,
      contentDescription: contentDescription ?? this.contentDescription,
      createdAt: createdAt ?? this.createdAt,
      isVisible: isVisible ?? this.isVisible,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'anchorX': anchor.dx,
        'anchorY': anchor.dy,
        'text': text,
        if (boxSize != null) 'boxWidth': boxSize!.width,
        if (boxSize != null) 'boxHeight': boxSize!.height,
        'label': label,
        'creatorName': creatorName,
        'contentLabel': contentLabel,
        'contentDescription': contentDescription,
        'createdAt': createdAt.toIso8601String(),
        'isVisible': isVisible,
      };

  factory TextAnnotation.fromJson(Map<String, dynamic> json) =>
      TextAnnotation(
        id: json['id'] as String,
        anchor: Offset(
          (json['anchorX'] as num).toDouble(),
          (json['anchorY'] as num).toDouble(),
        ),
        text: (json['text'] as String?) ?? '',
        boxSize: json['boxWidth'] != null && json['boxHeight'] != null
            ? Size(
                (json['boxWidth'] as num).toDouble(),
                (json['boxHeight'] as num).toDouble(),
              )
            : null,
        label: json['label'] as String?,
        creatorName: json['creatorName'] as String?,
        contentLabel: json['contentLabel'] as String?,
        contentDescription: json['contentDescription'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        isVisible: json['isVisible'] as bool? ?? true,
      );
}

/// Helper function computing shortest distance from point P to line segment AB.
double _distanceToSegment(Offset p, Offset a, Offset b) {
  final l2 = (b - a).distanceSquared;
  if (l2 == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2)
      .clamp(0.0, 1.0);
  final projection = Offset(a.dx + t * (b.dx - a.dx), a.dy + t * (b.dy - a.dy));
  return (p - projection).distance;
}
