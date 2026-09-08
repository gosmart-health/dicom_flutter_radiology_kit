import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';
import 'fixtures/synthetic_patterns.dart';

void main() {
  runApp(const DicomViewerApp());
}

class DicomViewerApp extends StatelessWidget {
  const DicomViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DICOM Flutter Radiology Kit Test Viewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1218),
        cardColor: const Color(0xFF181D26),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF388BFD),
          secondary: Color(0xFF58A6FF),
          surface: Color(0xFF161B22),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161B22),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      home: const DicomViewerWorkbench(),
    );
  }
}

/// Clinical viewport grid layout options: 1 on 1, 2 on 1, 4 on 1, 9 on 1.
enum ViewportLayout {
  oneOnOne('1 on 1 (1×1)', 1, 1),
  twoOnOne('2 on 1 (1×2)', 1, 2),
  fourOnOne('4 on 1 (2×2)', 2, 2),
  nineOnOne('9 on 1 (3×3)', 3, 3);

  final String label;
  final int rows;
  final int cols;
  const ViewportLayout(this.label, this.rows, this.cols);

  int get count => rows * cols;
}

class DicomViewerWorkbench extends StatefulWidget {
  const DicomViewerWorkbench({super.key});

  @override
  State<DicomViewerWorkbench> createState() => _DicomViewerWorkbenchState();
}

class _DicomViewerWorkbenchState extends State<DicomViewerWorkbench> {
  // Pool of 9 controllers for up to 3x3 layout
  late final List<ViewportController> _controllers;
  ViewportLayout _layout = ViewportLayout.oneOnOne;

  bool _showOverlay = true;
  String _selectedFixture = 'CT Phantom';
  bool _sidebarExpanded = true;

  DicomSeriesBuffer? _loadedSeries;
  int _currentFrameIndex = 0;
  bool _isLoadingFrame = false;
  late String _activeServerUrl;

  // In-memory persistent presentation states per frame index
  final Map<int, DicomPresentationState> _framePresentationCache = {};

  // Annotation controllers pool for up to 9 slots
  late final List<AnnotationController> _annotationControllers;
  AnnotationTool _activeTool = AnnotationTool.none;
  String? _collaboratorFilter;

  // Cache of annotations per study/series key and frame index:
  // Map<seriesKey, Map<frameIndex, List<DicomAnnotation>>>
  final Map<String, Map<int, List<DicomAnnotation>>> _seriesAnnotationCache = {};
  String? _activeSeriesKey;
  final List<int?> _slotActiveFrameIndex = List.filled(9, null);

  String _computeSeriesKey() {
    if (_loadedSeries != null) {
      final studyUid = _loadedSeries!.study?.studyInstanceUID ?? 'unknown_study';
      final seriesUid = _loadedSeries!.series.seriesInstanceUID;
      return '$studyUid/$seriesUid';
    }
    return 'fixture:$_selectedFixture';
  }

  void _saveCurrentSlotAnnotations() {
    if (_activeSeriesKey == null) return;
    final cache = _seriesAnnotationCache.putIfAbsent(_activeSeriesKey!, () => {});
    for (int s = 0; s < 9; s++) {
      final frameIdx = _slotActiveFrameIndex[s];
      if (frameIdx != null) {
        cache[frameIdx] =
            List<DicomAnnotation>.from(_annotationControllers[s].allAnnotations);
      }
    }
  }

  void _restoreSlotAnnotations(String newSeriesKey) {
    _saveCurrentSlotAnnotations();
    _activeSeriesKey = newSeriesKey;
    final cache = _seriesAnnotationCache[newSeriesKey] ?? {};
    final activeSlots = _layout.count;
    final totalFrames = _loadedSeries?.frameCount ?? 1;

    for (int s = 0; s < 9; s++) {
      if (s < activeSlots &&
          (_loadedSeries != null
              ? (_currentFrameIndex + s < totalFrames)
              : s == 0)) {
        final frameIdx = _loadedSeries != null ? (_currentFrameIndex + s) : 0;
        _slotActiveFrameIndex[s] = frameIdx;
        final saved = cache[frameIdx] ?? const <DicomAnnotation>[];
        _annotationControllers[s].setAnnotations(saved);
        _annotationControllers[s].setActiveTool(_activeTool);
        _annotationControllers[s].setFilterCreator(_collaboratorFilter);
      } else {
        _slotActiveFrameIndex[s] = null;
        _annotationControllers[s].setAnnotations(const <DicomAnnotation>[]);
        _annotationControllers[s].setActiveTool(_activeTool);
        _annotationControllers[s].setFilterCreator(_collaboratorFilter);
      }
    }
  }

  ViewportController get _primaryController => _controllers[0];
  AnnotationController get _primaryAnnotationController =>
      _annotationControllers[0];

  @override
  void initState() {
    super.initState();
    _activeServerUrl = DicomServerUrlStore.getLastUsedUrl();

    _annotationControllers = List.generate(9, (index) {
      return AnnotationController(
        initialTool: _activeTool,
        activeCreator: 'Dr. Radiologist',
      );
    });

    _controllers = List.generate(9, (index) {
      final controller = ViewportController();
      controller.onSliceStep = (direction) {
        if (_loadedSeries != null && _loadedSeries!.frameCount > 1) {
          final nextIdx = (_currentFrameIndex + direction)
              .clamp(0, _loadedSeries!.frameCount - 1);
          if (nextIdx != _currentFrameIndex) {
            _goToFrame(nextIdx);
          }
        }
      };

      // Live propagation hook: save presentation state per frame
      controller.onPresentationChanged = (state) {
        final frameNum = controller.frameIndex;
        if (frameNum != null && frameNum > 0) {
          _framePresentationCache[frameNum - 1] = state;
        }
      };

      return controller;
    });

    _loadCtPhantom();
  }

  @override
  void dispose() {
    _loadedSeries?.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final ac in _annotationControllers) {
      ac.dispose();
    }
    super.dispose();
  }

  void _loadCtPhantom() {
    _saveCurrentSlotAnnotations();
    _loadedSeries?.dispose();
    _loadedSeries = null;
    _framePresentationCache.clear();
    final frame = SyntheticPatterns.generateCtPhantom();

    for (int i = 0; i < _controllers.length; i++) {
      if (i == 0) {
        _controllers[i].resetZoomPan(notify: false);
        _controllers[i].setFrame(frame);
        _controllers[i].applyPreset(WindowPresets.softTissue);
        _controllers[i].updateMetadata(
          patientName: 'DOE^JOHN',
          patientId: 'SYN-CT-90210',
          studyDescription: 'CT THORAX W/ CONTRAST',
          seriesDescription: 'AXIAL 5.0mm SOFT TISSUE',
          frameIndex: 1,
          totalFrames: 1,
        );
      } else {
        _controllers[i].clear();
      }
    }
    setState(() {
      _currentFrameIndex = 0;
      _selectedFixture = 'CT Phantom';
    });
    _restoreSlotAnnotations('fixture:CT Phantom');
  }

  void _loadTg18Qc() {
    _saveCurrentSlotAnnotations();
    _loadedSeries?.dispose();
    _loadedSeries = null;
    _framePresentationCache.clear();
    final frame = SyntheticPatterns.generateTg18QcPattern();

    for (int i = 0; i < _controllers.length; i++) {
      if (i == 0) {
        _controllers[i].resetZoomPan(notify: false);
        _controllers[i].setFrame(frame);
        _controllers[i].setWindowLevel(2048, 4096);
        _controllers[i].updateMetadata(
          patientName: 'QUALITY^CONTROL',
          patientId: 'QC-TG18-001',
          studyDescription: 'TG18-QC DISPLAY CALIBRATION',
          seriesDescription: 'SMPTE DYNAMIC RANGE TEST',
          frameIndex: 1,
          totalFrames: 1,
        );
      } else {
        _controllers[i].clear();
      }
    }
    setState(() {
      _currentFrameIndex = 0;
      _selectedFixture = 'TG18-QC Test Pattern';
    });
    _restoreSlotAnnotations('fixture:TG18-QC Test Pattern');
  }

  void _loadDynamicRamp() {
    _saveCurrentSlotAnnotations();
    _loadedSeries?.dispose();
    _loadedSeries = null;
    _framePresentationCache.clear();
    final frame = SyntheticPatterns.generateDynamicRamp();

    for (int i = 0; i < _controllers.length; i++) {
      if (i == 0) {
        _controllers[i].resetZoomPan(notify: false);
        _controllers[i].setFrame(frame);
        _controllers[i].setWindowLevel(250, 2500);
        _controllers[i].updateMetadata(
          patientName: 'CALIBRATION^RAMP',
          patientId: 'RAMP-16BIT-002',
          studyDescription: 'CONTINUOUS 16-BIT HU GRADIENT',
          seriesDescription: '-1000 HU TO +2500 HU RAMP',
          frameIndex: 1,
          totalFrames: 1,
        );
      } else {
        _controllers[i].clear();
      }
    }
    setState(() {
      _currentFrameIndex = 0;
      _selectedFixture = 'Dynamic Ramp';
    });
    _restoreSlotAnnotations('fixture:Dynamic Ramp');
  }

  Future<void> _openQidoBrowser() async {
    await QidoBrowserDialog.show(
      context,
      onStudySelected: (study) {
        _saveCurrentSlotAnnotations();
        _loadedSeries?.dispose();
        _loadedSeries = null;
        _framePresentationCache.clear();
        for (final c in _controllers) {
          c.clear();
        }
        for (final ac in _annotationControllers) {
          ac.setAnnotations(const []);
        }
        setState(() {
          _currentFrameIndex = 0;
          _selectedFixture = 'Loading: ${study.patientName}';
        });
      },
      onSeriesLoaded: (seriesBuffer, initialFrame) {
        _saveCurrentSlotAnnotations();
        _loadedSeries?.dispose();
        _framePresentationCache.clear();
        setState(() {
          _loadedSeries = seriesBuffer;
          _currentFrameIndex = 0;
          _selectedFixture = 'QIDO: ${seriesBuffer.series.seriesDescription}';
        });

        _syncGridLayoutFrames();
        _restoreSlotAnnotations(_computeSeriesKey());

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Buffered ${seriesBuffer.frameCount} frame(s) into 16-bit memory.',
            ),
            backgroundColor: const Color(0xFF238636),
            duration: const Duration(seconds: 3),
          ),
        );
      },
    );
    if (mounted) {
      setState(() {
        _activeServerUrl = DicomServerUrlStore.getLastUsedUrl();
      });
    }
  }

  void _setAnnotationTool(AnnotationTool tool) {
    setState(() {
      _activeTool = tool;
    });
    for (final c in _annotationControllers) {
      c.setActiveTool(tool);
    }
  }

  void _setCollaboratorFilter(String? creator) {
    setState(() {
      _collaboratorFilter = creator;
    });
    for (final c in _annotationControllers) {
      c.setFilterCreator(creator);
    }
  }

  void _loadSampleAnnotations() {
    _primaryAnnotationController.clearAnnotations();

    // 1. Caliper across thorax
    final caliper = CaliperAnnotation(
      id: 'cal_thorax',
      start: const Offset(140, 256),
      end: const Offset(372, 256),
      label: 'Thoracic width',
      creatorName: 'Dr. Alice',
    );

    // 2. 3-point Angle at subcarina
    final angle = AngleAnnotation(
      id: 'ang_carina',
      p1: const Offset(210, 200),
      vertex: const Offset(256, 235),
      p2: const Offset(302, 200),
      label: 'Carinal angle',
      creatorName: 'Dr. Alice',
    );

    // 3. Circle around hyperdense nodule
    final circle = CircleAnnotation(
      id: 'circ_nodule',
      center: const Offset(332, 195),
      radius: 18.0,
      label: 'Hyperdense nodule',
      creatorName: 'Dr. Bob',
    );

    // 4. Ellipse around vertebra / spine
    final ellipse = EllipseAnnotation(
      id: 'ell_spine',
      center: const Offset(256, 360),
      radiusX: 28.0,
      radiusY: 18.0,
      rotation: 0.0,
      label: 'Vertebral body',
      creatorName: 'Dr. Alice',
    );

    // 5. Text annotation note
    final text = TextAnnotation(
      id: 'txt_finding',
      anchor: const Offset(340, 160),
      text: 'Suspicious nodule (180 HU)',
      creatorName: 'Dr. Bob',
    );

    _primaryAnnotationController.addAnnotation(caliper);
    _primaryAnnotationController.addAnnotation(angle);
    _primaryAnnotationController.addAnnotation(circle);
    _primaryAnnotationController.addAnnotation(ellipse);
    _primaryAnnotationController.addAnnotation(text);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Loaded clinical sample annotations (Dr. Alice & Dr. Bob).',
        ),
        backgroundColor: Color(0xFF238636),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openGspsModal() {
    _saveCurrentSlotAnnotations();
    final gsps = _primaryAnnotationController.toGspsPresentationState(
      contentLabel: 'WORKBENCH_EXPORT',
      contentDescription: 'Clinical review marks',
    );
    final jsonString = gsps.toJsonString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Row(
          children: [
            Icon(Icons.code, color: Color(0xFF58A6FF), size: 20),
            SizedBox(width: 8),
            Text(
              'DICOM GSPS Presentation State JSON',
              style: TextStyle(fontSize: 15, color: Colors.white),
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              jsonString,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFF7EE787),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getActiveSliceMetadata() {
    if (_loadedSeries != null && _loadedSeries!.frames.isNotEmpty) {
      final idx = _currentFrameIndex.clamp(0, _loadedSeries!.frames.length - 1);
      return _loadedSeries!.frames[idx].metadata.rawJson;
    }
    // Synthetic fallback metadata for test pattern fixtures
    return {
      '00080016': {
        'vr': 'UI',
        'Value': ['1.2.840.10008.5.1.4.1.1.7']
      },
      '00080018': {
        'vr': 'UI',
        'Value': ['1.2.826.0.1.3680043.9.7133.1.1']
      },
      '00080020': {
        'vr': 'DA',
        'Value': ['20260908']
      },
      '00080030': {
        'vr': 'TM',
        'Value': ['120000']
      },
      '00080060': {
        'vr': 'CS',
        'Value': ['OT']
      },
      '00080070': {
        'vr': 'LO',
        'Value': ['RadiologyKit']
      },
      '00080080': {
        'vr': 'LO',
        'Value': ['Radiology Department']
      },
      '00081030': {
        'vr': 'LO',
        'Value': [_selectedFixture]
      },
      '0008103E': {
        'vr': 'LO',
        'Value': ['Synthetic Calibration Test Pattern']
      },
      '00100010': {
        'vr': 'PN',
        'Value': [
          {
            'Alphabetic': _selectedFixture.contains('TG18')
                ? 'QUALITY^CONTROL'
                : 'CALIBRATION^RAMP'
          }
        ]
      },
      '00100020': {
        'vr': 'LO',
        'Value': [
          _selectedFixture.contains('TG18') ? 'QC-TG18-001' : 'RAMP-16BIT-002'
        ]
      },
      '00100040': {
        'vr': 'CS',
        'Value': ['O']
      },
      '0020000D': {
        'vr': 'UI',
        'Value': ['1.2.826.0.1.3680043.9.7133.1']
      },
      '0020000E': {
        'vr': 'UI',
        'Value': ['1.2.826.0.1.3680043.9.7133.1.1']
      },
      '00200013': {
        'vr': 'IS',
        'Value': ['1']
      },
      '00280002': {
        'vr': 'US',
        'Value': [1]
      },
      '00280004': {
        'vr': 'CS',
        'Value': ['MONOCHROME2']
      },
      '00280010': {
        'vr': 'US',
        'Value': [512]
      },
      '00280011': {
        'vr': 'US',
        'Value': [512]
      },
      '00280100': {
        'vr': 'US',
        'Value': [16]
      },
      '00280101': {
        'vr': 'US',
        'Value': [12]
      },
      '00280102': {
        'vr': 'US',
        'Value': [11]
      },
      '00280103': {
        'vr': 'US',
        'Value': [0]
      },
      '00281050': {
        'vr': 'DS',
        'Value': [_primaryController.windowCenter.toStringAsFixed(0)]
      },
      '00281051': {
        'vr': 'DS',
        'Value': [_primaryController.windowWidth.toStringAsFixed(0)]
      },
    };
  }

  void _openDicomDumpModal() {
    final metadata = _getActiveSliceMetadata();
    final sliceNum = _loadedSeries != null ? _currentFrameIndex + 1 : 1;
    final total = _loadedSeries != null ? _loadedSeries!.frameCount : 1;
    DicomDumpDialog.show(
      context,
      metadataJson: metadata,
      title: 'DICOM Dump — Slice $sliceNum of $total ($selectedFixtureName)',
    );
  }

  String get selectedFixtureName {
    if (_loadedSeries != null) {
      return _loadedSeries!.series.seriesDescription.isNotEmpty
          ? _loadedSeries!.series.seriesDescription
          : 'Series';
    }
    return _selectedFixture;
  }

  Future<void> _goToFrame(int index) async {
    if (_loadedSeries == null || _isLoadingFrame) return;
    if (index < 0 || index >= _loadedSeries!.frameCount) return;

    _saveCurrentSlotAnnotations();
    setState(() {
      _isLoadingFrame = true;
      _currentFrameIndex = index;
    });

    try {
      await _syncGridLayoutFrames();
      _restoreSlotAnnotations(_computeSeriesKey());
    } finally {
      if (mounted) {
        setState(() => _isLoadingFrame = false);
      }
    }
  }

  /// Synchronizes frame decoding and presentation states across all active grid slots.
  Future<void> _syncGridLayoutFrames() async {
    if (_loadedSeries == null) return;

    final totalCount = _loadedSeries!.frameCount;
    final activeSlots = _layout.count;

    for (int slot = 0; slot < 9; slot++) {
      final controller = _controllers[slot];
      if (slot < activeSlots) {
        final frameIdx = _currentFrameIndex + slot;
        if (frameIdx < totalCount) {
          final pixelFrame = await _loadedSeries!.getPixelFrame(frameIdx);
          if (pixelFrame != null && mounted) {
            // Apply or restore per-frame presentation state
            final cachedState = _framePresentationCache[frameIdx];
            if (cachedState != null) {
              controller.applyPresentationState(cachedState, notify: false);
              controller.setFrame(pixelFrame,
                  updateWindowLevelFromFrame: false);
            } else {
              controller.resetZoomPan(notify: false);
              final is8Bit = pixelFrame.bitsAllocated <= 8 ||
                  pixelFrame.rawPixels is Uint8List;
              if (is8Bit) {
                controller.setWindowLevel(128.0, 256.0);
                controller.setFrame(pixelFrame,
                    updateWindowLevelFromFrame: false);
              } else {
                final metaCenter = _loadedSeries!.frames.isNotEmpty
                    ? _loadedSeries!
                        .frames[frameIdx < _loadedSeries!.frames.length
                            ? frameIdx
                            : 0]
                        .metadata
                        .windowCenter
                    : null;
                final metaWidth = _loadedSeries!.frames.isNotEmpty
                    ? _loadedSeries!
                        .frames[frameIdx < _loadedSeries!.frames.length
                            ? frameIdx
                            : 0]
                        .metadata
                        .windowWidth
                    : null;
                if (metaCenter != null &&
                    metaWidth != null &&
                    metaWidth > 1.0) {
                  controller.setWindowLevel(metaCenter, metaWidth);
                  controller.setFrame(pixelFrame,
                      updateWindowLevelFromFrame: false);
                } else {
                  controller.setFrame(pixelFrame,
                      updateWindowLevelFromFrame: true);
                }
              }
            }

            controller.updateMetadata(
              patientName: _loadedSeries!.study?.patientName ?? 'Anonymous',
              patientId: _loadedSeries!.study?.patientId ?? '-',
              studyDescription:
                  _loadedSeries!.study?.studyDescription ?? 'DICOM Study',
              seriesDescription: _loadedSeries!.series.seriesDescription,
              frameIndex: frameIdx + 1,
              totalFrames: totalCount,
              pixelSpacing: pixelFrame.pixelSpacing,
            );
          }
        } else {
          controller.clear();
        }
      } else {
        controller.clear();
      }
    }
  }

  void _setLayout(ViewportLayout layout) {
    _saveCurrentSlotAnnotations();
    setState(() {
      _layout = layout;
    });
    _syncGridLayoutFrames();
    _restoreSlotAnnotations(_computeSeriesKey());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.medical_services_outlined,
                color: Color(0xFF388BFD), size: 20),
            SizedBox(width: 10),
            Text('DICOM Flutter Radiology Kit'),
            SizedBox(width: 8),
            Chip(
              label: Text('16-bit VOI LUT',
                  style: TextStyle(fontSize: 10, color: Colors.white)),
              backgroundColor: Color(0xFF238636),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: _openQidoBrowser,
            icon: const Icon(Icons.manage_search_rounded, size: 16),
            label: const Text('QIDO Patient Browser',
                style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F6FEB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 8),

          // Layout Grid Selector Menu
          PopupMenuButton<ViewportLayout>(
            icon: const Icon(Icons.grid_view_rounded, color: Color(0xFF58A6FF)),
            tooltip: 'Layout Grid ([1, 2, 4, 9] on 1)',
            onSelected: _setLayout,
            itemBuilder: (context) => [
              _buildLayoutMenuItem(
                  ViewportLayout.oneOnOne, Icons.crop_square_rounded),
              _buildLayoutMenuItem(
                  ViewportLayout.twoOnOne, Icons.view_agenda_rounded),
              _buildLayoutMenuItem(
                  ViewportLayout.fourOnOne, Icons.grid_view_rounded),
              _buildLayoutMenuItem(
                  ViewportLayout.nineOnOne, Icons.apps_rounded),
            ],
          ),

          IconButton(
            icon: Icon(_showOverlay ? Icons.layers : Icons.layers_clear),
            tooltip: 'Toggle HUD Overlays',
            onPressed: () => setState(() => _showOverlay = !_showOverlay),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            tooltip: 'Zoom In Primary',
            onPressed: () =>
                _primaryController.setZoom(_primaryController.zoom + 0.25),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            tooltip: 'Zoom Out Primary',
            onPressed: () =>
                _primaryController.setZoom(_primaryController.zoom - 0.25),
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Reset View & Presets',
            onPressed: () {
              for (final c in _controllers) {
                c.resetView();
              }
            },
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _openDicomDumpModal,
            icon: const Icon(Icons.data_object_rounded, size: 16),
            label: const Text('DICOM Dump', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF21262D),
              foregroundColor: const Color(0xFF58A6FF),
              side: const BorderSide(color: Color(0xFF30363D)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(_sidebarExpanded
                ? Icons.view_sidebar
                : Icons.view_sidebar_outlined),
            tooltip: 'Toggle Control Panel',
            onPressed: () =>
                setState(() => _sidebarExpanded = !_sidebarExpanded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          // Main Viewport Area: 1, 2, 4, or 9 on 1 Grid
          Expanded(
            child: Column(
              children: [
                _buildAnnotationToolbar(),
                Expanded(child: _buildViewportGrid()),
              ],
            ),
          ),

          // Control & Inspector Sidebar
          if (_sidebarExpanded)
            Container(
              width: 320,
              decoration: const BoxDecoration(
                color: Color(0xFF161B22),
                border: Border(left: BorderSide(color: Color(0xFF30363D))),
              ),
              child: _buildSidebar(),
            ),
        ],
      ),
    );
  }

  Widget _buildAnnotationToolbar() {
    return ListenableBuilder(
      listenable: _primaryAnnotationController,
      builder: (context, _) {
        final currentTool = _primaryAnnotationController.activeTool;
        final canUndo = _primaryAnnotationController.canUndo;
        final canRedo = _primaryAnnotationController.canRedo;
        final hasSelected =
            _primaryAnnotationController.selectedAnnotation != null;
        final canDelete = _primaryAnnotationController.hasDeletable;

        return Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF161B22),
            border: Border(
              bottom: BorderSide(color: Color(0xFF30363D), width: 1.5),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildToolButton(
                  icon: Icons.open_with,
                  label: 'Pan/W-L',
                  tool: AnnotationTool.none,
                  currentTool: currentTool,
                ),
                _buildToolButton(
                  icon: Icons.near_me_outlined,
                  label: 'Select',
                  tool: AnnotationTool.select,
                  currentTool: currentTool,
                ),
                const SizedBox(width: 4),
                const VerticalDivider(
                    width: 16, indent: 8, endIndent: 8, color: Color(0xFF30363D)),
                const SizedBox(width: 4),
                _buildToolButton(
                  icon: Icons.straighten,
                  label: 'Caliper (mm)',
                  tool: AnnotationTool.caliper,
                  currentTool: currentTool,
                ),
                _buildToolButton(
                  icon: Icons.square_foot_rounded,
                  label: 'Angle',
                  tool: AnnotationTool.angle,
                  currentTool: currentTool,
                ),
                _buildToolButton(
                  icon: Icons.timeline,
                  label: 'Polyline',
                  tool: AnnotationTool.polyline,
                  currentTool: currentTool,
                ),
                _buildToolButton(
                  icon: Icons.circle_outlined,
                  label: 'Circle',
                  tool: AnnotationTool.circle,
                  currentTool: currentTool,
                ),
                _buildToolButton(
                  icon: Icons.egg_outlined,
                  label: 'Ellipse',
                  tool: AnnotationTool.ellipse,
                  currentTool: currentTool,
                ),
                _buildToolButton(
                  icon: Icons.text_fields,
                  label: 'Text',
                  tool: AnnotationTool.text,
                  currentTool: currentTool,
                ),
                const SizedBox(width: 4),
                const VerticalDivider(
                    width: 16, indent: 8, endIndent: 8, color: Color(0xFF30363D)),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.undo, size: 18),
                  tooltip: 'Undo',
                  color: canUndo ? Colors.white : const Color(0xFF484F58),
                  onPressed: canUndo
                      ? () => _primaryAnnotationController.undo()
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.redo, size: 18),
                  tooltip: 'Redo',
                  color: canRedo ? Colors.white : const Color(0xFF484F58),
                  onPressed: canRedo
                      ? () => _primaryAnnotationController.redo()
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: hasSelected
                      ? 'Delete Selected (Del)'
                      : 'Delete Last Created (Del)',
                  color: canDelete
                      ? const Color(0xFFF85149)
                      : const Color(0xFF484F58),
                  onPressed: canDelete
                      ? () => _primaryAnnotationController.deleteSelected()
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.clear_all, size: 18),
                  tooltip: 'Clear All Annotations',
                  color: _primaryAnnotationController.allAnnotations.isNotEmpty
                      ? const Color(0xFF8B949E)
                      : const Color(0xFF484F58),
                  onPressed:
                      _primaryAnnotationController.allAnnotations.isNotEmpty
                          ? () => _primaryAnnotationController.clearAnnotations()
                          : null,
                ),
                const SizedBox(width: 16),
                _buildCollaboratorFilterDropdown(),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loadSampleAnnotations,
                  icon: const Icon(Icons.auto_awesome, size: 14),
                  label: const Text('Samples', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFEB3B),
                    side: const BorderSide(color: Color(0x66FFEB3B)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
                const SizedBox(width: 6),
                ElevatedButton.icon(
                  onPressed: _openGspsModal,
                  icon: const Icon(Icons.download_for_offline_outlined, size: 14),
                  label: const Text('GSPS JSON', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF21262D),
                    foregroundColor: const Color(0xFF58A6FF),
                    side: const BorderSide(color: Color(0xFF30363D)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required AnnotationTool tool,
    required AnnotationTool currentTool,
  }) {
    final isSelected = tool == currentTool;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _setAnnotationTool(tool),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF1F6FEB) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color:
                    isSelected ? const Color(0xFF58A6FF) : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? Colors.white : const Color(0xFFC9D1D9),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : const Color(0xFFC9D1D9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollaboratorFilterDropdown() {
    final collaborators = _primaryAnnotationController.collaborators.toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _collaboratorFilter,
          dropdownColor: const Color(0xFF161B22),
          isDense: true,
          hint: const Text('All Collaborators',
              style: TextStyle(fontSize: 11, color: Color(0xFF58A6FF))),
          icon: const Icon(Icons.arrow_drop_down,
              size: 16, color: Color(0xFF58A6FF)),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All Collaborators',
                  style: TextStyle(fontSize: 11, color: Colors.white)),
            ),
            for (final creator in collaborators)
              DropdownMenuItem<String?>(
                value: creator,
                child: Text('User: $creator',
                    style: const TextStyle(fontSize: 11, color: Colors.white)),
              ),
          ],
          onChanged: (val) => _setCollaboratorFilter(val),
        ),
      ),
    );
  }

  PopupMenuItem<ViewportLayout> _buildLayoutMenuItem(
      ViewportLayout layout, IconData icon) {
    final isSelected = _layout == layout;
    return PopupMenuItem<ViewportLayout>(
      value: layout,
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: isSelected
                  ? const Color(0xFF58A6FF)
                  : const Color(0xFF8B949E)),
          const SizedBox(width: 10),
          Text(
            layout.label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? const Color(0xFF58A6FF) : Colors.white,
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            const Icon(Icons.check, size: 16, color: Color(0xFF58A6FF)),
          ],
        ],
      ),
    );
  }

  Widget _buildViewportSlot(int slot) {
    return ClipRect(
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DicomViewport(
            controller: _controllers[slot],
            showOverlay: _showOverlay,
          ),
          DicomAnnotationLayer(
            viewportController: _controllers[slot],
            annotationController: _annotationControllers[slot],
          ),
        ],
      ),
    );
  }

  Widget _buildViewportGrid() {
    switch (_layout) {
      case ViewportLayout.oneOnOne:
        return _buildViewportSlot(0);

      case ViewportLayout.twoOnOne:
        return Row(
          children: [
            Expanded(child: _buildViewportSlot(0)),
            const VerticalDivider(
                width: 2, thickness: 2, color: Color(0xFF30363D)),
            Expanded(child: _buildViewportSlot(1)),
          ],
        );

      case ViewportLayout.fourOnOne:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildViewportSlot(0)),
                  const VerticalDivider(
                      width: 2, thickness: 2, color: Color(0xFF30363D)),
                  Expanded(child: _buildViewportSlot(1)),
                ],
              ),
            ),
            const Divider(height: 2, thickness: 2, color: Color(0xFF30363D)),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildViewportSlot(2)),
                  const VerticalDivider(
                      width: 2, thickness: 2, color: Color(0xFF30363D)),
                  Expanded(child: _buildViewportSlot(3)),
                ],
              ),
            ),
          ],
        );

      case ViewportLayout.nineOnOne:
        return Column(
          children: List.generate(3, (row) {
            return Expanded(
              child: Column(
                children: [
                  if (row > 0)
                    const Divider(
                        height: 2, thickness: 2, color: Color(0xFF30363D)),
                  Expanded(
                    child: Row(
                      children: List.generate(3, (col) {
                        final slot = row * 3 + col;
                        return Expanded(
                          child: Row(
                            children: [
                              if (col > 0)
                                const VerticalDivider(
                                    width: 2,
                                    thickness: 2,
                                    color: Color(0xFF30363D)),
                              Expanded(child: _buildViewportSlot(slot)),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            );
          }),
        );
    }
  }

  Widget _buildSidebar() {
    return ListenableBuilder(
      listenable:
          Listenable.merge([_primaryController, _primaryAnnotationController]),
      builder: (context, _) {
        final frame = _primaryController.currentFrame;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Fixture Selector
            _buildSectionHeader('STUDIES & FIXTURES'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildFixtureChip('CT Phantom',
                    _selectedFixture == 'CT Phantom', _loadCtPhantom),
                _buildFixtureChip('TG18-QC',
                    _selectedFixture == 'TG18-QC Test Pattern', _loadTg18Qc),
                _buildFixtureChip('Dynamic Ramp',
                    _selectedFixture == 'Dynamic Ramp', _loadDynamicRamp),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openQidoBrowser,
              icon: const Icon(Icons.cloud_sync_outlined, size: 16),
              label: const Text('QIDO Studies & Series Browser',
                  style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF58A6FF),
                side: const BorderSide(color: Color(0xFF388BFD)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.dns_outlined,
                      size: 12, color: Color(0xFF58A6FF)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Root: $_activeServerUrl',
                      style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF8B949E),
                          fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            if (_loadedSeries != null && _loadedSeries!.frameCount > 1) ...[
              const Divider(height: 32, color: Color(0xFF30363D)),
              _buildSectionHeader('SERIES SLICE NAVIGATION'),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Base Frame ${_currentFrameIndex + 1} / ${_loadedSeries!.frameCount}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF58A6FF)),
                  ),
                  if (_isLoadingFrame)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              Slider(
                value: _currentFrameIndex.toDouble(),
                min: 0.0,
                max: (_loadedSeries!.frameCount - 1).toDouble(),
                divisions: _loadedSeries!.frameCount > 1
                    ? _loadedSeries!.frameCount - 1
                    : 1,
                onChanged: (val) => _goToFrame(val.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 20),
                    onPressed:
                        _currentFrameIndex > 0 ? () => _goToFrame(0) : null,
                    tooltip: 'First Slice',
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    onPressed: _currentFrameIndex > 0
                        ? () => _goToFrame(_currentFrameIndex - 1)
                        : null,
                    tooltip: 'Previous Slice',
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    onPressed:
                        _currentFrameIndex < _loadedSeries!.frameCount - 1
                            ? () => _goToFrame(_currentFrameIndex + 1)
                            : null,
                    tooltip: 'Next Slice',
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 20),
                    onPressed:
                        _currentFrameIndex < _loadedSeries!.frameCount - 1
                            ? () => _goToFrame(_loadedSeries!.frameCount - 1)
                            : null,
                    tooltip: 'Last Slice',
                  ),
                ],
              ),
            ],

            const Divider(height: 32, color: Color(0xFF30363D)),

            // Viewport Grid Layout Selector
            _buildSectionHeader('VIEWPORT LAYOUT'),
            Wrap(
              spacing: 8,
              children: ViewportLayout.values.map((layout) {
                final isSelected = _layout == layout;
                return ChoiceChip(
                  label:
                      Text(layout.label, style: const TextStyle(fontSize: 11)),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) _setLayout(layout);
                  },
                  selectedColor: const Color(0xFF1F6FEB),
                  backgroundColor: const Color(0xFF21262D),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFFC9D1D9),
                  ),
                );
              }).toList(),
            ),

            const Divider(height: 32, color: Color(0xFF30363D)),

            // Clinical Window Presets
            _buildSectionHeader('PRIMARY CLINICAL PRESETS'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: WindowPresets.all.map((preset) {
                final isSelected = _primaryController.activePreset == preset;
                return ChoiceChip(
                  label:
                      Text(preset.name, style: const TextStyle(fontSize: 11)),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) _primaryController.applyPreset(preset);
                  },
                  selectedColor: const Color(0xFF1F6FEB),
                  backgroundColor: const Color(0xFF21262D),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFFC9D1D9),
                  ),
                );
              }).toList(),
            ),

            const Divider(height: 32, color: Color(0xFF30363D)),

            // Dynamic Window Level Controls
            _buildSectionHeader('PRIMARY WINDOW & LEVEL (HU)'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Center (C):',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text('${_primaryController.windowCenter.toStringAsFixed(1)} HU',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: _primaryController.windowCenter.clamp(-1000.0, 3000.0),
              min: -1000.0,
              max: 3000.0,
              onChanged: (val) {
                _primaryController.setWindowLevel(
                    val, _primaryController.windowWidth);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Width (W):',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text('${_primaryController.windowWidth.toStringAsFixed(1)} HU',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: _primaryController.windowWidth.clamp(1.0, 4000.0),
              min: 1.0,
              max: 4000.0,
              onChanged: (val) {
                _primaryController.setWindowLevel(
                    _primaryController.windowCenter, val);
              },
            ),

            const Divider(height: 32, color: Color(0xFF30363D)),

            // Zoom & Transform Inspector
            _buildSectionHeader('PRIMARY VIEWPORT TRANSFORM'),
            _buildInfoRow('Zoom Scale',
                '${(_primaryController.zoom * 100).toStringAsFixed(0)}%'),
            _buildInfoRow('Pan Offset',
                '(${_primaryController.panOffset.dx.toStringAsFixed(1)}, ${_primaryController.panOffset.dy.toStringAsFixed(1)})'),

            const Divider(height: 32, color: Color(0xFF30363D)),

            // Annotations & GSPS Section
            _buildSectionHeader('ANNOTATIONS & GSPS STATE'),
            _buildAnnotationsSidebarSection(),

            const Divider(height: 32, color: Color(0xFF30363D)),

            // DICOM Frame Metadata
            _buildSectionHeader('PRIMARY FRAME METADATA'),
            if (frame != null) ...[
              _buildInfoRow('Dimensions', '${frame.width} × ${frame.height}'),
              _buildInfoRow('Photometric', frame.photometricInterpretation),
              _buildInfoRow('Bits Allocated', '${frame.bitsAllocated}'),
              _buildInfoRow('Bits Stored', '${frame.bitsStored}'),
              _buildInfoRow('Pixel Representation',
                  frame.isSigned ? 'Signed (Int16)' : 'Unsigned (Uint16)'),
              _buildInfoRow('Rescale Slope', '${frame.rescaleSlope}'),
              _buildInfoRow('Rescale Intercept', '${frame.rescaleIntercept}'),
            ] else
              const Text('No active frame loaded',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        );
      },
    );
  }

  Widget _buildAnnotationsSidebarSection() {
    final annotations = _primaryAnnotationController.visibleAnnotations;
    final selected = _primaryAnnotationController.selectedAnnotation;

    if (annotations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF21262D),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: const Column(
          children: [
            Text(
              'No annotations on current slice.',
              style: TextStyle(fontSize: 12, color: Color(0xFF8B949E)),
            ),
            SizedBox(height: 4),
            Text(
              'Use Caliper, Angle, Circle, Ellipse, or Text on the toolbar to draw.',
              style: TextStyle(fontSize: 10, color: Color(0xFF484F58)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        children: [
          for (final ann in annotations) ...[
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              selected: selected?.id == ann.id,
              selectedTileColor: const Color(0xFF1F6FEB).withValues(alpha: 0.2),
              leading: Icon(
                _getAnnotationIcon(ann),
                size: 16,
                color: const Color(0xFFFFEB3B),
              ),
              title: Text(
                _getAnnotationTitle(ann),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              subtitle: Text(
                'By ${ann.creatorName ?? "Anonymous"} • ${ann.type.name.toUpperCase()}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF8B949E)),
              ),
              trailing: IconButton(
                icon:
                    const Icon(Icons.close, size: 14, color: Color(0xFF8B949E)),
                tooltip: 'Delete',
                onPressed: () =>
                    _primaryAnnotationController.removeAnnotation(ann.id),
              ),
              onTap: () => _primaryAnnotationController.selectAnnotation(ann),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFF30363D)),
          ],
        ],
      ),
    );
  }

  IconData _getAnnotationIcon(DicomAnnotation ann) {
    switch (ann.type) {
      case AnnotationType.caliper:
        return Icons.straighten;
      case AnnotationType.angle:
        return Icons.square_foot_rounded;
      case AnnotationType.polyline:
        return Icons.timeline;
      case AnnotationType.circle:
        return Icons.circle_outlined;
      case AnnotationType.ellipse:
        return Icons.egg_outlined;
      case AnnotationType.text:
        return Icons.text_fields;
    }
  }

  String _getAnnotationTitle(DicomAnnotation ann) {
    if (ann is CaliperAnnotation) {
      final val =
          ann.formatDistance(pixelSpacing: _primaryController.pixelSpacing);
      return ann.label != null && ann.label!.isNotEmpty
          ? '${ann.label}: $val'
          : 'Distance: $val';
    } else if (ann is AngleAnnotation) {
      final val = ann.formatAngle();
      return ann.label != null && ann.label!.isNotEmpty
          ? '${ann.label}: $val'
          : 'Angle: $val';
    } else if (ann is CircleAnnotation) {
      final area = ann.formatArea(pixelSpacing: _primaryController.pixelSpacing);
      return ann.label != null && ann.label!.isNotEmpty
          ? '${ann.label}: $area'
          : 'Circle ($area)';
    } else if (ann is EllipseAnnotation) {
      final area = ann.formatArea(pixelSpacing: _primaryController.pixelSpacing);
      return ann.label != null && ann.label!.isNotEmpty
          ? '${ann.label}: $area'
          : 'Ellipse ($area)';
    } else if (ann is PolylineAnnotation) {
      if (ann.isClosedOrClosureDetected) {
        final area = ann.formatArea(pixelSpacing: _primaryController.pixelSpacing);
        return ann.label != null && ann.label!.isNotEmpty
            ? '${ann.label}: $area'
            : 'Polygon ($area)';
      }
      return ann.label ?? 'Polyline (${ann.points.length} pts)';
    } else if (ann is TextAnnotation) {
      return '"${ann.text}"';
    }
    return ann.label ?? ann.type.name;
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
          color: Color(0xFF8B949E),
        ),
      ),
    );
  }

  Widget _buildFixtureChip(
      String title, bool isSelected, VoidCallback onSelected) {
    return FilterChip(
      label: Text(title, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: const Color(0xFF238636),
      backgroundColor: const Color(0xFF21262D),
      labelStyle:
          TextStyle(color: isSelected ? Colors.white : const Color(0xFFC9D1D9)),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E))),
          Text(value,
              style: const TextStyle(
                  fontSize: 11, fontFamily: 'monospace', color: Colors.white)),
        ],
      ),
    );
  }
}
