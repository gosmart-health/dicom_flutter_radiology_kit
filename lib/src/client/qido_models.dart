import '../imaging/pixel_spacing.dart';

/// Data models and DICOM JSON parsing utilities for DICOMweb QIDO-RS and WADO-RS.

/// Helper to parse DICOM JSON (Part 18 Standard Model) tag dictionaries.
class DicomJsonHelper {
  /// Extracts the first string value of a tag, or null if missing.
  static String? getString(Map<String, dynamic>? json, String tag) {
    if (json == null || !json.containsKey(tag)) return null;
    final item = json[tag];
    if (item is Map<String, dynamic>) {
      final value = item['Value'];
      if (value is List && value.isNotEmpty) {
        final first = value.first;
        if (first is String) return first;
        if (first is Map<String, dynamic> && first.containsKey('Alphabetic')) {
          return first['Alphabetic']?.toString();
        }
        return first?.toString();
      }
    }
    return null;
  }

  /// Extracts an integer value of a tag, or defaultValue if missing.
  static int? getInt(Map<String, dynamic>? json, String tag) {
    if (json == null || !json.containsKey(tag)) return null;
    final item = json[tag];
    if (item is Map<String, dynamic>) {
      final value = item['Value'];
      if (value is List && value.isNotEmpty) {
        final first = value.first;
        if (first is int) return first;
        if (first is num) return first.toInt();
        if (first is String) return int.tryParse(first.trim());
      }
    }
    return null;
  }

  /// Extracts a double/floating-point value of a tag.
  static double? getDouble(Map<String, dynamic>? json, String tag) {
    if (json == null || !json.containsKey(tag)) return null;
    final item = json[tag];
    if (item is Map<String, dynamic>) {
      final value = item['Value'];
      if (value is List && value.isNotEmpty) {
        final first = value.first;
        if (first is num) return first.toDouble();
        if (first is String) return double.tryParse(first.trim());
      }
    }
    return null;
  }

  /// Extracts a list of strings for multi-valued tags (e.g. Modalities in Study).
  static List<String> getStringList(Map<String, dynamic>? json, String tag) {
    if (json == null || !json.containsKey(tag)) return [];
    final item = json[tag];
    if (item is Map<String, dynamic>) {
      final value = item['Value'];
      if (value is List) {
        return value
            .map((e) {
              if (e is String) return e;
              if (e is Map<String, dynamic> && e.containsKey('Alphabetic')) {
                return e['Alphabetic']?.toString() ?? '';
              }
              return e?.toString() ?? '';
            })
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }
    return [];
  }

  /// Formats a DICOM Person Name (e.g. "DOE^JOHN^^^MD" -> "DOE, JOHN MD" or "DOE, JOHN").
  static String formatPersonName(String? rawName) {
    if (rawName == null || rawName.isEmpty) return 'Anonymous';
    final parts = rawName.split('^');
    if (parts.isEmpty || parts.every((p) => p.isEmpty)) return 'Anonymous';

    final last = parts.isNotEmpty ? parts[0].trim() : '';
    final first = parts.length > 1 ? parts[1].trim() : '';
    final middle = parts.length > 2 ? parts[2].trim() : '';
    final suffix = parts.length > 4 ? parts[4].trim() : '';

    final nameParts = [first, middle].where((p) => p.isNotEmpty).join(' ');
    if (last.isEmpty && nameParts.isEmpty) return 'Anonymous';
    if (nameParts.isEmpty) return suffix.isNotEmpty ? '$last $suffix' : last;
    if (last.isEmpty)
      return suffix.isNotEmpty ? '$nameParts $suffix' : nameParts;

    final base = '$last, $nameParts';
    return suffix.isNotEmpty ? '$base $suffix' : base;
  }

  /// Formats DICOM Date (YYYYMMDD) to ISO format (YYYY-MM-DD).
  static String formatIsoDate(String? dcmDate) {
    if (dcmDate == null || dcmDate.length < 8) return dcmDate ?? '-';
    final clean = dcmDate.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length < 8) return dcmDate;
    final year = clean.substring(0, 4);
    final month = clean.substring(4, 6);
    final day = clean.substring(6, 8);
    return '$year-$month-$day';
  }

  /// Formats DICOM Date (00080020) and Time (00080030) into ISO 8601 (YYYY-MM-DDTHH:mm:ss).
  static String formatIsoDateTime(String? dcmDate, String? dcmTime) {
    final dateStr = formatIsoDate(dcmDate);
    if (dateStr == '-') return '-';
    if (dcmTime == null || dcmTime.isEmpty) return dateStr;

    final cleanTime = dcmTime.replaceAll(RegExp(r'[^0-9]'), '');
    String hh = '00';
    String mm = '00';
    String ss = '00';

    if (cleanTime.length >= 2) hh = cleanTime.substring(0, 2);
    if (cleanTime.length >= 4) mm = cleanTime.substring(2, 4);
    if (cleanTime.length >= 6) ss = cleanTime.substring(4, 6);

    return '${dateStr}T$hh:$mm:$ss';
  }

  /// Extracts [PixelSpacing] from DICOM JSON:
  /// 1. (0028,0030) Pixel Spacing
  /// 2. (0018,1164) Imager Pixel Spacing
  /// 3. (5200,9229) Shared Functional Groups -> (0028,9110) Pixel Measures -> (0028,0030)
  /// 4. (5200,9230) Per-Frame Functional Groups -> (0028,9110) Pixel Measures -> (0028,0030)
  static PixelSpacing? getPixelSpacing(Map<String, dynamic>? json) {
    if (json == null) return null;

    PixelSpacing? extractFromTag(dynamic tagEntry) {
      if (tagEntry == null) return null;
      if (tagEntry is Map<String, dynamic>) {
        final val = tagEntry['Value'];
        final parsed = PixelSpacing.tryParse(val);
        if (parsed != null) return parsed;
      }
      return PixelSpacing.tryParse(tagEntry);
    }

    // 1. Direct (0028,0030) Pixel Spacing
    final ps = extractFromTag(json['00280030'] ?? json['0028,0030']);
    if (ps != null) return ps;

    // 2. Direct (0018,1164) Imager Pixel Spacing
    final ips = extractFromTag(json['00181164'] ?? json['0018,1164']);
    if (ips != null) return ips;

    // 3. Shared Functional Groups Sequence (5200,9229) -> Pixel Measures Sequence (0028,9110)
    final sharedSeq = json['52009229'] ?? json['5200,9229'];
    if (sharedSeq is Map<String, dynamic>) {
      final val = sharedSeq['Value'];
      if (val is List && val.isNotEmpty && val.first is Map<String, dynamic>) {
        final item = val.first as Map<String, dynamic>;
        final pixelMeasures = item['00289110'] ?? item['0028,9110'];
        if (pixelMeasures is Map<String, dynamic>) {
          final pmVal = pixelMeasures['Value'];
          if (pmVal is List && pmVal.isNotEmpty && pmVal.first is Map<String, dynamic>) {
            final pmItem = pmVal.first as Map<String, dynamic>;
            final pmPs = extractFromTag(pmItem['00280030'] ?? pmItem['0028,0030']);
            if (pmPs != null) return pmPs;
          }
        }
      }
    }

    // 4. Per-Frame Functional Groups Sequence (5200,9230) -> Pixel Measures Sequence (0028,9110)
    final perFrameSeq = json['52009230'] ?? json['5200,9230'];
    if (perFrameSeq is Map<String, dynamic>) {
      final val = perFrameSeq['Value'];
      if (val is List && val.isNotEmpty && val.first is Map<String, dynamic>) {
        final item = val.first as Map<String, dynamic>;
        final pixelMeasures = item['00289110'] ?? item['0028,9110'];
        if (pixelMeasures is Map<String, dynamic>) {
          final pmVal = pixelMeasures['Value'];
          if (pmVal is List && pmVal.isNotEmpty && pmVal.first is Map<String, dynamic>) {
            final pmItem = pmVal.first as Map<String, dynamic>;
            final pmPs = extractFromTag(pmItem['00280030'] ?? pmItem['0028,0030']);
            if (pmPs != null) return pmPs;
          }
        }
      }
    }

    return null;
  }
}

/// DICOM Study summary returned from QIDO-RS `/studies`.
class DicomStudy {
  final String studyInstanceUID;
  final String patientName;
  final String rawPatientName;
  final String patientId;
  final String patientBirthDate;
  final String accessionNumber;
  final String studyDate;
  final String studyTime;
  final String studyDateTimeIso;
  final String modality;
  final List<String> modalities;
  final String studyDescription;
  final int numberOfSeries;
  final int numberOfInstances;
  final Map<String, dynamic> rawJson;

  const DicomStudy({
    required this.studyInstanceUID,
    required this.patientName,
    required this.rawPatientName,
    required this.patientId,
    required this.patientBirthDate,
    required this.accessionNumber,
    required this.studyDate,
    required this.studyTime,
    required this.studyDateTimeIso,
    required this.modality,
    required this.modalities,
    required this.studyDescription,
    required this.numberOfSeries,
    required this.numberOfInstances,
    required this.rawJson,
  });

  factory DicomStudy.fromJson(Map<String, dynamic> json) {
    final studyInstanceUID = DicomJsonHelper.getString(json, '0020000D') ?? '';
    final rawPatientName = DicomJsonHelper.getString(json, '00100010') ?? '';
    final patientName = DicomJsonHelper.formatPersonName(rawPatientName);
    final patientId = DicomJsonHelper.getString(json, '00100020') ?? '-';
    final rawBirthDate = DicomJsonHelper.getString(json, '00100030');
    final patientBirthDate = DicomJsonHelper.formatIsoDate(rawBirthDate);
    final accessionNumber = DicomJsonHelper.getString(json, '00080050') ?? '-';
    final studyDate = DicomJsonHelper.getString(json, '00080020') ?? '';
    final studyTime = DicomJsonHelper.getString(json, '00080030') ?? '';
    final studyDateTimeIso =
        DicomJsonHelper.formatIsoDateTime(studyDate, studyTime);

    final modalitiesInStudy = DicomJsonHelper.getStringList(json, '00080061');
    final singleModality = DicomJsonHelper.getString(json, '00080060');
    final modalities = modalitiesInStudy.isNotEmpty
        ? modalitiesInStudy
        : (singleModality != null ? [singleModality] : <String>[]);
    final modality =
        modalities.isNotEmpty ? modalities.join('/') : (singleModality ?? 'OT');

    final studyDescription = DicomJsonHelper.getString(json, '00081030') ?? '-';
    final numberOfSeries = DicomJsonHelper.getInt(json, '00201206') ?? 1;
    final numberOfInstances = DicomJsonHelper.getInt(json, '00201208') ?? 0;

    return DicomStudy(
      studyInstanceUID: studyInstanceUID,
      patientName: patientName,
      rawPatientName: rawPatientName,
      patientId: patientId,
      patientBirthDate: patientBirthDate,
      accessionNumber: accessionNumber,
      studyDate: studyDate,
      studyTime: studyTime,
      studyDateTimeIso: studyDateTimeIso,
      modality: modality,
      modalities: modalities,
      studyDescription: studyDescription,
      numberOfSeries: numberOfSeries,
      numberOfInstances: numberOfInstances,
      rawJson: json,
    );
  }
}

/// DICOM Series summary returned from QIDO-RS `/studies/{studyUID}/series`.
class DicomSeries {
  final String seriesInstanceUID;
  final String studyInstanceUID;
  final String modality;
  final int seriesNumber;
  final String seriesDescription;
  final int numberOfInstances;
  final String performingPhysician;
  final Map<String, dynamic> rawJson;

  const DicomSeries({
    required this.seriesInstanceUID,
    required this.studyInstanceUID,
    required this.modality,
    required this.seriesNumber,
    required this.seriesDescription,
    required this.numberOfInstances,
    required this.performingPhysician,
    required this.rawJson,
  });

  bool get isImageSeries =>
      modality.toUpperCase() != 'PR' &&
      modality.toUpperCase() != 'KO' &&
      modality.toUpperCase() != 'SR' &&
      modality.toUpperCase() != 'AU' &&
      modality.toUpperCase() != 'DOC';

  factory DicomSeries.fromJson(Map<String, dynamic> json) {
    final seriesInstanceUID = DicomJsonHelper.getString(json, '0020000E') ?? '';
    final studyInstanceUID = DicomJsonHelper.getString(json, '0020000D') ?? '';
    final modality = DicomJsonHelper.getString(json, '00080060') ?? 'OT';
    final seriesNumber = DicomJsonHelper.getInt(json, '00200011') ?? 1;
    final seriesDescription =
        DicomJsonHelper.getString(json, '0008103E') ?? 'Series $seriesNumber';
    final numberOfInstances = DicomJsonHelper.getInt(json, '00201209') ?? 0;
    final rawPhysician = DicomJsonHelper.getString(json, '00081050');
    final performingPhysician = DicomJsonHelper.formatPersonName(rawPhysician);

    return DicomSeries(
      seriesInstanceUID: seriesInstanceUID,
      studyInstanceUID: studyInstanceUID,
      modality: modality,
      seriesNumber: seriesNumber,
      seriesDescription: seriesDescription,
      numberOfInstances: numberOfInstances,
      performingPhysician: performingPhysician,
      rawJson: json,
    );
  }
}

/// Summary metadata for a single DICOM instance/SOP object.
class DicomInstanceSummary {
  final String sopInstanceUID;
  final String sopClassUID;
  final int instanceNumber;
  final int rows;
  final int columns;
  final int bitsAllocated;
  final int bitsStored;
  final int highBit;
  final bool isSigned;
  final double rescaleSlope;
  final double rescaleIntercept;
  final double? windowCenter;
  final double? windowWidth;
  final String photometricInterpretation;
  final String? transferSyntaxUID;
  final PixelSpacing? pixelSpacing;
  final Map<String, dynamic> rawJson;

  bool get isImage =>
      sopClassUID != '1.2.840.10008.5.1.4.1.1.11.1' &&
      DicomJsonHelper.getString(rawJson, '00080060')?.toUpperCase() != 'PR';

  const DicomInstanceSummary({
    required this.sopInstanceUID,
    required this.sopClassUID,
    required this.instanceNumber,
    required this.rows,
    required this.columns,
    required this.bitsAllocated,
    required this.bitsStored,
    required this.highBit,
    required this.isSigned,
    required this.rescaleSlope,
    required this.rescaleIntercept,
    this.windowCenter,
    this.windowWidth,
    required this.photometricInterpretation,
    this.transferSyntaxUID,
    this.pixelSpacing,
    required this.rawJson,
  });

  DicomInstanceSummary copyWith({
    String? sopInstanceUID,
    String? sopClassUID,
    int? instanceNumber,
    int? rows,
    int? columns,
    int? bitsAllocated,
    int? bitsStored,
    int? highBit,
    bool? isSigned,
    double? rescaleSlope,
    double? rescaleIntercept,
    double? windowCenter,
    double? windowWidth,
    String? photometricInterpretation,
    String? transferSyntaxUID,
    PixelSpacing? pixelSpacing,
    Map<String, dynamic>? rawJson,
  }) {
    return DicomInstanceSummary(
      sopInstanceUID: sopInstanceUID ?? this.sopInstanceUID,
      sopClassUID: sopClassUID ?? this.sopClassUID,
      instanceNumber: instanceNumber ?? this.instanceNumber,
      rows: rows ?? this.rows,
      columns: columns ?? this.columns,
      bitsAllocated: bitsAllocated ?? this.bitsAllocated,
      bitsStored: bitsStored ?? this.bitsStored,
      highBit: highBit ?? this.highBit,
      isSigned: isSigned ?? this.isSigned,
      rescaleSlope: rescaleSlope ?? this.rescaleSlope,
      rescaleIntercept: rescaleIntercept ?? this.rescaleIntercept,
      windowCenter: windowCenter ?? this.windowCenter,
      windowWidth: windowWidth ?? this.windowWidth,
      photometricInterpretation:
          photometricInterpretation ?? this.photometricInterpretation,
      transferSyntaxUID: transferSyntaxUID ?? this.transferSyntaxUID,
      pixelSpacing: pixelSpacing ?? this.pixelSpacing,
      rawJson: rawJson ?? this.rawJson,
    );
  }

  factory DicomInstanceSummary.fromJson(Map<String, dynamic> json) {
    final sopInstanceUID = DicomJsonHelper.getString(json, '00080018') ?? '';
    final sopClassUID = DicomJsonHelper.getString(json, '00080016') ?? '';
    final instanceNumber = DicomJsonHelper.getInt(json, '00200013') ?? 1;
    final rows = DicomJsonHelper.getInt(json, '00280010') ?? 512;
    final columns = DicomJsonHelper.getInt(json, '00280011') ?? 512;
    final bitsAllocated = DicomJsonHelper.getInt(json, '00280100') ?? 16;
    final bitsStored = DicomJsonHelper.getInt(json, '00280101') ?? 12;
    final highBit = DicomJsonHelper.getInt(json, '00280102') ?? 11;
    final pixelRep = DicomJsonHelper.getInt(json, '00280103') ?? 0;
    final isSigned = pixelRep == 1;

    final rescaleSlope = DicomJsonHelper.getDouble(json, '00281053') ?? 1.0;
    final rescaleIntercept = DicomJsonHelper.getDouble(json, '00281052') ?? 0.0;
    final windowCenter = DicomJsonHelper.getDouble(json, '00281050');
    final windowWidth = DicomJsonHelper.getDouble(json, '00281051');
    final photometricInterpretation =
        DicomJsonHelper.getString(json, '00280004') ?? 'MONOCHROME2';
    final transferSyntaxUID = DicomJsonHelper.getString(json, '00020010');
    final pixelSpacing = DicomJsonHelper.getPixelSpacing(json);

    return DicomInstanceSummary(
      sopInstanceUID: sopInstanceUID,
      sopClassUID: sopClassUID,
      instanceNumber: instanceNumber,
      rows: rows,
      columns: columns,
      bitsAllocated: bitsAllocated,
      bitsStored: bitsStored,
      highBit: highBit,
      isSigned: isSigned,
      rescaleSlope: rescaleSlope,
      rescaleIntercept: rescaleIntercept,
      windowCenter: windowCenter,
      windowWidth: windowWidth,
      photometricInterpretation: photometricInterpretation,
      transferSyntaxUID: transferSyntaxUID,
      pixelSpacing: pixelSpacing,
      rawJson: json,
    );
  }
}
