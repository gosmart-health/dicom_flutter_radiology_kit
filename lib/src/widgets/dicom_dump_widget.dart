import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../dump/dicom_dump_models.dart';
import '../dump/dicom_dump_service.dart';
import '../utils/file_exporter.dart';

/// Reusable widget rendering a comprehensive, searchable flat grid DICOM dump
/// with Tag, VR, VM, Description, Value, and CSV/JSON export capabilities.
class DicomDumpWidget extends StatefulWidget {
  /// Initial static DICOM JSON metadata map.
  final Map<String, dynamic>? metadataJson;

  /// Optional stream of DICOM JSON metadata (updates dump reactively as slices change).
  final Stream<Map<String, dynamic>>? metadataStream;

  /// Header title displayed above the dump grid.
  final String title;

  /// Whether to display the JSON and CSV export buttons.
  final bool showExportButtons;

  /// Whether to display the search/filtering bar.
  final bool showSearchBar;

  const DicomDumpWidget({
    super.key,
    this.metadataJson,
    this.metadataStream,
    this.title = 'DICOM Metadata Dump',
    this.showExportButtons = true,
    this.showSearchBar = true,
  });

  @override
  State<DicomDumpWidget> createState() => _DicomDumpWidgetState();
}

class _DicomDumpWidgetState extends State<DicomDumpWidget> {
  Map<String, dynamic>? _currentMetadata;
  StreamSubscription<Map<String, dynamic>>? _streamSubscription;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _expandedSequences = {};

  @override
  void initState() {
    super.initState();
    _currentMetadata = widget.metadataJson;

    if (widget.metadataStream != null) {
      _streamSubscription = widget.metadataStream!.listen((data) {
        if (mounted) {
          setState(() {
            _currentMetadata = data;
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant DicomDumpWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.metadataJson != oldWidget.metadataJson &&
        widget.metadataJson != null) {
      _currentMetadata = widget.metadataJson;
    }
    if (widget.metadataStream != oldWidget.metadataStream) {
      _streamSubscription?.cancel();
      _streamSubscription = widget.metadataStream?.listen((data) {
        if (mounted) {
          setState(() {
            _currentMetadata = data;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metadata = _currentMetadata;

    if (metadata == null || metadata.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1218),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF8B949E), size: 36),
            const SizedBox(height: 12),
            Text(
              'No DICOM metadata available for this frame.',
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 14),
            ),
          ],
        ),
      );
    }

    final dumpResult = DicomDumpService.dump(metadata);
    final displayedEntries = _searchQuery.isEmpty
        ? dumpResult.entries
        : dumpResult.search(_searchQuery);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1218),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          _buildHeaderBar(context, metadata, dumpResult),

          // Search & Filter Toolbar
          if (widget.showSearchBar)
            _buildSearchToolbar(displayedEntries.length, dumpResult.count),

          const Divider(height: 1, thickness: 1, color: Color(0xFF30363D)),

          // Column Headers
          _buildGridHeaderRow(),

          const Divider(height: 1, thickness: 1, color: Color(0xFF30363D)),

          // Scrollable Grid Rows
          Expanded(
            child: displayedEntries.isEmpty
                ? const Center(
                    child: Text(
                      'No matching DICOM attributes found.',
                      style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    itemCount: displayedEntries.length,
                    itemBuilder: (context, index) {
                      final entry = displayedEntries[index];
                      return _buildEntryRow(entry, index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBar(
    BuildContext context,
    Map<String, dynamic> metadata,
    DicomDumpResult dumpResult,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        border: Border(bottom: BorderSide(color: Color(0xFF30363D))),
      ),
      child: Row(
        children: [
          const Icon(Icons.dataset_outlined,
              color: Color(0xFF388BFD), size: 20),
          const SizedBox(width: 10),
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Text(
              '${dumpResult.count} attributes',
              style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
            ),
          ),
          const Spacer(),

          // Export JSON Button
          if (widget.showExportButtons) ...[
            OutlinedButton.icon(
              onPressed: () => _exportJson(context, metadata),
              icon: const Icon(Icons.file_download_outlined, size: 14),
              label:
                  const Text('Download JSON', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF58A6FF),
                side: const BorderSide(color: Color(0xFF30363D)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
            const SizedBox(width: 8),

            // Export CSV Button
            OutlinedButton.icon(
              onPressed: () => _exportCsv(context, dumpResult),
              icon: const Icon(Icons.table_view_outlined, size: 14),
              label: const Text('Download CSV', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF7EE787),
                side: const BorderSide(color: Color(0xFF30363D)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Close Button if shown in modal
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Color(0xFF8B949E)),
            tooltip: 'Close Dump',
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchToolbar(int matchCount, int totalCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF161B22),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 12, color: Colors.white),
                decoration: InputDecoration(
                  hintText:
                      'Search attributes by tag "(0010,0020)", hex "00100020", name, or value...',
                  hintStyle:
                      const TextStyle(fontSize: 12, color: Color(0xFF6E7681)),
                  prefixIcon: const Icon(Icons.search,
                      size: 16, color: Color(0xFF8B949E)),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear,
                              size: 14, color: Color(0xFF8B949E)),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Showing $matchCount of $totalCount',
            style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
          ),
        ],
      ),
    );
  }

  Widget _buildGridHeaderRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF161B22),
      child: const Row(
        children: [
          SizedBox(
            width: 135,
            child: Text(
              'Tag',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B949E)),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              'VR',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B949E)),
            ),
          ),
          SizedBox(
            width: 45,
            child: Text(
              'VM',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B949E)),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Description',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B949E)),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              'Value',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B949E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryRow(DicomDumpEntry entry, int index) {
    final isEven = index % 2 == 0;
    final rowBg = isEven ? const Color(0xFF0F1218) : const Color(0xFF13171F);
    final hasChildren =
        entry.sequenceItems != null && entry.sequenceItems!.isNotEmpty;
    final isExpanded = _expandedSequences.contains(entry.tagHex);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: rowBg,
            border: const Border(bottom: BorderSide(color: Color(0xFF21262D))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tag (e.g. (0010,0020))
              SizedBox(
                width: 135,
                child: Row(
                  children: [
                    if (entry.depth > 0) SizedBox(width: entry.depth * 14.0),
                    if (hasChildren)
                      InkWell(
                        onTap: () {
                          setState(() {
                            if (isExpanded) {
                              _expandedSequences.remove(entry.tagHex);
                            } else {
                              _expandedSequences.add(entry.tagHex);
                            }
                          });
                        },
                        child: Icon(
                          isExpanded
                              ? Icons.arrow_drop_down
                              : Icons.arrow_right,
                          size: 16,
                          color: const Color(0xFF58A6FF),
                        ),
                      )
                    else if (entry.depth > 0)
                      const SizedBox(width: 16),
                    Expanded(
                      child: SelectableText(
                        entry.tagFormatted,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF58A6FF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // VR
              SizedBox(
                width: 50,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    entry.vr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFD29922),
                    ),
                  ),
                ),
              ),

              // VM
              SizedBox(
                width: 45,
                child: Text(
                  entry.description.valueMultiplicity,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF8B949E),
                  ),
                ),
              ),

              // Description
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.description.name,
                        style: TextStyle(
                          fontSize: 12,
                          color: entry.isPrivate
                              ? const Color(0xFFFFA657)
                              : Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (entry.isPrivate) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5C2B0E),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'PRIVATE',
                          style: TextStyle(
                              fontSize: 8,
                              color: Color(0xFFFFA657),
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Value
              Expanded(
                flex: 5,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectableText(
                        entry.displayValue,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: (entry.vr == 'UI' ||
                                  entry.vr == 'SH' ||
                                  entry.vr == 'LO')
                              ? 'monospace'
                              : null,
                          color: entry.isSequence
                              ? const Color(0xFF7EE787)
                              : const Color(0xFFC9D1D9),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy,
                          size: 12, color: Color(0xFF6E7681)),
                      tooltip: 'Copy Value',
                      splashRadius: 14,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 20, minHeight: 20),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: entry.displayValue));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Copied ${entry.tagFormatted} value to clipboard'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Nested Sequence Items
        if (hasChildren && isExpanded) ...[
          for (int itemIdx = 0;
              itemIdx < entry.sequenceItems!.length;
              itemIdx++) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              color: const Color(0xFF161B22),
              child: Row(
                children: [
                  const Icon(Icons.subdirectory_arrow_right,
                      size: 12, color: Color(0xFF58A6FF)),
                  const SizedBox(width: 6),
                  Text(
                    'Sequence Item #${itemIdx + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF58A6FF),
                    ),
                  ),
                ],
              ),
            ),
            for (int childIdx = 0;
                childIdx < entry.sequenceItems![itemIdx].length;
                childIdx++)
              _buildEntryRow(entry.sequenceItems![itemIdx][childIdx], childIdx),
          ],
        ],
      ],
    );
  }

  Future<void> _exportJson(
      BuildContext context, Map<String, dynamic> metadata) async {
    final enrichedJson = DicomDumpService.dumpJson(metadata);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(enrichedJson);
    final filename = 'dicom_dump_${DateTime.now().millisecondsSinceEpoch}.json';

    final status = await FileExporter.exportFile(
      content: jsonStr,
      filename: filename,
      mimeType: 'application/json',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status),
          backgroundColor: const Color(0xFF238636),
        ),
      );
    }
  }

  Future<void> _exportCsv(
      BuildContext context, DicomDumpResult dumpResult) async {
    final buffer = StringBuffer();
    buffer.writeln('Tag,VR,VM,Description,Value');

    void writeEntry(DicomDumpEntry entry) {
      final tag = _escapeCsv(entry.tagFormatted);
      final vr = _escapeCsv(entry.vr);
      final vm = _escapeCsv(entry.description.valueMultiplicity);
      final desc = _escapeCsv(entry.description.name);
      final val = _escapeCsv(entry.displayValue);
      buffer.writeln('$tag,$vr,$vm,$desc,$val');

      if (entry.sequenceItems != null) {
        for (final item in entry.sequenceItems!) {
          for (final child in item) {
            writeEntry(child);
          }
        }
      }
    }

    for (final entry in dumpResult.entries) {
      writeEntry(entry);
    }

    final csvStr = buffer.toString();
    final filename = 'dicom_dump_${DateTime.now().millisecondsSinceEpoch}.csv';

    final status = await FileExporter.exportFile(
      content: csvStr,
      filename: filename,
      mimeType: 'text/csv',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status),
          backgroundColor: const Color(0xFF238636),
        ),
      );
    }
  }

  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

/// Modal dialog helper displaying the [DicomDumpWidget] with click-outside-to-dismiss.
class DicomDumpDialog {
  /// Opens a modal dialog displaying the DICOM metadata dump.
  /// Click outside the modal dialog or the close button will dismiss it.
  static Future<void> show(
    BuildContext context, {
    Map<String, dynamic>? metadataJson,
    Stream<Map<String, dynamic>>? metadataStream,
    String title = 'DICOM Metadata Dump',
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true, // Click outside will dismiss
      barrierColor: const Color(0xA6000000),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F1218),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFF30363D)),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: SizedBox(
          width: 1100,
          height: 750,
          child: DicomDumpWidget(
            metadataJson: metadataJson,
            metadataStream: metadataStream,
            title: title,
          ),
        ),
      ),
    );
  }
}
