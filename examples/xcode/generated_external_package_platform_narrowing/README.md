# Versioned external package regression

This diagnostic fixture complements the automated `MultiplatformCacheAcceptanceTests`
workspace tests. It uses a real Git revision so it exercises SwiftPM's
`remoteSourceControl` classification and Tuist's revision-based external hashing.
A local package alone does not exercise that branch.

Run on Apple silicon with Xcode, its iOS SDKs, Git, Python 3.9+, and a Tuist binary
that includes module caching:

```sh
python3 reproduce.py --tuist /absolute/path/to/tuist --expect-reuse
```

The script copies this fixture into an isolated temporary directory, serves a
synthetic package through a Git daemon bound to `127.0.0.1`, and stops the daemon
on exit. It uses local caching (`--no-upload`), needs no hosted account, and retains
logs, artifacts, and `summary.json` in the printed evidence directory. Omitting
`--expect-reuse` checks the historical exact-hash behavior for comparison with an
older CLI.

The checks cover:

- A combined warm of `Shared` → `Leaf` for iOS device, simulator, and macOS.
- Positional focus on the unchanged incoming graph, which preserves its platform
  requirements, versus removing consumers before manifest loading, which changes
  the narrowed external graph.
- Reuse of the combined warm by each narrower graph, matching effective compiler
  settings per SDK, and actual device/simulator/macOS builds using those binaries.
- A negative case: an iOS-only warm cannot satisfy a required macOS SDK action.
- Distinct historical exact hashes with fixed Git revision and other inputs,
  including propagation of the leaf's platform-dependent hash to its parent.

The modern cache solves this with per-SDK REAPI actions and shared CAS file blobs.
Readers construct only the requested XCFramework slices locally. Products or
layouts without SDK-specific reuse use complete-output REAPI actions; historical
archives are cold misses. Explicit legacy mode retains its original behavior.

The automated workspace test additionally rewrites `Workspace.swift` from iOS +
macOS consumers to iOS-only and verifies substitution and builds. Keep this manual
fixture for the separate Git-revision hashing check, rather than duplicating the
full cache design or a dated validation report here.
