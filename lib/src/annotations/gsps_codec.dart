import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'annotation_model.dart';

/// DICOM PS 3.3 Graphic Object Model (0070,0009).
class GspsGraphicObject {
  final String graphicType; // POLYLINE, CIRCLE, ELLIPSE, POINT, INTERPOLATED
  final String units; // PIXEL or DISPLAY
  final List<double> graphicData; // [col_1, row_1, col_2, row_2, ...]
  final bool filled;

  const GspsGraphicObject({
    required this.graphicType,
    this.units = 'PIXEL',
    required this.graphicData,
    this.filled = false,
  });

  int get numberOfPoints => graphicData.length ~/ 2;

  Map<String, dynamic> toJson() => {
        'GraphicAnnotationUnits': units,
        'GraphicDimensions': 2,
        'NumberOfGraphicPoints': numberOfPoints,
        'GraphicData': graphicData,
        'GraphicType': graphicType,
        'GraphicFilled': filled ? 'Y' : 'N',
      };

  factory GspsGraphicObject.fromJson(Map<String, dynamic> json) {
    final rawData = json['GraphicData'] as List;
    final flatFloats = rawData.map((e) => (e as num).toDouble()).toList();
    return GspsGraphicObject(
      graphicType: json['GraphicType'] as String,
      units: (json['GraphicAnnotationUnits'] as String?) ?? 'PIXEL',
      graphicData: flatFloats,
      filled: (json['GraphicFilled'] as String?)?.toUpperCase() == 'Y',
    );
  }
}

/// DICOM PS 3.3 Text Object Model (0070,0008).
class GspsTextObject {
  final String unformattedTextValue;
  final Offset? anchorPoint;
  final String anchorUnits;
  final bool anchorPointVisible;
  final Rect? boundingBox;
  final String? boundingBoxUnits;

  const GspsTextObject({
    required this.unformattedTextValue,
    this.anchorPoint,
    this.anchorUnits = 'PIXEL',
    this.anchorPointVisible = true,
    this.boundingBox,
    this.boundingBoxUnits,
  });

  Map<String, dynamic> toJson() => {
        'UnformattedTextValue': unformattedTextValue,
        if (anchorPoint != null) ...{
          'AnchorPointAnnotationUnits': anchorUnits,
          'AnchorPoint': [anchorPoint!.dx, anchorPoint!.dy],
          'AnchorPointVisibility': anchorPointVisible ? 'Y' : 'N',
        },
        if (boundingBox != null) ...{
          'BoundingBoxAnnotationUnits': boundingBoxUnits ?? 'PIXEL',
          'BoundingBoxTopLeftHandCorner': [boundingBox!.left, boundingBox!.top],
          'BoundingBoxBottomRightHandCorner': [
            boundingBox!.right,
            boundingBox!.bottom
          ],
        },
      };

  factory GspsTextObject.fromJson(Map<String, dynamic> json) {
    Offset? anchor;
    if (json['AnchorPoint'] is List) {
      final list = json['AnchorPoint'] as List;
      if (list.length >= 2) {
        anchor = Offset(
          (list[0] as num).toDouble(),
          (list[1] as num).toDouble(),
        );
      }
    }
    Rect? box;
    if (json['BoundingBoxTopLeftHandCorner'] is List &&
        json['BoundingBoxBottomRightHandCorner'] is List) {
      final tl = json['BoundingBoxTopLeftHandCorner'] as List;
      final br = json['BoundingBoxBottomRightHandCorner'] as List;
      box = Rect.fromLTRB(
        (tl[0] as num).toDouble(),
        (tl[1] as num).toDouble(),
        (br[0] as num).toDouble(),
        (br[1] as num).toDouble(),
      );
    }

    return GspsTextObject(
      unformattedTextValue: (json['UnformattedTextValue'] as String?) ?? '',
      anchorPoint: anchor,
      anchorUnits: (json['AnchorPointAnnotationUnits'] as String?) ?? 'PIXEL',
      anchorPointVisible:
          (json['AnchorPointVisibility'] as String?)?.toUpperCase() != 'N',
      boundingBox: box,
      boundingBoxUnits: json['BoundingBoxAnnotationUnits'] as String?,
    );
  }
}

/// Container for a complete Presentation State annotation layer.
/// Directly maps to DICOM PS 3.3 Graphic Annotation Module (C.10.5) & Content Identification.
class GspsPresentationState {
  final String? sopInstanceUid;
  final String contentLabel;
  final String? contentDescription;
  final String? contentCreatorName;
  final DateTime creationDateTime;
  final List<DicomAnnotation> annotations;

  GspsPresentationState({
    this.sopInstanceUid,
    this.contentLabel = 'GSPS_LAYER',
    this.contentDescription,
    this.contentCreatorName,
    DateTime? creationDateTime,
    required List<DicomAnnotation> annotations,
  })  : creationDateTime = creationDateTime ?? DateTime.now(),
        annotations = List.unmodifiable(annotations);

  /// Converts annotations to standard DICOM PS 3.3 Graphic Objects.
  List<GspsGraphicObject> toGraphicObjects() {
    final list = <GspsGraphicObject>[];
    for (final ann in annotations) {
      if (ann is CaliperAnnotation) {
        list.add(GspsGraphicObject(
          graphicType: 'POLYLINE',
          graphicData: [ann.start.dx, ann.start.dy, ann.end.dx, ann.end.dy],
        ));
      } else if (ann is AngleAnnotation) {
        list.add(GspsGraphicObject(
          graphicType: 'POLYLINE',
          graphicData: [
            ann.p1.dx,
            ann.p1.dy,
            ann.vertex.dx,
            ann.vertex.dy,
            ann.p2.dx,
            ann.p2.dy,
          ],
        ));
      } else if (ann is PolylineAnnotation) {
        final data = <double>[];
        for (final p in ann.polylinePoints) {
          data.add(p.dx);
          data.add(p.dy);
        }
        if (ann.isClosed && ann.polylinePoints.length > 2) {
          data.add(ann.polylinePoints.first.dx);
          data.add(ann.polylinePoints.first.dy);
        }
        list.add(GspsGraphicObject(
          graphicType: 'POLYLINE',
          graphicData: data,
        ));
      } else if (ann is CircleAnnotation) {
        list.add(GspsGraphicObject(
          graphicType: 'CIRCLE',
          graphicData: [
            ann.center.dx,
            ann.center.dy,
            ann.perimeterPoint.dx,
            ann.perimeterPoint.dy,
          ],
        ));
      } else if (ann is EllipseAnnotation) {
        // DICOM ELLIPSE: 4 points = 8 values
        list.add(GspsGraphicObject(
          graphicType: 'ELLIPSE',
          graphicData: [
            ann.majorStart.dx,
            ann.majorStart.dy,
            ann.majorEnd.dx,
            ann.majorEnd.dy,
            ann.minorStart.dx,
            ann.minorStart.dy,
            ann.minorEnd.dx,
            ann.minorEnd.dy,
          ],
        ));
      }
    }
    return list;
  }

  /// Converts text annotations to standard DICOM PS 3.3 Text Objects.
  List<GspsTextObject> toTextObjects() {
    final list = <GspsTextObject>[];
    for (final ann in annotations) {
      if (ann is TextAnnotation) {
        list.add(GspsTextObject(
          unformattedTextValue: ann.text,
          anchorPoint: ann.anchor,
          boundingBox: ann.boxSize != null
              ? Rect.fromLTWH(
                  ann.anchor.dx,
                  ann.anchor.dy,
                  ann.boxSize!.width,
                  ann.boxSize!.height,
                )
              : null,
        ));
      }
    }
    return list;
  }

  /// Reconstructs annotations from DICOM Graphic and Text Objects.
  static List<DicomAnnotation> fromDicomObjects({
    required List<GspsGraphicObject> graphicObjects,
    required List<GspsTextObject> textObjects,
    String? creatorName,
    String? contentLabel,
  }) {
    final result = <DicomAnnotation>[];
    int counter = 1;

    for (final g in graphicObjects) {
      final pts = <Offset>[];
      for (int i = 0; i < g.graphicData.length - 1; i += 2) {
        pts.add(Offset(g.graphicData[i], g.graphicData[i + 1]));
      }
      if (pts.isEmpty) continue;

      final id = 'gsps_g_${counter++}';
      if (g.graphicType == 'POLYLINE') {
        if (pts.length == 2) {
          result.add(CaliperAnnotation(
            id: id,
            start: pts[0],
            end: pts[1],
            creatorName: creatorName,
            contentLabel: contentLabel,
          ));
        } else if (pts.length == 3) {
          result.add(AngleAnnotation(
            id: id,
            p1: pts[0],
            vertex: pts[1],
            p2: pts[2],
            creatorName: creatorName,
            contentLabel: contentLabel,
          ));
        } else {
          result.add(PolylineAnnotation(
            id: id,
            points: pts,
            creatorName: creatorName,
            contentLabel: contentLabel,
          ));
        }
      } else if (g.graphicType == 'CIRCLE' && pts.length >= 2) {
        final center = pts[0];
        final perim = pts[1];
        final r = (perim - center).distance;
        result.add(CircleAnnotation(
          id: id,
          center: center,
          radius: r,
          creatorName: creatorName,
          contentLabel: contentLabel,
        ));
      } else if (g.graphicType == 'ELLIPSE' && pts.length >= 4) {
        final majorA = pts[0];
        final majorB = pts[1];
        final minorA = pts[2];
        final minorB = pts[3];
        final center = Offset(
          (majorA.dx + majorB.dx) / 2.0,
          (majorA.dy + majorB.dy) / 2.0,
        );
        final rX = (majorB - majorA).distance / 2.0;
        final rY = (minorB - minorA).distance / 2.0;
        final diff = majorB - center;
        final rot = math.atan2(diff.dy, diff.dx);

        result.add(EllipseAnnotation(
          id: id,
          center: center,
          radiusX: rX,
          radiusY: rY,
          rotation: rot,
          creatorName: creatorName,
          contentLabel: contentLabel,
        ));
      }
    }

    for (final t in textObjects) {
      final id = 'gsps_t_${counter++}';
      final anchor = t.anchorPoint ?? t.boundingBox?.topLeft ?? Offset.zero;
      result.add(TextAnnotation(
        id: id,
        anchor: anchor,
        text: t.unformattedTextValue,
        boxSize: t.boundingBox?.size,
        creatorName: creatorName,
        contentLabel: contentLabel,
      ));
    }

    return result;
  }

  /// Serializes the presentation state to JSON.
  Map<String, dynamic> toJson() => {
        'sopInstanceUid': sopInstanceUid,
        'contentLabel': contentLabel,
        'contentDescription': contentDescription,
        'contentCreatorName': contentCreatorName,
        'creationDateTime': creationDateTime.toIso8601String(),
        'annotations': annotations.map((a) => a.toJson()).toList(),
        'dicomGraphicObjectSequence':
            toGraphicObjects().map((g) => g.toJson()).toList(),
        'dicomTextObjectSequence':
            toTextObjects().map((t) => t.toJson()).toList(),
      };

  factory GspsPresentationState.fromJson(Map<String, dynamic> json) {
    final annJsonList = json['annotations'] as List?;
    final annotations = <DicomAnnotation>[];

    if (annJsonList != null && annJsonList.isNotEmpty) {
      for (final raw in annJsonList) {
        final m = raw as Map<String, dynamic>;
        final typeStr = m['type'] as String?;
        switch (typeStr) {
          case 'caliper':
            annotations.add(CaliperAnnotation.fromJson(m));
            break;
          case 'angle':
            annotations.add(AngleAnnotation.fromJson(m));
            break;
          case 'polyline':
            annotations.add(PolylineAnnotation.fromJson(m));
            break;
          case 'circle':
            annotations.add(CircleAnnotation.fromJson(m));
            break;
          case 'ellipse':
            annotations.add(EllipseAnnotation.fromJson(m));
            break;
          case 'text':
            annotations.add(TextAnnotation.fromJson(m));
            break;
        }
      }
    } else if (json['dicomGraphicObjectSequence'] != null ||
        json['dicomTextObjectSequence'] != null) {
      // Reconstruct from DICOM sequences if raw annotations not present
      final gList = (json['dicomGraphicObjectSequence'] as List? ?? [])
          .map((e) => GspsGraphicObject.fromJson(e as Map<String, dynamic>))
          .toList();
      final tList = (json['dicomTextObjectSequence'] as List? ?? [])
          .map((e) => GspsTextObject.fromJson(e as Map<String, dynamic>))
          .toList();
      annotations.addAll(GspsPresentationState.fromDicomObjects(
        graphicObjects: gList,
        textObjects: tList,
        creatorName: json['contentCreatorName'] as String?,
        contentLabel: json['contentLabel'] as String?,
      ));
    }

    return GspsPresentationState(
      sopInstanceUid: json['sopInstanceUid'] as String?,
      contentLabel: (json['contentLabel'] as String?) ?? 'GSPS_LAYER',
      contentDescription: json['contentDescription'] as String?,
      contentCreatorName: json['contentCreatorName'] as String?,
      creationDateTime: json['creationDateTime'] != null
          ? DateTime.tryParse(json['creationDateTime'] as String)
          : null,
      annotations: annotations,
    );
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory GspsPresentationState.fromJsonString(String jsonStr) =>
      GspsPresentationState.fromJson(
          json.decode(jsonStr) as Map<String, dynamic>);
}

