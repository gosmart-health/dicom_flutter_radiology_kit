# Design Controls & Regulatory Documentation

This directory contains the FDA 510(k) and IEC 62304 / ISO 14971 aligned Design Controls documentation suite for `dicom_web_kit`.

The documents are prefixed with `gsd_XXX` in recommended reading order (from requirements to design, risk, V&V, traceability, and cybersecurity).

---

> [!IMPORTANT]
> **Regulatory Intent & Quality Management Scope**
> 
> While this project closely follows best quality control and design control management practices (aligned with IEC 62304, ISO 14971, and FDA 21 CFR 820.30), the existence and structure of these documents do **not** claim or certify that this open-source software has been developed under an audited or certified Quality Management System (QMS).
> 
> These artifacts are provided to **minimize regulatory friction and accelerate technical documentation** for downstream medical device manufacturers, system integrators, and healthcare organizations who are adopting, extending, and validating this software for actual clinical use within their own accredited QMS.

---

## Document Walkthrough Index

| Document | Regulatory Standard | Description |
| :--- | :--- | :--- |
| **[gsd_000_software_requirements_spec.md](./gsd_000_software_requirements_spec.md)** | IEC 62304 Cl. 5.2 | **Software Requirements Specification (SRS)**: Functional specifications, DICOM Transfer Syntaxes, 16-bit scalar preservation, performance benchmarks, and NEMA PS3.14 GSDF display rules. |
| **[gsd_010_system_design_specification.md](./gsd_010_system_design_specification.md)** | IEC 62304 Cl. 5.3 / 5.4 | **System Design Specification (SDS / SAD)**: Subsystem decomposition (`client`, `codecs`, `imaging`, `widgets`), Web Worker thread boundaries, and VOI LUT equations. |
| **[gsd_020_hazard_analysis_risk_management.md](./gsd_020_hazard_analysis_risk_management.md)** | ISO 14971:2019 / IEC 62304 Cl. 7 | **Hazard Analysis & Risk Management**: Software Risk Matrix identifying clinical hazards (detail loss, MONOCHROME1 inversion, WASM crashes) and software design risk controls. |
| **[gsd_030_verification_and_validation_plan.md](./gsd_030_verification_and_validation_plan.md)** | IEC 62304 Cl. 5.5 - 5.7 | **Verification & Validation Plan**: Test protocols across unit tests, browser Web Worker interop, and TG18 / SMPTE visual rendering accuracy validation. |
| **[gsd_040_traceability_matrix.md](./gsd_040_traceability_matrix.md)** | FDA Design Controls | **Requirements Traceability Matrix (RTM)**: Bi-directional matrix mapping **Requirements (SRS) <-> System Design (SDS) <-> Hazards (ISO 14971) <-> Verification Tests (V&V)**. |
| **[gsd_050_cybersecurity_and_soup_bom.md](./gsd_050_cybersecurity_and_soup_bom.md)** | FDA Cybersecurity Guidance | **Cybersecurity & SOUP BOM**: Software Bill of Materials (SBOM) for SOUP components (OpenJPEG WASM, Dart SDK, `package:web`), threat modeling, and PHI privacy rules. |
