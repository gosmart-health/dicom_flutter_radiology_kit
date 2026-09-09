import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'annotation_model.dart';
import 'gsps_codec.dart';

/// Available interactive tools in the annotation layer.
enum AnnotationTool {
  none,
  select,
  caliper,
  angle,
  polyline,
  circle,
  ellipse,
  text,
}

/// Controller managing annotation models, tool selection, multi-collaborator visibility,
/// draft shape creation, and undo/redo state.
class AnnotationController extends ChangeNotifier {
  AnnotationTool _activeTool = AnnotationTool.select;
  final List<DicomAnnotation> _annotations = [];
  DicomAnnotation? _selectedAnnotation;
  DicomAnnotation? _draftAnnotation;

  String? _activeCreator = 'Radiologist';
  String? _filterCreator; // null = Show all collaborators

  // Undo/Redo state snapshots
  final List<List<DicomAnnotation>> _undoStack = [];
  final List<List<DicomAnnotation>> _redoStack = [];

  bool _isDirty = false;
  bool get isDirty => _isDirty;

  void markClean() {
    if (_isDirty) {
      _isDirty = false;
      notifyListeners();
    }
  }

  void markDirty() {
    if (!_isDirty) {
      _isDirty = true;
      notifyListeners();
    }
  }

  AnnotationController({
    List<DicomAnnotation>? initialAnnotations,
    AnnotationTool initialTool = AnnotationTool.select,
    String? activeCreator = 'Radiologist',
  })  : _activeTool = initialTool,
        _activeCreator = activeCreator {
    if (initialAnnotations != null) {
      _annotations.addAll(initialAnnotations);
    }
  }

  AnnotationTool get activeTool => _activeTool;
  List<DicomAnnotation> get allAnnotations => List.unmodifiable(_annotations);
  DicomAnnotation? get selectedAnnotation => _selectedAnnotation;
  DicomAnnotation? get draftAnnotation => _draftAnnotation;
  String? get activeCreator => _activeCreator;
  String? get filterCreator => _filterCreator;

  /// Visible annotations after applying collaborator filter.
  List<DicomAnnotation> get visibleAnnotations {
    if (_filterCreator == null) {
      return _annotations.where((a) => a.isVisible).toList();
    }
    return _annotations
        .where((a) => a.isVisible && a.creatorName == _filterCreator)
        .toList();
  }

  /// All unique creator/collaborator names present in current annotations.
  Set<String> get collaborators {
    final set = <String>{};
    for (final a in _annotations) {
      if (a.creatorName != null && a.creatorName!.isNotEmpty) {
        set.add(a.creatorName!);
      }
    }
    return set;
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void setActiveTool(AnnotationTool tool) {
    if (_activeTool != tool) {
      _activeTool = tool;
      _draftAnnotation = null;
      if (tool != AnnotationTool.select) {
        _selectedAnnotation = null;
      }
      notifyListeners();
    }
  }

  void setActiveCreator(String? creator) {
    _activeCreator = creator;
    notifyListeners();
  }

  /// Filters visibility by specific collaborator, or null to view all collaborators.
  void setFilterCreator(String? creator) {
    _filterCreator = creator;
    if (_selectedAnnotation != null &&
        _filterCreator != null &&
        _selectedAnnotation!.creatorName != _filterCreator) {
      _selectedAnnotation = null;
    }
    notifyListeners();
  }

  void selectAnnotation(DicomAnnotation? annotation) {
    if (_selectedAnnotation?.id != annotation?.id) {
      _selectedAnnotation = annotation;
      notifyListeners();
    }
  }

  void setDraftAnnotation(DicomAnnotation? draft) {
    _draftAnnotation = draft;
    notifyListeners();
  }

  void addAnnotation(DicomAnnotation annotation) {
    _recordUndo();
    _isDirty = true;
    // Attach current active creator if not set
    final effective = annotation.creatorName == null && _activeCreator != null
        ? annotation.copyWith(creatorName: _activeCreator)
        : annotation;
    _annotations.add(effective);
    _selectedAnnotation = effective;
    _draftAnnotation = null;
    notifyListeners();
  }

  void updateAnnotation(DicomAnnotation updated) {
    final index = _annotations.indexWhere((a) => a.id == updated.id);
    if (index != -1) {
      _recordUndo();
      _isDirty = true;
      _annotations[index] = updated;
      if (_selectedAnnotation?.id == updated.id) {
        _selectedAnnotation = updated;
      }
      notifyListeners();
    }
  }

  void removeAnnotation(String id) {
    final index = _annotations.indexWhere((a) => a.id == id);
    if (index != -1) {
      _recordUndo();
      _isDirty = true;
      _annotations.removeAt(index);
      if (_selectedAnnotation?.id == id) {
        _selectedAnnotation = null;
      }
      notifyListeners();
    }
  }

  /// Whether an annotation is selected or any annotation is available to delete.
  bool get hasDeletable => _selectedAnnotation != null || _annotations.isNotEmpty;

  /// Deletes the currently selected annotation.
  /// If no annotation is explicitly selected, deletes the most recently created annotation.
  void deleteSelected() {
    if (_selectedAnnotation != null) {
      removeAnnotation(_selectedAnnotation!.id);
    } else if (_annotations.isNotEmpty) {
      removeAnnotation(_annotations.last.id);
    }
  }

  void clearAnnotations() {
    if (_annotations.isNotEmpty) {
      _recordUndo();
      _isDirty = true;
      _annotations.clear();
      _selectedAnnotation = null;
      _draftAnnotation = null;
      notifyListeners();
    }
  }

  /// Replaces active annotations (e.g. when switching frames, series, or studies).
  /// Resets selection and clears undo/redo stacks.
  void setAnnotations(List<DicomAnnotation> newAnnotations, {bool isDirty = false}) {
    _annotations.clear();
    _annotations.addAll(newAnnotations);
    _isDirty = isDirty;
    _selectedAnnotation = null;
    _draftAnnotation = null;
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    _redoStack.add(List.from(_annotations));
    final previous = _undoStack.removeLast();
    _annotations.clear();
    _annotations.addAll(previous);
    _isDirty = true;
    _selectedAnnotation = null;
    _draftAnnotation = null;
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undoStack.add(List.from(_annotations));
    final next = _redoStack.removeLast();
    _annotations.clear();
    _annotations.addAll(next);
    _isDirty = true;
    _selectedAnnotation = null;
    _draftAnnotation = null;
    notifyListeners();
  }

  void _recordUndo() {
    _undoStack.add(List.from(_annotations));
    _redoStack.clear();
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
    }
  }

  /// Exports current annotations as a DICOM GSPS presentation state.
  GspsPresentationState toGspsPresentationState({
    String? contentLabel,
    String? contentDescription,
    String? sopInstanceUid,
    String? studyInstanceUid,
    String? seriesInstanceUid,
    String? referencedSopInstanceUid,
    int? referencedFrameNumber,
  }) {
    return GspsPresentationState(
      sopInstanceUid: sopInstanceUid,
      studyInstanceUid: studyInstanceUid,
      seriesInstanceUid: seriesInstanceUid,
      referencedSopInstanceUid: referencedSopInstanceUid,
      referencedFrameNumber: referencedFrameNumber,
      contentLabel: contentLabel ?? 'GSPS_LAYER',
      contentDescription: contentDescription,
      contentCreatorName: _activeCreator,
      annotations: _annotations,
    );
  }

  /// Loads annotations from a DICOM GSPS presentation state.
  void loadGspsPresentationState(
    GspsPresentationState gsps, {
    bool append = false,
  }) {
    _recordUndo();
    if (!append) {
      _annotations.clear();
    }
    _annotations.addAll(gsps.annotations);
    _isDirty = false;
    _selectedAnnotation = null;
    _draftAnnotation = null;
    notifyListeners();
  }
}

