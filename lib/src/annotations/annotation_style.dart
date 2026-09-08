import 'package:flutter/material.dart';

/// Style configurations for the radiology imaging annotation layer.
/// Guaranteed high-contrast visibility across dense bone (white) and air (black).
class AnnotationStyle {
  /// Primary line and foreground color (Clinical Yellow).
  final Color primaryColor;

  /// Shadow / outline color for high-contrast contrast separation.
  final Color shadowColor;

  /// Foreground stroke width in screen pixels.
  final double strokeWidth;

  /// Shadow stroke width drawn directly beneath foreground lines.
  final double shadowStrokeWidth;

  /// Radius of manipulation handles in screen pixels.
  final double handleRadius;

  /// Stroke width for handle borders.
  final double handleBorderWidth;

  /// Handle fill color.
  final Color handleFillColor;

  /// Handle border color.
  final Color handleBorderColor;

  /// Text label style with shadow.
  final TextStyle textStyle;

  /// Background fill for text chips.
  final Color textBackgroundColor;

  const AnnotationStyle({
    this.primaryColor = const Color(0xFFFFEB3B), // High-visibility Yellow
    this.shadowColor = const Color(0xFF000000), // Solid Black Shadow
    this.strokeWidth = 2.0,
    this.shadowStrokeWidth = 4.5,
    this.handleRadius = 5.5,
    this.handleBorderWidth = 1.5,
    this.handleFillColor = const Color(0xFFFFEB3B),
    this.handleBorderColor = const Color(0xFF000000),
    this.textStyle = const TextStyle(
      color: Color(0xFFFFEB3B),
      fontSize: 12.0,
      fontWeight: FontWeight.bold,
      shadows: [
        Shadow(
          color: Color(0xFF000000),
          blurRadius: 3.0,
          offset: Offset(1.0, 1.0),
        ),
        Shadow(
          color: Color(0xFF000000),
          blurRadius: 3.0,
          offset: Offset(-1.0, -1.0),
        ),
      ],
    ),
    this.textBackgroundColor = const Color(0x99000000),
  });

  /// Paint for shadow pass.
  Paint get shadowLinePaint => Paint()
    ..color = shadowColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = shadowStrokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  /// Paint for foreground pass.
  Paint get foregroundLinePaint => Paint()
    ..color = primaryColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
}

