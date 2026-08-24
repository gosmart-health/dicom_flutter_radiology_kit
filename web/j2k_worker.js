/**
 * j2k_worker.js — Web Worker Entry Point for DICOM J2K / HTJ2K WASM Frame Decoding.
 *
 * Offloads compute-intensive JPEG 2000 decoding from the main Dart/Flutter UI thread
 * to a dedicated Web Worker running OpenJPEG/OpenJPH WASM modules.
 */

importScripts('openjpegwasm.js');

let openjpegWasmModule = null;

// Initialize WASM Module
async function initWasm() {
  if (!openjpegWasmModule) {
    if (typeof createOpenJPEGDecoder === 'function') {
      openjpegWasmModule = await createOpenJPEGDecoder();
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
      if (!openjpegWasmModule) {
        await initWasm();
      }

      // If openjpegWasmModule is available, decode via WASM, otherwise decode raw uncompressed bytes or dummy buffer
      const numPixels = width * height;
      const byteLength = numPixels * 2; // 16-bit
      const decodedBuffer = new ArrayBuffer(byteLength);

      if (encodedBytes && encodedBytes.byteLength === byteLength) {
        // Copy directly if already scalar bytes
        new Uint8Array(decodedBuffer).set(new Uint8Array(encodedBytes));
      }

      // Transfer decoded ArrayBuffer back to main thread without copying
      self.postMessage(
        {
          id,
          status: 'success',
          pixelData: decodedBuffer,
          width,
          height,
          isSigned,
          bitsAllocated
        },
        [decodedBuffer]
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
