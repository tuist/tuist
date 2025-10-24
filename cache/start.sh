#!/bin/bash
# Start script for cache service with environment variables

# S3 Configuration
export TUIST_S3_BUCKET_NAME="${TUIST_S3_BUCKET_NAME:-tuist-cache-bucket}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test-key}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test-secret}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
export TUIST_S3_ENDPOINT="${TUIST_S3_ENDPOINT}"
export TUIST_S3_VIRTUAL_HOST="${TUIST_S3_VIRTUAL_HOST:-false}"

# Start Phoenix server
mix phx.server