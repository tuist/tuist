#!/usr/bin/env bash
# mise description="Compile qa-agent as a macOS binary using Burrito"

set -euo pipefail

cd qa-agent

echo "Building qa-agent binary for macOS (Apple Silicon)..."

# Install dependencies
mix deps.get

# Build the release with Burrito
MIX_ENV=prod mix release qa_agent

# The binary will be in _build/prod/burrito_out/qa_agent_macos
if [ -f "_build/prod/burrito_out/qa_agent_macos" ]; then
    echo "✅ Successfully built qa-agent binary at: _build/prod/burrito_out/qa_agent_macos"
    
    # Copy to a conventional location
    mkdir -p build
    cp _build/prod/burrito_out/qa_agent_macos build/qa-agent
    echo "✅ Copied binary to: build/qa-agent"
else
    echo "❌ Failed to build qa-agent binary"
    exit 1
fi