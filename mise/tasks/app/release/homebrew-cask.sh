#!/bin/bash
#MISE description="Triggers the GitHub Actions workflow to release a new version of the Homebrew cask."
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
WORKFLOW_ID="130356792"

# The cask this dispatches points straight at the release asset, so bumping it
# before the DMG is attached publishes a 404 to every `brew install --cask tuist`.
# That is how app@0.25.5 broke installs: the release completed, but the DMG never
# made it onto it.
DMG_URL="https://github.com/tuist/tuist/releases/download/app@$VERSION/Tuist.dmg"
if ! curl --fail --silent --show-error --location --head --output /dev/null "$DMG_URL"; then
    echo "Error: $DMG_URL is not downloadable. Refusing to point the cask at a missing asset." >&2
    exit 1
fi

# Trigger the workflow
curl --fail-with-body -v -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$OWNER/$REPO/actions/workflows/$WORKFLOW_ID/dispatches" \
  -d "{\"ref\": \"main\", \"inputs\": {\"version\": \"$VERSION\", \"sha256\": \"$SHA256\"}}"
