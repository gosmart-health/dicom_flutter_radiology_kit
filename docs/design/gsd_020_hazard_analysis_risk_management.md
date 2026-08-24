# Hazard Analysis & Software Risk Management Plan

**Document ID:** RMF-DWK-001  
**Project:** `dicom_web_kit`  
**Regulatory Standard Alignment:** ISO 14971:2019, IEC 62304 Clause 7, FDA SaMD Safety Guidance  

---

## 1. Risk Management Framework
This document provides a Software Hazard Analysis for `dicom_web_kit`. It identifies potential software hazards associated with DICOM image decoding, memory manipulation, and viewport rendering, along with software risk control measures implemented in the architecture.

---

## 2. Hazard Analysis Matrix

| Hazard ID | Hazard Description | Cause / Trigger | Potential Severity | Initial Risk | Software Risk Mitigation (Design Control) | Residual Risk | Verification Method |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **HAZ-001** | **Diagnostic Detail Loss** (Premature 8-bit Quantization) | Converting 16-bit scalar pixel buffers directly to 8-bit before applying VOI LUT. | Critical | High | **Design Control:** Maintain raw 16-bit scalar data (`Int16List`/`Uint16List`) in `PixelFrame`. VOI LUT is computed dynamically on full scalar range during render pass. | Negligible | Unit test `PixelFrame` precision & dynamic LUT conversion tests. |
| **HAZ-002** | **Anatomical Inversion** (MONOCHROME1 misinterpretation) | Failing to invert luminance for MONOCHROME1 images, leading to inverted bone/air representation. | High | Medium | **Design Control:** `VoiLut.applyVoiLut()` checks `photometricInterpretation` tag and automatically applies $255 - \text{displayVal}$ inversion. | Negligible | Automated rendering test with MONOCHROME1 test datasets. |
| **HAZ-003** | **UI Freeze / Main Isolate Stutter** | Heavy JPEG 2000 frame decoding executed directly on main UI isolate thread. | Moderate | Medium | **Design Control:** All J2K/HTJ2K decoding is delegated to off-isolate Web Workers (`j2k_worker.js`) via `WasmWorkerBridge`. | Negligible | FPS performance benchmark tests under full decoding loads. |
| **HAZ-004** | **WASM Memory Crash / Corrupted Frame** | Malformed J2K payload or WASM heap overflow in `openjpegwasm.wasm`. | High | Medium | **Design Control:** Worker catches decoding exceptions, returns structured error messages, and prevents invalid buffer rendering. | Negligible | Fuzz testing codec input with invalid payload chunks. |
| **HAZ-005** | **Incorrect Window/Level Computation** | Integer overflow or division by zero when Window Width $W < 1.0$. | High | Medium | **Design Control:** `VoiLut` clamps $W \ge 1.0$ and handles scalar scaling with floating point bounds checking. | Negligible | Boundary test cases for $W \le 0$, negative center $C$, and extreme slope/intercept values. |
| **HAZ-006** | **Aspect Ratio / Spatial Distortion** | Incorrect image scaling or viewport stretching distorts anatomical proportions. | High | High | **Design Control:** `_ViewportPainter` applies uniform scaling transforms based on image dimensions and viewport aspect ratios. | Negligible | Visual regression testing against TG18 test patterns. |

---

## 3. Risk Management Conclusion
All identified hazards have been mitigated through software design controls. The residual risk for `dicom_web_kit` components is assessed as **acceptable** for medical image visualization.
