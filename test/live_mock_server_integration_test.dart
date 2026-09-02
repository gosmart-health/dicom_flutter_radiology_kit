import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_web_kit/dicom_web_kit.dart';
import 'dart:io';

void main() {
  group('Live Mock Server (localhost:8000) Integration Test', () {
    test('Queries live studies, series, buffers frames, and renders ui.Image', () async {
      try {
        final socket = await Socket.connect('localhost', 8000, timeout: const Duration(seconds: 1));
        await socket.close();
      } catch (e) {
        print('Skipping live mock server test: mock server not reachable on localhost:8000');
        return;
      }

      final client = DicomWebClient(baseUrl: 'http://localhost:8000');

      // 1. Fetch studies
      final studies = await client.queryStudies();
      expect(studies, isNotEmpty);
      print('Fetched ${studies.length} studies from live server');

      final study = studies.first;
      expect(study.studyInstanceUID, isNotEmpty);
      expect(study.patientName, isNotEmpty);
      print('First study: Patient=${study.patientName}, ID=${study.patientId}, Modality=${study.modality}, ISO Date=${study.studyDateTimeIso}');

      // 2. Fetch series
      final seriesList = await client.querySeries(studyInstanceUID: study.studyInstanceUID);
      expect(seriesList, isNotEmpty);
      final series = seriesList.first;
      print('First series: UID=${series.seriesInstanceUID}, Description=${series.seriesDescription}, Instances=${series.numberOfInstances}');

      // 3. Download series buffers
      final instances = await client.fetchInstanceMetadata(
        studyInstanceUID: series.studyInstanceUID,
        seriesInstanceUID: series.seriesInstanceUID,
      );
      expect(instances, isNotEmpty);
      print('Series instance metadata count: ${instances.length}');

      // Download first frame
      final firstInst = instances.first;
      final rawBytes = await client.fetchFrameBytes(
        studyInstanceUID: series.studyInstanceUID,
        seriesInstanceUID: series.seriesInstanceUID,
        sopInstanceUID: firstInst.sopInstanceUID,
        frameIndex: 0,
      );
      expect(rawBytes, isNotEmpty);
      print('Downloaded frame bytes: ${rawBytes.length} bytes');

      final frameBuffer = DicomFrameBuffer(
        frameIndex: 0,
        instanceNumber: firstInst.instanceNumber,
        sopInstanceUID: firstInst.sopInstanceUID,
        rawBytes: rawBytes,
        metadata: firstInst,
      );

      final pixelFrame = await frameBuffer.toPixelFrame();
      expect(pixelFrame.width, firstInst.rows);
      expect(pixelFrame.height, firstInst.columns);
      expect(pixelFrame.bitsAllocated, 16);
      print('Decoded PixelFrame: ${pixelFrame.width}x${pixelFrame.height}, Photometric: ${pixelFrame.photometricInterpretation}');

      final (minVal, maxVal) = pixelFrame.getMinMax();
      print('Pixel buffer min=$minVal, max=$maxVal');

      // 4. Render into ui.Image using VoiLut and decodeImageFromPixels
      final rgbaBytes = VoiLut.applyVoiLut(
        frame: pixelFrame,
        windowCenter: firstInst.windowCenter ?? 40.0,
        windowWidth: firstInst.windowWidth ?? 400.0,
      );

      expect(rgbaBytes.length, pixelFrame.width * pixelFrame.height * 4);

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgbaBytes,
        pixelFrame.width,
        pixelFrame.height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );

      final img = await completer.future;
      expect(img.width, pixelFrame.width);
      expect(img.height, pixelFrame.height);
      print('Successfully rendered live mock server frame into ${img.width}x${img.height} ui.Image!');
      img.dispose();
    });
  });
}
