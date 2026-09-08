import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

void main() {
  group('PixelSpacing tests', () {
    test('Calculates Euclidean distance in mm with anisotropic spacing', () {
      // Column spacing (dx) = 0.5 mm/px, Row spacing (dy) = 1.0 mm/px
      const spacing = PixelSpacing(rowSpacing: 1.0, columnSpacing: 0.5);

      // dx = 60 pixels -> 30 mm; dy = 40 pixels -> 40 mm
      // distance = sqrt(30^2 + 40^2) = 50 mm
      final dist = spacing.distanceMm(60.0, 40.0);
      expect(dist, closeTo(50.0, 1e-6));
    });

    test('tryParse parses DICOM tag string and list representations', () {
      final fromString = PixelSpacing.tryParse('0.75\\0.75');
      expect(fromString, isNotNull);
      expect(fromString!.rowSpacing, equals(0.75));
      expect(fromString.columnSpacing, equals(0.75));

      final fromComma = PixelSpacing.tryParse('1.25, 0.5');
      expect(fromComma, isNotNull);
      expect(fromComma!.rowSpacing, equals(1.25));
      expect(fromComma.columnSpacing, equals(0.5));

      final fromList = PixelSpacing.tryParse([0.8, 0.4]);
      expect(fromList, isNotNull);
      expect(fromList!.rowSpacing, equals(0.8));
      expect(fromList.columnSpacing, equals(0.4));

      expect(PixelSpacing.tryParse(null), isNull);
      expect(PixelSpacing.tryParse('invalid'), isNull);
    });

    test('Calculates caliper length and closed contour area with real CT pixel spacing', () {
      const ctSpacing = PixelSpacing(rowSpacing: 0.661468, columnSpacing: 0.661468);

      final caliper = CaliperAnnotation(
        id: 'cal_ct',
        start: const Offset(0, 0),
        end: const Offset(100, 0), // 100 pixels horizontally -> 66.15 mm
      );
      expect(caliper.computeDistance(pixelSpacing: ctSpacing), closeTo(66.1468, 1e-4));
      expect(caliper.formatDistance(pixelSpacing: ctSpacing), equals('66.1 mm'));

      final circle = CircleAnnotation(
        id: 'circ_ct',
        center: const Offset(50, 50),
        radius: 10.0,
      );
      // Area in px = 100 * pi. In mm² = 100 * pi * 0.661468^2 =~ 137.456 mm² -> 1.37 cm²
      expect(
        circle.computeArea(pixelSpacing: ctSpacing),
        closeTo(100 * math.pi * 0.661468 * 0.661468, 1e-3),
      );
      expect(circle.formatArea(pixelSpacing: ctSpacing), equals('1.37 cm²'));
    });
  });

  group('CaliperAnnotation tests', () {
    test('Calculates length in mm and formats display label', () {
      final caliper = CaliperAnnotation(
        id: 'cal_1',
        start: const Offset(100, 100),
        end: const Offset(160, 180), // dx = 60, dy = 80 -> px dist = 100
      );

      // Without pixel spacing -> pixels
      expect(caliper.computeDistance(), closeTo(100.0, 1e-6));
      expect(caliper.formatDistance(), equals('100.0 px'));

      // With isotropic 0.5 mm spacing -> 50.0 mm
      const spacing = PixelSpacing(rowSpacing: 0.5, columnSpacing: 0.5);
      expect(caliper.computeDistance(pixelSpacing: spacing), closeTo(50.0, 1e-6));
      expect(caliper.formatDistance(pixelSpacing: spacing), equals('50.0 mm'));
    });

    test('Handles and translation work accurately', () {
      final caliper = CaliperAnnotation(
        id: 'cal_1',
        start: const Offset(10, 20),
        end: const Offset(30, 40),
      );

      final translated = caliper.translate(const Offset(5, -5));
      expect(translated.start, equals(const Offset(15, 15)));
      expect(translated.end, equals(const Offset(35, 35)));

      final updatedStart = caliper.updateHandle('start', const Offset(0, 0));
      expect(updatedStart.start, equals(Offset.zero));
      expect(updatedStart.end, equals(const Offset(30, 40)));

      // Hit testing along segment
      expect(caliper.hitTest(const Offset(20, 30), 2.0), isTrue);
      expect(caliper.hitTest(const Offset(100, 100), 2.0), isFalse);
    });
  });

  group('AngleAnnotation tests', () {
    test('Calculates 90-degree right angle and 45-degree acute angle accurately', () {
      final rightAngle = AngleAnnotation(
        id: 'ang_90',
        p1: const Offset(100, 50),
        vertex: const Offset(100, 100),
        p2: const Offset(150, 100),
      );
      expect(rightAngle.computeAngleDegrees(), closeTo(90.0, 1e-4));
      expect(rightAngle.formatAngle(), equals('90.0°'));

      final acuteAngle = AngleAnnotation(
        id: 'ang_45',
        p1: const Offset(150, 50), // 45 degrees
        vertex: const Offset(100, 100),
        p2: const Offset(150, 100), // 0 degrees
      );
      expect(acuteAngle.computeAngleDegrees(), closeTo(45.0, 1e-4));
      expect(acuteAngle.formatAngle(), equals('45.0°'));
    });

    test('Angle translation and hit testing', () {
      final angle = AngleAnnotation(
        id: 'ang_1',
        p1: const Offset(0, 10),
        vertex: const Offset(0, 0),
        p2: const Offset(10, 0),
      );

      expect(angle.hitTest(const Offset(0, 5), 1.0), isTrue);
      expect(angle.hitTest(const Offset(5, 0), 1.0), isTrue);
      expect(angle.hitTest(const Offset(5, 5), 1.0), isFalse);

      final moved = angle.translate(const Offset(10, 10));
      expect(moved.vertex, equals(const Offset(10, 10)));
    });
  });

  group('PolylineAnnotation tests', () {
    test('Bounding box and handle updates', () {
      final poly = PolylineAnnotation(
        id: 'poly_1',
        points: const [Offset(10, 10), Offset(50, 20), Offset(30, 80)],
      );

      expect(poly.points.length, equals(3));
      final handles = poly.getHandles();
      expect(handles.length, equals(3));

      final updated = poly.updateHandle('point_1', const Offset(60, 25));
      expect(updated.points[1], equals(const Offset(60, 25)));
      expect(updated.points[0], equals(const Offset(10, 10)));
    });
  });

  group('CircleAnnotation tests', () {
    test('Perimeter point and radius resizing via handles', () {
      final circle = CircleAnnotation(
        id: 'circ_1',
        center: const Offset(100, 100),
        radius: 50.0,
      );

      expect(circle.perimeterPoint, equals(const Offset(150, 100)));
      expect(circle.points.length, equals(2));

      // Resize via pull handle
      final resized = circle.updateHandle('pull_right', const Offset(180, 100));
      expect(resized.radius, closeTo(80.0, 1e-4));

      // Hit test on circumference
      expect(circle.hitTest(const Offset(150, 100), 2.0), isTrue);
      expect(circle.hitTest(const Offset(100, 150), 2.0), isTrue);
      expect(circle.hitTest(const Offset(100, 100), 2.0), isFalse); // Inside, not on edge
    });
  });

  group('EllipseAnnotation tests', () {
    test('Generates 4 standard DICOM GSPS endpoints and rotation handle', () {
      final ellipse = EllipseAnnotation(
        id: 'ell_1',
        center: const Offset(100, 100),
        radiusX: 40.0,
        radiusY: 20.0,
        rotation: 0.0,
      );

      // Points: [majorStart, majorEnd, minorStart, minorEnd]
      expect(ellipse.points.length, equals(4));
      expect(ellipse.majorStart, equals(const Offset(60, 100)));
      expect(ellipse.majorEnd, equals(const Offset(140, 100)));
      expect(ellipse.minorStart, equals(const Offset(100, 80)));
      expect(ellipse.minorEnd, equals(const Offset(100, 120)));

      // Rotation handle extends along major axis
      expect(ellipse.rotationHandlePoint.dx, greaterThan(ellipse.majorEnd.dx));
      expect(ellipse.rotationHandlePoint.dy, equals(100.0));
    });

    test('Rotation handle rotates ellipse properly', () {
      final ellipse = EllipseAnnotation(
        id: 'ell_1',
        center: const Offset(100, 100),
        radiusX: 40.0,
        radiusY: 20.0,
        rotation: 0.0,
      );

      // Drag rotation handle straight down (90 degrees = pi / 2)
      final rotated = ellipse.updateHandle('rotation', const Offset(100, 200));
      expect(rotated.rotation, closeTo(math.pi / 2, 1e-4));

      // Now major axis is along Y!
      expect(rotated.majorEnd.dx, closeTo(100.0, 1e-4));
      expect(rotated.majorEnd.dy, closeTo(140.0, 1e-4));
    });

    test('Pull handles resize semi-axes independently', () {
      final ellipse = EllipseAnnotation(
        id: 'ell_1',
        center: const Offset(100, 100),
        radiusX: 40.0,
        radiusY: 20.0,
        rotation: 0.0,
      );

      final resizedX = ellipse.updateHandle('pull_major_end', const Offset(170, 100));
      expect(resizedX.radiusX, closeTo(70.0, 1e-4));
      expect(resizedX.radiusY, equals(20.0)); // Unchanged

      final resizedY = ellipse.updateHandle('pull_minor_end', const Offset(100, 135));
      expect(resizedY.radiusY, closeTo(35.0, 1e-4));
    });
  });

  group('TextAnnotation tests', () {
    test('Anchor, translation, and hit test', () {
      final text = TextAnnotation(
        id: 'txt_1',
        anchor: const Offset(50, 50),
        text: 'Suspicious nodule',
      );

      expect(text.hitTest(const Offset(55, 55), 2.0), isTrue);
      expect(text.hitTest(const Offset(500, 500), 2.0), isFalse);

      final translated = text.translate(const Offset(20, 10));
      expect(translated.anchor, equals(const Offset(70, 60)));
    });
  });

  group('Closed Contour Area Computation tests', () {
    test('CircleAnnotation computes area in pixels and mm²/cm²', () {
      final circle = CircleAnnotation(
        id: 'c1',
        center: const Offset(100, 100),
        radius: 10.0,
      );

      // Area in pixels: pi * 10^2 = 100 * pi =~ 314.159 px²
      final pxArea = circle.computeArea();
      expect(pxArea, closeTo(math.pi * 100, 1e-4));
      expect(circle.formatArea(), equals('314.2 px²'));

      // With isotropic 0.5 mm spacing:
      // areaMm2 = 314.159 * 0.5 * 0.5 = 78.5398 mm² (< 100 mm² -> mm²)
      const spacingIso = PixelSpacing(rowSpacing: 0.5, columnSpacing: 0.5);
      final mmArea = circle.computeArea(pixelSpacing: spacingIso);
      expect(mmArea, closeTo(math.pi * 100 * 0.25, 1e-4));
      expect(circle.formatArea(pixelSpacing: spacingIso), equals('78.5 mm²'));

      // Large circle with 1.0 mm spacing (radius = 50 -> area = 2500 * pi =~ 7853.98 mm² -> 78.54 cm²)
      final largeCircle = CircleAnnotation(
        id: 'c_large',
        center: const Offset(100, 100),
        radius: 50.0,
      );
      expect(
        largeCircle.formatArea(pixelSpacing: PixelSpacing.isotropic1mm),
        equals('78.54 cm²'),
      );
    });

    test('EllipseAnnotation computes area in pixels and mm²/cm²', () {
      final ellipse = EllipseAnnotation(
        id: 'e1',
        center: const Offset(200, 200),
        radiusX: 20.0,
        radiusY: 10.0,
      );

      // Area in pixels: pi * 20 * 10 = 200 * pi =~ 628.318 px²
      expect(ellipse.computeArea(), closeTo(200 * math.pi, 1e-4));
      expect(ellipse.formatArea(), equals('628.3 px²'));

      // With anisotropic spacing (row = 1.0, col = 0.5):
      // areaMm2 = 628.318 * 0.5 = 314.159 mm² (>= 100 mm² -> 3.14 cm²)
      const spacingAniso = PixelSpacing(rowSpacing: 1.0, columnSpacing: 0.5);
      expect(
        ellipse.computeArea(pixelSpacing: spacingAniso),
        closeTo(100 * math.pi, 1e-4),
      );
      expect(ellipse.formatArea(pixelSpacing: spacingAniso), equals('3.14 cm²'));
    });

    test('PolylineAnnotation computes area using Shoelace formula on closed contours', () {
      // 100x100 square: (0,0), (100,0), (100,100), (0,100)
      final square = PolylineAnnotation(
        id: 'poly_sq',
        points: const [
          Offset(0, 0),
          Offset(100, 0),
          Offset(100, 100),
          Offset(0, 100),
        ],
        isClosed: true,
      );

      expect(square.isClosedOrClosureDetected, isTrue);
      // Area = 10,000 px²
      expect(square.computeArea(), closeTo(10000.0, 1e-4));
      expect(square.formatArea(), equals('10000.0 px²'));

      // With 1.0 mm spacing: 10,000 mm² = 100.00 cm²
      expect(
        square.formatArea(pixelSpacing: PixelSpacing.isotropic1mm),
        equals('100.00 cm²'),
      );
      expect(square.centroid, equals(const Offset(50, 50)));
    });

    test('PolylineAnnotation detects closure when endpoints are within threshold', () {
      // Triangle where start is (0,0) and end is (5, 3) (distance = sqrt(34) =~ 5.83 <= 12.0)
      final detectedPolyline = PolylineAnnotation(
        id: 'poly_triangle',
        points: const [
          Offset(0, 0),
          Offset(60, 0),
          Offset(30, 40),
          Offset(5, 3), // proximal to (0,0)
        ],
        isClosed: false,
      );

      expect(detectedPolyline.isClosedOrClosureDetected, isTrue);
      expect(detectedPolyline.computeArea(), isNotNull);
      expect(detectedPolyline.formatArea(), isNotNull);
    });

    test('Open PolylineAnnotation returns null for area computation', () {
      final openPolyline = PolylineAnnotation(
        id: 'poly_open',
        points: const [
          Offset(0, 0),
          Offset(100, 0),
          Offset(100, 100),
        ],
        isClosed: false,
      );

      expect(openPolyline.isClosedOrClosureDetected, isFalse);
      expect(openPolyline.computeArea(), isNull);
      expect(openPolyline.formatArea(), isNull);
    });
  });

  group('Delete functionality tests', () {
    test('deleteSelected removes selected annotation', () {
      final controller = AnnotationController();
      final ann1 = CircleAnnotation(
        id: 'c1',
        center: const Offset(10, 10),
        radius: 5.0,
      );
      final ann2 = CircleAnnotation(
        id: 'c2',
        center: const Offset(20, 20),
        radius: 10.0,
      );

      controller.addAnnotation(ann1);
      controller.addAnnotation(ann2);
      expect(controller.allAnnotations.length, equals(2));

      // Select ann1 and delete
      controller.selectAnnotation(ann1);
      controller.deleteSelected();

      expect(controller.allAnnotations.length, equals(1));
      expect(controller.allAnnotations.first.id, equals('c2'));
      expect(controller.selectedAnnotation, isNull);
    });

    test('Immediately after drawing, deleteSelected removes the newly created object', () {
      final controller = AnnotationController();
      final caliper = CaliperAnnotation(
        id: 'cal_new',
        start: const Offset(0, 0),
        end: const Offset(50, 50),
      );

      // Immediately after adding/drawing:
      controller.addAnnotation(caliper);
      expect(controller.selectedAnnotation?.id, equals('cal_new'));
      expect(controller.hasDeletable, isTrue);

      controller.deleteSelected();
      expect(controller.allAnnotations, isEmpty);
      expect(controller.selectedAnnotation, isNull);
      expect(controller.hasDeletable, isFalse);
    });

    test('deleteSelected deletes most recent annotation when none explicitly selected', () {
      final controller = AnnotationController();
      final a1 = CircleAnnotation(id: 'a1', center: Offset.zero, radius: 5);
      final a2 = CircleAnnotation(id: 'a2', center: Offset.zero, radius: 10);

      controller.addAnnotation(a1);
      controller.addAnnotation(a2);
      controller.selectAnnotation(null); // Clear selection

      expect(controller.hasDeletable, isTrue);
      controller.deleteSelected();

      // a2 (last created) was deleted
      expect(controller.allAnnotations.length, equals(1));
      expect(controller.allAnnotations.first.id, equals('a1'));
    });
  });
}
