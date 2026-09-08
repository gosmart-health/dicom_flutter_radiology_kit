import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Bidirectional coordinate transformer between DICOM image pixel space and Viewport Canvas space.
/// Guarantees exact coordinate synchronization with [DicomViewport] under any pan and zoom.
class ViewportCoordinateTransform {
  final Size viewportSize;
  final int imageWidth;
  final int imageHeight;
  final double zoom;
  final Offset panOffset;
  final EdgeInsets inset;

  final double fitScale;
  final double effectiveScale;

  ViewportCoordinateTransform({
    required this.viewportSize,
    required this.imageWidth,
    required this.imageHeight,
    this.zoom = 1.0,
    this.panOffset = Offset.zero,
    this.inset = const EdgeInsets.all(4.0),
  })  : fitScale = _computeFitScale(
          viewportSize: viewportSize,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          inset: inset,
        ),
        effectiveScale = _computeFitScale(
              viewportSize: viewportSize,
              imageWidth: imageWidth,
              imageHeight: imageHeight,
              inset: inset,
            ) *
            zoom;

  static double _computeFitScale({
    required Size viewportSize,
    required int imageWidth,
    required int imageHeight,
    required EdgeInsets inset,
  }) {
    if (imageWidth <= 0 ||
        imageHeight <= 0 ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return 1.0;
    }
    final availableWidth =
        (viewportSize.width - inset.horizontal).clamp(1.0, double.infinity);
    final availableHeight =
        (viewportSize.height - inset.vertical).clamp(1.0, double.infinity);
    final scaleX = availableWidth / imageWidth;
    final scaleY = availableHeight / imageHeight;
    return math.min(scaleX, scaleY);
  }

  /// Maps a point from DICOM Image Pixel coordinates [0..imageWidth, 0..imageHeight]
  /// to Viewport screen coordinates.
  Offset imageToViewport(Offset imagePoint) {
    final centerX = viewportSize.width / 2.0 + panOffset.dx;
    final centerY = viewportSize.height / 2.0 + panOffset.dy;
    final screenX = centerX + (imagePoint.dx - imageWidth / 2.0) * effectiveScale;
    final screenY = centerY + (imagePoint.dy - imageHeight / 2.0) * effectiveScale;
    return Offset(screenX, screenY);
  }

  /// Maps a point from Viewport screen coordinates to DICOM Image Pixel coordinates.
  Offset viewportToImage(Offset viewportPoint) {
    if (effectiveScale == 0.0) return Offset.zero;
    final centerX = viewportSize.width / 2.0 + panOffset.dx;
    final centerY = viewportSize.height / 2.0 + panOffset.dy;
    final imgX = (viewportPoint.dx - centerX) / effectiveScale + imageWidth / 2.0;
    final imgY = (viewportPoint.dy - centerY) / effectiveScale + imageHeight / 2.0;
    return Offset(imgX, imgY);
  }

  /// Converts a scalar pixel distance on image to screen pixels.
  double imageDistanceToViewport(double imageDistance) =>
      imageDistance * effectiveScale;

  /// Converts a scalar distance on screen pixels to image pixels.
  double viewportDistanceToImage(double viewportDistance) =>
      effectiveScale > 0.0 ? viewportDistance / effectiveScale : 0.0;

  /// Maps an Image-space Rect to Viewport screen Rect.
  Rect imageRectToViewport(Rect imageRect) {
    final tl = imageToViewport(imageRect.topLeft);
    final br = imageToViewport(imageRect.bottomRight);
    return Rect.fromPoints(tl, br);
  }

  /// Clamps an image-space point to the valid pixel coordinate rectangle [0..imageWidth, 0..imageHeight].
  Offset clampImagePoint(Offset pt) {
    return Offset(
      pt.dx.clamp(0.0, imageWidth.toDouble()),
      pt.dy.clamp(0.0, imageHeight.toDouble()),
    );
  }
}

