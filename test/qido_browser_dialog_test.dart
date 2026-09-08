import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

void main() {
  testWidgets('QidoBrowserDialog renders headers, study data, and allows selecting study', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockStudiesResponse = json.encode([
      {
        '0020000D': {'vr': 'UI', 'Value': ['1.2.3.4.5']},
        '00100010': {'vr': 'PN', 'Value': [{'Alphabetic': 'DOE^JOHN'}]},
        '00100020': {'vr': 'LO', 'Value': ['GSH-001']},
        '00100030': {'vr': 'DA', 'Value': ['19800101']},
        '00080050': {'vr': 'SH', 'Value': ['ACC-999']},
        '00080020': {'vr': 'DA', 'Value': ['20260901']},
        '00080030': {'vr': 'TM', 'Value': ['103000']},
        '00080061': {'vr': 'CS', 'Value': ['CT']},
        '00081030': {'vr': 'LO', 'Value': ['CT THORAX']},
        '00201206': {'vr': 'IS', 'Value': [1]},
        '00201208': {'vr': 'IS', 'Value': [20]},
      }
    ]);

    final mockSeriesResponse = json.encode([
      {
        '0020000D': {'vr': 'UI', 'Value': ['1.2.3.4.5']},
        '0020000E': {'vr': 'UI', 'Value': ['1.2.3.4.5.1']},
        '00080060': {'vr': 'CS', 'Value': ['CT']},
        '00200011': {'vr': 'IS', 'Value': [1]},
        '0008103E': {'vr': 'LO', 'Value': ['Axial Soft Tissue']},
        '00081050': {'vr': 'PN', 'Value': [{'Alphabetic': 'SMITH^ALICE'}]},
        '00201209': {'vr': 'IS', 'Value': [20]},
      }
    ]);

    final mockClient = MockClient((request) async {
      if (request.url.path.endsWith('/studies')) {
        return http.Response(mockStudiesResponse, 200, headers: {'content-type': 'application/json'});
      }
      if (request.url.path.contains('/series')) {
        return http.Response(mockSeriesResponse, 200, headers: {'content-type': 'application/json'});
      }
      return http.Response('Not found', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QidoBrowserDialog(
            initialServerUrl: 'http://localhost:8000',
            httpClient: mockClient,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify dialog header and search controls
    expect(find.text('DICOMweb QIDO-RS Study Browser'), findsOneWidget);
    expect(find.text('DICOMweb Server Root'), findsOneWidget);

    // Verify grid column headers
    expect(find.text('Patient Name'), findsOneWidget);
    expect(find.text('Patient ID'), findsOneWidget);
    expect(find.text('Date of Birth'), findsOneWidget);
    expect(find.text('Accession Number'), findsOneWidget);
    expect(find.text('Study Date and Time (ISO)'), findsOneWidget);
    expect(find.text('Modality'), findsOneWidget);

    // Verify parsed study row content
    expect(find.text('DOE, JOHN'), findsOneWidget);
    expect(find.text('GSH-001'), findsOneWidget);
    expect(find.text('1980-01-01'), findsOneWidget);
    expect(find.text('ACC-999'), findsOneWidget);
    expect(find.text('2026-09-01T10:30:00'), findsOneWidget);

    // Tap on study row to drill down into series
    await tester.tap(find.text('DOE, JOHN'));
    await tester.pumpAndSettle();

    // Verify series level rendered
    expect(find.text('SERIES LEVEL'), findsOneWidget);
    expect(find.text('Series 1: Axial Soft Tissue'), findsOneWidget);
    expect(find.text('20 instance(s) • Dr. SMITH, ALICE'), findsOneWidget);
    expect(find.text('Download & View Series'), findsOneWidget);
  });

  testWidgets('QidoBrowserDialog pulls down past server roots and selects one', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      DicomServerUrlStore.clear();
    });

    DicomServerUrlStore.clear();
    DicomServerUrlStore.recordUrl('http://server-alpha.local:8000');
    DicomServerUrlStore.recordUrl('http://server-beta.local:8042');
    DicomServerUrlStore.recordUrl('http://server-gamma.local:9000');

    final mockClient = MockClient((request) async {
      return http.Response('[]', 200, headers: {'content-type': 'application/json'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QidoBrowserDialog(
            httpClient: mockClient,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify that the initial URL loaded from DicomServerUrlStore is server-gamma (most recently recorded)
    expect(find.text('http://server-gamma.local:9000'), findsOneWidget);

    // Tap on the pull-down arrow to open history menu
    final pullDownArrow = find.byTooltip('Recent DICOMweb Roots');
    expect(pullDownArrow, findsOneWidget);
    await tester.tap(pullDownArrow);
    await tester.pumpAndSettle();

    // Verify the history entries appear in the pull down menu
    expect(find.text('http://server-alpha.local:8000'), findsOneWidget);
    expect(find.text('http://server-beta.local:8042'), findsOneWidget);
    expect(find.text('http://server-gamma.local:9000'), findsAtLeast(1));

    // Tap on server-alpha to select it
    await tester.tap(find.text('http://server-alpha.local:8000'));
    await tester.pumpAndSettle();

    // Verify text field now displays server-alpha
    expect(find.text('http://server-alpha.local:8000'), findsOneWidget);
    // Verify DicomServerUrlStore updated last used URL to server-alpha
    expect(DicomServerUrlStore.getLastUsedUrl(), equals('http://server-alpha.local:8000'));
    expect(DicomServerUrlStore.getHistory().first, equals('http://server-alpha.local:8000'));
  });

  testWidgets('QidoBrowserDialog allows typing a new URL and records it to history upon query', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      DicomServerUrlStore.clear();
    });

    DicomServerUrlStore.clear();

    final mockClient = MockClient((request) async {
      return http.Response('[]', 200, headers: {'content-type': 'application/json'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QidoBrowserDialog(
            httpClient: mockClient,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter a new server root URL
    final urlField = find.widgetWithText(TextField, 'http://localhost:8000');
    await tester.enterText(urlField, 'http://new-pacs.hospital.org:8042/dicom-web');
    await tester.pumpAndSettle();

    // Click Query QIDO button
    await tester.tap(find.text('Query QIDO'));
    await tester.pumpAndSettle();

    // Verify recorded into history and last used
    expect(DicomServerUrlStore.getLastUsedUrl(), equals('http://new-pacs.hospital.org:8042/dicom-web'));
    expect(DicomServerUrlStore.getHistory(), contains('http://new-pacs.hospital.org:8042/dicom-web'));
  });

  testWidgets('QidoBrowserDialog compression mode dropdown requests RAW transfer syntax and never JPEG2000 LOSSLESS', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
    });

    final mockStudiesResponse = json.encode([
      {
        '0020000D': {'vr': 'UI', 'Value': ['1.2.840.113619.2.1']},
        '00100010': {'vr': 'PN', 'Value': [{'Alphabetic': 'TEST^PATIENT'}]},
        '00100020': {'vr': 'LO', 'Value': ['PID-001']},
        '00100030': {'vr': 'DA', 'Value': ['19750101']},
        '00080050': {'vr': 'SH', 'Value': ['ACC-100']},
        '00080020': {'vr': 'DA', 'Value': ['20260906']},
        '00080030': {'vr': 'TM', 'Value': ['090000']},
        '00080061': {'vr': 'CS', 'Value': ['CT']},
        '00081030': {'vr': 'LO', 'Value': ['HEAD CT']},
        '00201206': {'vr': 'IS', 'Value': [1]},
        '00201208': {'vr': 'IS', 'Value': [1]},
      }
    ]);

    final mockSeriesResponse = json.encode([
      {
        '0020000D': {'vr': 'UI', 'Value': ['1.2.840.113619.2.1']},
        '0020000E': {'vr': 'UI', 'Value': ['1.2.840.113619.2.1.1']},
        '00080060': {'vr': 'CS', 'Value': ['CT']},
        '00200011': {'vr': 'IS', 'Value': [1]},
        '0008103E': {'vr': 'LO', 'Value': ['Brain Axial']},
        '00081050': {'vr': 'PN', 'Value': [{'Alphabetic': 'PHYSICIAN^DR'}]},
        '00201209': {'vr': 'IS', 'Value': [1]},
      }
    ]);

    final metadataResponse = json.encode([
      {
        '00080018': {'vr': 'UI', 'Value': ['1.2.840.113619.2.1.1.1']},
        '00200013': {'vr': 'IS', 'Value': [1]},
        '00280010': {'vr': 'US', 'Value': [2]},
        '00280011': {'vr': 'US', 'Value': [2]},
        '00280100': {'vr': 'US', 'Value': [16]},
        '00280101': {'vr': 'US', 'Value': [16]},
        '00280102': {'vr': 'US', 'Value': [15]},
        '00280103': {'vr': 'US', 'Value': [0]},
        '00281052': {'vr': 'DS', 'Value': [0.0]},
        '00281053': {'vr': 'DS', 'Value': [1.0]},
        '00280004': {'vr': 'CS', 'Value': ['MONOCHROME2']},
      }
    ]);

    final rawPixels = Uint16List.fromList([100, 200, 300, 400]);
    final rawBytes = Uint8List.view(rawPixels.buffer);

    final List<String> capturedAcceptHeaders = [];

    final mockClient = MockClient((request) async {
      if (request.url.path.endsWith('/studies')) {
        return http.Response(mockStudiesResponse, 200, headers: {'content-type': 'application/json'});
      }
      if (request.url.path.contains('/series') && !request.url.path.contains('/metadata') && !request.url.path.contains('/frames')) {
        return http.Response(mockSeriesResponse, 200, headers: {'content-type': 'application/json'});
      }
      if (request.url.path.contains('/metadata')) {
        return http.Response(metadataResponse, 200, headers: {'content-type': 'application/json'});
      }
      if (request.url.path.contains('/frames/1')) {
        capturedAcceptHeaders.add(request.headers['Accept'] ?? '');
        return http.Response.bytes(
          rawBytes,
          200,
          headers: {'content-type': 'application/octet-stream'},
        );
      }
      return http.Response('Not found: ${request.url}', 404);
    });

    DicomSeriesBuffer? loadedSeriesResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QidoBrowserDialog(
            initialServerUrl: 'http://localhost:8000',
            defaultCompressionMode: DicomCompressionMode.raw,
            httpClient: mockClient,
            onSeriesLoaded: (buffer, frame) {
              loadedSeriesResult = buffer;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify RAW is selected in the compression mode dropdown
    expect(find.text('RAW'), findsOneWidget);

    // Select the study
    await tester.tap(find.text('TEST, PATIENT'));
    await tester.pumpAndSettle();

    // Click 'Download & View Series'
    await tester.tap(find.text('Download & View Series'));
    await tester.pumpAndSettle();

    // Verify a frame request was dispatched
    expect(capturedAcceptHeaders.length, 1);
    final header = capturedAcceptHeaders.first;

    // Verify RAW header format
    expect(header, 'multipart/related; type="application/octet-stream"; transfer-syntax="1.2.840.10008.1.2.1"');

    // Confirm that JPEG2000 LOSSLESS is NOT requested
    expect(header.contains('1.2.840.10008.1.2.4.90'), isFalse);
    expect(header.contains('image/jp2'), isFalse);
    expect(header.contains('JPEG2000'), isFalse);

    // Verify that the series was successfully loaded
    expect(loadedSeriesResult, isNotNull);
    expect(loadedSeriesResult!.frameCount, 1);
  });

  testWidgets('QidoBrowserDialog dropdown can switch from JPEG2000_LOSSLESS to RAW and correctly reflects transfer syntax', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockStudiesResponse = json.encode([
      {
        '0020000D': {'vr': 'UI', 'Value': ['1.2.3.4.5']},
        '00100010': {'vr': 'PN', 'Value': [{'Alphabetic': 'SWITCH^TEST'}]},
        '00100020': {'vr': 'LO', 'Value': ['PID-002']},
        '00100030': {'vr': 'DA', 'Value': ['19800101']},
        '00080050': {'vr': 'SH', 'Value': ['ACC-200']},
        '00080020': {'vr': 'DA', 'Value': ['20260906']},
        '00080030': {'vr': 'TM', 'Value': ['100000']},
        '00080061': {'vr': 'CS', 'Value': ['CT']},
        '00081030': {'vr': 'LO', 'Value': ['CT ABDOMEN']},
        '00201206': {'vr': 'IS', 'Value': [1]},
        '00201208': {'vr': 'IS', 'Value': [1]},
      }
    ]);

    final mockSeriesResponse = json.encode([
      {
        '0020000D': {'vr': 'UI', 'Value': ['1.2.3.4.5']},
        '0020000E': {'vr': 'UI', 'Value': ['1.2.3.4.5.1']},
        '00080060': {'vr': 'CS', 'Value': ['CT']},
        '00200011': {'vr': 'IS', 'Value': [1]},
        '0008103E': {'vr': 'LO', 'Value': ['Abdomen Series']},
        '00081050': {'vr': 'PN', 'Value': [{'Alphabetic': 'DOCTOR^RAD'}]},
        '00201209': {'vr': 'IS', 'Value': [1]},
      }
    ]);

    final metadataResponse = json.encode([
      {
        '00080018': {'vr': 'UI', 'Value': ['1.2.3.4.5.1.1']},
        '00200013': {'vr': 'IS', 'Value': [1]},
        '00280010': {'vr': 'US', 'Value': [2]},
        '00280011': {'vr': 'US', 'Value': [2]},
        '00280100': {'vr': 'US', 'Value': [16]},
        '00280101': {'vr': 'US', 'Value': [16]},
        '00280102': {'vr': 'US', 'Value': [15]},
        '00280103': {'vr': 'US', 'Value': [0]},
        '00281052': {'vr': 'DS', 'Value': [0.0]},
        '00281053': {'vr': 'DS', 'Value': [1.0]},
        '00280004': {'vr': 'CS', 'Value': ['MONOCHROME2']},
      }
    ]);

    final rawBytes = Uint8List(8);
    final List<String> capturedHeaders = [];

    final mockClient = MockClient((request) async {
      if (request.url.path.endsWith('/studies')) {
        return http.Response(mockStudiesResponse, 200, headers: {'content-type': 'application/json'});
      }
      if (request.url.path.contains('/series') && !request.url.path.contains('/metadata') && !request.url.path.contains('/frames')) {
        return http.Response(mockSeriesResponse, 200, headers: {'content-type': 'application/json'});
      }
      if (request.url.path.contains('/metadata')) {
        return http.Response(metadataResponse, 200, headers: {'content-type': 'application/json'});
      }
      if (request.url.path.contains('/frames/1')) {
        capturedHeaders.add(request.headers['Accept'] ?? '');
        return http.Response.bytes(rawBytes, 200, headers: {'content-type': 'application/octet-stream'});
      }
      return http.Response('Not found', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QidoBrowserDialog(
            initialServerUrl: 'http://localhost:8000',
            defaultCompressionMode: DicomCompressionMode.raw,
            httpClient: mockClient,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Switch dropdown from RAW to JPEG2000_LOSSLESS
    await tester.tap(find.text('RAW'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JPEG2000_LOSSLESS').last);
    await tester.pumpAndSettle();
    expect(find.text('JPEG2000_LOSSLESS'), findsOneWidget);

    // 2. Switch dropdown back to RAW
    await tester.tap(find.text('JPEG2000_LOSSLESS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RAW').last);
    await tester.pumpAndSettle();
    expect(find.text('RAW'), findsOneWidget);

    // 3. Drill down into study and load series
    await tester.tap(find.text('SWITCH, TEST'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Download & View Series'));
    await tester.pumpAndSettle();

    // 4. Assert header is strictly RAW and not JPEG2000 LOSSLESS
    expect(capturedHeaders.length, 1);
    expect(capturedHeaders.first, 'multipart/related; type="application/octet-stream"; transfer-syntax="1.2.840.10008.1.2.1"');
    expect(capturedHeaders.first.contains('1.2.840.10008.1.2.4.90'), isFalse);
    expect(capturedHeaders.first.contains('image/jp2'), isFalse);
  });
}


