# dicom_web_kit

Drop-in clinical medical imaging kit for Flutter Web & Desktop (Dart 3+ WasmGC, Skwasm/CanvasKit).

---

## Overview
`dicom_web_kit` is a zero-jank, high-performance DICOM medical image streaming and rendering library built for Flutter applications on web and desktop platforms. It provides direct WADO-RS / QIDO-RS DICOMweb streaming, WASM-powered Web Worker codec decoding for JPEG 2000 / HTJ2K off the main UI isolate, dynamic 16-bit scalar VOI LUT transformations, and interactive viewports with gesture controls and HUD overlays.

---

## Key Features & Architecture
- **Off-Thread Decoding**: Never decode large JPEG 2000 / HTJ2K DICOM frames on the main UI thread. All heavy decoding is dispatched to Web Workers (`web/j2k_worker.js`) running WASM OpenJPEG/OpenJPH builds via `package:web`.
- **Dynamic 16-Bit Scalar VOI LUT**: Raw pixel data is preserved in original scalar formats (`Int16List` / `Uint16List`). Modality Rescale (Slope/Intercept) and VOI LUTs (Window Center/Width) are computed dynamically during rendering without truncation.
- **WADO-RS Stream Processing**: Efficiently parses DICOMweb REST `multipart/related` streams into discrete frame arrays.
- **Skwasm / CanvasKit Viewport**: High-performance Flutter `DicomViewport` widget featuring smooth pan, zoom, and window level gestures.

---

## Quick Start

Add `dicom_web_kit` to your `pubspec.yaml`:

```yaml
dependencies:
  dicom_web_kit: ^0.1.0
```

### Basic Viewport Usage

```dart
import 'package:flutter/material.dart';
import 'package:dicom_web_kit/dicom_web_kit.dart';

class MedicalViewerPage extends StatefulWidget {
  const MedicalViewerPage({super.key});

  @override
  State<MedicalViewerPage> createState() => _MedicalViewerPageState();
}

class _MedicalViewerPageState extends State<MedicalViewerPage> {
  late final ViewportController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ViewportController();
    _loadSampleFrame();
  }

  void _loadSampleFrame() {
    // 16-bit scalar pixel buffer (512x512)
    final rawPixels = Int16List(512 * 512);
    final frame = PixelFrame(
      rawPixels: rawPixels,
      width: 512,
      height: 512,
      rescaleSlope: 1.0,
      rescaleIntercept: -1024.0,
    );

    _controller.setFrame(frame);
    _controller.updateMetadata(
      patientName: 'DOE^JOHN',
      patientId: '123456',
      studyDescription: 'CT CHEST WITH CONTRAST',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DICOM Web Kit Viewer')),
      body: DicomViewport(
        controller: _controller,
        showOverlay: true,
      ),
    );
  }
}
```

---

## Document Walkthrough (Regulatory & Quality System)

To minimize regulatory friction for downstream medical device integrators seeking FDA 510(k) clearance or CE Mark (IEC 62304 / ISO 14971 / ISO 13485 compliance), `dicom_web_kit` provides formal documentation suites categorized by prefix:
- **`gsd_XXX` (`d` for Design Controls)** under [`docs/design/`](./docs/design/)
- **`gsp_XXX` (`p` for Procedures / SOPs)** under [`docs/procedures/`](./docs/procedures/)

### Design Controls (`gsd_XXX`)

| Document | Regulatory Standard | Description |
| :--- | :--- | :--- |
| **[gsd_000: Software Requirements Specification](./docs/design/gsd_000_software_requirements_spec.md)** | IEC 62304 Cl. 5.2 | Functional specifications, DICOM Transfer Syntaxes, 16-bit scalar preservation, performance benchmarks, and NEMA PS3.14 GSDF display rules. |
| **[gsd_010: System Design Specification](./docs/design/gsd_010_system_design_specification.md)** | IEC 62304 Cl. 5.3 / 5.4 | Software Architecture Description (SAD), subsystem decomposition (`client`, `codecs`, `imaging`, `widgets`), Web Worker thread boundaries, and VOI LUT equations. |
| **[gsd_020: Hazard Analysis & Risk Management](./docs/design/gsd_020_hazard_analysis_risk_management.md)** | ISO 14971:2019 / IEC 62304 Cl. 7 | Software Hazard Analysis Matrix identifying clinical hazards (detail loss, MONOCHROME1 inversion, WASM crashes) and software design risk controls. |
| **[gsd_030: Verification & Validation Plan](./docs/design/gsd_030_verification_and_validation_plan.md)** | IEC 62304 Cl. 5.5 - 5.7 | Verification test protocols across unit tests, browser Web Worker interop, and TG18 / SMPTE visual rendering accuracy validation. |
| **[gsd_040: Traceability Matrix](./docs/design/gsd_040_traceability_matrix.md)** | FDA Design Controls | Bi-directional matrix mapping **Requirements (SRS) <-> System Design (SDS) <-> Hazards (ISO 14971) <-> Verification Tests (V&V)**. |
| **[gsd_050: Cybersecurity & SOUP BOM](./docs/design/gsd_050_cybersecurity_and_soup_bom.md)** | FDA Cybersecurity Guidance | Software Bill of Materials (SBOM) for SOUP components (OpenJPEG WASM, Dart SDK, `package:web`), threat modeling, and PHI privacy rules. |

### Standard Operating Procedures (`gsp_XXX`)

| Document | Regulatory Standard | Description |
| :--- | :--- | :--- |
| **[gsp_000: Software Development Procedure](./docs/procedures/gsp_000_software_development_procedure.md)** | IEC 62304 Cl. 5 / ISO 13485 Cl. 7.3 | Standard Operating Procedure defining Safety Class B lifecycle phases, unit/integration verification, ISO 14971 risk controls, and release criteria. |

---

## Directory Structure
- `lib/dicom_web_kit.dart`: Main public barrel export.
- `lib/src/client/`: WADO-RS / QIDO-RS REST client (`dicom_web_client.dart`) and multipart stream reader (`multipart_stream.dart`).
- `lib/src/codecs/`: Decoders, Web Worker WASM bridge (`wasm_worker_bridge.dart`), and codec router (`codec_router.dart`).
- `lib/src/imaging/`: 16-bit `PixelFrame`, dynamic `VoiLut` pipeline, and `WindowPresets`.
- `lib/src/widgets/`: Flutter `DicomViewport`, `ViewportController`, and HUD `Overlays`.
- `web/`: `j2k_worker.js`, `openjpegwasm.js`, and `openjpegwasm.wasm`.
- `docs/design/`: Design Controls & 510(k) compliance documentation suite.
- `docs/procedures/`: Standard Operating Procedures (SOPs) for medical device software development lifecycle.

---

## Medical & Diagnostic Disclaimer

> [!CAUTION]
> **NOT CERTIFIED FOR PRIMARY DIAGNOSTIC USE**
> 
> This software is provided for educational, research, software integration, or informational purposes only. It is **NOT** certified as a medical device and is **NOT** intended for primary diagnostic use, patient diagnosis, or clinical decision-making unless explicitly validated by the end user / integrator in accordance with applicable medical device regulatory standards (e.g., FDA 510(k), CE Mark under EU MDR, or local regulatory authorities).

---

## Contact & Ownership

- **Project Owner:** GoSmart.Health
- **Contact:** compliance@gosmart.health

---

## License
Apache License 2.0. See [`LICENSE`](./LICENSE) for full details.

