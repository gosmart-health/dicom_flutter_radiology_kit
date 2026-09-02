import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../codecs/codec_router.dart';
import 'qido_models.dart';
import 'series_buffer.dart';

/// Client for querying metadata and retrieving frame data from DICOMweb servers (QIDO-RS / WADO-RS).
class DicomWebClient {
  final String baseUrl;
  final Map<String, String>? headers;
  final http.Client _httpClient;

  DicomWebClient({
    required String baseUrl,
    this.headers,
    http.Client? httpClient,
  })  : baseUrl = normalizeBaseUrl(baseUrl),
        _httpClient = httpClient ?? http.Client();

  /// Normalizes server URL string ensuring standard DICOMweb root path.
  static String normalizeBaseUrl(String input) {
    var url = input.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.endsWith('/dicomweb') && !url.endsWith('/rs') && !url.contains('/studies')) {
      final uri = Uri.tryParse(url);
      if (uri != null && (uri.path.isEmpty || uri.path == '/')) {
        url = '$url/dicomweb';
      }
    }
    return url;
  }

  /// Queries studies list via QIDO-RS `/studies`.
  Future<List<DicomStudy>> queryStudies({
    String? patientName,
    String? patientId,
    String? accessionNumber,
    String? modality,
    int? limit,
    int? offset,
  }) async {
    final queryParams = <String, String>{};
    if (patientName != null && patientName.isNotEmpty) {
      queryParams['PatientName'] = patientName;
    }
    if (patientId != null && patientId.isNotEmpty) {
      queryParams['PatientID'] = patientId;
    }
    if (accessionNumber != null && accessionNumber.isNotEmpty) {
      queryParams['AccessionNumber'] = accessionNumber;
    }
    if (modality != null && modality.isNotEmpty) {
      queryParams['ModalitiesInStudy'] = modality;
    }
    if (limit != null && limit > 0) {
      queryParams['limit'] = limit.toString();
    }
    if (offset != null && offset > 0) {
      queryParams['offset'] = offset.toString();
    }

    final baseUri = Uri.parse('$baseUrl/studies');
    final uri = queryParams.isEmpty
        ? baseUri
        : baseUri.replace(queryParameters: queryParams);

    final requestHeaders = {
      'Accept': 'application/dicom+json, application/json',
      ...?headers,
    };

    final response = await _httpClient.get(uri, headers: requestHeaders);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to query studies (HTTP ${response.statusCode}): ${response.body}',
      );
    }

    final List<dynamic> jsonList = json.decode(response.body);
    return jsonList.map((item) => DicomStudy.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// Queries series for a study via QIDO-RS `/studies/{studyInstanceUID}/series`.
  Future<List<DicomSeries>> querySeries({
    required String studyInstanceUID,
  }) async {
    final uri = Uri.parse('$baseUrl/studies/$studyInstanceUID/series');
    final requestHeaders = {
      'Accept': 'application/dicom+json, application/json',
      ...?headers,
    };

    final response = await _httpClient.get(uri, headers: requestHeaders);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to query series (HTTP ${response.statusCode}): ${response.body}',
      );
    }

    final List<dynamic> jsonList = json.decode(response.body);
    return jsonList.map((item) => DicomSeries.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// Queries instance summaries for a series via QIDO-RS `/studies/{studyUID}/series/{seriesUID}/instances`.
  Future<List<DicomInstanceSummary>> queryInstances({
    required String studyInstanceUID,
    required String seriesInstanceUID,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/studies/$studyInstanceUID/series/$seriesInstanceUID/instances',
    );
    final requestHeaders = {
      'Accept': 'application/dicom+json, application/json',
      ...?headers,
    };

    final response = await _httpClient.get(uri, headers: requestHeaders);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to query instances (HTTP ${response.statusCode}): ${response.body}',
      );
    }

    final List<dynamic> jsonList = json.decode(response.body);
    final instances = jsonList
        .map((item) => DicomInstanceSummary.fromJson(item as Map<String, dynamic>))
        .toList();
    instances.sort((a, b) => a.instanceNumber.compareTo(b.instanceNumber));
    return instances;
  }

  /// Fetches series metadata via WADO-RS `/studies/{studyUID}/series/{seriesUID}/metadata`.
  Future<List<DicomInstanceSummary>> fetchInstanceMetadata({
    required String studyInstanceUID,
    required String seriesInstanceUID,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/studies/$studyInstanceUID/series/$seriesInstanceUID/metadata',
    );
    final requestHeaders = {
      'Accept': 'application/dicom+json, application/json',
      ...?headers,
    };

    final response = await _httpClient.get(uri, headers: requestHeaders);
    if (response.statusCode != 200) {
      return queryInstances(
        studyInstanceUID: studyInstanceUID,
        seriesInstanceUID: seriesInstanceUID,
      );
    }

    final List<dynamic> jsonList = json.decode(response.body);
    final instances = jsonList
        .map((item) => DicomInstanceSummary.fromJson(item as Map<String, dynamic>))
        .toList();
    instances.sort((a, b) => a.instanceNumber.compareTo(b.instanceNumber));
    return instances;
  }

  /// Retrieves a single DICOM frame raw bytes via WADO-RS RetrieveFrames.
  Future<Uint8List> fetchFrameBytes({
    required String studyInstanceUID,
    required String seriesInstanceUID,
    required String sopInstanceUID,
    required int frameIndex,
    DicomCompressionMode compressionMode = DicomCompressionMode.raw,
  }) async {
    final frameNumber = frameIndex + 1; // 1-indexed in DICOM WADO-RS
    final uri = Uri.parse(
      '$baseUrl/studies/$studyInstanceUID/series/$seriesInstanceUID/instances/$sopInstanceUID/frames/$frameNumber',
    );
    final requestHeaders = {
      'Accept': compressionMode.acceptHeader,
      ...?headers,
    };

    final response = await _httpClient.get(uri, headers: requestHeaders);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch frame $frameNumber (HTTP ${response.statusCode})',
      );
    }

    final contentType = response.headers['content-type'] ?? '';
    return _extractFramePayload(response.bodyBytes, contentType);
  }

  /// Downloads all objects and frames of a series into memory buffers [DicomSeriesBuffer].
  Future<DicomSeriesBuffer> downloadSeriesBuffers({
    DicomStudy? study,
    required DicomSeries series,
    DicomCompressionMode compressionMode = DicomCompressionMode.raw,
    void Function(int loaded, int total)? onProgress,
  }) async {
    // 1. Fetch metadata for all instances in series
    final instances = await fetchInstanceMetadata(
      studyInstanceUID: series.studyInstanceUID,
      seriesInstanceUID: series.seriesInstanceUID,
    );

    final total = instances.length;
    final List<DicomFrameBuffer> frameBuffers = [];

    // 2. Download frames sequentially/concurrently
    for (int i = 0; i < instances.length; i++) {
      final inst = instances[i];
      final rawBytes = await fetchFrameBytes(
        studyInstanceUID: series.studyInstanceUID,
        seriesInstanceUID: series.seriesInstanceUID,
        sopInstanceUID: inst.sopInstanceUID,
        frameIndex: 0,
        compressionMode: compressionMode,
      );

      // Inject negotiated transfer syntax if not explicitly in metadata
      final effectiveTransferSyntax = inst.transferSyntaxUID ?? compressionMode.transferSyntaxUID;
      final updatedMetadata = DicomInstanceSummary(
        sopInstanceUID: inst.sopInstanceUID,
        sopClassUID: inst.sopClassUID,
        instanceNumber: inst.instanceNumber,
        rows: inst.rows,
        columns: inst.columns,
        bitsAllocated: inst.bitsAllocated,
        bitsStored: inst.bitsStored,
        highBit: inst.highBit,
        isSigned: inst.isSigned,
        rescaleSlope: inst.rescaleSlope,
        rescaleIntercept: inst.rescaleIntercept,
        windowCenter: inst.windowCenter,
        windowWidth: inst.windowWidth,
        photometricInterpretation: inst.photometricInterpretation,
        transferSyntaxUID: effectiveTransferSyntax,
        rawJson: inst.rawJson,
      );

      frameBuffers.add(DicomFrameBuffer(
        frameIndex: i,
        instanceNumber: inst.instanceNumber,
        sopInstanceUID: inst.sopInstanceUID,
        rawBytes: rawBytes,
        metadata: updatedMetadata,
      ));

      if (onProgress != null) {
        onProgress(i + 1, total);
      }
    }

    return DicomSeriesBuffer(
      study: study,
      series: series,
      frames: frameBuffers,
      totalExpectedInstances: total,
      isComplete: frameBuffers.length == total,
    );
  }

  /// Extracts pure binary payload from multipart/related or raw bytes response.
  Uint8List _extractFramePayload(Uint8List bytes, String contentType) {
    if (bytes.isEmpty) return bytes;

    if (contentType.contains('multipart/related') || _looksLikeMultipart(bytes)) {
      String? boundary;
      final boundaryMatch = RegExp(r'boundary=(?:"([^"]+)"|([^;]+))', caseSensitive: false)
          .firstMatch(contentType);
      if (boundaryMatch != null) {
        boundary = boundaryMatch.group(1) ?? boundaryMatch.group(2)?.trim();
      }

      if (boundary != null) {
        final boundaryBytes = '--$boundary'.codeUnits;
        int idx = _indexOfSublist(bytes, boundaryBytes);
        if (idx != -1) {
          final payload = _stripHeaders(bytes.sublist(idx + boundaryBytes.length));
          int endIdx = _indexOfSublist(payload, boundaryBytes);
          if (endIdx != -1) {
            return payload.sublist(0, endIdx);
          }
          return payload;
        }
      }

      if (bytes.length >= 2 && bytes[0] == 45 && bytes[1] == 45) { // '--'
        final stripped = _stripHeaders(bytes);
        return stripped;
      }
    }

    return bytes;
  }

  static bool _looksLikeMultipart(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 45 && bytes[1] == 45; // '--'
  }

  static Uint8List _stripHeaders(Uint8List bytes) {
    final doubleCrlf = [13, 10, 13, 10];
    final doubleLf = [10, 10];
    int headerEnd = _indexOfSublist(bytes, doubleCrlf);
    if (headerEnd != -1) {
      var body = bytes.sublist(headerEnd + 4);
      return _trimTrailingBoundary(body);
    }
    headerEnd = _indexOfSublist(bytes, doubleLf);
    if (headerEnd != -1) {
      var body = bytes.sublist(headerEnd + 2);
      return _trimTrailingBoundary(body);
    }
    return bytes;
  }

  static Uint8List _trimTrailingBoundary(Uint8List body) {
    int lastBoundary = -1;
    for (int i = body.length - 2; i >= 0; i--) {
      if (body[i] == 45 && body[i + 1] == 45) { // '--'
        if (i > 0 && (body[i - 1] == 10 || body[i - 1] == 13)) {
          lastBoundary = i - (body[i - 1] == 10 && i > 1 && body[i - 2] == 13 ? 2 : 1);
          break;
        }
      }
    }
    if (lastBoundary > 0 && lastBoundary < body.length) {
      return body.sublist(0, lastBoundary);
    }
    return body;
  }

  static int _indexOfSublist(List<int> list, List<int> sublist) {
    if (sublist.isEmpty) return 0;
    for (int i = 0; i <= list.length - sublist.length; i++) {
      bool match = true;
      for (int j = 0; j < sublist.length; j++) {
        if (list[i + j] != sublist[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  void dispose() {
    _httpClient.close();
  }
}
