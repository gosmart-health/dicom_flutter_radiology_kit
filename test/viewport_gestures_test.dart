import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ViewportController gesture helpers', () {
    test('adjustWindowLevel adjusts center and width', () {
      final controller = ViewportController();
      controller.setWindowLevel(100.0, 500.0);

      controller.adjustWindowLevel(-20.0, 50.0);
      expect(controller.windowCenter, equals(80.0));
      expect(controller.windowWidth, equals(550.0));
    });

    test('adjustZoom adjusts zoom clamped to valid limits', () {
      final controller = ViewportController();
      controller.setZoom(1.0);

      controller.adjustZoom(0.5);
      expect(controller.zoom, equals(1.5));

      controller.adjustZoom(-5.0);
      expect(controller.zoom, equals(0.1)); // Clamped to 0.1 minimum
    });

    test('adjustPan adjusts panOffset', () {
      final controller = ViewportController();
      controller.setPanOffset(const Offset(10.0, 20.0));

      controller.adjustPan(const Offset(5.0, -10.0));
      expect(controller.panOffset, equals(const Offset(15.0, 10.0)));
    });

    test('stepSlice dispatches direction to onSliceStep callback', () {
      final controller = ViewportController();
      int? steppedDirection;
      controller.onSliceStep = (dir) => steppedDirection = dir;

      controller.stepSlice(1);
      expect(steppedDirection, equals(1));

      controller.stepSlice(-1);
      expect(steppedDirection, equals(-1));
    });
  });

  group('Desktop Mouse Gestures (general industrial PACS conventions)', () {
    testWidgets('Left mouse click drag adjusts Window/Level', (WidgetTester tester) async {
      final controller = ViewportController();
      controller.setWindowLevel(100.0, 500.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: ViewportGestureDetector(
                controller: controller,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(ViewportGestureDetector));

      // Drag right (+20 dx) and up (-30 dy)
      final gesture = await tester.startGesture(center, kind: ui.PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
      await gesture.moveBy(const Offset(20, -30));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // dx = +20 -> width increases by 20 * 2.0 = +40 -> 540.0
      expect(controller.windowWidth, equals(540.0));
      // dy = -30 -> drag UP decreases center by 30 * 2.0 = -60 -> 40.0 (brighter)
      expect(controller.windowCenter, equals(40.0));
    });

    testWidgets('Right mouse click drag zooms in and out', (WidgetTester tester) async {
      final controller = ViewportController();
      controller.setZoom(1.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: ViewportGestureDetector(
                controller: controller,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(ViewportGestureDetector));

      // Secondary (Right) mouse drag UP (-50 dy) -> Zoom in
      final gesture = await tester.startGesture(center, kind: ui.PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // Zoom should increase: 1.0 + (-(-50) * 0.01) = 1.5
      expect(controller.zoom, equals(1.5));
    });

    testWidgets('Shift + Left mouse click drag zooms in and out', (WidgetTester tester) async {
      final controller = ViewportController();
      controller.setZoom(1.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: ViewportGestureDetector(
                controller: controller,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(ViewportGestureDetector));

      // Simulate Shift key press
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

      // Primary (Left) mouse drag UP (-40 dy) with Shift held
      final gesture = await tester.startGesture(center, kind: ui.PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      // Zoom should increase: 1.0 + (40 * 0.01) = 1.4
      expect(controller.zoom, equals(1.4));
    });

    testWidgets('Middle mouse drag pans canvas', (WidgetTester tester) async {
      final controller = ViewportController();
      controller.setPanOffset(Offset.zero);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: ViewportGestureDetector(
                controller: controller,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(ViewportGestureDetector));

      // Middle button drag (+15 dx, +25 dy)
      final gesture = await tester.startGesture(center, kind: ui.PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
      await gesture.moveBy(const Offset(15, 25));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(controller.panOffset, equals(const Offset(15, 25)));
    });

    testWidgets('Ctrl + Left mouse drag pans canvas', (WidgetTester tester) async {
      final controller = ViewportController();
      controller.setPanOffset(Offset.zero);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: ViewportGestureDetector(
                controller: controller,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(ViewportGestureDetector));

      // Simulate Ctrl key press
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

      final gesture = await tester.startGesture(center, kind: ui.PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
      await gesture.moveBy(const Offset(30, -10));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(controller.panOffset, equals(const Offset(30, -10)));
    });

    testWidgets('Mouse wheel scroll triggers slice navigation', (WidgetTester tester) async {
      final controller = ViewportController();
      int? steppedDirection;
      controller.onSliceStep = (dir) => steppedDirection = dir;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: ViewportGestureDetector(
                controller: controller,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(ViewportGestureDetector));

      // Scroll Down -> Next Slice (+1)
      await tester.sendEventToBinding(PointerScrollEvent(
        position: center,
        scrollDelta: const Offset(0, 100),
      ));
      await tester.pump();
      expect(steppedDirection, equals(1));

      // Scroll Up -> Previous Slice (-1)
      await tester.sendEventToBinding(PointerScrollEvent(
        position: center,
        scrollDelta: const Offset(0, -100),
      ));
      await tester.pump();
      expect(steppedDirection, equals(-1));
    });

    testWidgets('Double click left button resets view', (WidgetTester tester) async {
      final controller = ViewportController();
      controller.setZoom(2.5);
      controller.setPanOffset(const Offset(50, 50));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: ViewportGestureDetector(
                controller: controller,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(ViewportGestureDetector));

      // First click
      final g1 = await tester.startGesture(center, kind: ui.PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
      await g1.up();
      await tester.pump(const Duration(milliseconds: 50));

      // Second click within 300ms
      final g2 = await tester.startGesture(center, kind: ui.PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
      await g2.up();
      await tester.pump();

      expect(controller.zoom, equals(1.0));
      expect(controller.panOffset, equals(Offset.zero));
    });
  });

  group('Mobile Touch Gestures (Apple HIG & clinical touch conventions)', () {
    testWidgets('1-finger drag adjusts Window / Level', (WidgetTester tester) async {
      final controller = ViewportController();
      controller.setWindowLevel(100.0, 500.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: ViewportGestureDetector(
                controller: controller,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(ViewportGestureDetector));

      // 1-finger touch drag right (+15 dx) and down (+20 dy)
      final touch = await tester.startGesture(center, kind: ui.PointerDeviceKind.touch);
      await touch.moveBy(const Offset(15, 20));
      await tester.pump();
      await touch.up();
      await tester.pump();

      // dx = +15 -> width increases by 15 * 2.0 = +30 -> 530.0
      expect(controller.windowWidth, equals(530.0));
      // dy = +20 -> drag DOWN increases center by 20 * 2.0 = +40 -> 140.0 (darker)
      expect(controller.windowCenter, equals(140.0));
    });

    testWidgets('2-finger touch drag pans and pinches zoom', (WidgetTester tester) async {
      final controller = ViewportController();
      controller.setPanOffset(Offset.zero);
      controller.setZoom(1.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: ViewportGestureDetector(
                controller: controller,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );

      // Start 2 fingers at (150, 200) and (250, 200) -> distance = 100, centroid = (200, 200)
      final finger1 = await tester.startGesture(const Offset(150, 200), kind: ui.PointerDeviceKind.touch);
      final finger2 = await tester.startGesture(const Offset(250, 200), kind: ui.PointerDeviceKind.touch);
      await tester.pump();

      // Move both fingers right by 20px, and spread finger2 further right by another 30px
      // New pos: finger1 = (170, 200), finger2 = (300, 200)
      // New centroid = (235, 200) -> pan delta = +35 dx
      // New distance = 130 -> distance delta = +30 -> zoom delta = +0.3
      await finger1.moveTo(const Offset(170, 200));
      await finger2.moveTo(const Offset(300, 200));
      await tester.pump();

      await finger1.up();
      await finger2.up();
      await tester.pump();

      expect(controller.panOffset.dx, greaterThan(0));
      expect(controller.zoom, greaterThan(1.0));
    });

    testWidgets('1-finger double tap resets view', (WidgetTester tester) async {
      final controller = ViewportController();
      controller.setZoom(3.0);
      controller.setPanOffset(const Offset(100, -50));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: ViewportGestureDetector(
                controller: controller,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(ViewportGestureDetector));

      // Tap 1
      final t1 = await tester.startGesture(center, kind: ui.PointerDeviceKind.touch);
      await t1.up();
      await tester.pump(const Duration(milliseconds: 50));

      // Tap 2
      final t2 = await tester.startGesture(center, kind: ui.PointerDeviceKind.touch);
      await t2.up();
      await tester.pump();

      expect(controller.zoom, equals(1.0));
      expect(controller.panOffset, equals(Offset.zero));
    });
  });

  group('Presentation State & Frame Index Overlays', () {
    test('DicomPresentationState serializes to and from JSON', () {
      const state = DicomPresentationState(
        windowCenter: 50.0,
        windowWidth: 350.0,
        zoom: 1.5,
        panOffset: Offset(12.0, -8.0),
        presetName: 'Abdomen',
      );

      final jsonMap = state.toJson();
      final deserialized = DicomPresentationState.fromJson(jsonMap);

      expect(deserialized, equals(state));
      expect(deserialized.windowCenter, equals(50.0));
      expect(deserialized.windowWidth, equals(350.0));
      expect(deserialized.zoom, equals(1.5));
      expect(deserialized.panOffset, equals(const Offset(12.0, -8.0)));
      expect(deserialized.presetName, equals('Abdomen'));
    });

    test('ViewportController exports and restores presentation state with event hook', () {
      final controller = ViewportController();
      DicomPresentationState? propagatedState;
      controller.onPresentationChanged = (s) => propagatedState = s;

      controller.setWindowLevel(100.0, 500.0);
      expect(propagatedState?.windowCenter, equals(100.0));
      expect(propagatedState?.windowWidth, equals(500.0));

      const newState = DicomPresentationState(
        windowCenter: -600.0,
        windowWidth: 1500.0,
        zoom: 2.0,
        panOffset: Offset(20.0, 30.0),
      );

      controller.applyPresentationState(newState);
      expect(controller.windowCenter, equals(-600.0));
      expect(controller.windowWidth, equals(1500.0));
      expect(controller.zoom, equals(2.0));
      expect(controller.panOffset, equals(const Offset(20.0, 30.0)));
      expect(propagatedState, equals(newState));
    });

    testWidgets('ViewportOverlays renders Img: frameIndex / totalFrames HUD indicator',
        (WidgetTester tester) async {
      final controller = ViewportController();
      controller.updateMetadata(
        patientName: 'TEST^PATIENT',
        frameIndex: 2,
        totalFrames: 128,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 500,
              child: ViewportOverlays(controller: controller),
            ),
          ),
        ),
      );

      expect(find.text('Img: 2 / 128'), findsOneWidget);

      controller.updateFrameIndices(frameIndex: 3, totalFrames: 128);
      await tester.pump();

      expect(find.text('Img: 3 / 128'), findsOneWidget);
    });
  });
}
