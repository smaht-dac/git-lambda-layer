#!/usr/bin/env bash
set -euo pipefail

. ./config.sh

[ -f "${LAYER_ZIP}" ] || { echo "ERROR: ${LAYER_ZIP} not found. Run build.sh first."; exit 1; }

ZIP_SIZE=$(stat -f%z "${LAYER_ZIP}" 2>/dev/null || stat -c%s "${LAYER_ZIP}")
MAX_DIRECT_BYTES=$((50 * 1024 * 1024))

DESCRIPTION="git and openssh binaries for Amazon Linux 2023 (Python 3.12 Lambda runtime)"

# Resolve the list of regions to publish to
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

# Decide whether to use S3 staging
USE_S3=false
S3_KEY=""
if [ -n "${S3_STAGING_BUCKET}" ] || [ "${ZIP_SIZE}" -gt "${MAX_DIRECT_BYTES}" ]; then
  USE_S3=true
  S3_KEY="layers/${LAYER_NAME}-$(date +%Y%m%d%H%M%S).zip"
  echo "Layer zip is ${ZIP_SIZE} bytes — uploading to s3://${S3_STAGING_BUCKET}/${S3_KEY}"
  aws s3 cp "${LAYER_ZIP}" "s3://${S3_STAGING_BUCKET}/${S3_KEY}"
fi

# Resolve account ID once upfront
ACCOUNT_ID="${AWS_ACCOUNT_ID}"
if [ -z "${ACCOUNT_ID}" ]; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

publish_region() {
  local region="$1"
  local layer_name="${LAYER_NAME}"
  local description="${DESCRIPTION}"
  local layer_zip="${LAYER_ZIP}"
  local principal="${LAYER_PRINCIPAL}"
  local account_id="${ACCOUNT_ID}"
  local use_s3="${USE_S3}"
  local s3_bucket="${S3_STAGING_BUCKET}"
  local s3_key="${S3_KEY}"

  echo "[${region}] Publishing layer..."

  local version
  if [ "${use_s3}" = "true" ]; then
    version=$(aws lambda publish-layer-version \
      --region "${region}" \
      --layer-name "${layer_name}" \
      --description "${description}" \
      --compatible-runtimes python3.12 \
      --compatible-architectures x86_64 \
      --content "S3Bucket=${s3_bucket},S3Key=${s3_key}" \
      --query Version --output text)
  else
    version=$(aws lambda publish-layer-version \
      --region "${region}" \
      --layer-name "${layer_name}" \
      --description "${description}" \
      --compatible-runtimes python3.12 \
      --compatible-architectures x86_64 \
      --zip-file "fileb://${layer_zip}" \
      --query Version --output text)
  fi

  echo "[${region}] Published version ${version}"

  # Grant cross-account access according to LAYER_PRINCIPAL
  if [ "${principal}" = "public" ]; then
    aws lambda add-layer-version-permission \
      --region "${region}" \
      --layer-name "${layer_name}" \
      --version-number "${version}" \
      --statement-id AllowPublicAccess \
      --action lambda:GetLayerVersion \
      --principal '*' > /dev/null
    echo "[${region}] Granted public access"

  elif [ "${principal}" = "none" ]; then
    echo "[${region}] No cross-account permission set (layer is private)"

  elif echo "${principal}" | grep -qE '^o-'; then
    # AWS Organization ID (starts with "o-")
    aws lambda add-layer-version-permission \
      --region "${region}" \
      --layer-name "${layer_name}" \
      --version-number "${version}" \
      --statement-id AllowOrgAccess \
      --action lambda:GetLayerVersion \
      --principal '*' \
      --organization-id "${principal}" > /dev/null
    echo "[${region}] Granted org access (${principal})"

  else
    # Treat as an AWS account ID
    aws lambda add-layer-version-permission \
      --region "${region}" \
      --layer-name "${layer_name}" \
      --version-number "${version}" \
      --statement-id AllowAccountAccess \
      --action lambda:GetLayerVersion \
      --principal "${principal}" > /dev/null
    echo "[${region}] Granted access to account ${principal}"
  fi

  echo "arn:aws:lambda:${region}:${account_id}:layer:${layer_name}:${version}"
}

export -f publish_region
export LAYER_NAME DESCRIPTION LAYER_ZIP LAYER_PRINCIPAL ACCOUNT_ID USE_S3 S3_STAGING_BUCKET S3_KEY

echo "Publishing to regions: $(echo "${REGIONS}" | tr '\n' ' ')"
echo ""

# Publish to all regions in parallel (up to 8 at a time)
echo "${REGIONS}" | xargs -P 8 -I{} bash -c 'publish_region "$@"' _ {}

echo ""
echo "Done. Use check.sh to list all published ARNs."
