#!/usr/bin/env bash
set -euo pipefail

. ./config.sh

[ -f "${LAYER_ZIP}" ] || { echo "ERROR: ${LAYER_ZIP} not found. Run build.sh first."; exit 1; }

echo "Unpacking ${LAYER_ZIP} into ./layer/ ..."
rm -rf layer
mkdir -p layer
unzip -q "${LAYER_ZIP}" -d layer

echo "Running integration test inside ${BUILD_IMAGE} ..."
docker run --rm \
  --entrypoint python3 \
  -v "${PWD}/layer:/opt" \
  -v "${PWD}/test:/var/task" \
  "${BUILD_IMAGE}" \
  /var/task/index.py

echo ""
echo "Test passed."
