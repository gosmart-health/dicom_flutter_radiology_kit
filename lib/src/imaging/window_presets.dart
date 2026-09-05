/// Clinical Window Preset representing Window Center and Window Width (in Hounsfield Units / DICOM values).
class WindowPreset {
  final String name;
  final double center;
  final double width;

  const WindowPreset(this.name, this.center, this.width);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WindowPreset &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          center == other.center &&
          width == other.width;

  @override
  int get hashCode => name.hashCode ^ center.hashCode ^ width.hashCode;

  @override
  String toString() => '$name (C: ${center.toInt()}, W: ${width.toInt()})';
}

/// Standard clinical DICOM window presets.
class WindowPresets {
  static const WindowPreset softTissue = WindowPreset('Soft Tissue', 40.0, 400.0);
  static const WindowPreset bone = WindowPreset('Bone', 400.0, 1800.0);
  static const WindowPreset lung = WindowPreset('Lung', -600.0, 1500.0);
  static const WindowPreset brain = WindowPreset('Brain', 40.0, 80.0);
  static const WindowPreset abdomen = WindowPreset('Abdomen', 50.0, 350.0);
  static const WindowPreset angio = WindowPreset('Angio', 300.0, 600.0);
  static const WindowPreset chest = WindowPreset('Chest', 40.0, 400.0);
  static const WindowPreset stroke = WindowPreset('Stroke', 35.0, 35.0);

  static const List<WindowPreset> all = [
    softTissue,
    bone,
    lung,
    brain,
    abdomen,
    angio,
    chest,
    stroke,
  ];
}
