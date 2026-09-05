import 'dart:convert';
import 'dart:ui';
import 'window_presets.dart';

/// Presentation state for an individual DICOM frame / instance.
/// Encapsulates VOI LUT window/level, geometric pan/zoom, and clinical presets.
/// Can be serialized to/from JSON to persist per user, per series, and per SOP Instance UID.
class DicomPresentationState {
  final double windowCenter;
  final double windowWidth;
  final double zoom;
  final Offset panOffset;
  final String? presetName;

  const DicomPresentationState({
    required this.windowCenter,
    required this.windowWidth,
    this.zoom = 1.0,
    this.panOffset = Offset.zero,
    this.presetName,
  });

  /// Creates a default presentation state.
  factory DicomPresentationState.defaultState({
    double windowCenter = 40.0,
    double windowWidth = 400.0,
    WindowPreset? preset = WindowPresets.softTissue,
  }) {
    return DicomPresentationState(
      windowCenter: preset?.center ?? windowCenter,
      windowWidth: preset?.width ?? windowWidth,
      zoom: 1.0,
      panOffset: Offset.zero,
      presetName: preset?.name,
    );
  }

  /// Copies this presentation state with optional modifications.
  DicomPresentationState copyWith({
    double? windowCenter,
    double? windowWidth,
    double? zoom,
    Offset? panOffset,
    String? presetName,
    bool clearPreset = false,
  }) {
    return DicomPresentationState(
      windowCenter: windowCenter ?? this.windowCenter,
      windowWidth: windowWidth ?? this.windowWidth,
      zoom: zoom ?? this.zoom,
      panOffset: panOffset ?? this.panOffset,
      presetName: clearPreset ? null : (presetName ?? this.presetName),
    );
  }

  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'windowCenter': windowCenter,
      'windowWidth': windowWidth,
      'zoom': zoom,
      'panDx': panOffset.dx,
      'panDy': panOffset.dy,
      'presetName': presetName,
    };
  }

  /// Deserializes from a JSON map.
  factory DicomPresentationState.fromJson(Map<String, dynamic> json) {
    return DicomPresentationState(
      windowCenter: (json['windowCenter'] as num?)?.toDouble() ?? 40.0,
      windowWidth: (json['windowWidth'] as num?)?.toDouble() ?? 400.0,
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1.0,
      panOffset: Offset(
        (json['panDx'] as num?)?.toDouble() ?? 0.0,
        (json['panDy'] as num?)?.toDouble() ?? 0.0,
      ),
      presetName: json['presetName'] as String?,
    );
  }

  String toJsonString() => json.encode(toJson());

  factory DicomPresentationState.fromJsonString(String source) =>
      DicomPresentationState.fromJson(json.decode(source) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DicomPresentationState &&
        other.windowCenter == windowCenter &&
        other.windowWidth == windowWidth &&
        other.zoom == zoom &&
        other.panOffset == panOffset &&
        other.presetName == presetName;
  }

  @override
  int get hashCode => Object.hash(windowCenter, windowWidth, zoom, panOffset, presetName);
}
