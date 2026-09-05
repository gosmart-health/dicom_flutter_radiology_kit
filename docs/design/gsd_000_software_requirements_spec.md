# Software Requirements Specification (SRS)

**Document ID:** SRS-DWK-001  
**Project:** `dicom_flutter_radiology_kit`  
**Regulatory Standard Alignment:** IEC 62304 Clause 5.2, FDA 21 CFR 820.30  

---

## 1. Scope & Purpose
This document specifies the functional, performance, display, and interface requirements for the `dicom_flutter_radiology_kit` library. Downstream medical device integrators can use this document as a baseline for software verification.

---

## 2. Functional Requirements (REQ-FUN)

| Requirement ID | Title | Description | Priority |
| :--- | :--- | :--- | :--- |
| **REQ-FUN-001** | WADO-RS Streaming | The system SHALL retrieve DICOM instance metadata and individual frame bytes via WADO-RS REST APIs. | High |
| **REQ-FUN-002** | Multipart Parsing | The system SHALL parse `multipart/related` HTTP response streams containing raw DICOM frame payloads. | High |
| **REQ-FUN-003** | Transfer Syntax Support | The system SHALL support Implicit VR Little Endian, Explicit VR Little Endian, JPEG 2000 (Lossless/Lossy), and HTJ2K. | High |
| **REQ-FUN-004** | Off-Thread Decoding | The system SHALL decode JPEG 2000 / HTJ2K frames in a Web Worker via WASM to prevent main UI isolate blocking. | High |
| **REQ-FUN-005** | 16-Bit Scalar Data Preservation | The system SHALL store raw pixel data in `Int16List` or `Uint16List` buffers without truncating to 8-bit. | High |
| **REQ-FUN-006** | Modality Rescale | The system SHALL apply Modality Rescale Slope and Intercept to raw pixel values before VOI LUT processing. | High |
| **REQ-FUN-007** | Dynamic VOI LUT | The system SHALL compute Window Center and Window Width transformations dynamically during display rendering. | High |
| **REQ-FUN-008** | Clinical Window Presets | The system SHALL provide pre-configured clinical window presets (Soft Tissue, Bone, Lung, Brain, Abdomen, Angio). | Medium |
| **REQ-FUN-009** | Anatomical HUD Overlays | The system SHALL display HUD overlays for patient demographic metadata, DICOM tags, orientation markers (A/P/L/R), and scale. | High |
| **REQ-FUN-010** | Desktop Multimodal Gestures | The system SHALL support desktop PACS mouse & modifier navigation conforming to general industrial PACS conventions: Left Click Drag for Window/Level ($\Delta x$ width, $\Delta y$ center/brightness), Right Click Drag or Shift+Left Drag for dynamic continuous Zoom (drag up = zoom in), Middle Click Drag or Ctrl/Cmd+Left Drag for Canvas Pan, Mouse Wheel for Series Stack Scrolling, and Double Click for View Reset. | High |
| **REQ-FUN-011** | Mobile Multi-Touch Gestures | The system SHALL support mobile/tablet touch gestures conforming to Apple iOS Human Interface Guidelines: 1-Finger Drag for Window/Level, 2-Finger Pinch/Spread for continuous Zoom around the touch centroid, 2-Finger Parallel Drag for Canvas Pan, and Double Tap for View Reset. | High |
| **REQ-FUN-012** | Gesture Collision Avoidance | The system SHALL avoid three-finger touch gestures on mobile to prevent collision with iOS system-level gestures (Copy, Paste, Undo) and OEM screenshot shortcuts. | Medium |

---

## 3. Performance & Quality Requirements (REQ-PERF)

| Requirement ID | Title | Performance Metric |
| :--- | :--- | :--- |
| **REQ-PERF-001** | Frame Rendering Latency | VOI LUT transformation and viewport draw SHALL complete within <16ms per frame (60 FPS rendering target). |
| **REQ-PERF-002** | Worker Initialization | Web Worker initialization SHALL complete within <500ms on modern browser engines. |
| **REQ-PERF-003** | Zero-Jank UI | Main UI isolate framing rate SHALL maintain >55 FPS during background Web Worker frame decoding. |

---

## 4. Regulatory & Display Standards Compliance (REQ-REG)

| Requirement ID | Standard | Requirement Description |
| :--- | :--- | :--- |
| **REQ-REG-001** | NEMA PS3.14 / GSDF | Image rendering SHALL support MONOCHROME1 and MONOCHROME2 Photometric Interpretations cleanly. |
| **REQ-REG-002** | DICOM Part 18 | WADO-RS / QIDO-RS client SHALL comply with DICOM Part 18 web services specifications. |

| **REQ-FUN-013** | Multi-Viewport Grid Layouts | The system SHALL support [1, 2, 4, 9] on 1 layout formats (1×1, 1×2, 2×2, 3×3) with synchronized frame offset stepping, allowing stack navigation to advance 1 slice across all visible cells concurrently. | High |
| **REQ-FUN-014** | Per-Frame Presentation State Persistence | The system SHALL maintain and expose presentation state parameters (Window Center, Window Width, Zoom, Pan Offset) per individual frame/instance with hooks for session restoration and live multi-user synchronization. | High |
| **REQ-FUN-015** | Frame Index HUD Display | The system HUD overlay SHALL render the active frame index and series total in the bottom-right corner (e.g. `Img: 2 / 128`). | High |
