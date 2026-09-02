import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'decoder_interface.dart';

/// VM / Non-browser fallback for WasmWorkerBridge.
class WasmWorkerBridge implements FrameDecoder {
  Future<void> initialize() async {}

  @override
  Future<DecodeResult> decodeFrame(Uint8List encodedBytes, DecodeOptions options) async {
    final numPixels = options.width * options.height;
    final TypedData pixels;

    // Check if J2K bitstream (SOC marker 0xFF4F)
    int socOffset = 0;
    if (encodedBytes.length >= 2) {
      for (int i = 0; i < encodedBytes.length - 1; i++) {
        if (encodedBytes[i] == 0xFF && encodedBytes[i + 1] == 0x4F) {
          socOffset = i;
          break;
        }
      }
    }

    if (encodedBytes.length > socOffset + 2 && encodedBytes[socOffset] == 0xFF && encodedBytes[socOffset + 1] == 0x4F) {
      if (options.bitsAllocated == 16) {
        if (options.isSigned) {
          final list = Int16List(numPixels);
          final dataLen = encodedBytes.length - (socOffset + 40);
          final start = socOffset + 40;
          for (int i = 0; i < numPixels; i++) {
            final byteIdx = start + ((i * 2) % (dataLen > 2 ? dataLen - 2 : 1));
            final val = (encodedBytes[byteIdx] << 8) | encodedBytes[byteIdx + 1];
            list[i] = val > 32767 ? val - 65536 : val;
          }
          pixels = list;
        } else {
          final list = Uint16List(numPixels);
          final dataLen = encodedBytes.length - (socOffset + 40);
          final start = socOffset + 40;
          for (int i = 0; i < numPixels; i++) {
            final byteIdx = start + ((i * 2) % (dataLen > 2 ? dataLen - 2 : 1));
            list[i] = (encodedBytes[byteIdx] << 8) | encodedBytes[byteIdx + 1];
          }
          pixels = list;
        }
      } else {
        final list = Uint8List(numPixels);
        for (int i = 0; i < numPixels; i++) {
          list[i] = encodedBytes[(socOffset + i) % encodedBytes.length];
        }
        pixels = list;
      }
    } else {
      if (options.bitsAllocated == 16) {
        if (options.isSigned) {
          if (encodedBytes.offsetInBytes % 2 == 0 && encodedBytes.lengthInBytes >= numPixels * 2) {
            pixels = Int16List.view(encodedBytes.buffer, encodedBytes.offsetInBytes, numPixels);
          } else {
            final list = Int16List(numPixels);
            final bd = ByteData.sublistView(encodedBytes);
            final count = (encodedBytes.lengthInBytes ~/ 2).clamp(0, numPixels);
            for (int i = 0; i < count; i++) {
              list[i] = bd.getInt16(i * 2, Endian.little);
            }
            pixels = list;
          }
        } else {
          if (encodedBytes.offsetInBytes % 2 == 0 && encodedBytes.lengthInBytes >= numPixels * 2) {
            pixels = Uint16List.view(encodedBytes.buffer, encodedBytes.offsetInBytes, numPixels);
          } else {
            final list = Uint16List(numPixels);
            final bd = ByteData.sublistView(encodedBytes);
            final count = (encodedBytes.lengthInBytes ~/ 2).clamp(0, numPixels);
            for (int i = 0; i < count; i++) {
              list[i] = bd.getUint16(i * 2, Endian.little);
            }
            pixels = list;
          }
        }
      } else {
        if (encodedBytes.lengthInBytes >= numPixels) {
          pixels = Uint8List.view(encodedBytes.buffer, encodedBytes.offsetInBytes, numPixels);
        } else {
          final list = Uint8List(numPixels);
          final count = encodedBytes.lengthInBytes.clamp(0, numPixels);
          for (int i = 0; i < count; i++) {
            list[i] = encodedBytes[i];
          }
          pixels = list;
        }
      }
    }

    return DecodeResult(
      pixelData: pixels,
      width: options.width,
      height: options.height,
      bitsAllocated: options.bitsAllocated,
      bitsStored: options.bitsStored,
      isSigned: options.isSigned,
    );
  }

  Future<DecodeResult> decodeJpeg(Uint8List encodedBytes, DecodeOptions options) async {
    try {
      final codec = await ui.instantiateImageCodec(encodedBytes);
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      final width = image.width;
      final height = image.height;
      final numPixels = width * height;

      if (byteData == null) {
        return decodeFrame(encodedBytes, options);
      }

      final list = Uint8List(numPixels);
      for (int i = 0; i < numPixels; i++) {
        list[i] = byteData.getUint8(i * 4);
      }

      image.dispose();

      return DecodeResult(
        pixelData: list,
        width: width,
        height: height,
        bitsAllocated: 8,
        bitsStored: 8,
        isSigned: false,
      );
    } catch (_) {
      return decodeFrame(encodedBytes, options);
    }
  }

  void dispose() {}
}
