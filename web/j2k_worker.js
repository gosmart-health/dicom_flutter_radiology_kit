/**
 * j2k_worker.js — Web Worker for DICOM J2K / HTJ2K, JPEG & RLE Decompression.
 *
 * Offloads compute-intensive JPEG 2000, JPEG, and RLE PackBits decoding from the main Dart/Flutter UI thread
 * to a dedicated Web Worker thread running OpenJPEG WASM, OffscreenCanvas, and typed-array RLE unpacking.
 */

try {
  importScripts('openjpegwasm.js');
} catch (e) {
  try {
    importScripts('../web/openjpegwasm.js');
  } catch (_) {}
}

let openjpegModule = null;
let j2kDecoder = null;

async function initWasm() {
  if (!openjpegModule) {
    if (typeof OpenJPEGWASM === 'function') {
      openjpegModule = await OpenJPEGWASM({
        locateFile: function(path, scriptDirectory) {
          if (path.indexOf('.wasm') !== -1) {
            return (scriptDirectory || '') + 'openjpegwasm.wasm';
          }
          return (scriptDirectory || '') + path;
        }
      });
      if (openjpegModule && openjpegModule.J2KDecoder) {
        j2kDecoder = new openjpegModule.J2KDecoder();
      }
    }
  }
}

/**
 * DICOM Part 5 Annex G RLE PackBits Decompressor in Web Worker.
 */
function decodeRlePackBits(bytes, width, height, bitsAllocated, isSigned) {
  const numPixels = width * height;
  if (bytes.length < 64) {
    const out = new ArrayBuffer(bytes.length);
    new Uint8Array(out).set(bytes);
    return { pixelData: out, width, height, isSigned, bitsAllocated };
  }

  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const numSegments = view.getUint32(0, true);
  if (numSegments < 1 || numSegments > 15) {
    const out = new ArrayBuffer(bytes.length);
    new Uint8Array(out).set(bytes);
    return { pixelData: out, width, height, isSigned, bitsAllocated };
  }

  const segmentOffsets = [];
  for (let s = 0; s < numSegments; s++) {
    segmentOffsets.push(view.getUint32((s + 1) * 4, true));
  }

  function unpackSegment(start, end, expectedLen) {
    const out = new Uint8Array(expectedLen);
    let outIdx = 0;
    let inIdx = start;
    while (inIdx < end && outIdx < expectedLen) {
      const n = bytes[inIdx++];
      if (n <= 127) {
        const count = n + 1;
        const copyLen = Math.min(count, end - inIdx, expectedLen - outIdx);
        out.set(bytes.subarray(inIdx, inIdx + copyLen), outIdx);
        inIdx += count;
        outIdx += copyLen;
      } else if (n >= 129) {
        const count = 257 - n;
        if (inIdx < end) {
          const val = bytes[inIdx++];
          const fillLen = Math.min(count, expectedLen - outIdx);
          out.fill(val, outIdx, outIdx + fillLen);
          outIdx += fillLen;
        }
      }
      // n === 128 (0x80) is no-op
    }
    return out;
  }

  const segments = [];
  for (let s = 0; s < numSegments; s++) {
    const start = segmentOffsets[s];
    const end = (s + 1 < numSegments) ? segmentOffsets[s + 1] : bytes.length;
    if (start >= bytes.length) break;
    segments.push(unpackSegment(start, Math.min(end, bytes.length), numPixels));
  }

  if (bitsAllocated > 8 && segments.length >= 2) {
    const msb = segments[0];
    const lsb = segments[1];
    const outBuffer = new ArrayBuffer(numPixels * 2);
    if (isSigned) {
      const out = new Int16Array(outBuffer);
      for (let i = 0; i < numPixels; i++) {
        const val = (msb[i] << 8) | lsb[i];
        out[i] = val > 32767 ? val - 65536 : val;
      }
    } else {
      const out = new Uint16Array(outBuffer);
      for (let i = 0; i < numPixels; i++) {
        out[i] = (msb[i] << 8) | lsb[i];
      }
    }
    return {
      pixelData: outBuffer,
      width,
      height,
      isSigned,
      bitsAllocated: 16
    };
  } else if (segments.length > 0) {
    const outBuffer = new ArrayBuffer(numPixels);
    new Uint8Array(outBuffer).set(segments[0]);
    return {
      pixelData: outBuffer,
      width,
      height,
      isSigned: false,
      bitsAllocated: 8
    };
  }

  const out = new ArrayBuffer(bytes.length);
  new Uint8Array(out).set(bytes);
  return { pixelData: out, width, height, isSigned, bitsAllocated };
}

self.onmessage = async function(e) {
  const { id, command, encodedBytes, width, height, isSigned, bitsAllocated } = e.data;

  if (command === 'init') {
    try {
      await initWasm();
      self.postMessage({ id, status: 'ready' });
    } catch (err) {
      self.postMessage({ id, status: 'error', message: err.message });
    }
    return;
  }

  if (command === 'decode') {
    const t0 = (typeof performance !== 'undefined') ? performance.now() : Date.now();
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

      const elapsed = ((typeof performance !== 'undefined' ? performance.now() : Date.now()) - t0).toFixed(1);
      console.log(`[DICOM-WORKER] Decoded J2K #${id} in ${elapsed}ms (${outBuffer.byteLength} bytes)`);

      self.postMessage(
        {
          id,
          status: 'success',
          pixelData: outBuffer,
          width: (frameInfo && frameInfo.width) ? frameInfo.width : (width || 512),
          height: (frameInfo && frameInfo.height) ? frameInfo.height : (height || 512),
          isSigned: (frameInfo && frameInfo.isSigned !== undefined) ? frameInfo.isSigned : isSigned,
          bitsAllocated: (frameInfo && frameInfo.bitsPerSample && frameInfo.bitsPerSample > 8) ? 16 : (bitsAllocated || 16)
        },
        [outBuffer]
      );
    } catch (error) {
      console.error(`[DICOM-WORKER] Error decoding J2K #${id}:`, error);
      try {
        if (j2kDecoder && j2kDecoder.delete) j2kDecoder.delete();
      } catch (_) {}
      try {
        if (openjpegModule && openjpegModule.J2KDecoder) {
          j2kDecoder = new openjpegModule.J2KDecoder();
        }
      } catch (_) {}

      self.postMessage({
        id,
        status: 'error',
        message: error.message || 'JPEG 2000 decoding failed in Web Worker'
      });
    }
    return;
  }

  if (command === 'decodeRle') {
    const t0 = (typeof performance !== 'undefined') ? performance.now() : Date.now();
    try {
      const inputBytes = (encodedBytes instanceof Uint8Array)
        ? encodedBytes
        : new Uint8Array(encodedBytes);

      const result = decodeRlePackBits(
        inputBytes,
        width || 512,
        height || 512,
        bitsAllocated || 16,
        Boolean(isSigned)
      );

      const elapsed = ((typeof performance !== 'undefined' ? performance.now() : Date.now()) - t0).toFixed(1);
      console.log(`[DICOM-WORKER] Decoded RLE #${id} in ${elapsed}ms`);

      self.postMessage(
        {
          id,
          status: 'success',
          pixelData: result.pixelData,
          width: result.width,
          height: result.height,
          isSigned: result.isSigned,
          bitsAllocated: result.bitsAllocated
        },
        [result.pixelData]
      );
    } catch (error) {
      console.error(`[DICOM-WORKER] Error decoding RLE #${id}:`, error);
      self.postMessage({
        id,
        status: 'error',
        message: error.message || 'RLE decoding failed in Web Worker'
      });
    }
    return;
  }

  if (command === 'decodeJpeg') {
    const t0 = (typeof performance !== 'undefined') ? performance.now() : Date.now();
    try {
      const inputBytes = (encodedBytes instanceof Uint8Array)
        ? encodedBytes
        : new Uint8Array(encodedBytes);

      const blob = new Blob([inputBytes], { type: 'image/jpeg' });
      if (typeof createImageBitmap === 'function') {
        const bmp = await createImageBitmap(blob);
        const canvas = (typeof OffscreenCanvas !== 'undefined')
          ? new OffscreenCanvas(bmp.width, bmp.height)
          : null;

        if (!canvas) {
          throw new Error('OffscreenCanvas not available in Web Worker');
        }

        const ctx = canvas.getContext('2d');
        ctx.drawImage(bmp, 0, 0);
        const imgData = ctx.getImageData(0, 0, bmp.width, bmp.height);
        const numPixels = bmp.width * bmp.height;
        const outBuffer = new ArrayBuffer(numPixels);
        const out = new Uint8Array(outBuffer);
        const data = imgData.data;
        for (let j = 0; j < numPixels; j++) {
          out[j] = data[j * 4];
        }
        if (bmp.close) bmp.close();

        const elapsed = ((typeof performance !== 'undefined' ? performance.now() : Date.now()) - t0).toFixed(1);
        console.log(`[DICOM-WORKER] Decoded JPEG #${id} in ${elapsed}ms`);

        self.postMessage(
          {
            id,
            status: 'success',
            pixelData: outBuffer,
            width: bmp.width,
            height: bmp.height,
            isSigned: false,
            bitsAllocated: 8
          },
          [outBuffer]
        );
      } else {
        throw new Error('createImageBitmap not supported in Web Worker');
      }
    } catch (error) {
      console.error(`[DICOM-WORKER] Error decoding JPEG #${id}:`, error);
      self.postMessage({
        id,
        status: 'error',
        message: error.message || 'JPEG decoding failed in Web Worker'
      });
    }
    return;
  }
};
