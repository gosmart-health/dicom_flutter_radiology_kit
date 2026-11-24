# dicom_flutter_radiology_kit

A Flutter Web library for DICOMweb streaming and 16-bit medical image rendering, with JPEG 2000 decoding offloaded to Web Workers.

## Documentation

Read the [documentation](https://gosmart.health/docs/dicom_flutter_radiology_kit/) for the quick start, architecture, and [DICOM conformance statement](https://gosmart.health/docs/dicom_flutter_radiology_kit/dicom_conformance_statement/).

To preview the documentation locally, install [uv](https://docs.astral.sh/uv/getting-started/installation/) and run from the repository root:

```sh
cd doc
uv sync
uv run zensical serve
```

Open the local address printed by Zensical (normally <http://127.0.0.1:8000/>). To build the static site instead, run `uv run zensical build` from `doc`.

## Medical disclaimer

This library is not a certified medical device and is not intended for primary diagnosis or clinical decision-making. Integrators are responsible for validation, risk management, and regulatory compliance before clinical deployment. See the [full disclaimer](https://gosmart.health/docs/dicom_flutter_radiology_kit/#medical-diagnostic-disclaimer-integrator-responsibility).

## License

Apache License 2.0. See [LICENSE](LICENSE).
