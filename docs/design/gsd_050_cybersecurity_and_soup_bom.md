# Cybersecurity Profile & Software Bill of Materials (SBOM)

**Document ID:** SEC-DWK-001  
**Project:** `dicom_flutter_radiology_kit`  
**Regulatory Standard Alignment:** FDA Cybersecurity in Medical Devices Guidance (2023), IEC 62304 SOUP Evaluation  

---

## 1. Executive Summary & Security Model
This document details the Software Bill of Materials (SBOM), SOUP (Software of Unknown Provenance) risk management, cybersecurity controls, and privacy safeguards for `dicom_flutter_radiology_kit`.

---

## 2. Software Bill of Materials (SBOM) / SOUP Inventory

| Component Name | Version / Commit | License | Source / Repository | Purpose | SOUP Risk Assessment |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **OpenJPEG / OpenJPH (WASM)** | Modern Build | BSD-2-Clause | OpenJPEG / OpenJPH | Off-thread Web Worker WASM J2K decoding | Low risk; runs in sandboxed Web Worker context. |
| **`package:web`** | `^1.0.0` | BSD-3-Clause | `pub.dev/packages/web` | Browser DOM & Web Worker JS interop | Low risk; official Dart web interop bindings. |
| **`http`** | `^1.2.0` | BSD-3-Clause | `pub.dev/packages/http` | WADO-RS REST request execution | Low risk; core Dart team HTTP package. |
| **`typed_data`** | `^1.3.2` | BSD-3-Clause | `pub.dev/packages/typed_data` | Efficient binary array manipulation | Low risk; official Dart core package. |

---

## 3. Cybersecurity & Data Integrity Safeguards

### 3.1 Web Worker Sandboxing & Memory Safety
* WASM OpenJPEG execution is strictly encapsulated within a dedicated browser Web Worker (`web/j2k_worker.js`).
* Memory transfers rely on browser-native `ArrayBuffer` transferrables, preventing cross-isolate memory contamination.

### 3.2 Data Privacy (PHI Protection)
* `dicom_flutter_radiology_kit` does not write or cache Protected Health Information (PHI) or DICOM datasets to persistent local storage (e.g. IndexedDB, LocalStorage, or disk) by default.
* Raw pixel bytes exist solely in volatile memory during active session viewports.

### 3.3 Network Communication Security
* WADO-RS / QIDO-RS network calls rely on standard HTTPS/TLS encryption provided by the host environment or `DicomWebClient`.
