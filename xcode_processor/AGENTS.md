# Xcode Processor

A dedicated Elixir/Phoenix application for server-side xcresult processing, running on macOS.

## Architecture

The xcode processor runs on Scaleway Mac minis and accepts webhooks from the main Tuist server. When an xcresult archive is uploaded, the server sends a webhook to the processor, which:

1. Downloads the xcresult archive from S3
2. Extracts the .xcresult bundle
3. Parses via a Swift NIF (using xcresulttool and custom parsing logic)
4. Returns structured test data as JSON

## Development

```bash
cd xcode_processor
mix deps.get
mix phx.server  # Runs on port 4003
```

## Swift NIF

The native Swift NIF is in `native/xcresult_nif/`. To build:

```bash
cd native/xcresult_nif
swift build -c release --replace-scm-with-registry
# Copy the built dylib to priv/native/
```

The NIF requires macOS with Xcode installed, as it uses `xcresulttool` to parse xcresult bundles.

## Testing

```bash
mix test
```

## Platform

The `platform/` directory contains nix-darwin configuration for managing Scaleway Mac minis declaratively. Unlike the Linux processor which uses NixOS + Colmena, this uses nix-darwin and `darwin-rebuild switch` directly.
