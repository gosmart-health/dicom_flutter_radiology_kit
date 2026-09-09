import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../imaging/pixel_spacing.dart';
import 'annotation_model.dart';
import 'gsps_dicom_encoder.dart';

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
  final String? studyInstanceUid;
  final String? seriesInstanceUid;
  final String? referencedSeriesUid;
  final String? referencedSopInstanceUid;
  final int? referencedFrameNumber;
  final List<DicomAnnotation> annotations;

  GspsPresentationState({
    this.sopInstanceUid,
    this.contentLabel = 'GSPS_LAYER',
    this.contentDescription,
    this.contentCreatorName,
    DateTime? creationDateTime,
    this.studyInstanceUid,
    this.seriesInstanceUid,
    this.referencedSeriesUid,
    this.referencedSopInstanceUid,
    this.referencedFrameNumber,
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
  /// When [includeMeasurementReadouts] is true, also generates companion text readouts for Calipers, Angles, Circles, Ellipses, and Polylines.
  List<GspsTextObject> toTextObjects({
    bool includeMeasurementReadouts = false,
    PixelSpacing? pixelSpacing,
  }) {
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
      } else if (includeMeasurementReadouts && ann is CaliperAnnotation) {
        final distStr = ann.formatDistance(pixelSpacing: pixelSpacing);
        final labelText = ann.label != null && ann.label!.isNotEmpty
            ? '${ann.label}: $distStr'
            : distStr;
        list.add(GspsTextObject(
          unformattedTextValue: labelText,
          anchorPoint: Offset(
            (ann.start.dx + ann.end.dx) / 2,
            (ann.start.dy + ann.end.dy) / 2,
          ),
        ));
      } else if (includeMeasurementReadouts && ann is AngleAnnotation) {
        final angleStr = ann.formatAngle();
        final labelText = ann.label != null && ann.label!.isNotEmpty
            ? '${ann.label}: $angleStr'
            : angleStr;
        list.add(GspsTextObject(
          unformattedTextValue: labelText,
          anchorPoint: ann.vertex,
        ));
      } else if (includeMeasurementReadouts && ann is CircleAnnotation) {
        final areaStr = ann.formatArea(pixelSpacing: pixelSpacing);
        final labelText = ann.label != null && ann.label!.isNotEmpty
            ? '${ann.label}: $areaStr'
            : areaStr;
        list.add(GspsTextObject(
          unformattedTextValue: labelText,
          anchorPoint: ann.center,
        ));
      } else if (includeMeasurementReadouts && ann is EllipseAnnotation) {
        final areaStr = ann.formatArea(pixelSpacing: pixelSpacing);
        final labelText = ann.label != null && ann.label!.isNotEmpty
            ? '${ann.label}: $areaStr'
            : areaStr;
        list.add(GspsTextObject(
          unformattedTextValue: labelText,
          anchorPoint: ann.center,
        ));
      } else if (includeMeasurementReadouts &&
          ann is PolylineAnnotation &&
          ann.isClosed) {
        final areaStr = ann.formatArea(pixelSpacing: pixelSpacing);
        if (areaStr != null) {
          final labelText = ann.label != null && ann.label!.isNotEmpty
              ? '${ann.label}: $areaStr'
              : areaStr;
          list.add(GspsTextObject(
            unformattedTextValue: labelText,
            anchorPoint: ann.polylinePoints.first,
          ));
        }
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
    final remainingTextObjects = List<GspsTextObject>.from(textObjects);
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
          // Caliper candidate. Match companion TextObject near midpoint
          final midpoint =
              Offset((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
          String? matchedLabel;
          for (int tIdx = 0; tIdx < remainingTextObjects.length; tIdx++) {
            final t = remainingTextObjects[tIdx];
            final anchor = t.anchorPoint ?? t.boundingBox?.topLeft;
            if (anchor != null && (anchor - midpoint).distance <= 30.0) {
              matchedLabel = t.unformattedTextValue;
              remainingTextObjects.removeAt(tIdx);
              break;
            }
          }

          result.add(CaliperAnnotation(
            id: id,
            start: pts[0],
            end: pts[1],
            label: matchedLabel,
            creatorName: creatorName,
            contentLabel: contentLabel,
          ));
        } else if (pts.length == 3) {
          // Angle candidate (p1, vertex, p2). Match companion TextObject near vertex
          final vertex = pts[1];
          String? matchedLabel;
          for (int tIdx = 0; tIdx < remainingTextObjects.length; tIdx++) {
            final t = remainingTextObjects[tIdx];
            final anchor = t.anchorPoint ?? t.boundingBox?.topLeft;
            if (anchor != null && (anchor - vertex).distance <= 30.0) {
              matchedLabel = t.unformattedTextValue;
              remainingTextObjects.removeAt(tIdx);
              break;
            }
          }

          result.add(AngleAnnotation(
            id: id,
            p1: pts[0],
            vertex: pts[1],
            p2: pts[2],
            label: matchedLabel,
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
        String? matchedLabel;
        for (int tIdx = 0; tIdx < remainingTextObjects.length; tIdx++) {
          final t = remainingTextObjects[tIdx];
          final anchor = t.anchorPoint ?? t.boundingBox?.topLeft;
          if (anchor != null && (anchor - center).distance <= 30.0) {
            matchedLabel = t.unformattedTextValue;
            remainingTextObjects.removeAt(tIdx);
            break;
          }
        }
        result.add(CircleAnnotation(
          id: id,
          center: center,
          radius: r,
          label: matchedLabel,
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

        String? matchedLabel;
        for (int tIdx = 0; tIdx < remainingTextObjects.length; tIdx++) {
          final t = remainingTextObjects[tIdx];
          final anchor = t.anchorPoint ?? t.boundingBox?.topLeft;
          if (anchor != null && (anchor - center).distance <= 30.0) {
            matchedLabel = t.unformattedTextValue;
            remainingTextObjects.removeAt(tIdx);
            break;
          }
        }

        result.add(EllipseAnnotation(
          id: id,
          center: center,
          radiusX: rX,
          radiusY: rY,
          rotation: rot,
          label: matchedLabel,
          creatorName: creatorName,
          contentLabel: contentLabel,
        ));
      }
    }

    // Remaining un-matched text objects become standalone TextAnnotations
    for (final t in remainingTextObjects) {
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

  static DicomAnnotation? _parseAnnotation(Map<String, dynamic> m) {
    final typeStr = m['type'] as String?;
    switch (typeStr) {
      case 'caliper':
        return CaliperAnnotation.fromJson(m);
      case 'angle':
        return AngleAnnotation.fromJson(m);
      case 'polyline':
        return PolylineAnnotation.fromJson(m);
      case 'circle':
        return CircleAnnotation.fromJson(m);
      case 'ellipse':
        return EllipseAnnotation.fromJson(m);
      case 'text':
        return TextAnnotation.fromJson(m);
      default:
        return null;
    }
  }

  factory GspsPresentationState.fromJson(Map<String, dynamic> json) {
    final annJsonList = json['annotations'] as List?;
    final annotations = <DicomAnnotation>[];

    if (annJsonList != null && annJsonList.isNotEmpty) {
      for (final raw in annJsonList) {
        if (raw is Map<String, dynamic>) {
          final ann = _parseAnnotation(raw);
          if (ann != null) annotations.add(ann);
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
      studyInstanceUid: json['studyInstanceUid'] as String?,
      seriesInstanceUid: json['seriesInstanceUid'] as String?,
      referencedSopInstanceUid: json['referencedSopInstanceUid'] as String?,
      referencedFrameNumber: json['referencedFrameNumber'] as int?,
      contentLabel: (json['contentLabel'] as String?) ?? 'GSPS_LAYER',
      contentDescription: json['contentDescription'] as String?,
      contentCreatorName: json['contentCreatorName'] as String?,
      creationDateTime: json['creationDateTime'] != null
          ? DateTime.tryParse(json['creationDateTime'] as String)
          : null,
      annotations: annotations,
    );
  }

  /// Deserializes a Presentation State from standard DICOM Part 18 JSON format
  /// (as returned by WADO-RS `/metadata` or QIDO-RS).
  factory GspsPresentationState.fromDicomJson(Map<String, dynamic> json) {
    String? getTagStr(String tag) {
      final obj = json[tag];
      if (obj is Map && obj.containsKey('Value') && obj['Value'] is List) {
        final list = obj['Value'] as List;
        if (list.isNotEmpty) {
          final first = list.first;
          if (first is String) return first;
          if (first is Map && first.containsKey('Alphabetic')) {
            return first['Alphabetic']?.toString();
          }
          return first?.toString();
        }
      }
      return null;
    }

    final sopUid = getTagStr('00080018');
    final studyUid = getTagStr('0020000D');
    final seriesUid = getTagStr('0020000E');
    final label = getTagStr('00700080') ?? 'GSPS_LAYER';
    final desc = getTagStr('00700081');
    final creator = getTagStr('00700084');

    DateTime? creationDt;
    final da = getTagStr('00700082');
    final tm = getTagStr('00700083');
    if (da != null && da.length >= 8) {
      final y = int.tryParse(da.substring(0, 4)) ?? 2000;
      final m = int.tryParse(da.substring(4, 6)) ?? 1;
      final d = int.tryParse(da.substring(6, 8)) ?? 1;
      int hr = 0, min = 0, sec = 0;
      if (tm != null && tm.length >= 2) {
        hr = int.tryParse(tm.substring(0, 2)) ?? 0;
        if (tm.length >= 4) min = int.tryParse(tm.substring(2, 4)) ?? 0;
        if (tm.length >= 6) sec = int.tryParse(tm.substring(4, 6)) ?? 0;
      }
      creationDt = DateTime(y, m, d, hr, min, sec);
    }

    // Extract referenced frame and image context
    String? refSeriesUid;
    String? refSopUid;
    int? refFrame;
    final refSeriesSeq = json['00081115'];
    if (refSeriesSeq is Map && refSeriesSeq['Value'] is List) {
      final seriesItems = refSeriesSeq['Value'] as List;
      if (seriesItems.isNotEmpty && seriesItems.first is Map) {
        final firstSeries = seriesItems.first as Map<String, dynamic>;
        final rawSeriesUid = firstSeries['0020000E'];
        if (rawSeriesUid is Map && rawSeriesUid['Value'] is List && (rawSeriesUid['Value'] as List).isNotEmpty) {
          refSeriesUid = (rawSeriesUid['Value'] as List).first?.toString();
        }
        final refImgSeq = firstSeries['00081140'];
        if (refImgSeq is Map && refImgSeq['Value'] is List) {
          final imgItems = refImgSeq['Value'] as List;
          if (imgItems.isNotEmpty && imgItems.first is Map) {
            final firstImg = imgItems.first as Map<String, dynamic>;
            final sopItem = firstImg['00081155'];
            if (sopItem is Map && sopItem['Value'] is List && (sopItem['Value'] as List).isNotEmpty) {
              refSopUid = (sopItem['Value'] as List).first?.toString();
            }
            final frameItem = firstImg['00081160'];
            if (frameItem is Map && frameItem['Value'] is List && (frameItem['Value'] as List).isNotEmpty) {
              final rawF = (frameItem['Value'] as List).first;
              if (rawF is int) {
                refFrame = rawF;
              } else if (rawF is String) {
                refFrame = int.tryParse(rawF);
              }
            }
          }
        }
      }
    }

    // Parse Graphic Annotation Sequence (0070,0001)
    final graphicObjects = <GspsGraphicObject>[];
    final textObjects = <GspsTextObject>[];

    final graphicAnnotationSeq = json['00700001'];
    if (graphicAnnotationSeq is Map && graphicAnnotationSeq['Value'] is List) {
      for (final annItem in graphicAnnotationSeq['Value'] as List) {
        if (annItem is! Map) continue;
        final m = annItem as Map<String, dynamic>;

        // Parse GraphicObjectSequence (0070,0009)
        final gSeq = m['00700009'];
        if (gSeq is Map && gSeq['Value'] is List) {
          for (final gRaw in gSeq['Value'] as List) {
            if (gRaw is! Map) continue;
            final gMap = gRaw as Map<String, dynamic>;
            final units = (gMap['00700020']?['Value'] as List?)?.firstOrNull?.toString() ?? 'PIXEL';
            final type = (gMap['00700023']?['Value'] as List?)?.firstOrNull?.toString() ?? 'POLYLINE';
            final filled = ((gMap['00700024']?['Value'] as List?)?.firstOrNull?.toString())?.toUpperCase() == 'Y';
            final rawData = (gMap['00700022']?['Value'] as List?) ?? [];
            final floats = rawData.map((e) => (e as num).toDouble()).toList();

            graphicObjects.add(GspsGraphicObject(
              graphicType: type,
              units: units,
              graphicData: floats,
              filled: filled,
            ));
          }
        }

        // Parse TextObjectSequence (0070,0008)
        final tSeq = m['00700008'];
        if (tSeq is Map && tSeq['Value'] is List) {
          for (final tRaw in tSeq['Value'] as List) {
            if (tRaw is! Map) continue;
            final tMap = tRaw as Map<String, dynamic>;
            final textVal = (tMap['00700006']?['Value'] as List?)?.firstOrNull?.toString() ??
                (tMap['00680006']?['Value'] as List?)?.firstOrNull?.toString() ??
                '';
            Offset? anchor;
            final rawAnchor = tMap['00700014']?['Value'] as List?;
            if (rawAnchor != null && rawAnchor.length >= 2) {
              anchor = Offset(
                (rawAnchor[0] as num).toDouble(),
                (rawAnchor[1] as num).toDouble(),
              );
            }
            final vis = ((tMap['00700015']?['Value'] as List?)?.firstOrNull?.toString())?.toUpperCase() != 'N';
            final anchorUnits = (tMap['00700016']?['Value'] as List?)?.firstOrNull?.toString() ?? 'PIXEL';

            textObjects.add(GspsTextObject(
              unformattedTextValue: textVal,
              anchorPoint: anchor,
              anchorUnits: anchorUnits,
              anchorPointVisible: vis,
            ));
          }
        }
      }
    }

    // 1. Check for GoSmart Health private semantics tag (0079,1001)
    // When present, provides 100% fidelity reconstruction of Caliper, Angle, and all widgets.
    final privateSemantics = json['00791001'];
    if (privateSemantics is Map && privateSemantics['Value'] is List && (privateSemantics['Value'] as List).isNotEmpty) {
      final rawVal = (privateSemantics['Value'] as List).first;
      if (rawVal is String && rawVal.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawVal);
          if (decoded is List) {
            final privateAnnotations = <DicomAnnotation>[];
            for (final item in decoded) {
              if (item is Map<String, dynamic>) {
                final ann = _parseAnnotation(item);
                if (ann != null) privateAnnotations.add(ann);
              }
            }
            if (privateAnnotations.isNotEmpty) {
              return GspsPresentationState(
                sopInstanceUid: sopUid,
                studyInstanceUid: studyUid,
                seriesInstanceUid: seriesUid,
                referencedSeriesUid: refSeriesUid,
                referencedSopInstanceUid: refSopUid,
                referencedFrameNumber: refFrame,
                contentLabel: label,
                contentDescription: desc,
                contentCreatorName: creator,
                creationDateTime: creationDt,
                annotations: privateAnnotations,
              );
            }
          }
        } catch (_) {
          // Fallback to standard DICOM sequence reconstruction
        }
      }
    }

    // 2. Standard DICOM Graphic & Text Object Sequence Reconstruction (fallback for 3rd-party PACS)
    final annotations = GspsPresentationState.fromDicomObjects(
      graphicObjects: graphicObjects,
      textObjects: textObjects,
      creatorName: creator,
      contentLabel: label,
    );

    return GspsPresentationState(
      sopInstanceUid: sopUid,
      studyInstanceUid: studyUid,
      seriesInstanceUid: seriesUid,
      referencedSeriesUid: refSeriesUid,
      referencedSopInstanceUid: refSopUid,
      referencedFrameNumber: refFrame,
      contentLabel: label,
      contentDescription: desc,
      contentCreatorName: creator,
      creationDateTime: creationDt,
      annotations: annotations,
    );
  }

  /// Encodes this Presentation State into a standard DICOM Part 10 binary dataset (`.dcm`).
  Uint8List toDicomPart10Bytes({
    required String studyInstanceUid,
    required String seriesInstanceUid,
    required String sopInstanceUid,
    int? frameNumber,
    PixelSpacing? pixelSpacing,
    String? patientName,
    String? patientId,
    String? patientBirthDate,
    String? patientSex,
    String? studyDate,
    String? studyTime,
    String? accessionNumber,
    String? presentationSeriesUid,
    String? presentationSopUid,
  }) {
    return GspsDicomEncoder.encodePart10(
      gsps: this,
      studyInstanceUid: studyInstanceUid,
      seriesInstanceUid: seriesInstanceUid,
      sopInstanceUid: sopInstanceUid,
      frameNumber: frameNumber ?? referencedFrameNumber,
      pixelSpacing: pixelSpacing,
      patientName: patientName,
      patientId: patientId,
      patientBirthDate: patientBirthDate,
      patientSex: patientSex,
      studyDate: studyDate,
      studyTime: studyTime,
      accessionNumber: accessionNumber,
      presentationSeriesUid: presentationSeriesUid,
      presentationSopUid: presentationSopUid,
    );
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory GspsPresentationState.fromJsonString(String jsonStr) =>
      GspsPresentationState.fromJson(
          json.decode(jsonStr) as Map<String, dynamic>);
}

