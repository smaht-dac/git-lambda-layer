#!/usr/bin/env bash
set -euo pipefail

. ./config.sh

if [ "${PUBLISH_REGIONS}" = "all" ]; then
  REGIONS=$(aws ssm get-parameters-by-path \
    --path /aws/service/global-infrastructure/services/lambda/regions \
    --query 'Parameters[].Value' --output text \
    | tr '[:blank:]' '\n' \
    | grep -v -e '^cn-' -e '^us-gov-' \
    | sort)
else
  REGIONS=$(echo "${PUBLISH_REGIONS}" | tr ',' '\n' | tr -d ' ')
fi

for region in ${REGIONS}; do
  echo "=== ${region} ==="
  aws lambda list-layer-versions \
    --region "${region}" \
    --layer-name "${LAYER_NAME}" \
    --query 'LayerVersions[*].{Version:Version,ARN:LayerVersionArn,Created:CreatedDate}' \
    --output table 2>/dev/null || echo "  (not published in ${region})"
done
