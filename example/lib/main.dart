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

  ViewportController get _primaryController => _controllers[0];

  @override
  void initState() {
    super.initState();
    _activeServerUrl = DicomServerUrlStore.getLastUsedUrl();

    _controllers = List.generate(9, (index) {
      final controller = ViewportController();
      controller.onSliceStep = (direction) {
        if (_loadedSeries != null && _loadedSeries!.frameCount > 1) {
          final nextIdx = (_currentFrameIndex + direction).clamp(0, _loadedSeries!.frameCount - 1);
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
    super.dispose();
  }

  void _loadCtPhantom() {
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
  }

  void _loadTg18Qc() {
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
  }

  void _loadDynamicRamp() {
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
  }

  Future<void> _openQidoBrowser() async {
    await QidoBrowserDialog.show(
      context,
      onStudySelected: (study) {
        _loadedSeries?.dispose();
        _loadedSeries = null;
        _framePresentationCache.clear();
        for (final c in _controllers) {
          c.clear();
        }
        setState(() {
          _currentFrameIndex = 0;
          _selectedFixture = 'Loading: ${study.patientName}';
        });
      },
      onSeriesLoaded: (seriesBuffer, initialFrame) {
        _loadedSeries?.dispose();
        _framePresentationCache.clear();
        setState(() {
          _loadedSeries = seriesBuffer;
          _currentFrameIndex = 0;
          _selectedFixture = 'QIDO: ${seriesBuffer.series.seriesDescription}';
        });

        _syncGridLayoutFrames();

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

  Future<void> _goToFrame(int index) async {
    if (_loadedSeries == null || _isLoadingFrame) return;
    if (index < 0 || index >= _loadedSeries!.frameCount) return;

    setState(() {
      _isLoadingFrame = true;
      _currentFrameIndex = index;
    });

    try {
      await _syncGridLayoutFrames();
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
              controller.setFrame(pixelFrame, updateWindowLevelFromFrame: false);
            } else {
              controller.resetZoomPan(notify: false);
              final is8Bit = pixelFrame.bitsAllocated <= 8 || pixelFrame.rawPixels is Uint8List;
              if (is8Bit) {
                controller.setWindowLevel(128.0, 256.0);
                controller.setFrame(pixelFrame, updateWindowLevelFromFrame: false);
              } else {
                final metaCenter = _loadedSeries!.frames.isNotEmpty
                    ? _loadedSeries!.frames[frameIdx < _loadedSeries!.frames.length ? frameIdx : 0].metadata.windowCenter
                    : null;
                final metaWidth = _loadedSeries!.frames.isNotEmpty
                    ? _loadedSeries!.frames[frameIdx < _loadedSeries!.frames.length ? frameIdx : 0].metadata.windowWidth
                    : null;
                if (metaCenter != null && metaWidth != null && metaWidth > 1.0) {
                  controller.setWindowLevel(metaCenter, metaWidth);
                  controller.setFrame(pixelFrame, updateWindowLevelFromFrame: false);
                } else {
                  controller.setFrame(pixelFrame, updateWindowLevelFromFrame: true);
                }
              }
            }

            controller.updateMetadata(
              patientName: _loadedSeries!.study?.patientName ?? 'Anonymous',
              patientId: _loadedSeries!.study?.patientId ?? '-',
              studyDescription: _loadedSeries!.study?.studyDescription ?? 'DICOM Study',
              seriesDescription: _loadedSeries!.series.seriesDescription,
              frameIndex: frameIdx + 1,
              totalFrames: totalCount,
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
    setState(() {
      _layout = layout;
    });
    _syncGridLayoutFrames();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.medical_services_outlined, color: Color(0xFF388BFD), size: 20),
            SizedBox(width: 10),
            Text('DICOM Flutter Radiology Kit'),
            SizedBox(width: 8),
            Chip(
              label: Text('16-bit VOI LUT', style: TextStyle(fontSize: 10, color: Colors.white)),
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
            label: const Text('QIDO Patient Browser', style: TextStyle(fontSize: 12)),
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
              _buildLayoutMenuItem(ViewportLayout.oneOnOne, Icons.crop_square_rounded),
              _buildLayoutMenuItem(ViewportLayout.twoOnOne, Icons.view_agenda_rounded),
              _buildLayoutMenuItem(ViewportLayout.fourOnOne, Icons.grid_view_rounded),
              _buildLayoutMenuItem(ViewportLayout.nineOnOne, Icons.apps_rounded),
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
            onPressed: () => _primaryController.setZoom(_primaryController.zoom + 0.25),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            tooltip: 'Zoom Out Primary',
            onPressed: () => _primaryController.setZoom(_primaryController.zoom - 0.25),
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
          IconButton(
            icon: Icon(_sidebarExpanded ? Icons.view_sidebar : Icons.view_sidebar_outlined),
            tooltip: 'Toggle Control Panel',
            onPressed: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          // Main Viewport Area: 1, 2, 4, or 9 on 1 Grid
          Expanded(
            child: _buildViewportGrid(),
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

  PopupMenuItem<ViewportLayout> _buildLayoutMenuItem(ViewportLayout layout, IconData icon) {
    final isSelected = _layout == layout;
    return PopupMenuItem<ViewportLayout>(
      value: layout,
      child: Row(
        children: [
          Icon(icon, size: 18, color: isSelected ? const Color(0xFF58A6FF) : const Color(0xFF8B949E)),
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

  Widget _buildViewportGrid() {
    switch (_layout) {
      case ViewportLayout.oneOnOne:
        return DicomViewport(
          controller: _controllers[0],
          showOverlay: _showOverlay,
        );

      case ViewportLayout.twoOnOne:
        return Row(
          children: [
            Expanded(
              child: DicomViewport(
                controller: _controllers[0],
                showOverlay: _showOverlay,
              ),
            ),
            const VerticalDivider(width: 2, thickness: 2, color: Color(0xFF30363D)),
            Expanded(
              child: DicomViewport(
                controller: _controllers[1],
                showOverlay: _showOverlay,
              ),
            ),
          ],
        );

      case ViewportLayout.fourOnOne:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: DicomViewport(
                      controller: _controllers[0],
                      showOverlay: _showOverlay,
                    ),
                  ),
                  const VerticalDivider(width: 2, thickness: 2, color: Color(0xFF30363D)),
                  Expanded(
                    child: DicomViewport(
                      controller: _controllers[1],
                      showOverlay: _showOverlay,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 2, thickness: 2, color: Color(0xFF30363D)),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: DicomViewport(
                      controller: _controllers[2],
                      showOverlay: _showOverlay,
                    ),
                  ),
                  const VerticalDivider(width: 2, thickness: 2, color: Color(0xFF30363D)),
                  Expanded(
                    child: DicomViewport(
                      controller: _controllers[3],
                      showOverlay: _showOverlay,
                    ),
                  ),
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
                  if (row > 0) const Divider(height: 2, thickness: 2, color: Color(0xFF30363D)),
                  Expanded(
                    child: Row(
                      children: List.generate(3, (col) {
                        final slot = row * 3 + col;
                        return Expanded(
                          child: Row(
                            children: [
                              if (col > 0)
                                const VerticalDivider(width: 2, thickness: 2, color: Color(0xFF30363D)),
                              Expanded(
                                child: DicomViewport(
                                  controller: _controllers[slot],
                                  showOverlay: _showOverlay,
                                ),
                              ),
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
      listenable: _primaryController,
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
                _buildFixtureChip('CT Phantom', _selectedFixture == 'CT Phantom', _loadCtPhantom),
                _buildFixtureChip('TG18-QC', _selectedFixture == 'TG18-QC Test Pattern', _loadTg18Qc),
                _buildFixtureChip('Dynamic Ramp', _selectedFixture == 'Dynamic Ramp', _loadDynamicRamp),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openQidoBrowser,
              icon: const Icon(Icons.cloud_sync_outlined, size: 16),
              label: const Text('QIDO Studies & Series Browser', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF58A6FF),
                side: const BorderSide(color: Color(0xFF388BFD)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.dns_outlined, size: 12, color: Color(0xFF58A6FF)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Root: $_activeServerUrl',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF8B949E), fontFamily: 'monospace'),
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
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF58A6FF)),
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
                divisions: _loadedSeries!.frameCount > 1 ? _loadedSeries!.frameCount - 1 : 1,
                onChanged: (val) => _goToFrame(val.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 20),
                    onPressed: _currentFrameIndex > 0 ? () => _goToFrame(0) : null,
                    tooltip: 'First Slice',
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    onPressed: _currentFrameIndex > 0 ? () => _goToFrame(_currentFrameIndex - 1) : null,
                    tooltip: 'Previous Slice',
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    onPressed: _currentFrameIndex < _loadedSeries!.frameCount - 1
                        ? () => _goToFrame(_currentFrameIndex + 1)
                        : null,
                    tooltip: 'Next Slice',
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 20),
                    onPressed: _currentFrameIndex < _loadedSeries!.frameCount - 1
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
                  label: Text(layout.label, style: const TextStyle(fontSize: 11)),
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
                  label: Text(preset.name, style: const TextStyle(fontSize: 11)),
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
                const Text('Center (C):', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text('${_primaryController.windowCenter.toStringAsFixed(1)} HU',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: _primaryController.windowCenter.clamp(-1000.0, 3000.0),
              min: -1000.0,
              max: 3000.0,
              onChanged: (val) {
                _primaryController.setWindowLevel(val, _primaryController.windowWidth);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Width (W):', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text('${_primaryController.windowWidth.toStringAsFixed(1)} HU',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: _primaryController.windowWidth.clamp(1.0, 4000.0),
              min: 1.0,
              max: 4000.0,
              onChanged: (val) {
                _primaryController.setWindowLevel(_primaryController.windowCenter, val);
              },
            ),

            const Divider(height: 32, color: Color(0xFF30363D)),

            // Zoom & Transform Inspector
            _buildSectionHeader('PRIMARY VIEWPORT TRANSFORM'),
            _buildInfoRow('Zoom Scale', '${(_primaryController.zoom * 100).toStringAsFixed(0)}%'),
            _buildInfoRow('Pan Offset',
                '(${_primaryController.panOffset.dx.toStringAsFixed(1)}, ${_primaryController.panOffset.dy.toStringAsFixed(1)})'),

            const Divider(height: 32, color: Color(0xFF30363D)),

            // DICOM Frame Metadata
            _buildSectionHeader('PRIMARY FRAME METADATA'),
            if (frame != null) ...[
              _buildInfoRow('Dimensions', '${frame.width} × ${frame.height}'),
              _buildInfoRow('Photometric', frame.photometricInterpretation),
              _buildInfoRow('Bits Allocated', '${frame.bitsAllocated}'),
              _buildInfoRow('Bits Stored', '${frame.bitsStored}'),
              _buildInfoRow('Pixel Representation', frame.isSigned ? 'Signed (Int16)' : 'Unsigned (Uint16)'),
              _buildInfoRow('Rescale Slope', '${frame.rescaleSlope}'),
              _buildInfoRow('Rescale Intercept', '${frame.rescaleIntercept}'),
            ] else
              const Text('No active frame loaded', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        );
      },
    );
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

  Widget _buildFixtureChip(String title, bool isSelected, VoidCallback onSelected) {
    return FilterChip(
      label: Text(title, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: const Color(0xFF238636),
      backgroundColor: const Color(0xFF21262D),
      labelStyle: TextStyle(color: isSelected ? Colors.white : const Color(0xFFC9D1D9)),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E))),
          Text(value, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white)),
        ],
      ),
    );
  }
}
