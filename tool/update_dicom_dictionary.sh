#!/usr/bin/env bash
set -euo pipefail

# update_dicom_dictionary.sh
# Downloads the latest DICOM standard attributes.json from innolitics/dicom-standard
# and generates lib/src/dictionary/dicom_dictionary.g.dart

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ATTRIBUTES_URL="https://raw.githubusercontent.com/innolitics/dicom-standard/master/standard/attributes.json"
OUTPUT_JSON="${SCRIPT_DIR}/attributes.json"

echo "==> Downloading latest DICOM attributes.json from ${ATTRIBUTES_URL}..."
curl -fsSL "${ATTRIBUTES_URL}" -o "${OUTPUT_JSON}"

if [[ ! -s "${OUTPUT_JSON}" ]]; then
  echo "Error: Downloaded attributes.json is empty or failed to download."
  exit 1
fi

echo "==> Download complete ($(wc -c < "${OUTPUT_JSON}" | tr -d ' ') bytes)."
echo "==> Running Dart dictionary generator..."

cd "${ROOT_DIR}"
fvm dart run tool/generate_dicom_dictionary.dart "${OUTPUT_JSON}"

# Clean up downloaded JSON cache to keep repo lean
rm -f "${OUTPUT_JSON}"

echo "==> DICOM Data Dictionary generation complete!"

