import 'package:flutter/material.dart';
import '../imaging/pixel_frame.dart';
import '../imaging/presentation_state.dart';
import '../imaging/window_presets.dart';

/// State controller for DICOM viewports managing active frame, zoom/pan transform, window width/center,
/// and live presentation state propagation hooks.
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

  int? _frameIndex;
  int? _totalFrames;

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

  /// Current 1-indexed frame number for HUD overlays (e.g. 2 of 128).
  int? get frameIndex => _frameIndex;

  /// Total frames in the series for HUD overlays (e.g. 128).
  int? get totalFrames => _totalFrames;

  /// Callback invoked whenever presentation state (W/L, Zoom, Pan) changes.
  /// Downstream systems (like FirePACS live synchronization or local persistence)
  /// can hook here to propagate real-time viewing updates.
  void Function(DicomPresentationState state)? onPresentationChanged;

  /// Exports current viewport rendering parameters as a serializable [DicomPresentationState].
  DicomPresentationState toPresentationState() {
    return DicomPresentationState(
      windowCenter: _windowCenter,
      windowWidth: _windowWidth,
      zoom: _zoom,
      panOffset: _panOffset,
      presetName: _activePreset?.name,
    );
  }

  /// Restores viewport parameters from a [DicomPresentationState].
  void applyPresentationState(DicomPresentationState state, {bool notify = true}) {
    _windowCenter = state.windowCenter;
    _windowWidth = state.windowWidth < 1.0 ? 1.0 : state.windowWidth;
    _zoom = state.zoom.clamp(0.1, 20.0);
    _panOffset = state.panOffset;
    if (state.presetName != null) {
      _activePreset = WindowPresets.all.cast<WindowPreset?>().firstWhere(
            (p) => p?.name == state.presetName,
            orElse: () => null,
          );
    } else {
      _activePreset = null;
    }
    if (notify) {
      notifyListeners();
      _dispatchPresentationChanged();
    }
  }

  void _dispatchPresentationChanged() {
    onPresentationChanged?.call(toPresentationState());
  }

  /// Updates frame numbering for HUD overlays.
  void updateFrameIndices({int? frameIndex, int? totalFrames}) {
    bool changed = false;
    if (frameIndex != null && frameIndex != _frameIndex) {
      _frameIndex = frameIndex;
      changed = true;
    }
    if (totalFrames != null && totalFrames != _totalFrames) {
      _totalFrames = totalFrames;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  void setFrame(PixelFrame frame, {bool updateWindowLevelFromFrame = false}) {
    _currentFrame = frame;
    if (updateWindowLevelFromFrame) {
      final (min, max) = frame.getMinMax();
      final double modMin = frame.getModalityValue(min.toInt());
      final double modMax = frame.getModalityValue(max.toInt());
      final computedWidth = (modMax - modMin).abs();
      if (computedWidth > 1.0) {
        _windowWidth = computedWidth;
        _windowCenter = modMin + (_windowWidth / 2.0);
      } else {
        _windowCenter = 2048.0;
        _windowWidth = 4096.0;
      }
      _activePreset = null;
      _dispatchPresentationChanged();
    }
    notifyListeners();
  }

  /// Clears active pixel frame from memory.
  void clearFrame() {
    _currentFrame = null;
    notifyListeners();
  }

  /// Clears active pixel frame and patient metadata from memory.
  void clear() {
    _currentFrame = null;
    _patientName = '';
    _patientId = '';
    _studyDescription = '';
    _seriesDescription = '';
    _frameIndex = null;
    _totalFrames = null;
    _zoom = 1.0;
    _panOffset = Offset.zero;
    notifyListeners();
  }

  /// Callback invoked when slice scrolling is triggered via mouse wheel or gesture.
  /// Parameter [direction] is +1 for next slice, -1 for previous slice.
  void Function(int direction)? onSliceStep;

  /// Dispatches slice step navigation to registered listeners or callbacks.
  void stepSlice(int direction) {
    if (direction != 0) {
      onSliceStep?.call(direction);
    }
  }

  void setWindowLevel(double center, double width) {
    _windowCenter = center;
    _windowWidth = width < 1.0 ? 1.0 : width;
    _activePreset = null;
    notifyListeners();
    _dispatchPresentationChanged();
  }

  /// Relative adjustment to active window width and center.
  void adjustWindowLevel(double deltaCenter, double deltaWidth) {
    setWindowLevel(_windowCenter + deltaCenter, _windowWidth + deltaWidth);
  }

  void applyPreset(WindowPreset preset) {
    _activePreset = preset;
    _windowCenter = preset.center;
    _windowWidth = preset.width;
    notifyListeners();
    _dispatchPresentationChanged();
  }

  void setZoom(double newZoom) {
    _zoom = newZoom.clamp(0.1, 20.0);
    notifyListeners();
    _dispatchPresentationChanged();
  }

  /// Relative adjustment to current zoom scale.
  void adjustZoom(double deltaZoom) {
    setZoom(_zoom + deltaZoom);
  }

  void setPanOffset(Offset offset) {
    _panOffset = offset;
    notifyListeners();
    _dispatchPresentationChanged();
  }

  /// Relative adjustment to pan offset.
  void adjustPan(Offset deltaOffset) {
    setPanOffset(_panOffset + deltaOffset);
  }

  void updateMetadata({
    String? patientName,
    String? patientId,
    String? studyDescription,
    String? seriesDescription,
    int? frameIndex,
    int? totalFrames,
  }) {
    if (patientName != null) _patientName = patientName;
    if (patientId != null) _patientId = patientId;
    if (studyDescription != null) _studyDescription = studyDescription;
    if (seriesDescription != null) _seriesDescription = seriesDescription;
    if (frameIndex != null) _frameIndex = frameIndex;
    if (totalFrames != null) _totalFrames = totalFrames;
    notifyListeners();
  }

  /// Whether zoom or pan has been customized away from default auto-fit / zero-pan.
  bool get isZoomPanModified => (_zoom - 1.0).abs() > 0.001 || _panOffset != Offset.zero;

  /// Resets zoom to 1.0 (auto-fit) and panOffset to Offset.zero.
  void resetZoomPan({bool notify = true}) {
    _zoom = 1.0;
    _panOffset = Offset.zero;
    if (notify) {
      notifyListeners();
      _dispatchPresentationChanged();
    }
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
    _dispatchPresentationChanged();
  }
}
