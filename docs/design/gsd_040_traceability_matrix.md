# Requirements Traceability Matrix (RTM)

**Document ID:** RTM-DWK-001  
**Project:** `dicom_flutter_radiology_kit`  
**Regulatory Standard Alignment:** IEC 62304 Clause 5.1.1 / 5.2.6, FDA Design Controls  

---

## 1. Bi-Directional Traceability Overview
This matrix establishes complete bi-directional traceability linking **Software Requirements (SRS)** $\leftrightarrow$ **System Design Specs (SDS)** $\leftrightarrow$ **Software Hazards (ISO 14971)** $\leftrightarrow$ **Verification Test Suites (V&V)**.

---

## 2. Traceability Matrix

| Requirement ID | Software Requirement Description | Design Spec Module | Hazard ID | Risk Mitigation | Verification Test Method | Pass Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **REQ-FUN-001** | WADO-RS Streaming | `DicomWebClient` | - | Standard HTTP error handling | Unit test `dicom_web_client_test.dart` | Pass |
| **REQ-FUN-002** | Multipart Stream Parsing | `MultipartStreamReader` | HAZ-004 | Boundary parsing & buffer validation | Unit test `multipart_stream_test.dart` | Pass |
| **REQ-FUN-003** | Transfer Syntax Support | `CodecRouter` | HAZ-004 | Transfer syntax UID routing | Integration test `codec_router_test.dart` | Pass |
| **REQ-FUN-004** | Off-Thread WASM Decoding | `WasmWorkerBridge` / `j2k_worker.js` | HAZ-003 | Web Worker isolate decoupling | Chrome web test `wasm_worker_bridge_test.dart` | Pass |
| **REQ-FUN-005** | 16-Bit Scalar Data Preservation | `PixelFrame` | HAZ-001 | Preserve `Int16List`/`Uint16List` buffers | Unit test `pixel_frame_test.dart` | Pass |
| **REQ-FUN-006** | Modality Rescale ($m \cdot x + b$) | `PixelFrame` | HAZ-005 | Floating point rescale calculation | Unit test `pixel_frame_test.dart` | Pass |
| **REQ-FUN-007** | Dynamic VOI LUT (Window W/L) | `VoiLut` | HAZ-001 / HAZ-005 | Dynamic scalar lookup & bounds clamping | Unit test `voi_lut_test.dart` | Pass |
| **REQ-FUN-008** | Clinical Window Presets | `WindowPresets` | HAZ-005 | Pre-validated clinical Hounsfield values | Unit test `window_presets_test.dart` | Pass |
| **REQ-FUN-009** | Anatomical HUD Overlays | `ViewportOverlays` | HAZ-002 | Demographics, tags, & orientation markers | Widget test `overlays_test.dart` | Pass |
| **REQ-FUN-010** | Interactive Pan & Zoom | `DicomViewport` & `ViewportController` | HAZ-006 | Uniform matrix scale & pan transforms | Widget test `dicom_viewport_test.dart` | Pass |
| **REQ-REG-001** | MONOCHROME1 Inversion | `VoiLut` | HAZ-002 | Luminance inversion ($255 - x$) | Unit test `voi_lut_test.dart` | Pass |
