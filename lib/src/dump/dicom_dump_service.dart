import '../dictionary/dicom_dictionary.g.dart';
import 'dicom_dump_models.dart';

/// Service providing DICOM metadata inspection, dictionary enrichment,
/// and formatted dump tree generation.
class DicomDumpService {
  /// Enriches raw DICOM JSON metadata by adding a `"description"` attribute definition
  /// to every tag element, matching the standard DICOM attributes schema.
  ///
  /// Nested sequences (`VR == 'SQ'`) are enriched recursively across all items.
  static Map<String, dynamic> dumpJson(Map<String, dynamic> dicomJson) {
    final enriched = <String, dynamic>{};
    final sortedKeys = dicomJson.keys.toList()..sort();

    for (final tagKey in sortedKeys) {
      final val = dicomJson[tagKey];
      if (val is Map<String, dynamic>) {
        final elementCopy = Map<String, dynamic>.from(val);
        final vr = elementCopy['vr'] as String?;
        final tagInfo = DicomDictionary.lookup(tagKey, vr: vr);

        // If sequence, enrich child items recursively
        if (vr == 'SQ' &&
            elementCopy.containsKey('Value') &&
            elementCopy['Value'] is List) {
          final items = elementCopy['Value'] as List;
          if (items.isNotEmpty && items.first is Map) {
            final enrichedItems = <Map<String, dynamic>>[];
            for (final item in items) {
              if (item is Map<String, dynamic>) {
                enrichedItems.add(dumpJson(item));
              } else {
                enrichedItems.add(item as Map<String, dynamic>);
              }
            }
            elementCopy['Value'] = enrichedItems;
          }
        }

        elementCopy['description'] = tagInfo.toJson();
        enriched[tagKey] = elementCopy;
      } else {
        enriched[tagKey] = val;
      }
    }

    return enriched;
  }

  /// Parses raw DICOM JSON into a structured [DicomDumpResult] containing human-readable
  /// formatted display strings, nested sequence hierarchies, and tag descriptions.
  static DicomDumpResult dump(Map<String, dynamic> dicomJson, {int depth = 0}) {
    final entries = <DicomDumpEntry>[];
    final sortedKeys = dicomJson.keys.toList()..sort();

    for (final tagKey in sortedKeys) {
      final val = dicomJson[tagKey];
      if (val is Map<String, dynamic>) {
        final vr = (val['vr'] as String? ?? 'UN').toUpperCase();
        final tagInfo = DicomDictionary.lookup(tagKey, vr: vr);
        final tagFormatted = DicomDictionary.formatTag(tagKey);
        final tagHex = DicomDictionary.normalizeTagId(tagKey);

        List<List<DicomDumpEntry>>? seqItems;
        final rawValue =
            val['Value'] ?? val['InlineBinary'] ?? val['BulkDataURI'];

        if (vr == 'SQ' && val.containsKey('Value') && val['Value'] is List) {
          final list = val['Value'] as List;
          if (list.isNotEmpty && list.first is Map) {
            seqItems = [];
            for (final item in list) {
              if (item is Map<String, dynamic>) {
                final childDump = dump(item, depth: depth + 1);
                seqItems.add(childDump.entries);
              }
            }
          }
        }

        final displayVal =
            formatDisplayValue(val, vr: vr, sequenceItems: seqItems);

        entries.add(
          DicomDumpEntry(
            tagHex: tagHex,
            tagFormatted: tagFormatted,
            vr: vr,
            rawValue: rawValue,
            displayValue: displayVal,
            description: tagInfo,
            sequenceItems: seqItems,
            depth: depth,
          ),
        );
      }
    }

    return DicomDumpResult(entries: entries);
  }

  /// Formats raw DICOM JSON value elements into human-readable strings.
  static String formatDisplayValue(
    Map<String, dynamic> element, {
    required String vr,
    List<List<DicomDumpEntry>>? sequenceItems,
  }) {
    if (sequenceItems != null && sequenceItems.isNotEmpty) {
      return '${sequenceItems.length} Sequence Item(s)';
    }

    if (element.containsKey('InlineBinary')) {
      final binary = element['InlineBinary'] as String? ?? '';
      return '[Inline Binary: ${binary.length} base64 chars]';
    }

    if (element.containsKey('BulkDataURI')) {
      return '[Bulk Data URI: ${element['BulkDataURI']}]';
    }

    final val = element['Value'];
    if (val == null) {
      return '(no value)';
    }

    if (val is List) {
      if (val.isEmpty) return '(empty)';

      // Handle Person Name (PN)
      if (vr == 'PN') {
        final names = val
            .map((v) {
              if (v is Map) {
                return v['Alphabetic']?.toString() ??
                    v.values.firstOrNull?.toString() ??
                    '';
              }
              return v.toString();
            })
            .where((s) => s.isNotEmpty)
            .toList();
        return names.join(' \\ ');
      }

      // Handle Dates (DA)
      if (vr == 'DA') {
        final dates = val.map((v) => _formatDicomDate(v.toString())).toList();
        return dates.join(' \\ ');
      }

      // Handle Times (TM)
      if (vr == 'TM') {
        final times = val.map((v) => _formatDicomTime(v.toString())).toList();
        return times.join(' \\ ');
      }

      return val.map((e) => e.toString()).join(' \\ ');
    }

    return val.toString();
  }

  static String _formatDicomDate(String str) {
    final clean = str.trim();
    if (clean.length == 8 && int.tryParse(clean) != null) {
      final y = clean.substring(0, 4);
      final m = clean.substring(4, 6);
      final d = clean.substring(6, 8);
      return '$y-$m-$d';
    }
    return clean;
  }

  static String _formatDicomTime(String str) {
    final clean = str.trim();
    if (clean.length >= 6 && int.tryParse(clean.substring(0, 6)) != null) {
      final h = clean.substring(0, 2);
      final m = clean.substring(2, 4);
      final s = clean.substring(4, 6);
      final ms = clean.length > 7 ? clean.substring(6) : '';
      return '$h:$m:$s$ms';
    }
    return clean;
  }
}
