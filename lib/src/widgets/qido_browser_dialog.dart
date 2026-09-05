import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../client/dicom_web_client.dart';
import '../client/qido_models.dart';
import '../client/series_buffer.dart';
import '../codecs/codec_router.dart';
import '../imaging/pixel_frame.dart';
import '../persistence/server_url_store.dart';

/// Interactive QIDO-RS Study & Series Browser dialog with WADO series buffering and compression selection.
class QidoBrowserDialog extends StatefulWidget {
  final String? initialServerUrl;
  final http.Client? httpClient;
  final DicomCompressionMode defaultCompressionMode;
  final void Function(DicomSeriesBuffer seriesBuffer, PixelFrame initialFrame)? onSeriesLoaded;
  final void Function(DicomStudy study)? onStudySelected;

  const QidoBrowserDialog({
    super.key,
    this.initialServerUrl,
    this.httpClient,
    this.defaultCompressionMode = DicomCompressionMode.raw,
    this.onSeriesLoaded,
    this.onStudySelected,
  });

  /// Session-persisted compression mode across dialog invocations.
  static DicomCompressionMode? _lastSelectedCompressionMode;

  /// Active session compression mode.
  static DicomCompressionMode? get activeCompressionMode => _lastSelectedCompressionMode;
  static set activeCompressionMode(DicomCompressionMode? mode) => _lastSelectedCompressionMode = mode;

  /// Static helper to launch the browser dialog.
  static Future<DicomSeriesBuffer?> show(
    BuildContext context, {
    String? initialServerUrl,
    http.Client? httpClient,
    DicomCompressionMode defaultCompressionMode = DicomCompressionMode.raw,
    void Function(DicomSeriesBuffer seriesBuffer, PixelFrame initialFrame)? onSeriesLoaded,
    void Function(DicomStudy study)? onStudySelected,
  }) {
    return showDialog<DicomSeriesBuffer>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => QidoBrowserDialog(
        initialServerUrl: initialServerUrl,
        httpClient: httpClient,
        defaultCompressionMode: defaultCompressionMode,
        onSeriesLoaded: onSeriesLoaded,
        onStudySelected: onStudySelected,
      ),
    );
  }

  @override
  State<QidoBrowserDialog> createState() => _QidoBrowserDialogState();
}

class _QidoBrowserDialogState extends State<QidoBrowserDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _filterController;
  late DicomCompressionMode _selectedCompressionMode;
  late List<String> _serverHistory;
  DicomWebClient? _client;

  bool _isLoadingStudies = false;
  bool _isLoadingSeries = false;
  bool _isDownloading = false;
  final ValueNotifier<({int loaded, int total})> _downloadProgressNotifier =
      ValueNotifier((loaded: 0, total: 0));
  String? _errorMessage;

  List<DicomStudy> _allStudies = [];
  List<DicomStudy> _filteredStudies = [];
  DicomStudy? _selectedStudy;
  List<DicomSeries> _seriesList = [];
  DicomSeries? _selectedSeries;

  @override
  void initState() {
    super.initState();
    _selectedCompressionMode = QidoBrowserDialog._lastSelectedCompressionMode ?? widget.defaultCompressionMode;
    final initialUrl = widget.initialServerUrl ?? DicomServerUrlStore.getLastUsedUrl();
    _urlController = TextEditingController(text: initialUrl);
    _serverHistory = DicomServerUrlStore.getHistory();
    _filterController = TextEditingController();
    _filterController.addListener(_applyFilter);
    _fetchStudies();
  }

  @override
  void dispose() {
    _filterController.removeListener(_applyFilter);
    _urlController.dispose();
    _filterController.dispose();
    _downloadProgressNotifier.dispose();
    _client?.dispose();
    super.dispose();
  }

  void _onSelectServerUrl(String url) {
    _urlController.text = url;
    DicomServerUrlStore.recordUrl(url);
    setState(() {
      _serverHistory = DicomServerUrlStore.getHistory();
    });
    _fetchStudies();
  }

  void _initClient() {
    _client?.dispose();
    _client = DicomWebClient(
      baseUrl: _urlController.text.trim(),
      httpClient: widget.httpClient,
    );
  }

  Future<void> _fetchStudies() async {
    final currentUrl = _urlController.text.trim();
    if (currentUrl.isNotEmpty) {
      DicomServerUrlStore.recordUrl(currentUrl);
      _serverHistory = DicomServerUrlStore.getHistory();
    }

    setState(() {
      _isLoadingStudies = true;
      _errorMessage = null;
      _selectedStudy = null;
      _seriesList = [];
      _selectedSeries = null;
    });

    try {
      _initClient();
      final studies = await _client!.queryStudies();
      if (!mounted) return;
      setState(() {
        _allStudies = studies;
        _isLoadingStudies = false;
      });
      _applyFilter();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingStudies = false;
        _errorMessage = 'Failed to load studies: $e';
        _allStudies = [];
        _filteredStudies = [];
      });
    }
  }

  void _applyFilter() {
    final query = _filterController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredStudies = _allStudies);
      return;
    }

    setState(() {
      _filteredStudies = _allStudies.where((s) {
        return s.patientName.toLowerCase().contains(query) ||
            s.rawPatientName.toLowerCase().contains(query) ||
            s.patientId.toLowerCase().contains(query) ||
            s.accessionNumber.toLowerCase().contains(query) ||
            s.modality.toLowerCase().contains(query) ||
            s.studyDescription.toLowerCase().contains(query);
      }).toList();
    });
  }

  Future<void> _selectStudy(DicomStudy study) async {
    widget.onStudySelected?.call(study);
    setState(() {
      _selectedStudy = study;
      _isLoadingSeries = true;
      _seriesList = [];
      _selectedSeries = null;
      _errorMessage = null;
    });

    try {
      final series = await _client!.querySeries(studyInstanceUID: study.studyInstanceUID);
      if (!mounted) return;
      setState(() {
        _seriesList = series;
        _isLoadingSeries = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingSeries = false;
        _errorMessage = 'Failed to load series: $e';
      });
    }
  }

  Future<void> _loadSeriesIntoBuffer(DicomSeries series) async {
    setState(() {
      _selectedSeries = series;
      _isDownloading = true;
      _errorMessage = null;
    });
    _downloadProgressNotifier.value = (loaded: 0, total: series.numberOfInstances);

    try {
      final seriesBuffer = await _client!.downloadSeriesBuffers(
        study: _selectedStudy,
        series: series,
        compressionMode: _selectedCompressionMode,
        onProgress: (loaded, total) {
          _downloadProgressNotifier.value = (loaded: loaded, total: total);
        },
      );

      // Decode initial frame for viewport
      PixelFrame? initialFrame;
      if (seriesBuffer.frameCount > 0) {
        initialFrame = await seriesBuffer.getPixelFrame(0);
      }

      if (mounted) {
        Navigator.of(context).pop(seriesBuffer);
      }

      if (widget.onSeriesLoaded != null && initialFrame != null) {
        widget.onSeriesLoaded!(seriesBuffer, initialFrame);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _errorMessage = 'Download error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = (size.width * 0.88).clamp(850.0, 1250.0);
    final dialogHeight = (size.height * 0.85).clamp(550.0, 850.0);

    return Dialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF30363D))),
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            _buildDialogHeader(),
            _buildServerBar(),
            if (_errorMessage != null) _buildErrorBanner(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Studies Grid (Left/Main)
                  Expanded(
                    flex: 6,
                    child: _buildStudiesGrid(),
                  ),

                  // Divider
                  const VerticalDivider(width: 1, color: Color(0xFF30363D)),

                  // Series Level Drilldown (Right)
                  Expanded(
                    flex: 4,
                    child: _buildSeriesPanel(),
                  ),
                ],
              ),
            ),
            if (_isDownloading) _buildDownloadProgressFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1C2128),
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
        border: Border(bottom: BorderSide(color: Color(0xFF30363D))),
      ),
      child: Row(
        children: [
          const Icon(Icons.manage_search_rounded, color: Color(0xFF58A6FF), size: 22),
          const SizedBox(width: 10),
          const Text(
            'DICOMweb QIDO-RS Study Browser',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: Color(0xFF8B949E)),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildServerBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        border: Border(bottom: BorderSide(color: Color(0xFF21262D))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'DICOMweb Server Root',
                hintText: 'http://localhost:8000',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF161B22),
                prefixIcon: const Icon(Icons.dns_outlined, size: 18, color: Color(0xFF58A6FF)),
                suffixIcon: PopupMenuButton<String>(
                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF58A6FF)),
                  tooltip: 'Recent DICOMweb Roots',
                  color: const Color(0xFF1C2128),
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(color: Color(0xFF30363D)),
                  ),
                  onSelected: _onSelectServerUrl,
                  itemBuilder: (context) {
                    return _serverHistory.map((url) {
                      final isCurrent = url.toLowerCase() == _urlController.text.trim().toLowerCase();
                      return PopupMenuItem<String>(
                        value: url,
                        height: 36,
                        child: Row(
                          children: [
                            Icon(
                              isCurrent ? Icons.check : Icons.history,
                              size: 16,
                              color: isCurrent ? const Color(0xFF58A6FF) : const Color(0xFF8B949E),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                url,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isCurrent ? const Color(0xFF58A6FF) : Colors.white,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList();
                  },
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onSubmitted: (_) => _fetchStudies(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _filterController,
              decoration: InputDecoration(
                labelText: 'Filter Studies (Name, ID...)',
                hintText: 'Search...',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF161B22),
                prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8B949E)),
                suffixIcon: _filterController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => _filterController.clear(),
                      )
                    : null,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Compression Mode Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tune, size: 14, color: Color(0xFF58A6FF)),
                const SizedBox(width: 6),
                DropdownButtonHideUnderline(
                  child: DropdownButton<DicomCompressionMode>(
                    value: _selectedCompressionMode,
                    dropdownColor: const Color(0xFF1C2128),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF58A6FF), size: 18),
                    items: DicomCompressionMode.values.map((mode) {
                      return DropdownMenuItem(
                        value: mode,
                        child: Text(mode.label, style: const TextStyle(fontSize: 11)),
                      );
                    }).toList(),
                    onChanged: (mode) {
                      if (mode != null) {
                        setState(() => _selectedCompressionMode = mode);
                        QidoBrowserDialog._lastSelectedCompressionMode = mode;
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _isLoadingStudies ? null : _fetchStudies,
            icon: _isLoadingStudies
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh, size: 16),
            label: const Text('Query QIDO'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF238636),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF4C1D1D),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF7B72), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFFFF7B72), fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudiesGrid() {
    if (_isLoadingStudies) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5),
            SizedBox(height: 12),
            Text('Querying DICOMweb studies...', style: TextStyle(color: Color(0xFF8B949E))),
          ],
        ),
      );
    }

    if (_filteredStudies.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_off_outlined, size: 48, color: Color(0xFF484F58)),
            const SizedBox(height: 12),
            Text(
              _allStudies.isEmpty ? 'No studies found on server' : 'No matching studies found',
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _fetchStudies,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry Fetch'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Grid Header
        Container(
          color: const Color(0xFF21262D),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _buildHeaderCell('Patient Name', flex: 3),
              _buildHeaderCell('Patient ID', flex: 2),
              _buildHeaderCell('Date of Birth', flex: 2),
              _buildHeaderCell('Accession Number', flex: 2),
              _buildHeaderCell('Study Date and Time (ISO)', flex: 3),
              _buildHeaderCell('Modality', flex: 1),
            ],
          ),
        ),

        // Grid Rows
        Expanded(
          child: ListView.separated(
            itemCount: _filteredStudies.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF21262D)),
            itemBuilder: (context, index) {
              final study = _filteredStudies[index];
              final isSelected = _selectedStudy?.studyInstanceUID == study.studyInstanceUID;

              return Material(
                color: isSelected ? const Color(0xFF1F6FEB).withValues(alpha: 0.2) : Colors.transparent,
                child: InkWell(
                  onTap: _isDownloading ? null : () => _selectStudy(study),
                  hoverColor: const Color(0xFF30363D).withValues(alpha: 0.4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: isSelected
                          ? const Border(left: BorderSide(color: Color(0xFF58A6FF), width: 3))
                          : null,
                    ),
                    child: Row(
                      children: [
                        _buildDataCell(study.patientName, flex: 3, isBold: true),
                        _buildDataCell(study.patientId, flex: 2, isMonospace: true),
                        _buildDataCell(study.patientBirthDate, flex: 2),
                        _buildDataCell(study.accessionNumber, flex: 2, isMonospace: true),
                        _buildDataCell(study.studyDateTimeIso, flex: 3, isMonospace: true),
                        _buildModalityCell(study.modality, flex: 1),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Footer status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF0D1117),
          child: Text(
            'Showing ${_filteredStudies.length} of ${_allStudies.length} studies • Click a row to view series',
            style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
          ),
        ),
      ],
    );
  }

  Widget _buildSeriesPanel() {
    if (_selectedStudy == null) {
      return Container(
        color: const Color(0xFF0D1117),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined, size: 36, color: Color(0xFF484F58)),
              SizedBox(height: 10),
              Text(
                'Select a Study from the list\nto view its Series and Instances',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF0D1117),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Study Summary Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFF161B22),
              border: Border(bottom: BorderSide(color: Color(0xFF30363D))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder_special, size: 16, color: Color(0xFF58A6FF)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _selectedStudy!.studyDescription,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Patient: ${_selectedStudy!.patientName} (${_selectedStudy!.patientId})',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFC9D1D9)),
                ),
                Text(
                  'Date: ${_selectedStudy!.studyDateTimeIso} • Modality: ${_selectedStudy!.modality}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text('Negotiated Mode: ', style: TextStyle(fontSize: 11, color: Color(0xFF8B949E))),
                    Text(
                      _selectedCompressionMode.label,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF58A6FF)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Series List Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF1C2128),
            child: const Row(
              children: [
                Text(
                  'SERIES LEVEL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: Color(0xFF8B949E),
                  ),
                ),
              ],
            ),
          ),

          // Series List Content
          Expanded(
            child: _isLoadingSeries
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _seriesList.isEmpty
                    ? const Center(
                        child: Text('No series available', style: TextStyle(color: Color(0xFF8B949E))),
                      )
                    : ListView.separated(
                        itemCount: _seriesList.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF21262D)),
                        itemBuilder: (context, index) {
                          final series = _seriesList[index];
                          final isDownloadingThis = _isDownloading &&
                              _selectedSeries?.seriesInstanceUID == series.seriesInstanceUID;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF238636),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        series.modality,
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Series ${series.seriesNumber}: ${series.seriesDescription}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${series.numberOfInstances} instance(s) • Dr. ${series.performingPhysician}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _isDownloading ? null : () => _loadSeriesIntoBuffer(series),
                                    icon: isDownloadingThis
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.download_for_offline_outlined, size: 16),
                                    label: Text(
                                      isDownloadingThis
                                          ? 'Buffering...'
                                          : 'Download & View Series',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1F6FEB),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadProgressFooter() {
    return ValueListenableBuilder<({int loaded, int total})>(
      valueListenable: _downloadProgressNotifier,
      builder: (context, progressData, _) {
        final loaded = progressData.loaded;
        final total = progressData.total;
        final progress = total > 0 ? (loaded / total) : 0.0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF161B22),
            border: Border(top: BorderSide(color: Color(0xFF30363D))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Buffering [${_selectedCompressionMode.label}] into 16-bit memory: $loaded / $total frames',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF58A6FF)),
                  ),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                backgroundColor: const Color(0xFF21262D),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF388BFD)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderCell(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: Color(0xFF8B949E),
        ),
      ),
    );
  }

  Widget _buildDataCell(String value, {required int flex, bool isBold = false, bool isMonospace = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          fontFamily: isMonospace ? 'monospace' : null,
          color: isBold ? Colors.white : const Color(0xFFC9D1D9),
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildModalityCell(String modality, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF21262D),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: Text(
          modality,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF58A6FF)),
        ),
      ),
    );
  }
}
