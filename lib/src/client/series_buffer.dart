import 'dart:typed_data';
import 'package:dicom_web_kit/src/codecs/codec_router.dart';
import 'package:dicom_web_kit/src/codecs/decoder_interface.dart';
import 'package:dicom_web_kit/src/imaging/pixel_frame.dart';
import 'qido_models.dart';

/// In-memory buffer for a single downloaded DICOM frame payload.
class DicomFrameBuffer {
  final int frameIndex;
  final int instanceNumber;
  final String sopInstanceUID;
  final Uint8List rawBytes;
  final DicomInstanceSummary metadata;

  DicomFrameBuffer({
    required this.frameIndex,
    required this.instanceNumber,
    required this.sopInstanceUID,
    required this.rawBytes,
    required this.metadata,
  });

  /// Decodes this frame into a [PixelFrame] preserving 16-bit scalar pixel buffers.
  Future<PixelFrame> toPixelFrame() async {
    final transferSyntax = metadata.transferSyntaxUID ?? DicomTransferSyntaxes.explicitVRLittleEndian;
    final options = DecodeOptions(
      width: metadata.rows,
      height: metadata.columns,
      bitsAllocated: metadata.bitsAllocated,
      bitsStored: metadata.bitsStored,
      isSigned: metadata.isSigned,
      photometricInterpretation: metadata.photometricInterpretation,
    );

    final decodeResult = await CodecRouter.decode(
      transferSyntaxUID: transferSyntax,
      frameBytes: rawBytes,
      options: options,
    );

    return PixelFrame(
      rawPixels: decodeResult.pixelData,
      width: decodeResult.width,
      height: decodeResult.height,
      rescaleSlope: metadata.rescaleSlope,
      rescaleIntercept: metadata.rescaleIntercept,
      photometricInterpretation: metadata.photometricInterpretation,
      bitsAllocated: decodeResult.bitsAllocated,
      bitsStored: decodeResult.bitsStored,
      isSigned: decodeResult.isSigned,
    );
  }
}

/// In-memory storage container for a downloaded DICOM series and its frames.
class DicomSeriesBuffer {
  final DicomStudy? study;
  final DicomSeries series;
  final List<DicomFrameBuffer> frames;
  final int totalExpectedInstances;
  final bool isComplete;

  DicomSeriesBuffer({
    this.study,
    required this.series,
    required this.frames,
    required this.totalExpectedInstances,
    required this.isComplete,
  });

  /// Total number of frames currently in buffer.
  int get frameCount => frames.length;

  /// Retrieves frame buffer at index.
  DicomFrameBuffer? getFrame(int index) {
    if (index < 0 || index >= frames.length) return null;
    return frames[index];
  }

  /// Decodes and returns the [PixelFrame] at index.
  Future<PixelFrame?> getPixelFrame(int index) async {
    final frame = getFrame(index);
    if (frame == null) return null;
    return await frame.toPixelFrame();
  }

  /// Clears in-memory frame buffers.
  void clear() {
    frames.clear();
  }
}

