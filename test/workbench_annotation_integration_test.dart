import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../example/lib/main.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Workbench & Annotation Layer Integration Tests', () {
    testWidgets(
        'Workbench renders annotation toolbar, activates tools, and loads samples',
        (tester) async {
      // Set test screen size large enough for 1920x1080 workstation
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const DicomViewerApp());
      await tester.pumpAndSettle();

      // Verify DicomViewerWorkbench and DicomAnnotationLayer are present
      expect(find.byType(DicomViewerWorkbench), findsOneWidget);
      expect(find.byType(DicomAnnotationLayer), findsOneWidget);

      // Verify Annotation Toolbar tool buttons exist
      expect(find.text('Pan/W-L'), findsOneWidget);
      expect(find.text('Select'), findsOneWidget);
      expect(find.text('Caliper (mm)'), findsOneWidget);
      expect(find.text('Angle'), findsOneWidget);
      expect(find.text('Circle'), findsOneWidget);
      expect(find.text('Ellipse'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);
      expect(find.text('Samples'), findsOneWidget);
      expect(find.text('GSPS JSON'), findsOneWidget);

      // Tap "Samples" to load clinical sample annotations
      await tester.tap(find.text('Samples'));
      await tester.pumpAndSettle();

      // Verify annotations exist in the layer
      final layer = tester.widget<DicomAnnotationLayer>(
        find.byType(DicomAnnotationLayer).first,
      );
      final annotations = layer.annotationController.allAnnotations;
      expect(annotations.length, equals(5));

      // Verify specific annotation types and measurements
      final caliper = annotations.whereType<CaliperAnnotation>().first;
      expect(caliper.label, equals('Thoracic width'));
      // dx = 372 - 140 = 232 px * 0.625 mm = 145.0 mm
      final distMm = caliper.computeDistance(
        pixelSpacing: layer.viewportController.pixelSpacing,
      );
      expect(distMm, closeTo(145.0, 1.0));

      final angle = annotations.whereType<AngleAnnotation>().first;
      expect(angle.label, equals('Carinal angle'));

      final circle = annotations.whereType<CircleAnnotation>().first;
      expect(circle.label, equals('Hyperdense nodule'));

      final text = annotations.whereType<TextAnnotation>().first;
      expect(text.text, equals('Suspicious nodule (180 HU)'));

      // Verify Collaborator filtering
      expect(
        layer.annotationController.collaborators,
        containsAll(['Dr. Alice', 'Dr. Bob']),
      );

      // Filter to Dr. Alice
      layer.annotationController.setFilterCreator('Dr. Alice');
      await tester.pump();
      expect(layer.annotationController.visibleAnnotations.length, equals(3));
      for (final a in layer.annotationController.visibleAnnotations) {
        expect(a.creatorName, equals('Dr. Alice'));
      }

      // Reset to All Collaborators
      layer.annotationController.setFilterCreator(null);
      await tester.pump();
      expect(layer.annotationController.visibleAnnotations.length, equals(5));

      // Tap "GSPS JSON" to open modal dialog
      await tester.ensureVisible(find.text('GSPS JSON'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GSPS JSON'));
      await tester.pumpAndSettle();

      // Verify dialog is opened and contains GSPS sequence tags
      expect(
        find.text('DICOM GSPS Presentation State JSON'),
        findsOneWidget,
      );
      expect(find.byType(SelectableText), findsOneWidget);

      // Close modal
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('DICOM GSPS Presentation State JSON'), findsNothing);
    });

    testWidgets(
        'Tapping Pan/W-L restores Pan, Zoom, and Window Level gestures on the Workbench',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const DicomViewerApp());
      await tester.pumpAndSettle();

      final layerFinder = find.byType(DicomAnnotationLayer).first;
      final layer = tester.widget<DicomAnnotationLayer>(layerFinder);
      final viewportCtrl = layer.viewportController;

      final initialCenter = viewportCtrl.windowCenter;
      final initialWidth = viewportCtrl.windowWidth;
      final initialZoom = viewportCtrl.zoom;

      final center = tester.getCenter(layerFinder);

      // 1. Activate Caliper tool and draw a Caliper
      await tester.tap(find.text('Caliper (mm)'));
      await tester.pumpAndSettle();

      final caliperGesture = await tester.startGesture(center - const Offset(50, 0));
      await tester.pump();
      await caliperGesture.moveTo(center + const Offset(50, 0));
      await tester.pump();
      await caliperGesture.up();
      await tester.pumpAndSettle();

      // Tool auto-switched to Select and shape was drawn
      expect(layer.annotationController.allAnnotations.length, equals(1));

      // 2. Click "Pan/W-L" button in toolbar
      await tester.tap(find.text('Pan/W-L'));
      await tester.pumpAndSettle();

      expect(layer.annotationController.activeTool, equals(AnnotationTool.none));

      // 3. Perform Left-drag on viewport to adjust Window/Level
      final wlGesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await tester.pump();
      await wlGesture.moveTo(center + const Offset(40, 20));
      await tester.pump();
      await wlGesture.up();
      await tester.pumpAndSettle();

      // Window Center and Width must have changed (gestures restored!)
      expect(viewportCtrl.windowWidth, isNot(equals(initialWidth)));
      expect(viewportCtrl.windowCenter, isNot(equals(initialCenter)));

      // 4. Perform Right-drag on viewport to adjust Zoom
      final zoomGesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await zoomGesture.moveTo(center - const Offset(0, 50));
      await tester.pump();
      await zoomGesture.up();
      await tester.pumpAndSettle();

      expect(viewportCtrl.zoom, greaterThan(initialZoom));
    });

    testWidgets(
        'Switching study/fixtures isolates and restores annotations per study/series',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const DicomViewerApp());
      await tester.pumpAndSettle();

      final layerFinder = find.byType(DicomAnnotationLayer).first;
      var layer = tester.widget<DicomAnnotationLayer>(layerFinder);

      // 1. Initially CT Phantom is loaded with 0 annotations.
      expect(layer.annotationController.allAnnotations, isEmpty);

      // 2. Load Samples on CT Phantom
      await tester.tap(find.text('Samples'));
      await tester.pumpAndSettle();
      expect(layer.annotationController.allAnnotations.length, equals(5));

      // 3. Switch fixture to "TG18-QC" via fixture chip
      await tester.tap(find.text('TG18-QC'));
      await tester.pumpAndSettle();

      layer = tester.widget<DicomAnnotationLayer>(find.byType(DicomAnnotationLayer).first);
      // Verify TG18-QC has 0 annotations (clean slate, no leakage from CT Phantom!)
      expect(layer.annotationController.allAnnotations, isEmpty);

      // 4. Switch back to "CT Phantom"
      await tester.tap(find.text('CT Phantom'));
      await tester.pumpAndSettle();

      layer = tester.widget<DicomAnnotationLayer>(find.byType(DicomAnnotationLayer).first);
      // Verify the 5 annotations on CT Phantom were automatically restored!
      expect(layer.annotationController.allAnnotations.length, equals(5));
    });
  });
}
