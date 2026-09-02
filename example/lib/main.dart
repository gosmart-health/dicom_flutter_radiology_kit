import 'package:flutter/material.dart';
import 'package:dicom_web_kit/dicom_web_kit.dart';
import 'fixtures/synthetic_patterns.dart';

void main() {
  runApp(const DicomViewerApp());
}

class DicomViewerApp extends StatelessWidget {
  const DicomViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DICOM Web Kit Test Viewer',
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

class DicomViewerWorkbench extends StatefulWidget {
  const DicomViewerWorkbench({super.key});

  @override
  State<DicomViewerWorkbench> createState() => _DicomViewerWorkbenchState();
}

class _DicomViewerWorkbenchState extends State<DicomViewerWorkbench> {
  late final ViewportController _controller;
  bool _showOverlay = true;
  String _selectedFixture = 'CT Phantom';
  bool _sidebarExpanded = true;

  DicomSeriesBuffer? _loadedSeries;
  int _currentFrameIndex = 0;
  bool _isLoadingFrame = false;

  @override
  void initState() {
    super.initState();
    _controller = ViewportController();
    _loadCtPhantom();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _loadCtPhantom() {
    _loadedSeries = null;
    final frame = SyntheticPatterns.generateCtPhantom();
    _controller.setFrame(frame);
    _controller.applyPreset(WindowPresets.softTissue);
    _controller.updateMetadata(
      patientName: 'DOE^JOHN',
      patientId: 'SYN-CT-90210',
      studyDescription: 'CT THORAX W/ CONTRAST',
      seriesDescription: 'AXIAL 5.0mm SOFT TISSUE',
    );
    setState(() => _selectedFixture = 'CT Phantom');
  }

  void _loadTg18Qc() {
    _loadedSeries = null;
    final frame = SyntheticPatterns.generateTg18QcPattern();
    _controller.setFrame(frame);
    _controller.setWindowLevel(2048, 4096);
    _controller.updateMetadata(
      patientName: 'QUALITY^CONTROL',
      patientId: 'QC-TG18-001',
      studyDescription: 'TG18-QC DISPLAY CALIBRATION',
      seriesDescription: 'SMPTE DYNAMIC RANGE TEST',
    );
    setState(() => _selectedFixture = 'TG18-QC Test Pattern');
  }

  void _loadDynamicRamp() {
    _loadedSeries = null;
    final frame = SyntheticPatterns.generateDynamicRamp();
    _controller.setFrame(frame);
    _controller.setWindowLevel(250, 2500);
    _controller.updateMetadata(
      patientName: 'CALIBRATION^RAMP',
      patientId: 'RAMP-16BIT-002',
      studyDescription: 'CONTINUOUS 16-BIT HU GRADIENT',
      seriesDescription: '-1000 HU TO +2500 HU RAMP',
    );
    setState(() => _selectedFixture = 'Dynamic Ramp');
  }

  Future<void> _openQidoBrowser() async {
    await QidoBrowserDialog.show(
      context,
      initialServerUrl: 'http://localhost:8000',
      onSeriesLoaded: (seriesBuffer, initialFrame) {
        setState(() {
          _loadedSeries = seriesBuffer;
          _currentFrameIndex = 0;
          _selectedFixture = 'QIDO: ${seriesBuffer.series.seriesDescription}';
        });

        final metaCenter = seriesBuffer.frames.isNotEmpty ? seriesBuffer.frames.first.metadata.windowCenter : null;
        final metaWidth = seriesBuffer.frames.isNotEmpty ? seriesBuffer.frames.first.metadata.windowWidth : null;
        if (metaCenter != null && metaWidth != null && metaWidth > 1.0) {
          _controller.setWindowLevel(metaCenter, metaWidth);
          _controller.setFrame(initialFrame, updateWindowLevelFromFrame: false);
        } else {
          _controller.setFrame(initialFrame, updateWindowLevelFromFrame: true);
        }
        _controller.updateMetadata(
          patientName: seriesBuffer.study?.patientName ?? 'Anonymous',
          patientId: seriesBuffer.study?.patientId ?? '-',
          studyDescription: seriesBuffer.study?.studyDescription ?? 'DICOM Study',
          seriesDescription: seriesBuffer.series.seriesDescription,
        );

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
  }

  Future<void> _goToFrame(int index) async {
    if (_loadedSeries == null || _isLoadingFrame) return;
    if (index < 0 || index >= _loadedSeries!.frameCount) return;

    setState(() {
      _isLoadingFrame = true;
      _currentFrameIndex = index;
    });

    try {
      final frame = await _loadedSeries!.getPixelFrame(index);
      if (frame != null && mounted) {
        _controller.setFrame(frame);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingFrame = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.medical_services_outlined, color: Color(0xFF388BFD), size: 20),
            SizedBox(width: 10),
            Text('DICOM Web Kit'),
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
          IconButton(
            icon: Icon(_showOverlay ? Icons.layers : Icons.layers_clear),
            tooltip: 'Toggle HUD Overlays',
            onPressed: () => setState(() => _showOverlay = !_showOverlay),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            tooltip: 'Zoom In',
            onPressed: () => _controller.setZoom(_controller.zoom + 0.25),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            tooltip: 'Zoom Out',
            onPressed: () => _controller.setZoom(_controller.zoom - 0.25),
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Reset View & Presets',
            onPressed: () => _controller.resetView(),
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
          // Main Viewport
          Expanded(
            child: DicomViewport(
              controller: _controller,
              showOverlay: _showOverlay,
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

  Widget _buildSidebar() {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final frame = _controller.currentFrame;
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

            if (_loadedSeries != null && _loadedSeries!.frameCount > 1) ...[
              const Divider(height: 32, color: Color(0xFF30363D)),
              _buildSectionHeader('SERIES SLICE NAVIGATION'),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Frame ${_currentFrameIndex + 1} / ${_loadedSeries!.frameCount}',
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

            // Clinical Window Presets
            _buildSectionHeader('CLINICAL PRESETS'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: WindowPresets.all.map((preset) {
                final isSelected = _controller.activePreset == preset;
                return ChoiceChip(
                  label: Text(preset.name, style: const TextStyle(fontSize: 11)),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) _controller.applyPreset(preset);
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
            _buildSectionHeader('WINDOW & LEVEL (HU)'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Center (C):', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text('${_controller.windowCenter.toStringAsFixed(1)} HU',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: _controller.windowCenter.clamp(-1000.0, 3000.0),
              min: -1000.0,
              max: 3000.0,
              onChanged: (val) {
                _controller.setWindowLevel(val, _controller.windowWidth);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Width (W):', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text('${_controller.windowWidth.toStringAsFixed(1)} HU',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: _controller.windowWidth.clamp(1.0, 4000.0),
              min: 1.0,
              max: 4000.0,
              onChanged: (val) {
                _controller.setWindowLevel(_controller.windowCenter, val);
              },
            ),

            const Divider(height: 32, color: Color(0xFF30363D)),

            // Zoom & Transform Inspector
            _buildSectionHeader('VIEWPORT TRANSFORM'),
            _buildInfoRow('Zoom Scale', '${(_controller.zoom * 100).toStringAsFixed(0)}%'),
            _buildInfoRow('Pan Offset', '(${_controller.panOffset.dx.toStringAsFixed(1)}, ${_controller.panOffset.dy.toStringAsFixed(1)})'),

            const Divider(height: 32, color: Color(0xFF30363D)),

            // DICOM Frame Metadata
            _buildSectionHeader('FRAME METADATA'),
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
