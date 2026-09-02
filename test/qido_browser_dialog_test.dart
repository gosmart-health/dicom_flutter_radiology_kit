import 'dart:convert';
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
}

