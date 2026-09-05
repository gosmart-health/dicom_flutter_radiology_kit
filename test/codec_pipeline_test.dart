import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';
import 'fixtures/fixture_bytes.dart';

void main() {
  group('Codec Pipeline Cross-Platform Unit Tests', () {
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
        frameBytes: TestFixtureBytes.rawFrame,
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

      final rgba = VoiLut.applyVoiLut(
        frame: frame,
        windowCenter: 2048.0,
        windowWidth: 4096.0,
      );

      expect(rgba.length, 512 * 512 * 4);
    });

    test('Decodes JPEG Process 1 (8-bit Baseline) frame fixture', () async {
      const options = DecodeOptions(
        width: 512,
        height: 512,
        bitsAllocated: 8,
        bitsStored: 8,
        isSigned: false,
      );

      final result = await CodecRouter.decode(
        transferSyntaxUID: DicomTransferSyntaxes.jpegBaseline1,
        frameBytes: TestFixtureBytes.jpegFrame,
        options: options,
      );

      expect(result.width, 512);
      expect(result.height, 512);
      expect(result.pixelData.lengthInBytes, greaterThanOrEqualTo(512 * 512));
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
        frameBytes: TestFixtureBytes.j2kFrame,
        options: options,
      );

      expect(result.width, 512);
      expect(result.height, 512);
      expect(result.pixelData.lengthInBytes, greaterThanOrEqualTo(512 * 512 * 2));
    });
  });
}
