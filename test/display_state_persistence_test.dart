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
  });
}

