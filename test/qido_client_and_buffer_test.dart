import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dicom_web_kit/dicom_web_kit.dart';

void main() {
  group('DicomWebClient & SeriesBuffer Integration', () {
    test('Queries studies and parses study list', () async {
      final mockResponse = json.encode([
        {
          '0020000D': {'vr': 'UI', 'Value': ['1.2.3.4.5']},
          '00100010': {'vr': 'PN', 'Value': [{'Alphabetic': 'DOE^JOHN'}]},
          '00100020': {'vr': 'LO', 'Value': ['P123']},
          '00100030': {'vr': 'DA', 'Value': ['19800512']},
          '00080050': {'vr': 'SH', 'Value': ['ACC999']},
          '00080020': {'vr': 'DA', 'Value': ['20260901']},
          '00080030': {'vr': 'TM', 'Value': ['120000']},
          '00080061': {'vr': 'CS', 'Value': ['CT']},
          '00081030': {'vr': 'LO', 'Value': ['CT CHEST']},
          '00201206': {'vr': 'IS', 'Value': [1]},
          '00201208': {'vr': 'IS', 'Value': [10]},
        }
      ]);

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/studies')) {
          return http.Response(mockResponse, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not found', 404);
      });

      final client = DicomWebClient(baseUrl: 'http://localhost:8000', httpClient: mockClient);
      final studies = await client.queryStudies();

      expect(studies.length, 1);
      expect(studies[0].patientName, 'DOE, JOHN');
      expect(studies[0].patientId, 'P123');
      expect(studies[0].patientBirthDate, '1980-05-12');
      expect(studies[0].accessionNumber, 'ACC999');
      expect(studies[0].studyDateTimeIso, '2026-09-01T12:00:00');
      expect(studies[0].modality, 'CT');
    });

    test('Downloads series buffers and decodes PixelFrame', () async {
      final metadataResponse = json.encode([
        {
          '00080018': {'vr': 'UI', 'Value': ['1.2.3.4.5.1.1']},
          '00200013': {'vr': 'IS', 'Value': [1]},
          '00280010': {'vr': 'US', 'Value': [4]},
          '00280011': {'vr': 'US', 'Value': [4]},
          '00280100': {'vr': 'US', 'Value': [16]},
          '00280101': {'vr': 'US', 'Value': [12]},
          '00280102': {'vr': 'US', 'Value': [11]},
          '00280103': {'vr': 'US', 'Value': [0]},
          '00281052': {'vr': 'DS', 'Value': [-1000.0]},
          '00281053': {'vr': 'DS', 'Value': [1.0]},
          '00280004': {'vr': 'CS', 'Value': ['MONOCHROME2']},
        }
      ]);

      // 4x4 16-bit uncompressed pixels = 16 pixels * 2 bytes = 32 bytes
      final rawUint16 = Uint16List.fromList([
        1000, 1050, 1100, 1150,
        1200, 1250, 1300, 1350,
        1400, 1450, 1500, 1550,
        1600, 1650, 1700, 1750,
      ]);
      final pixelBytes = Uint8List.view(rawUint16.buffer);

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/metadata')) {
          return http.Response(metadataResponse, 200);
        }
        if (request.url.path.contains('/frames/1')) {
          return http.Response.bytes(
            pixelBytes,
            200,
            headers: {'content-type': 'application/octet-stream'},
          );
        }
        return http.Response('Not found', 404);
      });

      final client = DicomWebClient(baseUrl: 'http://localhost:8000', httpClient: mockClient);
      final series = DicomSeries.fromJson({
        '0020000D': {'vr': 'UI', 'Value': ['1.2.3.4.5']},
        '0020000E': {'vr': 'UI', 'Value': ['1.2.3.4.5.1']},
        '00080060': {'vr': 'CS', 'Value': ['CT']},
        '00200011': {'vr': 'IS', 'Value': [1]},
        '0008103E': {'vr': 'LO', 'Value': ['Test Series']},
        '00201209': {'vr': 'IS', 'Value': [1]},
      });

      final seriesBuffer = await client.downloadSeriesBuffers(series: series);
      expect(seriesBuffer.frameCount, 1);
      expect(seriesBuffer.isComplete, true);

      final pixelFrame = await seriesBuffer.getPixelFrame(0);
      expect(pixelFrame, isNotNull);
      expect(pixelFrame!.width, 4);
      expect(pixelFrame.height, 4);
      expect(pixelFrame.bitsAllocated, 16);
      expect(pixelFrame.rescaleIntercept, -1000.0);
      expect(pixelFrame.rescaleSlope, 1.0);

      // Verify raw 16-bit scalar pixel preservation
      expect(pixelFrame.rawPixels, isA<Uint16List>());
      final list = pixelFrame.rawPixels as Uint16List;
      expect(list[0], 1000);
      expect(list[15], 1750);
      expect(pixelFrame.getModalityValue(list[0]), 0.0); // 1000 - 1000 = 0 HU
    });
  });
}

