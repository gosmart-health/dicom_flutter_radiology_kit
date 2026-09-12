import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

void main() {
  group('Live Mock Server (localhost:8000) STOW-RS & WADO-RS Integration Test', () {
    test('Stores GSPS instance via STOW-RS and retrieves it via WADO-RS', () async {
      try {
        final socket = await Socket.connect('localhost', 8000,
            timeout: const Duration(seconds: 1));
        await socket.close();
      } catch (e) {
        print('Skipping live mock server test: mock server not reachable on localhost:8000');
        return;
      }

      final client = DicomWebClient(baseUrl: 'http://localhost:8000');

      // 1. Query live studies
      final studies = await client.queryStudies();
      expect(studies, isNotEmpty);
      final study = studies.firstWhere(
        (s) => s.numberOfInstances <= 30,
        orElse: () => studies.first,
      );
      print('Target study: ${study.patientName} (${study.studyInstanceUID})');

      // 2. Query series
      final seriesList = await client.querySeries(studyInstanceUID: study.studyInstanceUID);
      expect(seriesList, isNotEmpty);
      final series = seriesList.firstWhere(
        (s) => s.numberOfInstances <= 30,
        orElse: () => seriesList.first,
      );
      print('Target series: ${series.seriesDescription} (${series.seriesInstanceUID})');

      // 3. Query instances
      final instances = await client.queryInstances(
        studyInstanceUID: study.studyInstanceUID,
        seriesInstanceUID: series.seriesInstanceUID,
      );
      expect(instances, isNotEmpty);
      final imageInst = instances.first;

      // 4. Create sample annotations
      final caliper = CaliperAnnotation(
        id: 'cal_stow_1',
        start: const Offset(120, 140),
        end: const Offset(260, 140),
        label: 'Aortic diameter',
        creatorName: 'Dr. TestRunner',
      );
      final note = TextAnnotation(
        id: 'txt_stow_1',
        anchor: const Offset(150, 100),
        text: 'Calcification detected',
        creatorName: 'Dr. TestRunner',
      );

      final gsps = GspsPresentationState(
        contentLabel: 'LIVE_STOW_TEST',
        contentDescription: 'Automated integration test annotation',
        contentCreatorName: 'Dr. TestRunner',
        referencedSopInstanceUid: imageInst.sopInstanceUID,
        referencedFrameNumber: 1,
        annotations: [caliper, note],
      );

      final dicomBytes = gsps.toDicomPart10Bytes(
        studyInstanceUid: study.studyInstanceUID,
        seriesInstanceUid: series.seriesInstanceUID,
        sopInstanceUid: imageInst.sopInstanceUID,
        frameNumber: 1,
        patientName: study.patientName,
        patientId: study.patientId,
      );

      expect(dicomBytes, isNotEmpty);
      print('Encoded GSPS DICOM Part 10 bytes: ${dicomBytes.length} bytes');

      // 5. Store via STOW-RS
      final storedSopUid = await client.storePresentationState(
        studyInstanceUID: study.studyInstanceUID,
        dicomPart10Bytes: dicomBytes,
      );
      print('Successfully stored GSPS via STOW-RS: $storedSopUid');
      expect(storedSopUid, isNotEmpty);

      // 6. Retrieve via WADO-RS
      final retrievedList = await client.fetchPresentationStates(
        studyInstanceUID: study.studyInstanceUID,
      );
      print('Retrieved ${retrievedList.length} presentation state(s) from server');
      expect(retrievedList, isNotEmpty);

      // Find our stored presentation state
      final match = retrievedList.firstWhere(
        (ps) => ps.contentLabel == 'LIVE_STOW_TEST' || ps.sopInstanceUid == storedSopUid,
        orElse: () => retrievedList.first,
      );

      expect(match.annotations, isNotEmpty);
      print('Matched retrieved GSPS annotations: ${match.annotations.length} items');
      expect(match.annotations.any((a) => a is CaliperAnnotation), isTrue);
      expect(match.annotations.any((a) => a is TextAnnotation), isTrue);

      final retrievedText = match.annotations.whereType<TextAnnotation>().first;
      expect(retrievedText.text, equals('Calcification detected'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
