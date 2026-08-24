# Software Requirements Specification (SRS)

**Document ID:** SRS-DWK-001  
**Project:** `dicom_web_kit`  
**Regulatory Standard Alignment:** IEC 62304 Clause 5.2, FDA 21 CFR 820.30  

---

## 1. Scope & Purpose
This document specifies the functional, performance, display, and interface requirements for the `dicom_web_kit` library. Downstream medical device integrators can use this document as a baseline for software verification.

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
| **REQ-FUN-010** | Interactive Pan & Zoom | The system SHALL support pan and zoom gesture operations with viewport transformation updates. | High |

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
