# Changelog

All notable changes to `dicom_flutter_radiology_kit` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.3] - 2026-09-11

### Added
- **Presentation Creation Date & Time Support (`(0070,0082)` / `(0070,0083)`)**:
  - Parsed DICOM tags `(0070,0082)` (`PresentationCreationDate`) and `(0070,0083)` (`PresentationCreationTime`) into `DicomSeries`.
  - Formatted ISO timestamps (`presentationCreationDateTimeIso`) and generated numerical sort keys (`dateTimeSortKey`).
  - Enforced latest-to-oldest sorting for PR series returned by `DicomWebClient.querySeries`.
  - Formatted and rendered creation date and time subtitles on PR series cards in `QidoBrowserDialog`.
- **Explicit Web Platform Indexing**:
  - Declared `platforms: web:` in `pubspec.yaml` to restrict pub.dev indexer strictly to Flutter Web.

### Fixed
- **Multi-Frame GSPS Restoration**:
  - Fixed multi-frame presentation state loading in `example/lib/main.dart` and `AnnotationController`, ensuring individual frame states map strictly to their referenced frame (`fs.referencedFrameNumber - 1`) rather than aggregating onto Frame 0.
- **Per-Frame Display State Persistence**:
  - Preserved per-frame presentation parameters (Window Center, Window Width, Zoom, Pan Offset) in `ViewportController` and serialized them into binary DICOM Part 10 GSPS datasets (`GspsDicomEncoder`) for STOW-RS storage.

### Documentation
- Updated `README.md`, `doc/dicom_conformance_statement.md`, `doc/design/`, `doc/user_guide/user_guide.md`, `llms.txt`, and package doc comments to specify Flutter Web as the exclusive target platform.

## [0.0.2] - 2026-09-09

### Added
- **Native DICOM Part 10 GSPS Binary Encoder (`GspsDicomEncoder`)**:
  - Implemented compliant Part 10 DICOM file writer producing binary Grayscale Softcopy Presentation State (GSPS) storage SOP Class (`1.2.840.10008.5.1.4.1.1.11.1`) datasets (`application/dicom`).
  - Standard 128-byte preamble with ASCII `"DICM"` magic marker prefix.
  - Complete File Meta Information header (Group 0002) with Little Endian Explicit VR transfer syntax (`1.2.840.10008.1.2.1`), Media Storage SOP Class UID, and Media Storage SOP Instance UID.
  - Full module encapsulation: Patient Module, General Study Module, General Series Module, SOP Common Module, Presentation State Identification Module, Presentation State Relationship Module, Graphic Annotation Module (`0070,0001`), Graphic Layer Module (`0070,0060`), and Softcopy VOI LUT Module.
  - Serialization of graphic objects: `POLYLINE` (calipers, Cobb angles, open and closed polylines), `CIRCLE` (center & perimeter point pairs), `ELLIPSE` (4-point major/minor axes bounding points), and `TEXT` (`UnformattedTextValue` with anchor coordinates and bounding boxes).
- **STOW-RS Presentation State Store Client (`DicomWebClient.storePresentationState`)**:
  - Direct PACS/VNA persistence via DICOMweb STOW-RS REST standard.
  - Streams `multipart/related; type="application/dicom"` HTTP POST requests encapsulating binary GSPS Part 10 datasets to `/studies` and `/studies/{studyUID}` endpoints.
- **QIDO-RS Presentation State Retrieval & Dynamic Viewport Integration**:
  - Added `DicomWebClient.fetchSeriesPresentationStates` and `fetchPresentationStates` to fetch and parse GSPS JSON metadata (`application/dicom+json`) into native annotation objects.
  - Enhanced `QidoBrowserDialog` with dedicated presentation state badge styling and active `[Load & Apply Annotations]` action buttons on PR series cards.
  - Context-aware series matching (`currentLoadedSeries`) enabling instant annotation injection into active viewports without re-downloading image pixel frames.
- **Testing & Quality Verification**:
  - Added unit test suite `test/gsps_dicom_encoder_test.dart` verifying binary DICOM layout, preamble, DICM prefix, Little Endian Explicit VR tags, nested sequences, and graphic data geometries.
  - Added widget tests in `test/qido_browser_dialog_test.dart` verifying PR series rendering, button enablement, and annotation loading callbacks.
  - Added live integration test `test/live_mock_stow_wado_test.dart` validating full roundtrip STOW-RS store, QIDO-RS search, and WADO-RS retrieval against the mock DICOM server.

## [0.0.1] - 2026-09-08

### Added
- **Full DICOM Data Dictionary & Generator**:
  - Full attribute dictionary generated from the standard `innolitics/dicom-standard` (`attributes.json`) comprising 5,041 exact standard tags and 88 repeating group wildcard patterns (curves `50xx`, overlays `60xx`, `002031xx`).
  - Standardized `DicomTagInfo` model providing tag hex ID, formatted representation `(GGGG,EEEE)`, name, keyword, VR, VM, and retirement status.
  - Private tag identification and automatic classification for odd-numbered groups (Private Creator `(GGGG,0010-00FF)` and Private Data).
  - Generator script (`tool/generate_dicom_dictionary.dart`) and download script (`tool/update_dicom_dictionary.sh`) for automated dictionary maintenance.
- **DICOM Dump Service (`DicomDumpService`)**:
  - `DicomDumpService.dumpJson`: Generates enriched DICOM JSON with human-readable `"description"` metadata entries embedded.
  - `DicomDumpService.dump`: Flattens and parses DICOM metadata into structured `DicomDumpResult` and `DicomDumpEntry` models with formatted values (Person Names, Dates, Times, Sequences `SQ`).
  - Search and filtering across tags `(GGGG,EEEE)`, hex `GGGGEEEE`, keywords, attribute descriptions, or values.
- **DICOM Dump Widget & Modal Dialog**:
  - `DicomDumpWidget`: Reusable clinical metadata inspector with flat grid layout (`Tag`, `VR`, `VM`, `Description`, `Value`), live search toolbar, expandable sequence trees, and reactive `Stream<Map<String, dynamic>>` support.
  - `DicomDumpDialog.show`: Dark radiology-themed modal dialog with click-outside-to-dismiss (`barrierDismissible: true`).
  - Cross-platform file exports: "Download JSON" and "Download CSV" via `FileExporter` with native browser downloads on Web (`web.Blob` / `HTMLAnchorElement`) and clipboard fallback on Desktop/VM.
- **Viewer Toolbar Integration**:
  - Integrated "DICOM Dump" action button into the example app's top AppBar for instant inspection of the currently focused slice metadata.

### Fixed
- **Transfer Syntax Selection & Verification**:
  - Fixed issue where requesting RAW transfer syntax could inadvertently request JPEG 2000 Lossless.
  - Fixed JPEG 2000 Lossless decoding across Web Worker WASM bridge (`web/j2k_worker.js`) and ensured proper negotiation with PACS endpoints (such as Orthanc).

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
