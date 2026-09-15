# External package platform narrowing

This reproduction warms a versioned Swift package shared by an iOS framework and
a macOS executable, then generates each consumer. `Shared` depends on the `Leaf`
module, whose implementation uses `#if os(...)`. This exercises both a leaf key
and the propagation of that key into a dependent module.

## Run

Requires macOS on Apple silicon, Xcode with the iOS SDKs, Git, Python 3.9+, and a
Tuist executable that includes binary caching:

```sh
python3 reproduce.py --tuist /absolute/path/to/tuist
```

The runner copies the fixture to a fresh temporary directory and prints its
location. It creates a synthetic Git repository and serves only that repository
using a Git daemon bound to `127.0.0.1`; the daemon stops when the runner exits.
The loopback transport is deliberate: SwiftPM classifies file-based Git URLs as
`localSourceControl`, which Tuist hashes from source files. A Git URL exercises
the `remoteSourceControl` loader branch and revision-based external hashing.
No hosted project, credentials, remote cache, or published package is required.
The runner isolates Tuist's cache, configuration, and session directories and
uses `cache --no-upload`.

The default mode checks the original exact-hash behavior recorded below. To
check whether a binary reuses the combined artifact, use:

```sh
python3 reproduce.py --tuist /absolute/path/to/tuist --expect-reuse
```

The forward regression mode runs the same artifact compatibility and reverse
reuse checks, then fails if either narrower graph misses the combined warm.
It must not be made to pass by removing destination strings from all keys.

## What is checked

1. `tuist install` resolves the synthetic external package.
2. `tuist cache PhoneConsumer MacConsumer --cache-profile only-external --configuration Debug --no-upload`
   builds and stores `Leaf` and `Shared` with iOS device, iOS simulator, and macOS
   slices. Their actual XCFramework property lists are inspected.
3. With both consumers still present in `Project.swift`, focusing either one
   using positional `generate` arguments reuses both binaries. The generated
   project must reference both XCFrameworks.
4. `TUIST_CONSUMER_SCOPE=ios` or `macos` changes the manifest's target list before
   loading. Generation succeeds but does not reference either cached artifact.
5. With caching disabled, Xcode's effective compilation settings for `Shared`
   are compared per SDK between combined and narrower graphs. Relevant minimum
   deployment targets, compiler flags, architecture settings, module settings,
   and optimization settings must agree.
6. The fixture explicitly links copies of the **combined warmed artifacts**.
   Xcode builds the narrower consumers for iOS device, iOS simulator, and macOS.
   The macOS executable runs and checks its platform-specific result. This is
   an artifact compatibility check; cache entries are never renamed or aliased.
7. A fresh iOS-only cache contains no macOS slice. Generation from the combined
   graph must miss it, while the matching iOS-only graph must reuse it.
8. Session logs must show at least three distinct **external-project** hashes
   for each module. The revision, identity, settings and version inputs must stay
   fixed, the leaf must have no dependencies, and the parent's dependency hash
   must follow the leaf's key for the corresponding destination set. This prevents
   accidentally testing only local source hashing or an unrelated input change.

Each command has a log in the evidence directory. `summary.json` records cache
substitution results, distinct external hashes, inspected slices, and compared
compiler settings. These are entirely synthetic data. The temporary directory
is retained so build results and actual artifacts can be inspected.

## Validation snapshot

Validated on September 9, 2026 with Xcode 26.5 (17F42) and Apple Swift 6.3.2:

- Tuist 4.205.0: all workflow, compiler-setting, hash-input, artifact, and reverse
  reuse checks passed. `--expect-reuse` failed specifically at its final assertion
  that narrower graphs should reuse the combined warm.
- Tuist 4.208.0-canary.16: the same cache substitution behavior, per-SDK settings,
  artifact builds, and reverse reuse checks passed.
- Checkout `5335c929c79a515e2e804d7d246135acca7deb4f`: generated the targeted
  workspace with `tuist generate tuist TuistKit TuistKitTests ProjectDescription
  --no-open`, built the `tuist` scheme with `xcodebuild` and code signing disabled,
  then ran the final reproduction against that executable. All default-mode
  checks passed. Its CLI tree is identical to the locally recorded `origin/main`
  at `2cac7e4d4e7e89a5b49049f474105d9cc23f66ff`.
- The fixture's Swift files pass the repository's SwiftFormat configuration.

## Root cause

`ManifestGraphLoader` evaluates manifests and creates the graph before applying
graph mappers. Both warming preload and cache-enabled generation use the same
default project/workspace mappers. Positional focus arguments are applied later.

`ExternalProjectsPlatformNarrowerGraphMapper` derives external destinations by
propagating and unioning the destinations of local consumers through
`GraphTraverser.externalTargetSupportedDestinations()`. It also prunes deployment
targets for excluded platforms. Narrowing precedes focus in both cache warming
and generation, so focusing the same incoming graph preserves its destination
set. Loading a manifest with fewer platform consumers changes that set.

`TargetContentHasher` includes the sorted destinations in each external target's
key, alongside the package revision, target identity, settings, dependency
hashes, and cache/compiler version inputs. A leaf's destination change alters
its key and then its dependents' keys. `TargetsToCacheBinariesGraphMapper` requests
that exact key. It does not search for an artifact with a compatible superset of
slices. Warming puts all selected platforms into one XCFramework under the
combined key.

This is a cache reuse limitation across different incoming graphs. It is not a
disagreement between warming and generation about how to narrow the same graph.
The fixture makes the incoming graph difference explicit through a manifest
environment variable. For any real project, differing initial graphs alone do
not identify which manifest, environment value, workspace selection, checkout
state, or command wrapper caused the difference. Inspect those inputs before
attributing it to positional focus flags.

## Compatibility and fix boundary

The combined artifact is compatible with this fixture's narrower consumers:
SDK-specific compilation settings agree and Xcode links the actual slices.
This does not establish compatibility for every package or a previously built
artifact that has not been inspected.

Removing destinations would also collapse the reverse direction: an iOS-only
warm could satisfy a macOS lookup despite containing no macOS code. Keeping the
original broad package platforms in the hash has the same problem unless warming
always builds all of them, which would defeat platform narrowing and can attempt
platforms that the package cannot actually build for.

A general fix needs a directional compatibility contract. A platform-specific
artifact/key design must hash each platform's dependency closure and settings,
preserve macro host requirements and dependency conditions, validate SDK,
variant, architecture, deployment target and compiler compatibility, and handle
resource bundles separately. Alternatively, an indexed superset lookup must
prove those same inputs match before choosing an artifact. Filename aliases or
blindly trying broader destination hashes do not prove that.

For older clients, a practical workaround is to warm and generate with the same
manifest/environment/workspace scope, using positional focus only after loading;
another is to warm each genuinely different scope.

See [the implemented design](durable-fix.md) for SDK fingerprints that point to a
single combined XCFramework, compatibility checks, rollout boundaries, and the
automated acceptance test that rewrites `Workspace.swift`. The validation
snapshot above describes the original behavior, before that implementation.
