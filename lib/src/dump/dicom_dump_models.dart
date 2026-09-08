import '../dictionary/dicom_tag_info.dart';

/// Represents a single tag entry in a human-readable and structured DICOM dump.
class DicomDumpEntry {
  /// 8-character normalized hex tag string, e.g. "00100010".
  final String tagHex;

  /// Standard formatted tag string, e.g. "(0010,0010)".
  final String tagFormatted;

  /// Value Representation (VR), e.g. "PN", "LO", "SQ".
  final String vr;

  /// Raw value from the DICOM JSON object (typically a List or Map).
  final dynamic rawValue;

  /// Human-readable display value.
  final String displayValue;

  /// Full attribute dictionary description for this tag.
  final DicomTagInfo description;

  /// If this tag is a Sequence (SQ), contains each sequence item's child entries.
  final List<List<DicomDumpEntry>>? sequenceItems;

  /// Nesting depth for hierarchical tree view (0 = root).
  final int depth;

  const DicomDumpEntry({
    required this.tagHex,
    required this.tagFormatted,
    required this.vr,
    required this.rawValue,
    required this.displayValue,
    required this.description,
    this.sequenceItems,
    this.depth = 0,
  });

  /// Whether this entry is a DICOM Sequence (`VR == 'SQ'`) with child items.
  bool get isSequence =>
      vr == 'SQ' || (sequenceItems != null && sequenceItems!.isNotEmpty);

  /// Whether this tag is a Private Tag.
  bool get isPrivate => description.isPrivate;

  /// Serializes this entry to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'tag': tagFormatted,
      'id': tagHex,
      'vr': vr,
      'value': rawValue,
      'displayValue': displayValue,
      'description': description.toJson(),
      if (sequenceItems != null)
        'items': sequenceItems!
            .map((item) => item.map((e) => e.toJson()).toList())
            .toList(),
    };
  }

  @override
  String toString() => '$tagFormatted $vr [${description.name}]: $displayValue';
}

/// Structured result of a DICOM metadata dump operation.
class DicomDumpResult {
  /// Top-level list of parsed dump entries.
  final List<DicomDumpEntry> entries;

  const DicomDumpResult({required this.entries});

  /// Returns total count of top-level tags in the dump.
  int get count => entries.length;

  /// Filters entries by search query matching tag hex, standard tag, name, keyword, or value.
  List<DicomDumpEntry> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return entries;

    final results = <DicomDumpEntry>[];
    _searchRecursive(entries, q, results);
    return results;
  }

  void _searchRecursive(
    List<DicomDumpEntry> list,
    String query,
    List<DicomDumpEntry> matched,
  ) {
    for (final entry in list) {
      final matchesThis = entry.tagHex.toLowerCase().contains(query) ||
          entry.tagFormatted.toLowerCase().contains(query) ||
          entry.description.name.toLowerCase().contains(query) ||
          entry.description.keyword.toLowerCase().contains(query) ||
          entry.displayValue.toLowerCase().contains(query);

      if (matchesThis) {
        matched.add(entry);
      } else if (entry.sequenceItems != null) {
        for (final item in entry.sequenceItems!) {
          _searchRecursive(item, query, matched);
        }
      }
    }
  }

  /// Converts the dump result back into a standard list of JSON maps.
  List<Map<String, dynamic>> toJsonList() {
    return entries.map((e) => e.toJson()).toList();
  }
}
