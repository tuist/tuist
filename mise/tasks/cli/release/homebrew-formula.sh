#!/bin/bash
#MISE description="Triggers the GitHub Actions workflow to release a new version of the Homebrew formula."
set -eo pipefail

# Parse command line arguments
VERSION=""
GITHUB_TOKEN=""
SHA256=""

usage() {
    echo "Usage: $0 --version VERSION --github-token TOKEN --sha256 SHA256"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --version) VERSION="$2"; shift ;;
        --github-token) GITHUB_TOKEN="$2"; shift ;;
        --sha256) SHA256="$2"; shift ;;
        *) ;;
    esac
    shift
done

# Check if VERSION, GITHUB_TOKEN, and SHA256 are provided
if [ -z "$VERSION" ] || [ -z "$GITHUB_TOKEN" ] || [ -z "$SHA256" ]; then
    echo "Error: Missing required options."
    usage
fi

OWNER="tuist"
REPO="homebrew-tuist"
WORKFLOW_ID="90129194"

# Trigger the workflow
curl -v X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$OWNER/$REPO/actions/workflows/$WORKFLOW_ID/dispatches" \
  -d "{\"ref\": \"main\", \"inputs\": {\"version\": \"$VERSION\", \"sha256\": \"$SHA256\"}}"
