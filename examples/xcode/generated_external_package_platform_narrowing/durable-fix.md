# Durable fix: cache build variants independently

Status: proposed implementation design, grounded in the runnable reproduction
in this directory. This document does not change the production cache format.

## Decision

Make a target's **SDK-specific build artifact** the unit of remote caching.
Give every artifact an immutable key computed from the build recipe and the
dependency artifacts for that SDK. Keep the existing graph platform narrowing;
it determines which artifacts a command requires, without becoming a global
input to every artifact's identity.

An iOS/macOS warm then publishes these independent entries:

```text
Shared / iOS device     -> Leaf / iOS device
Shared / iOS simulator  -> Leaf / iOS simulator
Shared / macOS         -> Leaf / macOS
```

An iOS-only generation requests the first two entries. A macOS-only generation
requests the third. Their keys are identical to the corresponding entries from
the combined warm. Generation assembles the requested binary slices into a
local XCFramework so existing linking behavior remains familiar.

There is no search over destination supersets and no mutable "available
platforms" object. Independently warming iOS and macOS fills the same entries
that a combined warm would produce, regardless of order or concurrency.

## Identity contract

Introduce a `CacheBuildVariant` separate from `Destination` and `PlatformFilter`.
The existing platform filter cannot distinguish iOS device from simulator.
Variants distinguish SDK and environment: iOS device, iOS simulator, native
macOS, Mac Catalyst, and the corresponding supported tvOS/watchOS/visionOS
variants. Macro executables use an explicit macOS host build context.

A canonical, versioned recipe determines each key:

```text
artifactKey = H(encode(
    binaryFormatVersion,
    productKind,
    targetIdentity,
    sourceIdentity,
    buildVariant,
    compilerAndSDKIdentity,
    architecturePolicy,
    configuration,
    canonicalBuildInputs,
    orderedDependencyArtifactKeys
))
```

Use an unambiguous canonical encoding, with stable ordering and explicit fields.
The transport can retain the currently supported digest representation; changing
the digest algorithm is not required to solve this bug.

`canonicalBuildInputs` includes the settings and inputs emitted for this build:
the relevant deployment target, device-family settings, package traits and
aliases, compile flags, module maps and headers, generated source/accessor
contents, Info.plist/resource inputs, linkage, and supported script inputs.
Preserve the source/revision identity protections of the current hashers.
The external-revision shortcut alone is insufficient to describe generated
inputs or a platform build recipe.

Do not remove destination information indiscriminately. Values that affect the
selected build remain in its recipe. For example, changing device-family
settings may change asset compilation. Native macOS availability is not an
input to an iOS compilation simply because another consumer happens to exist.

The `CacheBuildPlan` must drive **both hashing and warming**. In particular,
normalize and emit the variant's supported SDK settings in that plan, then build
that plan. Hashing a projected iOS graph while compiling an independently
constructed combined graph would leave another hash/build mismatch.

Avoid requiring `xcodebuild -showBuildSettings` per target during generation.
Share the generator's settings/input construction with the plan builder, and
include the Xcode/compiler/SDK identity to account for toolchain defaults.
Retain unresolved xcconfig expressions and their input contents conservatively;
do not claim that two build recipes are equivalent by stripping unfamiliar
settings. The acceptance tests compare actual Xcode settings to validate this
shared implementation.

## Dependency hashing needs a build context

Memoize traversal by `(target reference, build context)`, rather than by target
reference alone. Evaluate dependency conditions in the current context before
selecting dependency artifacts. For example:

```text
Shared[iOS] -> Leaf[iOS]
Shared[iOS] -> Macro[macOS host] -> MacroSupport[macOS host]
Shared[macOS] -> Leaf[macOS]
```

This matters when a library is used both at runtime and through a macro in the
same graph. Globally projecting one graph to iOS cannot correctly represent
those two contexts. A macOS-only dependency must not enter the iOS runtime
dependency hash; a macro's macOS dependencies must not be projected away.

The existing `GraphHashedTarget` and `GraphContentHasher` memoization have no
build-context dimension. Add a binary-artifact planning/hash layer with that
dimension; reuse the lower-level source/settings/resource hashers. Keep generic
graph hashing and selective-testing behavior separate from this change.

Use the preserved graph with sources to derive identities. Use the mapped
generation graph to determine required variants. Do not hash an already
substituted binary dependency as if it were the source target's recipe. Preserve
the existing focus semantics; changing when focus runs is not necessary for
this fix.

## Warming and lookup

1. Derive the required build actions and dependency closure from the shared plan.
2. Batch-fetch their exact `(name, artifactKey)` entries.
3. Build only missing actions, grouped into schemes by SDK/variant. A missing
   macOS artifact must not cause an existing iOS artifact to be rebuilt.
4. Validate each output against its planned SDK, variant, architectures, product
   identity, and deployment target. Publish that artifact under its planned key.
5. Store independently completed artifacts so an interrupted warm retains useful
   completed work. Never publish an incomplete artifact or mark an unsuccessful
   upload as remotely available.

The existing `CacheStorableItem` protocol already identifies objects by name
and hash and supports batches. It can address several variant entries with the
same target name. No new server-side superset index or database table is needed
for this strategy. Audit client helpers that assume one result per target and
batch sizes that now contain more entries.

Initially, replace a target during generation only when **every required
variant and the replaceable dependency closure** is available and validated.
Otherwise keep that target in source. This deliberately preserves whole-target
replacement; platform-dependent mixtures of source and binaries are a separate
optimization, not a prerequisite for reuse across narrower graphs.

The consequences are deterministic:

| Available artifacts | Requested graph | Result |
| --- | --- | --- |
| iOS device, simulator, macOS | iOS only | Reuse iOS artifacts |
| iOS device, simulator, macOS | macOS only | Reuse macOS artifact |
| iOS device, simulator | iOS and macOS | Keep target in source; warming builds missing macOS actions |
| iOS and macOS warmed separately | iOS and macOS | Reuse both |
| iOS simulator only | iOS device and simulator | Keep target in source |
| Any variant with different compiler/settings/dependencies | That variant | Miss |

Keep target-level hit reporting conservative: a partial artifact hit is not a
successful target replacement. The aggregate of requested keys may identify a
local assembly or a logical target request, but it must never be used as a remote
artifact lookup key. This design does not include the separate diagnostic-input
reporting work.

## Artifact layout and local assembly

For frameworks/libraries, store one valid single-variant XCFramework per remote
entry. Include the complete planned architecture set in that entry; do not
quietly let the warming machine's active architecture choose its contents.
Keep a versioned manifest alongside the payload with its variant, recipe key,
architecture coverage, deployment target, product identity, and dependency keys.
Verify that metadata against both the request and the actual artifact, using the
existing signing/integrity boundary.

Assemble the requested entries into a deterministic local XCFramework directory
keyed by the ordered artifact keys and assembler version. Merge validated,
disjoint library records and preserve their Swift modules, headers, dSYMs, and
App Intents metadata. This does not require launching `xcodebuild` once per
target during generation. A missing or conflicting library record is a miss,
not permission to pick the first directory.

Publish local assemblies atomically under an assembly lock. Copy or clone their
contents rather than leaving links into independently evictable cache entries.
Protect fetched inputs from eviction until assembly finishes. Derived assemblies
can be pruned independently without changing remote identity. For frameworks,
the assembler can still hand one path per target to `CacheGraphMutator`.

## Resource bundles are part of the fix

Current warming builds bundles for a simulator or macOS and can persist the
last platform's bundle under a shared key. Removing
`CFBundleSupportedPlatforms` does not establish that compiled resources are
portable across SDKs. Versioned binary keys must not carry that assumption into
the new format.

Build and store resource bundles per SDK/variant, including device and Catalyst
where requested. Preserve the appropriate generated bundle metadata and resource
accessor contract for each artifact. The code artifact's dependency recipe must
include the matching resource artifact key.

Add a cached-resource descriptor containing paths indexed by build variant.
Generation must copy exactly the matching bundle to the expected product name
using SDK/environment selection, with Xcode input/output dependencies declared.
`PlatformCondition` alone is insufficient because it does not distinguish device
and simulator. Missing variants must cause source fallback during generation,
and an unexpected SDK at build time must fail explicitly rather than copy an
arbitrary variant. Do not embed several bundles with the same product name.

`CacheGraphMutator` and the resource-copy generator need to accept this descriptor
instead of assuming every cached target is represented by one interchangeable
filesystem path. Preserve the existing rules that keep resource targets editable
when their owning code target stays in source.

## Concrete implementation boundaries

| Component | Change |
| --- | --- |
| `TuistCache` | Add build-variant, artifact-recipe, requirement-plan, and contextual dependency-hashing types. Reuse low-level hashers. |
| `TuistKit` warming service | Consume the shared plan, select missing actions per variant, generate matching build graphs, and store outputs per action. |
| Cache EE scheme generation | Group missing actions by their exact build variant, including host tools and resource builds. |
| Cache EE replacement mapper | Batch-fetch required keys, validate entries, assemble binaries, and require complete coverage before replacement. |
| Cache EE storage | Carry/validate per-artifact manifests; preserve immutable entries and protect assembly inputs from eviction. |
| `XcodeGraph` / generator | Represent cached resource variants and select the correct bundle during the Xcode build. |
| Cache EE graph mutator | Accept assembled binary paths and resource-variant descriptors while retaining dependency/source-focus rules. |

The private cache submodule and public CLI changes must be released together.
The public repository must pin the corresponding submodule commit; a public-only
hasher change cannot implement this contract.

## Migration

Introduce a new binary-cache format namespace (v8). New readers never treat v7
objects as v8 artifacts and never rename a v7 key into the new namespace. The
existing v7 objects can expire normally; old clients can continue using them.
Expect a cold cache for the new format. Warm v8 with the new CLI in CI before
rolling that CLI out broadly. Rollback selects the old CLI and its old namespace.

Land the planner, writer, reader/assembler, and resource support behind one
internal format gate until the complete acceptance suite passes. Enable writer
and reader together. Do not ship a reader-only key change or mixed-format
fallback that conceals incomplete coverage.

## Required regression coverage

Keep the real loading/warming/generation fixture in this directory as an
acceptance test. Update its storage assertions for per-variant entries and local
assemblies, and make the current `--expect-reuse` outcome the default passing
expectation. Read artifact manifests rather than depending on diagnostic log
format for the new key assertions.

The release gate must cover:

1. A combined warm followed by iOS-only and macOS-only manifest loading: both hit,
   both link, and both use the exact corresponding keys from the combined warm.
2. Separate iOS and macOS warms followed by combined generation: both orders hit.
   Concurrent warms cannot overwrite one another's coverage.
3. Missing device, simulator, native macOS, or Catalyst coverage: source fallback;
   a subsequent warm builds only missing actions.
4. A conditional macOS-only dependency: changing it does not change an unrelated
   iOS build recipe, but does invalidate the macOS recipe and its dependents.
5. The same dependency used by iOS runtime code and a macOS macro: distinct
   contextual keys, correct host execution, and successful cached builds.
6. Resource bundles with compiled assets and platform-specific contents: correct
   device/simulator/macOS/Catalyst selection and runtime resource lookup.
7. Changes to relevant deployment targets, compiler/SDK versions, flags, package
   traits, generated accessors, or architecture policy: a miss for affected
   recipes. Consumer removal alone must not change those recipes.
8. Signed but mislabelled/incomplete payloads, assembly interruption, pruning,
   and concurrent assembly: no incomplete or dangling artifact is returned.
9. Source-focus exceptions, static/dynamic dependency combinations, and hostless
   tests: existing replacement and link behavior stays valid.
10. v7/v8 isolation: no cross-version reads or writes, and no incorrect reuse
    after rollback.

Unit tests cover contextual planning and completeness decisions. Storage and
assembler tests use real artifact layouts. Acceptance tests run the actual CLI
and Xcode, following the repository's targeted Xcode test workflow. The current
reproduction proves the motivating compatibility case; these additional gates
are required before claiming that the general implementation is safe.

## Rejected shortcuts

- Dropping destinations permits an iOS-only artifact to satisfy a macOS request.
- Hashing every package's advertised platforms requires warming unsupported or
  unneeded platforms, or falsely advertises coverage that was never built.
- Writing aliases for every destination subset grows combinatorially and still
  needs to solve contextual dependency and resource compatibility.
- A mutable "latest superset" record introduces coverage races and requires a
  compatibility catalog. Exact per-variant keys avoid that additional protocol.

The intended invariant is simple: adding or removing consumers changes the set
of artifacts requested, while an unchanged build recipe keeps the same key.
