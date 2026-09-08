import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

void main() {
  final sampleMetadata = {
    '00100010': {
      'vr': 'PN',
      'Value': [
        {'Alphabetic': 'DOE^JOHN'}
      ],
    },
    '00100020': {
      'vr': 'LO',
      'Value': ['PATIENT-12345'],
    },
    '0020000D': {
      'vr': 'UI',
      'Value': ['1.2.840.10008.1.2.3.4'],
    },
    '00280010': {
      'vr': 'US',
      'Value': [512],
    },
    '00280011': {
      'vr': 'US',
      'Value': [512],
    },
  };

  group('DicomDumpWidget Tests', () {
    testWidgets('Renders empty state when metadata is null or empty',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DicomDumpWidget(metadataJson: null),
          ),
        ),
      );

      expect(find.text('No DICOM metadata available for this frame.'),
          findsOneWidget);
    });

    testWidgets('Renders header columns and metadata rows in flat grid',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DicomDumpWidget(
              metadataJson: sampleMetadata,
              title: 'Test DICOM Dump',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Title & count
      expect(find.text('Test DICOM Dump'), findsOneWidget);
      expect(find.text('5 attributes'), findsOneWidget);

      // Grid Headers
      expect(find.text('Tag'), findsOneWidget);
      expect(find.text('VR'), findsOneWidget);
      expect(find.text('VM'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Value'), findsOneWidget);

      // Entries
      expect(find.text('(0010,0010)'), findsOneWidget);
      expect(find.text("Patient's Name"), findsOneWidget);
      expect(find.text('DOE^JOHN'), findsOneWidget);

      expect(find.text('(0010,0020)'), findsOneWidget);
      expect(find.text('Patient ID'), findsOneWidget);
      expect(find.text('PATIENT-12345'), findsOneWidget);

      // Export buttons
      expect(find.text('Download JSON'), findsOneWidget);
      expect(find.text('Download CSV'), findsOneWidget);
    });

    testWidgets('Filters entries via live search query', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DicomDumpWidget(metadataJson: sampleMetadata),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('(0010,0010)'), findsOneWidget);
      expect(find.text('(0028,0010)'), findsOneWidget);

      // Search for "Rows"
      await tester.enterText(find.byType(TextField), 'Rows');
      await tester.pumpAndSettle();

      expect(find.text('(0028,0010)'), findsOneWidget); // Rows
      expect(find.text('(0010,0010)'), findsNothing); // Patient Name hidden
      expect(find.text('(0010,0020)'), findsNothing); // Patient ID hidden

      // Clear search
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(find.text('(0010,0010)'), findsOneWidget);
      expect(find.text('(0028,0010)'), findsOneWidget);
    });

    testWidgets('Updates reactively via metadataStream', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final streamController = StreamController<Map<String, dynamic>>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DicomDumpWidget(
              metadataStream: streamController.stream,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No DICOM metadata available for this frame.'),
          findsOneWidget);

      // Emit new metadata
      streamController.add(sampleMetadata);
      await tester.pumpAndSettle();

      expect(find.text('(0010,0010)'), findsOneWidget);
      expect(find.text('DOE^JOHN'), findsOneWidget);

      await streamController.close();
    });

    testWidgets(
        'DicomDumpDialog.show displays modal and dismisses on click outside',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  DicomDumpDialog.show(
                    ctx,
                    metadataJson: sampleMetadata,
                    title: 'Modal DICOM Dump',
                  );
                },
                child: const Text('Open Dump Modal'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Modal DICOM Dump'), findsNothing);

      // Tap button to open modal
      await tester.tap(find.text('Open Dump Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Modal DICOM Dump'), findsOneWidget);
      expect(find.text('(0010,0010)'), findsOneWidget);

      // Tap outside the modal (e.g. at the top edge of screen) to dismiss
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Modal DICOM Dump'), findsNothing);
    });
  });
}
