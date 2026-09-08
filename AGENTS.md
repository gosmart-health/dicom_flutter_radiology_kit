# AGENTS.md — DicomFlutterRadiologyKit Project Guidelines

## Project Architecture & Tech Stack
- **Target:** Flutter Web & Desktop (Dart 3+ WasmGC, Skwasm/CanvasKit).
- **Core Package Scope:** Drop-in medical imaging kit (`dicom_flutter_radiology_kit`) focusing on clinical/embedded review, WADO-RS streaming, and zero-jank 16-bit rendering.
- Tooling: Always use `fvm`with the Dart and Flutter tooling and use the latest stable release
- **Key Constraints:**
  - Do NOT decode large J2K/HTJ2K frames on the main UI isolate. Offload to Web Workers (`web/j2k_worker.js`) running WASM (OpenJPEG/OpenJPH).
  - Do NOT cast 16-bit raw pixel streams directly to 8-bit. Always preserve `Int16List`/`Uint16List` scalar values and apply Modality/VOI LUTs dynamically.
  - Do NOT include full standard DICOM Part 6 data dictionaries in core bundles; use minimal static rendering tag constants.
  - Use `package:web` and modern Dart JS interop for all browser/worker bindings.

## GitHub Commit Style

### Antigravity Plug-In Bug

- What I know: There seems to be widely reported bug where when the plug-in presents "Accept" button, it also corrupts the git index file.
- Check when files are changed or altered if the index is correct and if not reset it before we can commit.
- I will remove this instruction when the bug is fixed.

### The 'dev' Branch is technically the 'main' branch for Developers

- When a "commit and PR" is requested we PR to 'dev' from a feature branch. If you are not sure, ask before committing.
- Often a user will forget to save the edits before requesting the commit. Remind us if you think we missed saving.
- Ensure that the commit message is clear and concise. 
- We should not be committing directly to the `dev` branch. If a commit is requested via a dev branch ask first before committing to it. This is to ensure that the changes are properly tested and reviewed before being merged into the main development branch.
