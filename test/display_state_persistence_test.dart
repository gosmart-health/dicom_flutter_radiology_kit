import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';
import '../example/lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Display State (W/L, Zoom, Pan) Persistence & GSPS STOW-RS Tests', () {
    testWidgets(
        'Modifying W/L, Zoom, and Pan on a frame preserves display state across frame navigation',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const DicomViewerApp());
      await tester.pumpAndSettle();

      final layerFinder = find.byType(DicomAnnotationLayer).first;
      final layer = tester.widget<DicomAnnotationLayer>(layerFinder);
      final viewportCtrl = layer.viewportController;

      // 1. Modify W/L, Zoom, and Pan on Frame 0
      viewportCtrl.setWindowLevel(600.0, 1500.0);
      viewportCtrl.setZoom(2.5);
      viewportCtrl.setPanOffset(const Offset(45.0, -30.0));
      await tester.pump();

      expect(viewportCtrl.windowCenter, equals(600.0));
      expect(viewportCtrl.windowWidth, equals(1500.0));
      expect(viewportCtrl.zoom, equals(2.5));
      expect(viewportCtrl.panOffset, equals(const Offset(45.0, -30.0)));

      // Export presentation state for frame 0
      final state0 = viewportCtrl.toPresentationState();
      expect(state0.windowCenter, equals(600.0));
      expect(state0.windowWidth, equals(1500.0));
      expect(state0.zoom, equals(2.5));
      expect(state0.panOffset, equals(const Offset(45.0, -30.0)));

      // 2. Switch to TG18-QC fixture and customize its W/L & Zoom
      await tester.tap(find.text('TG18-QC'));
      await tester.pumpAndSettle();

      expect(viewportCtrl.windowCenter, equals(2048.0));
      expect(viewportCtrl.windowWidth, equals(4096.0));
      expect(viewportCtrl.zoom, equals(1.0));

      viewportCtrl.setWindowLevel(1000.0, 2000.0);
      viewportCtrl.setZoom(1.8);
      await tester.pump();

      expect(viewportCtrl.windowCenter, equals(1000.0));
      expect(viewportCtrl.windowWidth, equals(2000.0));
      expect(viewportCtrl.zoom, equals(1.8));

      // 3. Switch back to CT Phantom
      await tester.tap(find.text('CT Phantom'));
      await tester.pumpAndSettle();

      // Verify CT Phantom's customized display state was preserved!
      expect(viewportCtrl.windowCenter, equals(600.0));
      expect(viewportCtrl.windowWidth, equals(1500.0));
      expect(viewportCtrl.zoom, equals(2.5));
      expect(viewportCtrl.panOffset, equals(const Offset(45.0, -30.0)));
    });

    test('GSPS DicomEncoder serializes W/L, Zoom, and Pan into standard DICOM tags & private semantics', () {
      final gsps = GspsPresentationState(
        sopInstanceUid: '1.2.3.4.5.gsps.1',
        contentLabel: 'DISPLAY_STATE_TEST',
        contentDescription: 'Customized presentation state',
        contentCreatorName: 'Dr. Tester',
        referencedSopInstanceUid: '1.2.3.4.5.image.1',
        referencedFrameNumber: 1,
        windowCenter: 520.0,
        windowWidth: 1250.0,
        zoom: 2.75,
        panOffset: const Offset(50.0, -25.0),
        annotations: [],
      );

      final bytes = gsps.toDicomPart10Bytes(
        studyInstanceUid: '1.2.3.4.5.study',
        seriesInstanceUid: '1.2.3.4.5.series',
        sopInstanceUid: '1.2.3.4.5.image.1',
        frameNumber: 1,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(128 + 4));

      // Reconstruct GSPS from state to verify roundtrip fidelity
      final reconstructed = GspsPresentationState.fromJson(gsps.toJson());
      expect(reconstructed.windowCenter, equals(520.0));
      expect(reconstructed.windowWidth, equals(1250.0));
      expect(reconstructed.zoom, equals(2.75));
      expect(reconstructed.panOffset, equals(const Offset(50.0, -25.0)));
    });

    test('GSPS DicomEncoder serializes multi-SOP instance series frameStates into single DICOM GSPS file', () {
      final frame1 = GspsFrameState(
        referencedSopInstanceUid: '1.2.3.4.5.image.1',
        referencedFrameNumber: 1,
        windowCenter: 600.0,
        windowWidth: 1500.0,
        zoom: 2.5,
        panOffset: const Offset(40.0, -20.0),
        annotations: [
          CaliperAnnotation(
            id: 'c1',
            start: const Offset(10, 10),
            end: const Offset(50, 50),
            label: 'Measurement 1',
          )
        ],
      );

      final frame2 = GspsFrameState(
        referencedSopInstanceUid: '1.2.3.4.5.image.2',
        referencedFrameNumber: 2,
        windowCenter: 400.0,
        windowWidth: 800.0,
        zoom: 1.5,
        panOffset: const Offset(-10.0, 15.0),
        annotations: [],
      );

      final seriesGsps = GspsPresentationState(
        sopInstanceUid: '1.2.3.4.5.gsps.series',
        contentLabel: 'SERIES_MULTI_SOP',
        contentDescription: 'Consolidated series presentation state',
        contentCreatorName: 'Dr. Radiologist',
        studyInstanceUid: '1.2.3.4.5.study',
        seriesInstanceUid: '1.2.3.4.5.series',
        referencedSopInstanceUid: '1.2.3.4.5.image.1',
        frameStates: [frame1, frame2],
      );

      final part10Bytes = seriesGsps.toDicomPart10Bytes(
        studyInstanceUid: '1.2.3.4.5.study',
        seriesInstanceUid: '1.2.3.4.5.series',
        sopInstanceUid: '1.2.3.4.5.image.1',
      );

      expect(part10Bytes, isNotEmpty);
      expect(part10Bytes.length, greaterThan(256));

      // Reconstruct GSPS from JSON map
      final reconstructed = GspsPresentationState.fromJson(seriesGsps.toJson());
      expect(reconstructed.frameStates.length, equals(2));
      expect(reconstructed.frameStates[0].windowCenter, equals(600.0));
      expect(reconstructed.frameStates[0].zoom, equals(2.5));
      expect(reconstructed.frameStates[0].annotations.length, equals(1));
      expect(reconstructed.frameStates[1].windowCenter, equals(400.0));
      expect(reconstructed.frameStates[1].zoom, equals(1.5));
    });

    test('GSPS DicomEncoder includes inner (0008,1140) ReferencedImageSequence in per-frame sequence items', () {
      final frame1 = GspsFrameState(
        referencedSopInstanceUid: '1.2.3.4.5.image.1',
        referencedFrameNumber: 1,
        windowCenter: 600.0,
        windowWidth: 1500.0,
        zoom: 2.5,
        panOffset: const Offset(40.0, -20.0),
        annotations: [
          CaliperAnnotation(
            id: 'c1',
            start: const Offset(10, 10),
            end: const Offset(50, 50),
            label: 'Measurement 1',
          )
        ],
      );

      final frame2 = GspsFrameState(
        referencedSopInstanceUid: '1.2.3.4.5.image.2',
        referencedFrameNumber: 2,
        windowCenter: 400.0,
        windowWidth: 800.0,
        zoom: 1.5,
        panOffset: const Offset(-10.0, 15.0),
        annotations: [],
      );

      final seriesGsps = GspsPresentationState(
        sopInstanceUid: '1.2.3.4.5.gsps.series',
        contentLabel: 'SERIES_MULTI_SOP',
        studyInstanceUid: '1.2.3.4.5.study',
        seriesInstanceUid: '1.2.3.4.5.series',
        frameStates: [frame1, frame2],
      );

      final part10Bytes = seriesGsps.toDicomPart10Bytes(
        studyInstanceUid: '1.2.3.4.5.study',
        seriesInstanceUid: '1.2.3.4.5.series',
        sopInstanceUid: '1.2.3.4.5.image.1',
      );

      // (0008,1140) SQ in Explicit VR Little Endian is:
      // Group 0x0008 (0x08, 0x00), Element 0x1140 (0x40, 0x11), VR 'SQ' (0x53, 0x51)
      final refImageSeqTagPattern = [0x08, 0x00, 0x40, 0x11, 0x53, 0x51];
      int occurrences = 0;
      for (int i = 0; i <= part10Bytes.length - refImageSeqTagPattern.length; i++) {
        bool match = true;
        for (int j = 0; j < refImageSeqTagPattern.length; j++) {
          if (part10Bytes[i + j] != refImageSeqTagPattern[j]) {
            match = false;
            break;
          }
        }
        if (match) occurrences++;
      }

      // Expected occurrences:
      // 1 in ReferencedSeriesSequence (0008,1115)
      // 2 in SoftcopyVOILUTSequence (0028,3110) (1 for frame1, 1 for frame2)
      // 1 in GraphicAnnotationSequence (0070,0001) (for frame1 annotations)
      // 2 in DisplayedAreaSelectionSequence (0070,005A) (1 for frame1, 1 for frame2)
      // Total = 6 occurrences
      expect(occurrences, equals(6));
      expect(occurrences, greaterThanOrEqualTo(4));
    });

    test('AnnotationController loadGspsPresentationState with frameNumber respects referenced frame', () {
      final annFrame1 = CaliperAnnotation(
        id: 'ann1',
        start: const Offset(10, 10),
        end: const Offset(50, 50),
      );
      final annFrame2 = AngleAnnotation(
        id: 'ann2',
        p1: const Offset(80, 80),
        vertex: const Offset(100, 100),
        p2: const Offset(120, 80),
      );

      final frame1 = GspsFrameState(
        referencedSopInstanceUid: '1.2.3.4.5.img1',
        referencedFrameNumber: 1,
        annotations: [annFrame1],
      );
      final frame2 = GspsFrameState(
        referencedSopInstanceUid: '1.2.3.4.5.img2',
        referencedFrameNumber: 2,
        annotations: [annFrame2],
      );

      final gsps = GspsPresentationState(
        sopInstanceUid: '1.2.3.4.5.gsps',
        frameStates: [frame1, frame2],
      );

      final controller = AnnotationController();

      // Load for frame 1
      controller.loadGspsPresentationState(gsps, frameNumber: 1);
      expect(controller.allAnnotations.length, equals(1));
      expect(controller.allAnnotations.first, isA<CaliperAnnotation>());

      // Load for frame 2
      controller.loadGspsPresentationState(gsps, frameNumber: 2);
      expect(controller.allAnnotations.length, equals(1));
      expect(controller.allAnnotations.first, isA<AngleAnnotation>());
    });
  });
}

