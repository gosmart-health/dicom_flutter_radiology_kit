# Changelog

All notable changes to `dicom_flutter_radiology_kit` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.0] - 2026-09-04

### Pre-Release Evaluation Version

Initial evaluation release of `dicom_flutter_radiology_kit` — a drop-in medical imaging toolkit for Flutter Web and Desktop targeting clinical review workflows, zero-jank 16-bit scalar VOI LUT rendering, and WADO-RS streaming.

#### Added
- **16-Bit Scalar VOI LUT Engine**:
  - Direct preservation of 16-bit `Uint16List`/`Int16List` scalar pixel values without lossy 8-bit down-casting.
  - Real-time dynamic Window Center ($C$) and Window Width ($W$) contrast mapping.
  - Modality LUT rescale intercept and slope transformations.
  - Standard clinical window presets (Soft Tissue, Bone, Lung, Brain, Abdomen, Angio).
- **Web Worker WASM Codec Architecture**:
  - Background Web Worker decoding (`web/j2k_worker.js`) running compiled WebAssembly (OpenJPEG/OpenJPH) for zero-jank frame rendering.
  - Multi-transfer-syntax support: JPEG 2000 (Lossless & Lossy), JPEG Baseline (8-bit), RLE PackBits (16-bit), and uncompressed RAW scalar frames.
  - Pure WasmGC and CanvasKit/Skwasm target compatibility using `package:web`.
- **Multimodal Viewport Interaction & Gestures**:
  - **Desktop PACS Mode:** Rapid one-handed mouse operation (Left Click Drag for W/L, Right Click Drag / Shift+Left Drag for Zoom, Middle Click Drag / Ctrl/Cmd+Left Drag for Pan, Wheel for slice navigation, Double Click for View Reset).
  - **Mobile & Tablet Touch Mode:** Native multi-touch conforming to Apple HIG (1-finger drag for W/L, 2-finger pinch for Zoom, 2-finger drag for Pan, double-tap for View Reset; avoids 3-finger OS gesture collisions).
  - Strict hard-edge viewport clipping (`ClipRect`) preventing pixel bleeding across grid cells.
  - Aspect-ratio-preserving auto-fit scale calculations with configurable margins/insets.
- **Multi-Viewport Layout Grid & Synchronized Stack Scrolling**:
  - Layout formats: [1, 2, 4, 9] on 1 grid arrangements (`1×1`, `1×2`, `2×2`, `3×3`).
  - Synchronized 1-slice stepping across grid slots during mouse wheel and gesture scrolling.
  - Clinical HUD overlays displaying patient demographics, series info, W/L levels, zoom percentage, and clinical frame index (`Img: X / Y`).
- **DICOMweb Client & QIDO-RS Study Browser**:
  - WADO-RS frame streaming with multipart/related byte-range response parsing.
  - QIDO-RS patient and study browser dialog with modality filtering, search, and server URL history persistence.
  - In-memory 16-bit `SeriesBuffer` caching with per-frame presentation state persistence and live synchronization hooks (`onPresentationChanged`) for downstream PACS integration (e.g., FirePACS).
- **Documentation & Verification**:
  - Clinical User Guide detailing desktop workstation and mobile touch interaction paradigms.
  - System Requirements Specification (SRS), System Design Specification (SDS), and Integration Specifications.
  - Automated test suite covering codecs, buffer streaming, gestures, VOI LUT rendering, and viewport auto-fitting (51 automated tests).
