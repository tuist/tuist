# Per-SDK binary cache reuse

## Problem

An external dependency's destinations are narrowed using the incoming consumer graph. Changing Workspace.swift from iOS plus macOS to iOS-only changes the old exact target hash, even if the iOS compiler inputs and usable binary slices are unchanged. Positional generate focus applied to the same incoming graph does not reproduce this difference.

## Identity and storage

Keep the exact hash for fallback and derive SDK-specific fingerprints from the effective compilation inputs and recursive dependency fingerprints. Supported SDKs are iOS device, iOS simulator, Catalyst, and macOS with standard architectures; unsupported/custom architecture configurations retain exact lookup.

Each SDK fingerprint defines a cache action, encoded with standard REAPI Action and Command messages plus a build-input descriptor. An ActionResult references a Tree containing that SDK's framework directory and its validated XCFramework plist descriptor. Files, directory messages, trees, and action inputs are stored by SHA-256 and byte size in CAS. The client uses ActionCache, FindMissingBlobs, and ByteStream services, with the same account and project authentication conventions as Bazel.

There is one action per SDK, rather than one index entry for every possible SDK subset. Shared file contents are uploaded once per digest; an iOS-only reader downloads only its required SDK trees and missing files. Action results are published after their blobs. The old generic KV compatibility index is removed.

## Local materialization

Warming still uses xcodebuild to validate and create the XCFramework. The storage adapter extracts SDK descriptors and trees from that result. On a hit, all required SDK actions must be present. The reader verifies blob digests, rejects unsafe directory entries and escaping symlinks, restores executable bits, and combines the selected slice directories with a merged Info.plist. It does not invoke xcodebuild during generation.

Materialized outputs are cached by their selected tree digests and reused on subsequent requests. CAS blobs and materialized outputs use the binary-cache budget; action metadata uses the support-cache budget. Missing or malformed cache data becomes a miss, with exact-hash lookup retained for historical artifacts.

Separately warmed iOS and macOS outputs can now compose into one XCFramework. An iOS-only publication still cannot satisfy a request needing an absent macOS action. Legacy module-cache mode remains unchanged and does not use this design.

## Validation

The workspace acceptance scenario warms both consumers, rewrites Workspace.swift to iOS-only, checks SDK action/CAS reuse and repeat-generation materialization reuse, and builds device and simulator consumers. Unit tests cover independent SDK publication, directional misses, shared-file deduplication, corrupt blobs, failed publication, versioned framework symlinks, and executable bits. A loopback gRPC test exercises the real REAPI transport, streaming and digest verification.

The loopback-Git reproduction exercises a real external Swift package: warming retains the assembled XCFramework locally, while narrower generation restores only the requested SDKs from CAS. Run it with `--expect-reuse` against the built CLI.
