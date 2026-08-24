import 'dart:convert';
import 'package:http/http.dart' as http;

/// Client for querying metadata and retrieving frame data from DICOMweb servers (WADO-RS / QIDO-RS).
class DicomWebClient {
  final String baseUrl;
  final Map<String, String>? headers;
  final http.Client _httpClient;

  DicomWebClient({
    required this.baseUrl,
    this.headers,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Fetches dataset metadata for a given study/series using WADO-RS Metadata endpoint.
  Future<List<Map<String, dynamic>>> fetchInstanceMetadata({
    required String studyInstanceUID,
    required String seriesInstanceUID,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/studies/$studyInstanceUID/series/$seriesInstanceUID/metadata',
    );
    final requestHeaders = {
      'Accept': 'application/dicom+json',
      ...?headers,
    };

    final response = await _httpClient.get(uri, headers: requestHeaders);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch metadata (HTTP ${response.statusCode}): ${response.reasonPhrase}',
      );
    }

    final List<dynamic> jsonList = json.decode(response.body);
    return jsonList.cast<Map<String, dynamic>>();
  }

  /// Retrieves DICOM frame raw bytes via WADO-RS RetrieveFrames.
  Future<List<int>> fetchFrameBytes({
    required String studyInstanceUID,
    required String seriesInstanceUID,
    required String sopInstanceUID,
    required int frameIndex,
  }) async {
    final frameNumber = frameIndex + 1; // 1-indexed in DICOM WADO-RS
    final uri = Uri.parse(
      '$baseUrl/studies/$studyInstanceUID/series/$seriesInstanceUID/instances/$sopInstanceUID/frames/$frameNumber',
    );
    final requestHeaders = {
      'Accept': 'multipart/related; type="application/octet-stream"',
      ...?headers,
    };

    final response = await _httpClient.get(uri, headers: requestHeaders);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch frame $frameNumber (HTTP ${response.statusCode})',
      );
    }

    return response.bodyBytes;
  }

  void dispose() {
    _httpClient.close();
  }
}
