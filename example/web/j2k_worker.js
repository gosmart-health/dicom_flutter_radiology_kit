/**
 * j2k_worker.js — Web Worker for DICOM J2K / HTJ2K WASM Frame Decoding.
 *
 * Offloads compute-intensive JPEG 2000 decoding from the main Dart/Flutter UI thread
 * to a dedicated Web Worker running OpenJPEG WASM.
 */

importScripts('openjpegwasm.js');

let openjpegModule = null;
let j2kDecoder = null;

async function initWasm() {
  if (!openjpegModule) {
    if (typeof OpenJPEGWASM === 'function') {
      openjpegModule = await OpenJPEGWASM({
        locateFile: function(path) {
          if (path.indexOf('.wasm') !== -1) {
            return 'openjpegwasm.wasm';
          }
          return path;
        }
      });
      if (openjpegModule && openjpegModule.J2KDecoder) {
        j2kDecoder = new openjpegModule.J2KDecoder();
      }
    }
  }
}

self.onmessage = async function(e) {
  const { id, command, encodedBytes, width, height, isSigned, bitsAllocated } = e.data;

  if (command === 'init') {
    await initWasm();
    self.postMessage({ id, status: 'ready' });
    return;
  }

  if (command === 'decode') {
    try {
      if (!openjpegModule || !j2kDecoder) {
        await initWasm();
      }

      if (!openjpegModule || !j2kDecoder) {
        throw new Error('OpenJPEG WASM module failed to initialize');
      }

      const inputBytes = (encodedBytes instanceof Uint8Array)
        ? encodedBytes
        : new Uint8Array(encodedBytes);

      const encodedBuffer = j2kDecoder.getEncodedBuffer(inputBytes.length);
      encodedBuffer.set(inputBytes);
      j2kDecoder.decode();

      const frameInfo = j2kDecoder.getFrameInfo();
      const decodedRaw = j2kDecoder.getDecodedBuffer();

      // Copy into new transferable ArrayBuffer
      const outBuffer = new ArrayBuffer(decodedRaw.byteLength);
      new Uint8Array(outBuffer).set(decodedRaw);

      self.postMessage(
        {
          id,
          status: 'success',
          pixelData: outBuffer,
          width: (frameInfo && frameInfo.width) ? frameInfo.width : width,
          height: (frameInfo && frameInfo.height) ? frameInfo.height : height,
          isSigned: (frameInfo && frameInfo.isSigned !== undefined) ? frameInfo.isSigned : isSigned,
          bitsAllocated: (frameInfo && frameInfo.bitsPerSample && frameInfo.bitsPerSample > 8) ? 16 : (bitsAllocated || 16)
        },
        [outBuffer]
      );
    } catch (error) {
      self.postMessage({
        id,
        status: 'error',
        message: error.message || 'Decoding failed in Web Worker'
      });
    }
  }
};
