import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PixelFrame createTestFrame({int width = 512, int height = 512}) {
    return PixelFrame(
      rawPixels: Uint8List(width * height),
      width: width,
      height: height,
      pixelSpacing: const PixelSpacing(rowSpacing: 0.5, columnSpacing: 0.5),
    );
  }

  group('DicomAnnotationLayer Widget & Interaction Tests', () {
    testWidgets('Renders empty layer without crashing when no frame is present',
        (tester) async {
      final viewportCtrl = ViewportController();
      final annotCtrl = AnnotationController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DicomAnnotationLayer(
                viewportController: viewportCtrl,
                annotationController: annotCtrl,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DicomAnnotationLayer), findsOneWidget);
    });

    testWidgets('Attaches viewportController to annotationController on mount',
        (tester) async {
      final viewportCtrl = ViewportController();
      final annotCtrl = AnnotationController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DicomAnnotationLayer(
                viewportController: viewportCtrl,
                annotationController: annotCtrl,
              ),
            ),
          ),
        ),
      );

      expect(annotCtrl.isDirty, isFalse);

      viewportCtrl.setWindowLevel(500.0, 1200.0);
      expect(annotCtrl.isDirty, isTrue);
    });

    testWidgets('Draws Caliper via drag gesture and calculates distance in mm',
        (tester) async {
      final viewportCtrl = ViewportController();
      final annotCtrl =
          AnnotationController(initialTool: AnnotationTool.caliper);
      final frame = createTestFrame();
      viewportCtrl.setFrame(frame);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 512,
                height: 512,
                child: DicomAnnotationLayer(
                  viewportController: viewportCtrl,
                  annotationController: annotCtrl,
                  inset: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      );

      final layerFinder = find.byType(DicomAnnotationLayer);
      final topLeft = tester.getTopLeft(layerFinder);

      // Drag from (100, 100) to (160, 180) -> dx = 60, dy = 80 -> px dist = 100
      // With 0.5 mm spacing -> 50.0 mm
      final gesture = await tester.startGesture(topLeft + const Offset(100, 100));
      await tester.pump();
      await gesture.moveTo(topLeft + const Offset(160, 180));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(annotCtrl.allAnnotations.length, equals(1));
      final caliper = annotCtrl.allAnnotations.first as CaliperAnnotation;
      expect(caliper.start.dx, closeTo(100.0, 1.0));
      expect(caliper.start.dy, closeTo(100.0, 1.0));
      expect(caliper.end.dx, closeTo(160.0, 1.0));
      expect(caliper.end.dy, closeTo(180.0, 1.0));

      final distMm = caliper.computeDistance(pixelSpacing: viewportCtrl.pixelSpacing);
      expect(distMm, closeTo(50.0, 1.0));
    });

    testWidgets('Creates Circle and selects it', (tester) async {
      final viewportCtrl = ViewportController();
      final annotCtrl = AnnotationController(initialTool: AnnotationTool.circle);
      final frame = createTestFrame();
      viewportCtrl.setFrame(frame);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 512,
                height: 512,
                child: DicomAnnotationLayer(
                  viewportController: viewportCtrl,
                  annotationController: annotCtrl,
                  inset: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      );

      final topLeft = tester.getTopLeft(find.byType(DicomAnnotationLayer));

      // Drag circle from center (200, 200) outwards by 50 px
      final gesture = await tester.startGesture(topLeft + const Offset(200, 200));
      await tester.pump();
      await gesture.moveTo(topLeft + const Offset(250, 200));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(annotCtrl.allAnnotations.length, equals(1));
      final circle = annotCtrl.allAnnotations.first as CircleAnnotation;
      expect(circle.center.dx, closeTo(200.0, 1.0));
      expect(circle.center.dy, closeTo(200.0, 1.0));
      expect(circle.radius, closeTo(50.0, 1.0));
    });

    testWidgets('Creates and edits TextAnnotation in-place', (tester) async {
      final viewportCtrl = ViewportController();
      final annotCtrl = AnnotationController(initialTool: AnnotationTool.text);
      final frame = createTestFrame();
      viewportCtrl.setFrame(frame);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 512,
                height: 512,
                child: DicomAnnotationLayer(
                  viewportController: viewportCtrl,
                  annotationController: annotCtrl,
                  inset: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      );

      final topLeft = tester.getTopLeft(find.byType(DicomAnnotationLayer));

      // Tap to place text annotation
      await tester.tapAt(topLeft + const Offset(150, 150));
      await tester.pumpAndSettle();

      // Inline text field should be visible
      expect(find.byType(TextField), findsOneWidget);

      // Enter clinical note and submit
      await tester.enterText(find.byType(TextField), 'Fracture line');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(annotCtrl.allAnnotations.length, equals(1));
      final textAnn = annotCtrl.allAnnotations.first as TextAnnotation;
      expect(textAnn.text, equals('Fracture line'));
      expect(textAnn.anchor.dx, closeTo(150.0, 1.0));
      expect(textAnn.anchor.dy, closeTo(150.0, 1.0));
    });

    testWidgets('Annotations remain anchored to image coordinates during zoom and pan',
        (tester) async {
      final viewportCtrl = ViewportController();
      final annotCtrl = AnnotationController();
      final frame = createTestFrame();
      viewportCtrl.setFrame(frame);

      // Add a caliper on the lesion at pixel coordinates (100, 100) -> (200, 200)
      final lesionCaliper = CaliperAnnotation(
        id: 'lesion_1',
        start: const Offset(100, 100),
        end: const Offset(200, 200),
      );
      annotCtrl.addAnnotation(lesionCaliper);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 512,
                height: 512,
                child: DicomAnnotationLayer(
                  viewportController: viewportCtrl,
                  annotationController: annotCtrl,
                  inset: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      );

      // Initially zoom = 1.0, pan = (0, 0)
      expect(annotCtrl.allAnnotations.first.points[0], equals(const Offset(100, 100)));

      // Perform 3x zoom and pan
      viewportCtrl.setZoom(3.0);
      viewportCtrl.setPanOffset(const Offset(60, -40));
      await tester.pump();

      // Image coordinates of annotation MUST remain exactly at (100, 100)
      final afterZoomAnn = annotCtrl.allAnnotations.first as CaliperAnnotation;
      expect(afterZoomAnn.start, equals(const Offset(100, 100)));
      expect(afterZoomAnn.end, equals(const Offset(200, 200)));

      // Verify coordinate transformation math reflects the zoom and pan on canvas
      final transform = ViewportCoordinateTransform(
        viewportSize: const Size(512, 512),
        imageWidth: 512,
        imageHeight: 512,
        zoom: viewportCtrl.zoom,
        panOffset: viewportCtrl.panOffset,
        inset: EdgeInsets.zero,
      );

      final screenStart = transform.imageToViewport(afterZoomAnn.start);
      final restoredStart = transform.viewportToImage(screenStart);
      expect(restoredStart.dx, closeTo(100.0, 1e-4));
      expect(restoredStart.dy, closeTo(100.0, 1e-4));
    });

    testWidgets(
        'Auto-selects Select tool upon drawing completion and always honors grabbing handles',
        (tester) async {
      final viewportCtrl = ViewportController();
      final annotCtrl =
          AnnotationController(initialTool: AnnotationTool.caliper);
      final frame = createTestFrame();
      viewportCtrl.setFrame(frame);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 512,
                height: 512,
                child: DicomAnnotationLayer(
                  viewportController: viewportCtrl,
                  annotationController: annotCtrl,
                  inset: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      );

      final topLeft = tester.getTopLeft(find.byType(DicomAnnotationLayer));

      // 1. Draw a caliper from (50, 50) to (150, 50)
      final drawGesture =
          await tester.startGesture(topLeft + const Offset(50, 50));
      await tester.pump();
      await drawGesture.moveTo(topLeft + const Offset(150, 50));
      await tester.pump();
      await drawGesture.up();
      await tester.pump();

      // Tool should auto-switch to Select and annotation should be selected!
      expect(annotCtrl.activeTool, equals(AnnotationTool.select));
      expect(annotCtrl.selectedAnnotation, isNotNull);
      final createdCaliper = annotCtrl.selectedAnnotation as CaliperAnnotation;
      expect(createdCaliper.start, equals(const Offset(50, 50)));
      expect(createdCaliper.end, equals(const Offset(150, 50)));

      // 2. Now switch active tool BACK to Caliper
      annotCtrl.setActiveTool(AnnotationTool.caliper);
      expect(annotCtrl.activeTool, equals(AnnotationTool.caliper));
      // Re-select caliper so handles are active
      annotCtrl.selectAnnotation(createdCaliper);

      // Drag the 'end' handle located at (150, 50) to (180, 50)
      final handleGesture =
          await tester.startGesture(topLeft + const Offset(150, 50));
      await tester.pump();
      await handleGesture.moveTo(topLeft + const Offset(180, 50));
      await tester.pump();
      await handleGesture.up();
      await tester.pump();

      // Verify handle grab was honored (caliper was adjusted, NOT a new caliper created)
      expect(annotCtrl.allAnnotations.length, equals(1));
      final updatedCaliper = annotCtrl.allAnnotations.first as CaliperAnnotation;
      expect(updatedCaliper.end.dx, closeTo(180.0, 1.0));
      expect(updatedCaliper.start.dx, closeTo(50.0, 1.0));
    });

    testWidgets(
        'Immediately after drawing an object, pressing Delete key removes it',
        (tester) async {
      final viewportCtrl = ViewportController();
      final annotCtrl =
          AnnotationController(initialTool: AnnotationTool.circle);
      final frame = createTestFrame();
      viewportCtrl.setFrame(frame);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 512,
                height: 512,
                child: DicomAnnotationLayer(
                  viewportController: viewportCtrl,
                  annotationController: annotCtrl,
                  inset: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      );

      final topLeft = tester.getTopLeft(find.byType(DicomAnnotationLayer));

      // Draw a circle from (200, 200) to (250, 200)
      final gesture = await tester.startGesture(topLeft + const Offset(200, 200));
      await tester.pump();
      await gesture.moveTo(topLeft + const Offset(250, 200));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // Shape is created, selected, and active
      expect(annotCtrl.allAnnotations.length, equals(1));
      expect(annotCtrl.selectedAnnotation, isNotNull);

      // Now immediately press Delete key on keyboard
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      // The newly created circle is immediately deleted!
      expect(annotCtrl.allAnnotations, isEmpty);
      expect(annotCtrl.selectedAnnotation, isNull);
    });

    testWidgets(
        'While selected, pressing Backspace key deletes the selected object',
        (tester) async {
      final viewportCtrl = ViewportController();
      final annotCtrl = AnnotationController();
      final frame = createTestFrame();
      viewportCtrl.setFrame(frame);

      final c1 = CircleAnnotation(id: 'c1', center: const Offset(100, 100), radius: 30);
      final c2 = CircleAnnotation(id: 'c2', center: const Offset(200, 200), radius: 40);
      annotCtrl.addAnnotation(c1);
      annotCtrl.addAnnotation(c2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 512,
                height: 512,
                child: DicomAnnotationLayer(
                  viewportController: viewportCtrl,
                  annotationController: annotCtrl,
                  inset: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      );

      // Select c1
      annotCtrl.selectAnnotation(c1);
      await tester.pump();

      // Press Backspace key
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      // c1 is deleted, c2 remains
      expect(annotCtrl.allAnnotations.length, equals(1));
      expect(annotCtrl.allAnnotations.first.id, equals('c2'));
    });

    testWidgets(
        'Clicking near starting point of polyline detects closure and finishes polygon',
        (tester) async {
      final viewportCtrl = ViewportController();
      final annotCtrl =
          AnnotationController(initialTool: AnnotationTool.polyline);
      final frame = createTestFrame();
      viewportCtrl.setFrame(frame);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 512,
                height: 512,
                child: DicomAnnotationLayer(
                  viewportController: viewportCtrl,
                  annotationController: annotCtrl,
                  inset: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      );

      final topLeft = tester.getTopLeft(find.byType(DicomAnnotationLayer));

      // Click vertex 1: (100, 100)
      await tester.tapAt(topLeft + const Offset(100, 100));
      await tester.pump();

      // Click vertex 2: (200, 100)
      await tester.tapAt(topLeft + const Offset(200, 100));
      await tester.pump();

      // Click vertex 3: (150, 200)
      await tester.tapAt(topLeft + const Offset(150, 200));
      await tester.pump();

      // Click near vertex 1: (103, 102) -> within closure threshold!
      await tester.tapAt(topLeft + const Offset(103, 102));
      await tester.pump();

      // Polyline should be completed with isClosed: true and tool switched to Select!
      expect(annotCtrl.activeTool, equals(AnnotationTool.select));
      expect(annotCtrl.allAnnotations.length, equals(1));
      final poly = annotCtrl.allAnnotations.first as PolylineAnnotation;
      expect(poly.isClosed, isTrue);
      expect(poly.computeArea(), isNotNull);
    });

    testWidgets(
        'Pan/Zoom/Window Level gestures pass through and restore when tool is Pan/W-L (none)',
        (tester) async {
      final viewportCtrl = ViewportController();
      final annotCtrl = AnnotationController(initialTool: AnnotationTool.caliper);
      final frame = createTestFrame();
      viewportCtrl.setFrame(frame);
      viewportCtrl.setWindowLevel(100.0, 200.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 512,
                height: 512,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DicomViewport(controller: viewportCtrl),
                    DicomAnnotationLayer(
                      viewportController: viewportCtrl,
                      annotationController: annotCtrl,
                      inset: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final layerFinder = find.byType(DicomAnnotationLayer);
      final topLeft = tester.getTopLeft(layerFinder);

      // 1. Draw a Caliper in Caliper mode
      final gesture = await tester.startGesture(topLeft + const Offset(100, 100));
      await tester.pump();
      await gesture.moveTo(topLeft + const Offset(150, 150));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(annotCtrl.allAnnotations.length, equals(1));

      // 2. Switch tool back to Pan/W-L (AnnotationTool.none)
      annotCtrl.setActiveTool(AnnotationTool.none);
      await tester.pump();

      // 3. Perform a drag on the viewport
      // In Pan/W-L mode, Left Click Drag adjusts Window / Level:
      // Dragging dx = 50, dy = 30
      final dragGesture =
          await tester.startGesture(topLeft + const Offset(200, 200));
      await tester.pump();
      await dragGesture.moveTo(topLeft + const Offset(250, 230));
      await tester.pump();
      await dragGesture.up();
      await tester.pump();

      // Verify Window / Level was modified by the gesture (gesture is restored!)
      // Delta dx = 50 * 2.0 = +100 width -> 200 + 100 = 300
      // Delta dy = 30 * 2.0 = +60 center -> 100 + 60 = 160
      expect(viewportCtrl.windowWidth, closeTo(300.0, 1.0));
      expect(viewportCtrl.windowCenter, closeTo(160.0, 1.0));

      // 4. Test Right Click Drag (Zoom) in Pan/W-L mode
      final initialZoom = viewportCtrl.zoom;
      final rightDrag = await tester.startGesture(
        topLeft + const Offset(200, 200),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      // Drag up by 50 px -> Zoom in
      await rightDrag.moveTo(topLeft + const Offset(200, 150));
      await tester.pump();
      await rightDrag.up();
      await tester.pump();

      expect(viewportCtrl.zoom, greaterThan(initialZoom));
    });

    testWidgets('Clamps annotation translation to image boundaries',
        (tester) async {
      final viewportCtrl = ViewportController();
      final annotCtrl = AnnotationController(initialTool: AnnotationTool.select);
      final frame = createTestFrame(width: 512, height: 512);
      viewportCtrl.setFrame(frame);

      final caliper = CaliperAnnotation(
        id: 'c1',
        start: const Offset(50, 50),
        end: const Offset(150, 50),
      );
      annotCtrl.addAnnotation(caliper);
      annotCtrl.selectAnnotation(caliper);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 512,
                height: 512,
                child: DicomAnnotationLayer(
                  viewportController: viewportCtrl,
                  annotationController: annotCtrl,
                  inset: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      );

      final layerFinder = find.byType(DicomAnnotationLayer);
      final topLeft = tester.getTopLeft(layerFinder);

      // 1. Drag shape far to top-left beyond (0,0)
      final gesture = await tester.startGesture(topLeft + const Offset(100, 50));
      await tester.pump();
      await gesture.moveTo(topLeft + const Offset(-300, -300));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final updated1 = annotCtrl.allAnnotations.first as CaliperAnnotation;
      expect(updated1.geometricBounds.left, greaterThanOrEqualTo(0.0));
      expect(updated1.geometricBounds.top, greaterThanOrEqualTo(0.0));

      // 2. Drag shape far to bottom-right beyond (512, 512)
      final gesture2 = await tester.startGesture(topLeft + const Offset(50, 50));
      await tester.pump();
      await gesture2.moveTo(topLeft + const Offset(1000, 1000));
      await tester.pump();
      await gesture2.up();
      await tester.pump();

      final updated2 = annotCtrl.allAnnotations.first as CaliperAnnotation;
      expect(updated2.geometricBounds.right, lessThanOrEqualTo(512.0));
      expect(updated2.geometricBounds.bottom, lessThanOrEqualTo(512.0));
    });

    testWidgets('DicomAnnotationLayer wraps in ClipRect to prevent overflow',
        (tester) async {
      final viewportCtrl = ViewportController();
      final annotCtrl = AnnotationController();
      final frame = createTestFrame();
      viewportCtrl.setFrame(frame);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: DicomAnnotationLayer(
                viewportController: viewportCtrl,
                annotationController: annotCtrl,
              ),
            ),
          ),
        ),
      );

      final clipRects = find.descendant(
        of: find.byType(DicomAnnotationLayer),
        matching: find.byType(ClipRect),
      );
      expect(clipRects, findsAtLeastNWidgets(1));
    });

    test('AnnotationController.setAnnotations replaces annotations and resets state', () {
      final annotCtrl = AnnotationController();
      final a1 = CaliperAnnotation(
        id: '1',
        start: const Offset(10, 10),
        end: const Offset(20, 20),
      );
      annotCtrl.addAnnotation(a1);
      expect(annotCtrl.allAnnotations.length, equals(1));
      expect(annotCtrl.selectedAnnotation?.id, equals(a1.id));
      expect(annotCtrl.canUndo, isTrue);

      final a2 = CircleAnnotation(
        id: '2',
        center: const Offset(30, 30),
        radius: 15.0,
      );
      annotCtrl.setAnnotations([a2]);
      expect(annotCtrl.allAnnotations.length, equals(1));
      expect(annotCtrl.allAnnotations.first.id, equals('2'));
      expect(annotCtrl.selectedAnnotation, isNull);
      expect(annotCtrl.canUndo, isFalse);
    });

    testWidgets('Draws Caliper via click-move-click gesture (two-click placement)',
        (tester) async {
      final viewportCtrl = ViewportController();
      final annotCtrl =
          AnnotationController(initialTool: AnnotationTool.caliper);
      final frame = createTestFrame();
      viewportCtrl.setFrame(frame);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 512,
                height: 512,
                child: DicomAnnotationLayer(
                  viewportController: viewportCtrl,
                  annotationController: annotCtrl,
                  inset: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      );

      final topLeft = tester.getTopLeft(find.byType(DicomAnnotationLayer));

      // 1. First click down & up at (100, 100) without dragging
      await tester.tapAt(topLeft + const Offset(100, 100));
      await tester.pump();

      // Verify draft annotation is active and not committed yet
      expect(annotCtrl.draftAnnotation, isNotNull);
      expect(annotCtrl.allAnnotations, isEmpty);

      // 2. Second click at (200, 100)
      await tester.tapAt(topLeft + const Offset(200, 100));
      await tester.pump();

      // Caliper should be committed!
      expect(annotCtrl.allAnnotations.length, equals(1));
      final caliper = annotCtrl.allAnnotations.first as CaliperAnnotation;
      expect(caliper.start.dx, closeTo(100.0, 1.0));
      expect(caliper.start.dy, closeTo(100.0, 1.0));
      expect(caliper.end.dx, closeTo(200.0, 1.0));
      expect(caliper.end.dy, closeTo(100.0, 1.0));
      expect(annotCtrl.activeTool, equals(AnnotationTool.select));
    });

    testWidgets('Draws Angle via 3 clicks (P1 -> Vertex -> P2) with correct vertices',
        (tester) async {
      final viewportCtrl = ViewportController();
      final annotCtrl =
          AnnotationController(initialTool: AnnotationTool.angle);
      final frame = createTestFrame();
      viewportCtrl.setFrame(frame);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 512,
                height: 512,
                child: DicomAnnotationLayer(
                  viewportController: viewportCtrl,
                  annotationController: annotCtrl,
                  inset: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      );

      final topLeft = tester.getTopLeft(find.byType(DicomAnnotationLayer));

      // Click 1: P1 at (100, 200)
      await tester.tapAt(topLeft + const Offset(100, 200));
      await tester.pump();
      expect(annotCtrl.draftAnnotation, isNotNull);
      expect(annotCtrl.allAnnotations, isEmpty);

      // Click 2: Vertex at (100, 100)
      await tester.tapAt(topLeft + const Offset(100, 100));
      await tester.pump();
      expect(annotCtrl.draftAnnotation, isNotNull);
      expect(annotCtrl.allAnnotations, isEmpty);

      // Click 3: P2 at (200, 100)
      await tester.tapAt(topLeft + const Offset(200, 100));
      await tester.pump();

      // Angle should be committed!
      expect(annotCtrl.allAnnotations.length, equals(1));
      final angle = annotCtrl.allAnnotations.first as AngleAnnotation;
      expect(angle.p1.dx, closeTo(100.0, 1.0));
      expect(angle.p1.dy, closeTo(200.0, 1.0));
      expect(angle.vertex.dx, closeTo(100.0, 1.0));
      expect(angle.vertex.dy, closeTo(100.0, 1.0));
      expect(angle.p2.dx, closeTo(200.0, 1.0));
      expect(angle.p2.dy, closeTo(100.0, 1.0));

      // Arm 1 is vertical (100, 200) -> (100, 100)
      // Arm 2 is horizontal (100, 100) -> (200, 100)
      // Angle should be exactly 90.0°
      expect(angle.computeAngleDegrees(), closeTo(90.0, 0.1));
      expect(annotCtrl.activeTool, equals(AnnotationTool.select));
    });
  });
}

