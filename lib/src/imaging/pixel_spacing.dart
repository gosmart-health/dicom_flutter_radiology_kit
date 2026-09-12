import 'dart:math' as math;

/// Pixel spacing in millimeters along the row (vertical) and column (horizontal) dimensions.
/// Represents DICOM Tag (0028,0030) `Pixel Spacing`.
class PixelSpacing {
  /// Spacing between the centers of adjacent rows (vertical spacing dy), in mm.
  final double rowSpacing;

  /// Spacing between the centers of adjacent columns (horizontal spacing dx), in mm.
  final double columnSpacing;

  const PixelSpacing({
    required this.rowSpacing,
    required this.columnSpacing,
  });

  /// Row spacing in millimeters.
  double get rowSpacingMm => rowSpacing;

  /// Column spacing in millimeters.
  double get columnSpacingMm => columnSpacing;

  /// Default isotropic 1.0 mm/pixel spacing.
  static const isotropic1mm = PixelSpacing(rowSpacing: 1.0, columnSpacing: 1.0);

  /// Computes the physical Euclidean distance in mm between two points in pixel coordinates.
  double distanceMm(double dxPixels, double dyPixels) {
    final physicalDx = dxPixels * columnSpacing;
    final physicalDy = dyPixels * rowSpacing;
    return math.sqrt(physicalDx * physicalDx + physicalDy * physicalDy);
  }

  /// Parses DICOM (0028,0030) value: "rowSpacing\\columnSpacing", List of doubles/strings, or DICOM JSON map.
  static PixelSpacing? tryParse(dynamic value) {
    if (value == null) return null;
    if (value is PixelSpacing) return value;
    if (value is Map) {
      if (value.containsKey('Value')) {
        return tryParse(value['Value']);
      }
      if (value.containsKey('rowSpacing') && value.containsKey('columnSpacing')) {
        final row = (value['rowSpacing'] is num)
            ? (value['rowSpacing'] as num).toDouble()
            : double.tryParse(value['rowSpacing'].toString());
        final col = (value['columnSpacing'] is num)
            ? (value['columnSpacing'] as num).toDouble()
            : double.tryParse(value['columnSpacing'].toString());
        if (row != null && col != null && row > 0 && col > 0) {
          return PixelSpacing(rowSpacing: row, columnSpacing: col);
        }
      }
    }
    if (value is String) {
      final parts = value.split(RegExp(r'[\\,\s]+')).where((s) => s.isNotEmpty).toList();
      if (parts.length >= 2) {
        final row = double.tryParse(parts[0]);
        final col = double.tryParse(parts[1]);
        if (row != null && col != null && row > 0 && col > 0) {
          return PixelSpacing(rowSpacing: row, columnSpacing: col);
        }
      }
    } else if (value is List) {
      if (value.length == 1) {
        return tryParse(value[0]);
      }
      if (value.length >= 2) {
        final row = (value[0] is num) ? (value[0] as num).toDouble() : double.tryParse(value[0].toString());
        final col = (value[1] is num) ? (value[1] as num).toDouble() : double.tryParse(value[1].toString());
        if (row != null && col != null && row > 0 && col > 0) {
          return PixelSpacing(rowSpacing: row, columnSpacing: col);
        }
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'rowSpacing': rowSpacing,
        'columnSpacing': columnSpacing,
      };

  factory PixelSpacing.fromJson(Map<String, dynamic> json) => PixelSpacing(
        rowSpacing: (json['rowSpacing'] as num).toDouble(),
        columnSpacing: (json['columnSpacing'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PixelSpacing &&
          runtimeType == other.runtimeType &&
          rowSpacing == other.rowSpacing &&
          columnSpacing == other.columnSpacing;

  @override
  int get hashCode => Object.hash(rowSpacing, columnSpacing);

  @override
  String toString() => 'PixelSpacing(row: ${rowSpacing}mm, col: ${columnSpacing}mm)';
}

