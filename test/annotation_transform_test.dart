import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

void main() {
  group('ViewportCoordinateTransform & Zoom/Pan Anchoring Tests', () {
    test('Round-trip coordinate transformation is invertible', () {
      final transform = ViewportCoordinateTransform(
        viewportSize: const Size(800, 600),
        imageWidth: 512,
        imageHeight: 512,
        zoom: 2.5,
        panOffset: const Offset(45, -30),
        inset: const EdgeInsets.all(4.0),
      );

      final testPoints = [
        Offset.zero,
        const Offset(256, 256), // Center of image
        const Offset(512, 512),
        const Offset(123.4, 456.7),
      ];

      for (final pt in testPoints) {
        final screen = transform.imageToViewport(pt);
        final backToImg = transform.viewportToImage(screen);
        expect(backToImg.dx, closeTo(pt.dx, 1e-5));
        expect(backToImg.dy, closeTo(pt.dy, 1e-5));
      }
    });

    test('Center of image maps to center of viewport when panOffset is zero', () {
      final transform = ViewportCoordinateTransform(
        viewportSize: const Size(600, 400),
        imageWidth: 512,
        imageHeight: 512,
        zoom: 1.0,
        panOffset: Offset.zero,
      );

      final imageCenter = const Offset(256, 256);
      final screenPos = transform.imageToViewport(imageCenter);

      expect(screenPos.dx, closeTo(300.0, 1e-5));
      expect(screenPos.dy, closeTo(200.0, 1e-5));
    });

    test('Pan shifts rendered coordinates directly by panOffset', () {
      const pan = Offset(50, -25);
      final transformWithoutPan = ViewportCoordinateTransform(
        viewportSize: const Size(600, 400),
        imageWidth: 512,
        imageHeight: 512,
        zoom: 1.0,
        panOffset: Offset.zero,
      );

      final transformWithPan = ViewportCoordinateTransform(
        viewportSize: const Size(600, 400),
        imageWidth: 512,
        imageHeight: 512,
        zoom: 1.0,
        panOffset: pan,
      );

      final imgPoint = const Offset(100, 150);
      final screen1 = transformWithoutPan.imageToViewport(imgPoint);
      final screen2 = transformWithPan.imageToViewport(imgPoint);

      expect(screen2.dx - screen1.dx, closeTo(pan.dx, 1e-5));
      expect(screen2.dy - screen1.dy, closeTo(pan.dy, 1e-5));
    });

    test('Zoom scales visual distance linearly while image coordinates remain constant', () {
      final t1 = ViewportCoordinateTransform(
        viewportSize: const Size(1000, 1000),
        imageWidth: 500,
        imageHeight: 500,
        zoom: 1.0,
        panOffset: Offset.zero,
        inset: EdgeInsets.zero,
      );

      final t2 = ViewportCoordinateTransform(
        viewportSize: const Size(1000, 1000),
        imageWidth: 500,
        imageHeight: 500,
        zoom: 3.0,
        panOffset: Offset.zero,
        inset: EdgeInsets.zero,
      );

      // Distance between two points on image
      const pA = Offset(200, 250);
      const pB = Offset(300, 250); // delta = 100 px on image

      final screenDist1 = (t1.imageToViewport(pB) - t1.imageToViewport(pA)).distance;
      final screenDist2 = (t2.imageToViewport(pB) - t2.imageToViewport(pA)).distance;

      // 3x zoom triples visual screen distance
      expect(screenDist2, closeTo(screenDist1 * 3.0, 1e-5));

      // Inverse projection verifies image coordinates never change
      final restoredA = t2.viewportToImage(t2.imageToViewport(pA));
      final restoredB = t2.viewportToImage(t2.imageToViewport(pB));
      expect(restoredA.dx, closeTo(pA.dx, 1e-5));
      expect(restoredB.dx, closeTo(pB.dx, 1e-5));
    });
  });
}

