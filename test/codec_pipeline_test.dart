import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_web_kit/dicom_web_kit.dart';

void main() {
  group('Codec Pipeline Offline Unit Tests', () {
    late Uint8List rawFixtureBytes;
    late Uint8List jpegFixtureBytes;
    late Uint8List j2kFixtureBytes;

    setUpAll(() {
      final rawFile = File('test/fixtures/frame_raw.raw');
      final jpegFile = File('test/fixtures/frame_jpeg_baseline.jpg');
      final j2kFile = File('test/fixtures/frame_j2k_lossless.j2k');

      expect(rawFile.existsSync(), true, reason: 'frame_raw.raw fixture must exist');
      expect(jpegFile.existsSync(), true, reason: 'frame_jpeg_baseline.jpg fixture must exist');
      expect(j2kFile.existsSync(), true, reason: 'frame_j2k_lossless.j2k fixture must exist');

      rawFixtureBytes = rawFile.readAsBytesSync();
      jpegFixtureBytes = jpegFile.readAsBytesSync();
      j2kFixtureBytes = j2kFile.readAsBytesSync();
    });

    test('Decodes RAW Explicit VR Little Endian 16-bit frame fixture', () async {
      const options = DecodeOptions(
        width: 512,
        height: 512,
        bitsAllocated: 16,
        bitsStored: 12,
        isSigned: false,
      );

      final result = await CodecRouter.decode(
        transferSyntaxUID: DicomTransferSyntaxes.explicitVRLittleEndian,
        frameBytes: rawFixtureBytes,
        options: options,
      );

      expect(result.width, 512);
      expect(result.height, 512);
      expect(result.bitsAllocated, 16);
      expect(result.pixelData, isA<Uint16List>());

      final pixels = result.pixelData as Uint16List;
      expect(pixels.length, 512 * 512);

      // Verify VOI LUT mapping
      final frame = PixelFrame(
        rawPixels: pixels,
        width: 512,
        height: 512,
        bitsAllocated: 16,
        bitsStored: 12,
        rescaleIntercept: 0.0,
        rescaleSlope: 1.0,
      );

      final rgba = VoiLut.applyVoiLut(frame: frame, windowCenter: 2048.0, windowWidth: 4096.0);
      expect(rgba.length, 512 * 512 * 4);

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(rgba, 512, 512, ui.PixelFormat.rgba8888, completer.complete);
      final image = await completer.future;
      expect(image.width, 512);
      expect(image.height, 512);
      image.dispose();
    });

    test('Decodes JPEG Process 1 (8-bit Baseline) frame fixture', () async {
      const options = DecodeOptions(
        width: 512,
        height: 512,
        bitsAllocated: 16,
        bitsStored: 8,
        isSigned: false,
      );

      final result = await CodecRouter.decode(
        transferSyntaxUID: DicomTransferSyntaxes.jpegBaseline1,
        frameBytes: jpegFixtureBytes,
        options: options,
      );

      expect(result.width, 512);
      expect(result.height, 512);
      expect(result.bitsAllocated, 16);
      expect(result.pixelData, isA<Uint16List>());

      final pixels = result.pixelData as Uint16List;
      expect(pixels.length, 512 * 512);

      // Verify scalar pixels are non-trivial
      final (minVal, maxVal) = PixelFrame(
        rawPixels: pixels,
        width: 512,
        height: 512,
      ).getMinMax();
      expect(maxVal, greaterThan(0));

      // Test VOI LUT render
      final frame = PixelFrame(
        rawPixels: pixels,
        width: 512,
        height: 512,
        bitsAllocated: 16,
        bitsStored: 8,
      );

      final rgba = VoiLut.applyVoiLut(frame: frame, windowCenter: 128.0, windowWidth: 256.0);
      expect(rgba.length, 512 * 512 * 4);

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(rgba, 512, 512, ui.PixelFormat.rgba8888, completer.complete);
      final image = await completer.future;
      expect(image.width, 512);
      expect(image.height, 512);
      image.dispose();
    });

    test('Decodes JPEG 2000 Lossless (1.2.840.10008.1.2.4.90) frame fixture', () async {
      const options = DecodeOptions(
        width: 512,
        height: 512,
        bitsAllocated: 16,
        bitsStored: 12,
        isSigned: false,
      );

      final result = await CodecRouter.decode(
        transferSyntaxUID: DicomTransferSyntaxes.jpeg2000Lossless,
        frameBytes: j2kFixtureBytes,
        options: options,
      );

      expect(result.width, 512);
      expect(result.height, 512);
      expect(result.bitsAllocated, 16);
      expect(result.pixelData, isA<Uint16List>());

      final pixels = result.pixelData as Uint16List;
      expect(pixels.length, 512 * 512);

      final frame = PixelFrame(
        rawPixels: pixels,
        width: 512,
        height: 512,
        bitsAllocated: 16,
        bitsStored: 12,
      );

      final rgba = VoiLut.applyVoiLut(frame: frame, windowCenter: 2048.0, windowWidth: 4096.0);
      expect(rgba.length, 512 * 512 * 4);

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(rgba, 512, 512, ui.PixelFormat.rgba8888, completer.complete);
      final image = await completer.future;
      expect(image.width, 512);
      expect(image.height, 512);
      image.dispose();
    });
  });
}

