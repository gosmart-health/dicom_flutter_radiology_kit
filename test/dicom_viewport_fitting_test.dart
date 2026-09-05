import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ViewportController zoom/pan reset and modification tracking', () {
    test('isZoomPanModified detects initial vs modified states', () {
      final controller = ViewportController();
      expect(controller.isZoomPanModified, isFalse);

      controller.setZoom(1.2);
      expect(controller.isZoomPanModified, isTrue);

      controller.resetZoomPan();
      expect(controller.isZoomPanModified, isFalse);

      controller.setPanOffset(const Offset(5, 10));
      expect(controller.isZoomPanModified, isTrue);

      controller.resetZoomPan();
      expect(controller.isZoomPanModified, isFalse);
    });

    test('resetZoomPan resets zoom to 1.0 and pan to Offset.zero', () {
      final controller = ViewportController();
      controller.setZoom(2.5);
      controller.setPanOffset(const Offset(100, -50));

      controller.resetZoomPan();
      expect(controller.zoom, equals(1.0));
      expect(controller.panOffset, equals(Offset.zero));
    });
  });

  group('Fit-to-Viewport aspect ratio scaling math', () {
    double computeFitScale({
      required double viewportWidth,
      required double viewportHeight,
      required double imageWidth,
      required double imageHeight,
      EdgeInsets inset = const EdgeInsets.all(4.0),
    }) {
      final availableWidth = (viewportWidth - inset.horizontal).clamp(1.0, double.infinity);
      final availableHeight = (viewportHeight - inset.vertical).clamp(1.0, double.infinity);
      final double scaleX = availableWidth / imageWidth;
      final double scaleY = availableHeight / imageHeight;
      return math.min(scaleX, scaleY);
    }

    test('Square image in rectangular viewport fits within both dimensions', () {
      // 512x512 image in 400x200 viewport (e.g. 1x2 or 2x2 layout slot)
      final fitScale = computeFitScale(
        viewportWidth: 400,
        viewportHeight: 200,
        imageWidth: 512,
        imageHeight: 512,
        inset: const EdgeInsets.all(4.0),
      );

      // Height is constrained: (200 - 8) / 512 = 192 / 512 = 0.375
      expect(fitScale, closeTo(0.375, 0.001));
      // Scaled dimensions:
      final renderedWidth = 512 * fitScale;
      final renderedHeight = 512 * fitScale;
      expect(renderedWidth, lessThanOrEqualTo(400 - 8));
      expect(renderedHeight, lessThanOrEqualTo(200 - 8));
    });

    test('Tall image in square viewport is height-constrained', () {
      // 1000x2000 image in 500x500 viewport
      final fitScale = computeFitScale(
        viewportWidth: 500,
        viewportHeight: 500,
        imageWidth: 1000,
        imageHeight: 2000,
        inset: EdgeInsets.zero,
      );

      // scaleX = 500/1000 = 0.5; scaleY = 500/2000 = 0.25
      expect(fitScale, equals(0.25));
      expect(1000 * fitScale, equals(250));
      expect(2000 * fitScale, equals(500));
    });

    test('Wide image in square viewport is width-constrained', () {
      // 2000x1000 image in 500x500 viewport
      final fitScale = computeFitScale(
        viewportWidth: 500,
        viewportHeight: 500,
        imageWidth: 2000,
        imageHeight: 1000,
        inset: EdgeInsets.zero,
      );

      // scaleX = 500/2000 = 0.25; scaleY = 500/1000 = 0.5
      expect(fitScale, equals(0.25));
      expect(2000 * fitScale, equals(500));
      expect(1000 * fitScale, equals(250));
    });
  });

  group('DicomViewport Widget Clipping and Rendering', () {
    testWidgets('DicomViewport wraps tree in hard-edge ClipRect', (WidgetTester tester) async {
      final controller = ViewportController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: DicomViewport(
                controller: controller,
                inset: const EdgeInsets.all(8.0),
              ),
            ),
          ),
        ),
      );

      // Verify the top-level ClipRect exists with Clip.hardEdge
      final clipRectFinder = find.byType(ClipRect);
      expect(clipRectFinder, findsWidgets);

      final clipRectWidget = tester.widget<ClipRect>(clipRectFinder.first);
      expect(clipRectWidget.clipBehavior, equals(Clip.hardEdge));
    });

    testWidgets('DicomViewport accepts custom inset property', (WidgetTester tester) async {
      final controller = ViewportController();
      const customInset = EdgeInsets.symmetric(horizontal: 10, vertical: 20);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: DicomViewport(
                controller: controller,
                inset: customInset,
              ),
            ),
          ),
        ),
      );

      final viewportWidget = tester.widget<DicomViewport>(find.byType(DicomViewport));
      expect(viewportWidget.inset, equals(customInset));
    });
  });
}
