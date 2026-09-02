import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

void main() {
  group('Compression Mode & Transfer Syntaxes', () {
    test('DicomCompressionMode defines expected transfer syntaxes and accept headers', () {
      expect(DicomCompressionMode.raw.label, 'RAW');
      expect(DicomCompressionMode.raw.transferSyntaxUID, DicomTransferSyntaxes.explicitVRLittleEndian);
      expect(DicomCompressionMode.raw.acceptHeader, contains('application/octet-stream'));

      expect(DicomCompressionMode.jpeg2000Lossless.label, 'JPEG2000_LOSSLESS');
      expect(DicomCompressionMode.jpeg2000Lossless.transferSyntaxUID, DicomTransferSyntaxes.jpeg2000Lossless);
      expect(DicomCompressionMode.jpeg2000Lossless.acceptHeader, contains('1.2.840.10008.1.2.4.90'));

      expect(DicomCompressionMode.jpeg2000.label, 'JPEG2000');
      expect(DicomCompressionMode.jpeg2000.transferSyntaxUID, DicomTransferSyntaxes.jpeg2000Lossy);
      expect(DicomCompressionMode.jpeg2000.acceptHeader, contains('1.2.840.10008.1.2.4.91'));

      expect(DicomCompressionMode.rle.label, 'RLE');
      expect(DicomCompressionMode.rle.transferSyntaxUID, DicomTransferSyntaxes.rleLossless);
      expect(DicomCompressionMode.rle.acceptHeader, contains('1.2.840.10008.1.2.5'));

      expect(DicomCompressionMode.jpeg.label, 'JPEG');
      expect(DicomCompressionMode.jpeg.transferSyntaxUID, DicomTransferSyntaxes.jpegBaseline1);
      expect(DicomCompressionMode.jpeg.acceptHeader, contains('1.2.840.10008.1.2.4.50'));
    });

    test('CodecRouter decodes 16-bit RLE PackBits frames', () async {
      final builder = BytesBuilder();
      // 64-byte DICOM RLE Header: 16 uint32s
      final header = Uint32List(16);
      header[0] = 2; // 2 segments (MSB and LSB)
      header[1] = 64; // Segment 1 offset
      header[2] = 64 + 4; // Segment 2 offset (after 4 bytes of segment 1)

      builder.add(Uint8List.view(header.buffer));

      // Segment 1 (MSBs): Run-length 2 of 1, Run-length 2 of 3 (PackBits: -1, 1, -1, 3)
      // In PackBits: n = 257 - 2 = 255. Byte 255 followed by 1 -> yields [1, 1]
      builder.add([255, 1, 255, 3]);

      // Segment 2 (LSBs): Run-length 2 of 2, Run-length 2 of 4 (PackBits: 255, 2, 255, 4)
      builder.add([255, 2, 255, 4]);

      final rleBytes = builder.toBytes();

      const options = DecodeOptions(
        width: 2,
        height: 2,
        bitsAllocated: 16,
        bitsStored: 12,
        isSigned: false,
      );

      final result = await CodecRouter.decode(
        transferSyntaxUID: DicomTransferSyntaxes.rleLossless,
        frameBytes: rleBytes,
        options: options,
      );

      expect(result.pixelData, isA<Uint16List>());
      final list = result.pixelData as Uint16List;
      expect(list.length, 4);
      expect(list[0], 0x0102); // 258
      expect(list[1], 0x0102); // 258
      expect(list[2], 0x0304); // 772
      expect(list[3], 0x0304); // 772
    });
  });
}

