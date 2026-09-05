import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

void main() {
  test('VoiLut and ui.decodeImageFromPixels render 16-bit frames without RangeError', () async {
    // 512x512 16-bit scalar synthetic data
    final numPixels = 512 * 512;
    final uint16Data = Uint16List(numPixels);
    for (int i = 0; i < numPixels; i++) {
      uint16Data[i] = (i % 4096);
    }

    final frame = PixelFrame(
      rawPixels: uint16Data,
      width: 512,
      height: 512,
      rescaleSlope: 1.0,
      rescaleIntercept: -1024.0,
      bitsAllocated: 16,
      bitsStored: 12,
    );

    // Apply VOI LUT
    final rgbaBytes = VoiLut.applyVoiLut(
      frame: frame,
      windowCenter: 40.0,
      windowWidth: 400.0,
    );

    expect(rgbaBytes.length, 512 * 512 * 4);

    // Decode into ui.Image
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgbaBytes,
      512,
      512,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );

    final img = await completer.future;
    expect(img.width, 512);
    expect(img.height, 512);
    img.dispose();
  });
}

