#!/usr/bin/env bash

# Name of the Lambda layer
export LAYER_NAME="git-lambda-al2023"

# Docker image used for build — must be the AL2023-based Lambda Python 3.12 image
export BUILD_IMAGE="public.ecr.aws/lambda/python:3.12"

# Output zip filename
export LAYER_ZIP="layer.zip"

# AWS regions to publish to.
# Use "all" to query SSM for all Lambda-enabled regions (excluding cn-* and us-gov-*).
# Use a comma-separated list for specific regions, e.g. "us-east-1,us-west-2,eu-west-1"
export PUBLISH_REGIONS="us-east-1"

# Layer sharing / cross-account access:
#   "public"                    — adds principal '*'  (any AWS account can use the layer)
#   "none"                      — no permission call  (private to your account only)
#   "<account-id>"              — share with one specific AWS account
#   "<id1>,<id2>,<id3>"         — share with multiple specific AWS accounts (comma-separated)
#   "<org-id>"                  — share with an AWS Organization (e.g. "o-abc123def456")
export LAYER_PRINCIPAL="none"

# S3 staging bucket for the layer zip (optional).
# Leave blank to use the Lambda API's direct --zip-file upload (works up to 50 MB).
# Set this if your layer.zip exceeds 50 MB: s3://${S3_STAGING_BUCKET}/layers/
export S3_STAGING_BUCKET=""

# AWS account ID that owns the layer.
# Leave blank to derive from "aws sts get-caller-identity" at publish time.
export AWS_ACCOUNT_ID=""
