import 'package:flutter/material.dart';
import '../imaging/pixel_frame.dart';
import '../imaging/window_presets.dart';

/// State controller for DICOM viewports managing active frame, zoom/pan transform, window width/center.
class ViewportController extends ChangeNotifier {
  PixelFrame? _currentFrame;
  double _windowCenter = 40.0;
  double _windowWidth = 400.0;
  double _zoom = 1.0;
  Offset _panOffset = Offset.zero;
  WindowPreset? _activePreset = WindowPresets.softTissue;
  String _patientName = '';
  String _patientId = '';
  String _studyDescription = '';
  String _seriesDescription = '';

  PixelFrame? get currentFrame => _currentFrame;
  double get windowCenter => _windowCenter;
  double get windowWidth => _windowWidth;
  double get zoom => _zoom;
  Offset get panOffset => _panOffset;
  WindowPreset? get activePreset => _activePreset;

  String get patientName => _patientName;
  String get patientId => _patientId;
  String get studyDescription => _studyDescription;
  String get seriesDescription => _seriesDescription;

  void setFrame(PixelFrame frame, {bool updateWindowLevelFromFrame = false}) {
    _currentFrame = frame;
    if (updateWindowLevelFromFrame) {
      final (min, max) = frame.getMinMax();
      final double modMin = frame.getModalityValue(min.toInt());
      final double modMax = frame.getModalityValue(max.toInt());
      _windowWidth = (modMax - modMin).abs();
      _windowCenter = modMin + (_windowWidth / 2.0);
      _activePreset = null;
    }
    notifyListeners();
  }

  void setWindowLevel(double center, double width) {
    _windowCenter = center;
    _windowWidth = width < 1.0 ? 1.0 : width;
    _activePreset = null;
    notifyListeners();
  }

  void applyPreset(WindowPreset preset) {
    _activePreset = preset;
    _windowCenter = preset.center;
    _windowWidth = preset.width;
    notifyListeners();
  }

  void setZoom(double newZoom) {
    _zoom = newZoom.clamp(0.1, 20.0);
    notifyListeners();
  }

  void setPanOffset(Offset offset) {
    _panOffset = offset;
    notifyListeners();
  }

  void updateMetadata({
    String? patientName,
    String? patientId,
    String? studyDescription,
    String? seriesDescription,
  }) {
    if (patientName != null) _patientName = patientName;
    if (patientId != null) _patientId = patientId;
    if (studyDescription != null) _studyDescription = studyDescription;
    if (seriesDescription != null) _seriesDescription = seriesDescription;
    notifyListeners();
  }

  void resetView() {
    _zoom = 1.0;
    _panOffset = Offset.zero;
    if (_activePreset != null) {
      _windowCenter = _activePreset!.center;
      _windowWidth = _activePreset!.width;
    } else {
      _windowCenter = 40.0;
      _windowWidth = 400.0;
    }
    notifyListeners();
  }
}
