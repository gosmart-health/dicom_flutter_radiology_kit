import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

void main() {
  group('DICOM GSPS Softcopy Presentation State Serialization Tests', () {
    test('Maps all annotation types to standard DICOM PS 3.3 Graphic & Text Objects', () {
      final caliper = CaliperAnnotation(
        id: 'c1',
        start: const Offset(10, 20),
        end: const Offset(50, 60),
        creatorName: 'Dr. Smith',
        contentLabel: 'CALIPER_1',
      );

      final angle = AngleAnnotation(
        id: 'a1',
        p1: const Offset(10, 10),
        vertex: const Offset(20, 20),
        p2: const Offset(30, 10),
        creatorName: 'Dr. Jones',
      );

      final circle = CircleAnnotation(
        id: 'circ1',
        center: const Offset(100, 100),
        radius: 25.0,
        creatorName: 'Dr. Smith',
      );

      final ellipse = EllipseAnnotation(
        id: 'e1',
        center: const Offset(200, 200),
        radiusX: 40.0,
        radiusY: 20.0,
        rotation: 0.0,
        creatorName: 'Dr. Smith',
      );

      final text = TextAnnotation(
        id: 't1',
        anchor: const Offset(300, 300),
        text: 'Nodule 4mm',
        creatorName: 'Dr. Jones',
      );

      final gsps = GspsPresentationState(
        sopInstanceUid: '1.2.840.10008.5.1.4.1.1.11.1.999',
        contentLabel: 'STUDY_GSPS',
        contentDescription: 'Review marks',
        contentCreatorName: 'Dr. Smith',
        annotations: [caliper, angle, circle, ellipse, text],
      );

      // Verify Graphic Objects
      final graphicObjects = gsps.toGraphicObjects();
      expect(graphicObjects.length, equals(4));

      // Caliper -> POLYLINE with 4 values
      expect(graphicObjects[0].graphicType, equals('POLYLINE'));
      expect(graphicObjects[0].graphicData, equals([10.0, 20.0, 50.0, 60.0]));

      // Angle -> POLYLINE with 6 values
      expect(graphicObjects[1].graphicType, equals('POLYLINE'));
      expect(graphicObjects[1].graphicData.length, equals(6));

      // Circle -> CIRCLE with 4 values (center, perimeter)
      expect(graphicObjects[2].graphicType, equals('CIRCLE'));
      expect(graphicObjects[2].graphicData, equals([100.0, 100.0, 125.0, 100.0]));

      // Ellipse -> ELLIPSE with 8 values (4 points: major endpoints, minor endpoints)
      expect(graphicObjects[3].graphicType, equals('ELLIPSE'));
      expect(graphicObjects[3].graphicData.length, equals(8));
      expect(graphicObjects[3].graphicData[0], equals(160.0)); // majorStart.dx
      expect(graphicObjects[3].graphicData[2], equals(240.0)); // majorEnd.dx

      // Verify Text Objects
      final textObjects = gsps.toTextObjects();
      expect(textObjects.length, equals(1));
      expect(textObjects[0].unformattedTextValue, equals('Nodule 4mm'));
      expect(textObjects[0].anchorPoint, equals(const Offset(300, 300)));
    });

    test('Full JSON serialization and round-trip parsing', () {
      final caliper = CaliperAnnotation(
        id: 'c1',
        start: const Offset(15, 25),
        end: const Offset(80, 95),
        label: 'Left lung lesion',
        creatorName: 'Radiologist A',
      );

      final circle = CircleAnnotation(
        id: 'circ1',
        center: const Offset(150, 150),
        radius: 35.0,
        creatorName: 'Radiologist B',
      );

      final gsps = GspsPresentationState(
        contentLabel: 'PERSISTED_STATE',
        annotations: [caliper, circle],
      );

      final jsonStr = gsps.toJsonString();
      final restored = GspsPresentationState.fromJsonString(jsonStr);

      expect(restored.contentLabel, equals('PERSISTED_STATE'));
      expect(restored.annotations.length, equals(2));

      final restoredCal = restored.annotations[0] as CaliperAnnotation;
      expect(restoredCal.start, equals(const Offset(15, 25)));
      expect(restoredCal.end, equals(const Offset(80, 95)));
      expect(restoredCal.label, equals('Left lung lesion'));
      expect(restoredCal.creatorName, equals('Radiologist A'));

      final restoredCirc = restored.annotations[1] as CircleAnnotation;
      expect(restoredCirc.center, equals(const Offset(150, 150)));
      expect(restoredCirc.radius, equals(35.0));
      expect(restoredCirc.creatorName, equals('Radiologist B'));
    });

    test('Reconstructing annotations from standard DICOM sequence JSON', () {
      final dicomJson = {
        'contentLabel': 'DICOM_RECONSTRUCTED',
        'contentCreatorName': 'Dr. Provider',
        'dicomGraphicObjectSequence': [
          {
            'GraphicAnnotationUnits': 'PIXEL',
            'GraphicDimensions': 2,
            'NumberOfGraphicPoints': 2,
            'GraphicData': [50.0, 50.0, 100.0, 100.0],
            'GraphicType': 'POLYLINE',
            'GraphicFilled': 'N',
          },
          {
            'GraphicAnnotationUnits': 'PIXEL',
            'GraphicDimensions': 2,
            'NumberOfGraphicPoints': 2,
            'GraphicData': [200.0, 200.0, 250.0, 200.0],
            'GraphicType': 'CIRCLE',
            'GraphicFilled': 'N',
          }
        ],
        'dicomTextObjectSequence': [
          {
            'UnformattedTextValue': 'Imported Text',
            'AnchorPoint': [300.0, 300.0],
            'AnchorPointAnnotationUnits': 'PIXEL',
            'AnchorPointVisibility': 'Y',
          }
        ],
      };

      final gsps = GspsPresentationState.fromJson(dicomJson);
      expect(gsps.annotations.length, equals(3));
      expect(gsps.annotations[0], isA<CaliperAnnotation>());
      expect(gsps.annotations[1], isA<CircleAnnotation>());
      expect(gsps.annotations[2], isA<TextAnnotation>());
      expect((gsps.annotations[2] as TextAnnotation).text, equals('Imported Text'));
    });

    test('Multi-collaborator filtering in AnnotationController', () {
      final controller = AnnotationController(activeCreator: 'Dr. Alice');

      final ann1 = CaliperAnnotation(
        id: '1',
        start: const Offset(10, 10),
        end: const Offset(20, 20),
        creatorName: 'Dr. Alice',
      );
      final ann2 = CaliperAnnotation(
        id: '2',
        start: const Offset(30, 30),
        end: const Offset(40, 40),
        creatorName: 'Dr. Bob',
      );
      final ann3 = TextAnnotation(
        id: '3',
        anchor: const Offset(50, 50),
        text: 'Review note',
        creatorName: 'Dr. Charlie',
      );

      controller.addAnnotation(ann1);
      controller.addAnnotation(ann2);
      controller.addAnnotation(ann3);

      // 1. All collaborators
      expect(controller.collaborators, containsAll(['Dr. Alice', 'Dr. Bob', 'Dr. Charlie']));
      expect(controller.visibleAnnotations.length, equals(3));

      // 2. Filter to Dr. Alice only
      controller.setFilterCreator('Dr. Alice');
      expect(controller.visibleAnnotations.length, equals(1));
      expect(controller.visibleAnnotations.first.creatorName, equals('Dr. Alice'));

      // 3. Filter to Dr. Bob only
      controller.setFilterCreator('Dr. Bob');
      expect(controller.visibleAnnotations.length, equals(1));
      expect(controller.visibleAnnotations.first.creatorName, equals('Dr. Bob'));

      // 4. Reset filter to see ALL collaborators
      controller.setFilterCreator(null);
      expect(controller.visibleAnnotations.length, equals(3));
    });
  });
}
