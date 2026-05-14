#!/usr/bin/env bash
set -euo pipefail

. ./config.sh

echo "Building layer using image: ${BUILD_IMAGE}"
rm -f "${LAYER_ZIP}"

docker run --rm \
  --entrypoint bash \
  -v "${PWD}:/out" \
  "${BUILD_IMAGE}" \
  /out/build_layer.sh

echo ""
echo "Build complete: ${LAYER_ZIP}"
echo "Contents preview:"
unzip -l "${LAYER_ZIP}" | grep -E "(bin/git|bin/ssh|libexec/git-core/git-remote)" | head -10
