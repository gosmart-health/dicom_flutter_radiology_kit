import 'dart:async';
import 'dart:typed_data';
import 'package:dicom_flutter_radiology_kit/src/codecs/codec_router.dart';
import 'package:dicom_flutter_radiology_kit/src/codecs/decoder_interface.dart';
import 'package:dicom_flutter_radiology_kit/src/imaging/pixel_frame.dart';
import 'qido_models.dart';

/// Represents a progressive frame event emitted as a series streams over the network.
class DicomProgressiveFrame {
  final int index;
  final int totalCount;
  final DicomFrameBuffer frameBuffer;
  final PixelFrame? predecodedPixelFrame;

  const DicomProgressiveFrame({
    required this.index,
    required this.totalCount,
    required this.frameBuffer,
    this.predecodedPixelFrame,
  });

  /// Returns the decoded [PixelFrame], utilizing predecoded instance if present.
  Future<PixelFrame> toPixelFrame() async =>
      predecodedPixelFrame ?? await frameBuffer.toPixelFrame();
}

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

/// In-memory storage container for a downloaded DICOM series and its frames with
/// dynamic progressive buffering and frame caching.
class DicomSeriesBuffer {
  final DicomStudy? study;
  final DicomSeries series;
  final List<DicomFrameBuffer> frames;
  int totalExpectedInstances;
  bool _isCompleteExplicit;
  final int maxCacheSize;

  final Map<int, PixelFrame> _decodedCache = {};
  final List<int> _lruKeys = [];
  final StreamController<DicomFrameBuffer> _frameAddedController =
      StreamController<DicomFrameBuffer>.broadcast();

  DicomSeriesBuffer({
    this.study,
    required this.series,
    required this.frames,
    required this.totalExpectedInstances,
    bool isComplete = false,
    this.maxCacheSize = 50,
  }) : _isCompleteExplicit = isComplete;

  /// Stream of frames added dynamically during progressive network retrieval.
  Stream<DicomFrameBuffer> get onFrameAdded => _frameAddedController.stream;

  /// Total number of frames currently in buffer.
  int get frameCount => frames.length;

  /// Whether all expected instances in this series have been received.
  bool get isComplete =>
      _isCompleteExplicit || (totalExpectedInstances > 0 && frames.length >= totalExpectedInstances);

  set isComplete(bool value) {
    _isCompleteExplicit = value;
  }

  bool _isDisposed = false;

  /// Whether this buffer has been disposed.
  bool get isDisposed => _isDisposed;

  /// Appends a newly retrieved frame buffer to memory.
  void addFrame(DicomFrameBuffer frame) {
    if (_isDisposed) return;
    frames.add(frame);
    if (!_frameAddedController.isClosed) {
      _frameAddedController.add(frame);
    }
  }

  /// Retrieves frame buffer at index.
  DicomFrameBuffer? getFrame(int index) {
    if (index < 0 || index >= frames.length) return null;
    return frames[index];
  }

  /// Pre-populates decoded [PixelFrame] cache for instantaneous cine scrubbing with LRU eviction.
  void cachePixelFrame(int index, PixelFrame frame) {
    if (_isDisposed) return;
    if (_decodedCache.containsKey(index)) {
      _lruKeys.remove(index);
    } else if (_lruKeys.length >= maxCacheSize) {
      final oldest = _lruKeys.removeAt(0);
      _decodedCache.remove(oldest);
    }
    _lruKeys.add(index);
    _decodedCache[index] = frame;
  }

  /// Decodes and returns the [PixelFrame] at index with in-memory caching.
  Future<PixelFrame?> getPixelFrame(int index) async {
    if (_isDisposed) return null;
    if (_decodedCache.containsKey(index)) {
      _lruKeys.remove(index);
      _lruKeys.add(index);
      return _decodedCache[index];
    }
    final frame = getFrame(index);
    if (frame == null) return null;
    final decoded = await frame.toPixelFrame();
    cachePixelFrame(index, decoded);
    return decoded;
  }

  /// Clears in-memory frame buffers and cached decoded pixels.
  void clear() {
    frames.clear();
    _decodedCache.clear();
    _lruKeys.clear();
  }

  /// Disposes internal broadcast stream controller.
  void dispose() {
    _isDisposed = true;
    _frameAddedController.close();
    clear();
  }
}
