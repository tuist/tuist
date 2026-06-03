# Changelog

All notable changes to this project will be documented in this file.
## What's Changed in 4.195.12<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* move framework search path setup into a graph mapper by [@fortmarek](https://github.com/fortmarek) in [#11054](https://github.com/tuist/tuist/pull/11054)
* generate foreign build aggregates as scripts by [@pepicrft](https://github.com/pepicrft) in [#11030](https://github.com/tuist/tuist/pull/11030)
* inherit canary fixture feature flags by [@pepicrft](https://github.com/pepicrft) in [#11050](https://github.com/tuist/tuist/pull/11050)
* always expose -Swift.h for Swift-only SPM frameworks (#11007) by [@fortmarek](https://github.com/fortmarek) in [#11012](https://github.com/tuist/tuist/pull/11012)
* pass precompiled framework search paths to Swift inline, not via @resp by [@fortmarek](https://github.com/fortmarek) in [#11033](https://github.com/tuist/tuist/pull/11033)
* keep test target buildable when only a test-case-level skip matches by [@fortmarek](https://github.com/fortmarek) in [#11032](https://github.com/tuist/tuist/pull/11032)
* use AsyncParsableCommand for plugin run and test commands by [@rwjc](https://github.com/rwjc)
* infer DerivedData location for inspect build and tests by [@natanrolnik](https://github.com/natanrolnik) in [#11015](https://github.com/tuist/tuist/pull/11015)
* stop emitting -Xcc @resp into OTHER_SWIFT_FLAGS (Xcode 26 "expected exactly one compiler job") by [@fortmarek](https://github.com/fortmarek) in [#11023](https://github.com/tuist/tuist/pull/11023)
* finish test command early when every test target is filtered out by [@fortmarek](https://github.com/fortmarek) in [#11010](https://github.com/tuist/tuist/pull/11010)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.195.11...4.195.12

## What's Changed in 4.195.11<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* hash the resolved embedded product closure into the cache content hash by [@fortmarek](https://github.com/fortmarek) in [#10984](https://github.com/tuist/tuist/pull/10984)
* pass explicit working directory to manifest evaluation by [@fortmarek](https://github.com/fortmarek) in [#10996](https://github.com/tuist/tuist/pull/10996)
* isolate acceptance fixtures from feature flags by [@pepicrft](https://github.com/pepicrft) in [#10993](https://github.com/tuist/tuist/pull/10993)
* Fix Swift-only package framework modulemaps by [@pepicrft](https://github.com/pepicrft) in [#10971](https://github.com/tuist/tuist/pull/10971)
* avoid checkout cwd for SwiftPM package dumps by [@pepicrft](https://github.com/pepicrft) in [#10966](https://github.com/tuist/tuist/pull/10966)
* avoid expanding recursive exclusion globs by [@pepicrft](https://github.com/pepicrft) in [#10957](https://github.com/tuist/tuist/pull/10957)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.195.7...4.195.11

## What's Changed in 4.195.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use combined module map to avoid argument list too long errors by [@fortmarek](https://github.com/fortmarek)
* anchor SwiftPM module-map flags on absolute derived-dir to survive symlinked .build/checkouts by [@fortmarek](https://github.com/fortmarek)
* preserve module names for xcframework wrappers by [@pepicrft](https://github.com/pepicrft)
* stop duplicating SwiftPM output during tuist install by [@shgew](https://github.com/shgew)
* respect configured SwiftPM scratch paths by [@sanghyeok-kim](https://github.com/sanghyeok-kim)
* canonicalize xcodebuild analytics metadata by [@pepicrft](https://github.com/pepicrft)
* ignore embeddable watch apps in redundant dependency inspection by [@shgew](https://github.com/shgew)
* preserve asset symbol generation for buildable-folder xcassets by [@pepicrft](https://github.com/pepicrft)
* emit cross-project PBXTargetDependency for foreign build consumers by [@fortmarek](https://github.com/fortmarek)
* pass explicit workingDirectory to swift package commands by [@fortmarek](https://github.com/fortmarek)
* keep tuist dump stdout machine-readable by [@pepicrft](https://github.com/pepicrft)
* re-run foreign build script when inputs cannot be tracked by [@fortmarek](https://github.com/fortmarek)
* align tuist hash selective-testing with the test pipeline by [@fortmarek](https://github.com/fortmarek)
* apply test quarantine to --without-building and shard runs by [@fortmarek](https://github.com/fortmarek)
* Indentation in StringsTemplate.swift by [@teameh](https://github.com/teameh)
* retry run metadata upload on transient errors by [@fortmarek](https://github.com/fortmarek)
### ⚡ Performance

* use Set for project path lookups in tree-shake mapper by [@inju2403](https://github.com/inju2403)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.195.0...4.195.7

## What's Changed in 4.195.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* expose is_quarantined on test case run API by [@justine-acorns](https://github.com/justine-acorns)
* add onOutdatedDependencies action to GenerationOptions by [@freak4pc](https://github.com/freak4pc)
### 🐛 Bug Fixes

* deduplicate conditioned xcframework search paths by [@fortmarek](https://github.com/fortmarek)
* bind shard reference across split build/test jobs by [@fortmarek](https://github.com/fortmarek)
* avoid collecting large verbose HTTP bodies by [@fortmarek](https://github.com/fortmarek)
* map default actor isolation to MainActor by [@fortmarek](https://github.com/fortmarek)
* synthesize Bundle.module for static frameworks with .metal in buildable folders by [@pepicrft](https://github.com/pepicrft)
* release SwiftPM lock before invoking manifest subprocesses by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.193.3...4.195.0

## What's Changed in 4.193.3<!-- RELEASE NOTES START -->

### ⛰️  Features

* allow forwarding extra env vars to manifest evaluation by [@pepicrft](https://github.com/pepicrft)
### 🐛 Bug Fixes

* coordinate SwiftPM graph reads by [@pepicrft](https://github.com/pepicrft)
* propagate selective testing and module cache analytics across --build-only / --without-building by [@fortmarek](https://github.com/fortmarek)
* avoid invalidating shared URLSession on no-op HTTPSettings writes by [@fortmarek](https://github.com/fortmarek)
* handle nested buildable folder xcstrings by [@pepicrft](https://github.com/pepicrft)
* make metadata upload non-fatal by [@pepicrft](https://github.com/pepicrft)
* rewrite dangling pre/post-action targets at prune time by [@fortmarek](https://github.com/fortmarek)
* allow folder resources to overlap sources by [@pepicrft](https://github.com/pepicrft)
* route static xcframeworks behind dynamic via search paths, not relink by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.192.3...4.193.3

## What's Changed in 4.192.3<!-- RELEASE NOTES START -->

### ⛰️  Features

* rename Tuist `cache` to `xcodeCache` by [@fortmarek](https://github.com/fortmarek)
* add tuist test case update command by [@justine-acorns](https://github.com/justine-acorns)
### 🐛 Bug Fixes

* remove noisy transport-level HTTP error logging by [@fortmarek](https://github.com/fortmarek)
* limit implicit import source scans by [@pepicrft](https://github.com/pepicrft)
* CLI hangs running processes concurrently by [@pepicrft](https://github.com/pepicrft)
* resolve race condition in CachedManifestLoader parallel writes by [@ze-diaz](https://github.com/ze-diaz)
* duplicate selective testing log messages and improve skip reason clarity by [@irena327](https://github.com/irena327)
* skip run metadata upload when no auth is available by [@pepicrft](https://github.com/pepicrft)
* make multi-process token refresh resilient to slow peers and rotation races by [@fortmarek](https://github.com/fortmarek)
* support PackageDescription context by [@Kyle-Ye](https://github.com/Kyle-Ye)
* respect disabled autogenerated workspace schemes by [@pepicrft](https://github.com/pepicrft)
* treat non-source files in buildable folders as resources by [@fortmarek](https://github.com/fortmarek)
* preserve whitespace in plist template for Array-root scalars by [@winston-riley-zocdoc](https://github.com/winston-riley-zocdoc)
* preserve pruned test plan metadata by [@pepicrft](https://github.com/pepicrft)
* include macOS SDK version in ProjectDescriptionHelpers cache key by [@pepicrft](https://github.com/pepicrft)
* skip fully cached missing test plans by [@pepicrft](https://github.com/pepicrft)
* disable HAR recording for cache daemon by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.191.5...4.192.3

## What's Changed in 4.191.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use stamp file for macro copy phase to keep incremental rebuilds by [@fortmarek](https://github.com/fortmarek)
* fix macro copy phase output collision on macOS consumer targets by [@freak4pc](https://github.com/freak4pc)
* intersect linkable dep destinations for orphan local SPM tests by [@mqzkim](https://github.com/mqzkim)
* re-embed test target frameworks not embedded in host by [@pepicrft](https://github.com/pepicrft)
* make shared cache and state writes safe across concurrent processes by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.191.1...4.191.5

## What's Changed in 4.191.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* stabilize cache EE canary acceptance test by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.191.0...4.191.1

## What's Changed in 4.191.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add --skip-macro-support-targets flag to tuist graph by [@natanrolnik](https://github.com/natanrolnik)
* re-add config-driven network proxy opt-out by [@pepicrft](https://github.com/pepicrft)
* add "Skip" quarantine mode for test cases by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* keep static framework xcstrings on main target Resources phase by [@pepicrft](https://github.com/pepicrft)
* refresh expired tokens under optionalAuthentication by [@fortmarek](https://github.com/fortmarek)
* add TuistHTTP to TuistConfigLoader cross-platform deps by [@fortmarek](https://github.com/fortmarek)
* bump tuist.Command to 0.14.1 to surface xcodebuild stderr by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.188.5...4.191.0

## What's Changed in 4.188.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* update xcactivitylog_nif package path after processor consolidation by [@fortmarek](https://github.com/fortmarek)
* honor #if guards in inspect dependencies --only implicit by [@fortmarek](https://github.com/fortmarek)
* restore [Path] overload of TestAction.testPlans as deprecated by [@fortmarek](https://github.com/fortmarek)
* sanitize target name in generated Obj-C bundle accessor identifiers by [@pepicrft](https://github.com/pepicrft)
### ⚡ Performance

* lower URLSession resource timeout from 300s to 90s by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.188.2...4.188.5

## What's Changed in 4.188.2<!-- RELEASE NOTES START -->

### ⛰️  Features

* add CopyFileElement.buildProduct for embedding target products in Copy Files phases by [@freak4pc](https://github.com/freak4pc)
* generate .xctestplan files from ProjectDescription by [@fortmarek](https://github.com/fortmarek)
* add 'tuist teardown cache' command by [@fortmarek](https://github.com/fortmarek)
* add --inspect-mode off to skip result bundle upload by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* upload build run when -derivedDataPath is passed via passthrough by [@fortmarek](https://github.com/fortmarek)
* include source filename in selective testing hash by [@fortmarek](https://github.com/fortmarek)
* preserve bundle directory in AppleArchive uploads by [@fortmarek](https://github.com/fortmarek)
* handle buildable-folder xcstrings stale analysis by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.186.2...4.188.2

## What's Changed in 4.186.2<!-- RELEASE NOTES START -->

### ⛰️  Features

* AppleArchive for xcresult upload + respect --inspect-mode remote by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* skip xcodebuild when -skip-testing clears selective tests by [@fortmarek](https://github.com/fortmarek)
* respect repo optional auth in command tracking by [@pepicrft](https://github.com/pepicrft)
* scope cache warm target selection to non-test roots by [@pepicrft](https://github.com/pepicrft)
* make swift-file-system the default filesystem backend by [@pepicrft](https://github.com/pepicrft)
* restore static framework .xcstrings localization by [@pepicrft](https://github.com/pepicrft)
* propagate default-enabled Swift package traits by [@pepicrft](https://github.com/pepicrft)
* add muted/unmuted test case event types by [@justine-acorns](https://github.com/justine-acorns)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.185.1...4.186.2

## What's Changed in 4.185.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* support config-driven network proxy opt-out by [@pepicrft](https://github.com/pepicrft)
### 🐛 Bug Fixes

* skip result bundle upload when --inspect-mode local by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.184.2...4.185.1

## What's Changed in 4.184.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Support  optional Buildable Folders by [@PaulTaykalo](https://github.com/PaulTaykalo)
* error instead of silently ignoring mismatched test shard flags by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.184.1...4.184.2

## What's Changed in 4.184.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add feature flag headers by [@pepicrft](https://github.com/pepicrft)
### 🐛 Bug Fixes

* map static library dependencies in XcodeGraph by [@pepicrft](https://github.com/pepicrft)
* ensure package product dependencies are initialized by [@pepicrft](https://github.com/pepicrft)
* preserve scheme buildAction targets in `tuist test <scheme>` focus by [@fortmarek](https://github.com/fortmarek)
### 🚜 Refactor

* deprecate unused `swiftVersion` on `TuistProject.tuist(...)` by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.183.0...4.184.1

## What's Changed in 4.183.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add paginated test case events endpoint by [@justine-acorns](https://github.com/justine-acorns)
### 🐛 Bug Fixes

* scope `tuist test <scheme>` to the scheme's test plan targets by [@fortmarek](https://github.com/fortmarek)
* Fix xcstrings handling in buildable folders by [@pepicrft](https://github.com/pepicrft)
* handle strictMemorySafety with empty dump-package JSON by [@alpaka99](https://github.com/alpaka99)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.182.0...4.183.0

## What's Changed in 4.182.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* preserve test targets for local SPM packages by [@sabade-omkar](https://github.com/sabade-omkar)
* resolve inspect bundle app names like share by [@pepicrft](https://github.com/pepicrft)
* drop fd-limit caps when swift-file-system backend is enabled by [@pepicrft](https://github.com/pepicrft)
### 🐛 Bug Fixes

* clear pruned expandVariableFromTarget instead of dropping the scheme by [@fortmarek](https://github.com/fortmarek)
* use literal string matching in ManifestLoader to fix hang on large output by [@sabade-omkar](https://github.com/sabade-omkar)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.181.1...4.182.0

## What's Changed in 4.181.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* reject xcodebuild action verbs in passthrough arguments by [@fortmarek](https://github.com/fortmarek)
* use proxy-aware URLSession for cache endpoint latency checks by [@changusmc](https://github.com/changusmc)
* handle binary wrapper xcframework name collisions for Singular and Firebase patterns by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.181.0...4.181.1

## What's Changed in 4.181.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* auto-detect HTTP proxy from HTTPS_PROXY/HTTP_PROXY by [@pepicrft](https://github.com/pepicrft)
### 🐛 Bug Fixes

* stop excluding transitive deps from cache hashing for positional targets by [@fortmarek](https://github.com/fortmarek)
* Catalyst should use macosx sdk by [@wojmangh](https://github.com/wojmangh)
* Make StringProtocol.range(of:) scan UTF-8 bytes by [@pepicrft](https://github.com/pepicrft)
* resolve bare "container:" xctestplan target references by [@fortmarek](https://github.com/fortmarek)
* Add warning for missing xctestplan files by [@yhkaplan](https://github.com/yhkaplan)
* bump FileSystem to 0.16.1 for Musl support by [@fortmarek](https://github.com/fortmarek)
* preserve original error when test result parsing fails by [@fortmarek](https://github.com/fortmarek)
* fix synthesized resource interface generation for numeric target names by [@pepicrft](https://github.com/pepicrft)
* skip token refresh when optionalAuthentication is enabled by [@pepicrft](https://github.com/pepicrft)
* keep xcstrings in Resources phase for static framework stale detection by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.180.0...4.181.0

## What's Changed in 4.180.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* process test insights remotely by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* ignore .DS_Store files when hashing buildable folders by [@heoblitz](https://github.com/heoblitz)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.179.3...4.180.0

## What's Changed in 4.179.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* skip embedding extensions in unit test targets by [@danieleformichelli](https://github.com/danieleformichelli)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.179.2...4.179.3

## What's Changed in 4.179.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add retry middleware for OpenAPI requests by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.179.1...4.179.2

## What's Changed in 4.179.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resolve StoreKit configuration paths relative to the xcworkspace bundle by [@jsj](https://github.com/jsj)
* use Modules include path for source-built ProjectDescription by [@jsj](https://github.com/jsj)
* resolve relative -testProductsPath when writing selective testing graph by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.179.0...4.179.1

## What's Changed in 4.179.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add parameterized test argument support by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* mark generated bundle accessors as nonisolated by [@DimaMishchenko](https://github.com/DimaMishchenko)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.178.1...4.179.0

## What's Changed in 4.178.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* support self-managed shard archives by [@pepicrft](https://github.com/pepicrft)
### 🐛 Bug Fixes

* avoid duplicate App Intents dependency file list outputs by [@pepicrft](https://github.com/pepicrft)
* link test runs to builds and fix command event metadata by [@fortmarek](https://github.com/fortmarek)
* declare symlink target in macro copy script input paths for sandbox compatibility by [@zippi-MD](https://github.com/zippi-MD)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.177.0...4.178.1

## What's Changed in 4.177.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add --cache-profile option to cache warm with profile-driven exclusions by [@gnejfejf2](https://github.com/gnejfejf2)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.176.4...4.177.0

## What's Changed in 4.176.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* write empty shard matrix on all early return paths by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.176.3...4.176.4

## What's Changed in 4.176.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use overwrite option when writing module maps by [@fortmarek](https://github.com/fortmarek)
* update Package.resolved to match current dependencies by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.176.2...4.176.3

## What's Changed in 4.176.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix xcstrings stale-string detection for multiplatform static frameworks by [@pepicrft](https://github.com/pepicrft)
* mkdir data race by [@fortmarek](https://github.com/fortmarek)
* write empty shard matrix output when selective testing skips all tests by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.176.1...4.176.2

## What's Changed in 4.176.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add workspace-level DerivedData location support by [@davidpasztor](https://github.com/davidpasztor)
### 🐛 Bug Fixes

* add retry logic to build uploads by [@fortmarek](https://github.com/fortmarek)
* add nonisolated(unsafe) to generated plist accessors with Any type by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.175.0...4.176.1

## What's Changed in 4.175.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* fix App Intents metadata for cached xcframeworks by [@pepicrft](https://github.com/pepicrft)
* upload build data from tuist xcodebuild build by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* handle existing files during shard xctestrun write by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.7...4.175.0

## What's Changed in 4.174.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* namespace dependency-derived artifacts by [@pepicrft](https://github.com/pepicrft)
* fix cross-project test host embed and TEST_HOST settings by [@pepicrft](https://github.com/pepicrft)
### 🚜 Refactor

* remove local MCP command by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.4...4.174.7

## What's Changed in 4.174.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add missing TuistTesting dependency to TuistCASTests by [@jsj](https://github.com/jsj)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.3...4.174.4

## What's Changed in 4.174.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix selective testing not skipping unchanged test targets by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.2...4.174.3

## What's Changed in 4.174.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* deduplicate entries during Apple Archive compression by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.1...4.174.2

## What's Changed in 4.174.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* dereference symlinks during Apple Archive compression by [@fortmarek](https://github.com/fortmarek)
* resolve result bundle symlink before remote upload by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.0...4.174.1

## What's Changed in 4.174.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add defaultSwiftVersion generation option and respect package-declared Swift versions by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.173.1...4.174.0

## What's Changed in 4.173.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resource/file glob excluding with ** pattern incorrectly excludes all sibling files by [@stefanomondino](https://github.com/stefanomondino)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.173.0...4.173.1

## What's Changed in 4.173.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add --inspect-mode flag for remote xcresult processing by [@fortmarek](https://github.com/fortmarek)
* support shared volumes for test shard distribution by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* preserve .swiftmodule directories in shard archives by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.172.0...4.173.0

## What's Changed in 4.172.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add remote processing mode for tuist inspect test by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* focus to scope to scheme test targets by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.171.5...4.172.0

## What's Changed in 4.171.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix xctestproducts lookup after AppleArchive extraction by [@fortmarek](https://github.com/fortmarek)
* resolve incorrect storeKitConfigurationPath and GPX paths in generated xcschemes by [@fortmarek](https://github.com/fortmarek)
* embed App Intents metadata in cached xcframeworks by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.171.3...4.171.5

## What's Changed in 4.171.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* archive shard bundle directly from source with exclude patterns by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.171.2...4.171.3

## What's Changed in 4.171.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* preserve external static xcframework deps for cached dynamics by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.171.1...4.171.2

## What's Changed in 4.171.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* strip dSYMs and compress shard bundle before upload by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.171.0...4.171.1

## What's Changed in 4.171.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add retries for OIDC token failures



**Full Changelog**: https://github.com/tuist/tuist/compare/4.170.1...4.171.0

## What's Changed in 4.170.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add selective testing observability via MCP, API, CLI, and skills by [@pepicrft](https://github.com/pepicrft)
### 🐛 Bug Fixes

* replace file-based CAS analytics with SQLite for faster inspect build by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.169.2...4.170.1

## What's Changed in 4.169.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle remote binary wrapper xcframework name collisions by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.169.1...4.169.2

## What's Changed in 4.169.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* honor explicit run executable for extension schemes by [@pepicrft](https://github.com/pepicrft)
* preserve input order in bounded concurrentMap by [@fortmarek](https://github.com/fortmarek)
### 🚜 Refactor

* replace FileHandler with FileSystem by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.169.0...4.169.1

## What's Changed in 4.169.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* link build runs to shard plans by [@fortmarek](https://github.com/fortmarek)
* resolving SPM Targets with automatic product type using baseProductType by [@Loupehope](https://github.com/Loupehope)
### 🐛 Bug Fixes

* support .tbd stub files in xcframeworks by [@pepicrft](https://github.com/pepicrft)
* add missing macOS platforms to mise.lock by [@fortmarek](https://github.com/fortmarek)
### ⚡ Performance

* use dictionary lookup for target resolution in PackageInfoMapper by [@inju2403](https://github.com/inju2403)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.167.0...4.169.0

## What's Changed in 4.167.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add native shard matrix output for all CI providers by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.166.2...4.167.0

## What's Changed in 4.166.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* show suite names in shard log for suite granularity by [@fortmarek](https://github.com/fortmarek)
* use structural action log timing for test run duration reporting by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.166.0...4.166.2

## What's Changed in 4.166.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Allow configuring expected signatures for XCFrameworks exposed by Swift packages by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.165.0...4.166.0

## What's Changed in 4.165.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* run quarantined tests instead of skipping them by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* remove containsResources special-casing for static frameworks by [@pepicrft](https://github.com/pepicrft)
* sort concurrentMap results in content hashers for determinism by [@fortmarek](https://github.com/fortmarek)
* infer platform destination for shard enumeration from graph by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.164.1...4.165.0

## What's Changed in 4.164.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* pass destination to test enumeration for suite sharding by [@fortmarek](https://github.com/fortmarek)
* fix macro copy script failing on clean builds by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.164.0...4.164.1

## What's Changed in 4.164.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* skip project generation for --without-building with embedded selective testing graph by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.163.1...4.164.0

## What's Changed in 4.163.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add test sharding support by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* support macOS app bundle layout by [@lechuckcaptain](https://github.com/lechuckcaptain)
* always copy macro executable on incremental builds by [@ffittschen](https://github.com/ffittschen)
* fix static framework resource bundle crash when using xcstrings by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.162.0...4.163.1

## What's Changed in 4.162.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add storages option to cache configuration by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.161.4...4.162.0

## What's Changed in 4.161.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove unsupported DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER build setting by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.161.3...4.161.4

## What's Changed in 4.161.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* increase URLSession max connections per host to 20 by [@fortmarek](https://github.com/fortmarek)
* normalize swift package target names with spaces by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.161.1...4.161.3

## What's Changed in 4.161.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* process builds remotely by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* prevent xcstrings stale extraction state in static targets by [@pepicrft](https://github.com/pepicrft)
* use SDK-conditioned FRAMEWORK_SEARCH_PATHS for xcframeworks by [@wojmangh](https://github.com/wojmangh)
* resolve merge commit to actual PR head SHA by [@fortmarek](https://github.com/fortmarek)
* only record /cache/ac hashes for test targets, not their deps by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.160.3...4.161.1

## What's Changed in 4.160.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* redact sensitive headers in verbose HTTP logs by [@fortmarek](https://github.com/fortmarek)
* restore TuistCacheEE submodule pointer to include empty graph fix by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.160.1...4.160.3

## What's Changed in 4.160.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* log test targets that will be tested by [@pepicrft](https://github.com/pepicrft)
### 🐛 Bug Fixes

* use xcactivitylog UUID as build ID for remote processing by [@fortmarek](https://github.com/fortmarek)
* allow iOS bundle targets to have dependencies by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.159.0...4.160.1

## What's Changed in 4.159.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload CLI session to S3 after command event creation by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* add audio and video file extensions to validResourceExtensions by [@natanrolnik](https://github.com/natanrolnik)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.158.2...4.159.0

## What's Changed in 4.158.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use CFBundleExecutable for binary lookup in tuist share by [@fortmarek](https://github.com/fortmarek)
* correct SYMROOT path in cache warm builds by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.158.0...4.158.2

## What's Changed in 4.158.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* server-side xcactivitylog processing by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* filter pruned test targets from -only-testing flags by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.157.4...4.158.0

## What's Changed in 4.157.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resolve --path flag not working for tuist setup cache by [@fortmarek](https://github.com/fortmarek)
* use modern launchctl bootstrap/bootout for cache daemon by [@fortmarek](https://github.com/fortmarek)
* use modern launchctl bootstrap/bootout for cache daemon by [@fortmarek](https://github.com/fortmarek)
* skip binary cache mapping when graph is empty after selective testing by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.157.1...4.157.4

## What's Changed in 4.157.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add watch2AppContainer product type for watchOS-only apps by [@BugorBN](https://github.com/BugorBN)
### 🐛 Bug Fixes

* resolve missing module dependencies with cached local frameworks by [@pepicrft](https://github.com/pepicrft)
* override SYMROOT in cache warm builds to prevent custom build location mismatch by [@gnejfejf2](https://github.com/gnejfejf2)
* restore generate run analytics on dashboard by [@fortmarek](https://github.com/fortmarek)
* handle selectively-pruned targets in --test-targets validation by [@fortmarek](https://github.com/fortmarek)
* include all platform-matching xcframework slices in FRAMEWORK_SEARCH_PATHS by [@ngs](https://github.com/ngs)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.156.0...4.157.1

## What's Changed in 4.156.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track machine metrics by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* support OIDC account tokens for registry login on CI by [@pepicrft](https://github.com/pepicrft)
* fix build category detection for Xcode 26.3+ with compilation cache by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.4...4.156.0

## What's Changed in 4.155.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* archive builds for static targets with xcassets by [@Iron-Ham](https://github.com/Iron-Ham)
* prevent multiple commands produce when static product depends on same-named xcframework by [@pepicrft](https://github.com/pepicrft)
* exclude non-test-dependency targets from workspace scheme build action by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.2...4.155.4

## What's Changed in 4.155.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* expose ProjectDescription product on Linux for DocC generation by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.1...4.155.2

## What's Changed in 4.155.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* correctly detect incremental builds with Xcode compilation cache by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.0...4.155.1

## What's Changed in 4.155.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* group test attachments by repetition by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* bump Rosalind to 0.7.22 and restore dependency versions by [@fortmarek](https://github.com/fortmarek)
* propagate module map flags to configuration-level setting overrides by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.154.4...4.155.0

## What's Changed in 4.154.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* bump Rosalind to 0.7.22 and swift-protobuf to 1.35.1 by [@fortmarek](https://github.com/fortmarek)
* fix build categorization for Xcode 26+ compilation cache by [@fortmarek](https://github.com/fortmarek)
* bump XCLogParser to 0.2.46 and improve activity log error messages by [@fortmarek](https://github.com/fortmarek)
### 📚 Documentation

* replace SourceDocs ProjectDescription reference with DocC by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.154.1...4.154.4

## What's Changed in 4.154.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix buildable-folder header visibility and generation crash by [@pepicrft](https://github.com/pepicrft)
* treat opaque directories as files in buildable folder resolution by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.154.0...4.154.1

## What's Changed in 4.154.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload and display all test attachments from xcresult bundles by [@fortmarek](https://github.com/fortmarek)
* make tuist inspect bundle available on Linux by [@fortmarek](https://github.com/fortmarek)
* prune old binary cache entries on startup by [@pepicrft](https://github.com/pepicrft)
* vendor XcodeGraph into tuist and reconcile dependency graphs by [@pepicrft](https://github.com/pepicrft)
* add "Ask on Launch" executable option for scheme actions by [@FelixLisczyk](https://github.com/FelixLisczyk)
* add warningsAsErrors generation option by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* include transitive search paths through dynamic framework dependencies by [@pepicrft](https://github.com/pepicrft)
* exclude directories from buildable folder resolved files by [@fortmarek](https://github.com/fortmarek)
* cap concurrency to avoid file descriptor exhaustion by [@fortmarek](https://github.com/fortmarek)
* Fix case-insensitive prioritize local packages over registry by [@fdiaz](https://github.com/fdiaz)
* add xcassets and xcstrings to sources build phase for static targets by [@pepicrft](https://github.com/pepicrft)
* update Command package to 0.14.0 by [@fortmarek](https://github.com/fortmarek)
* make CacheLocalStorage.clean public by [@fortmarek](https://github.com/fortmarek)
* bump FileSystem to 0.15.0 for setFileTimes support by [@fortmarek](https://github.com/fortmarek)
* sort Set iterations in graph mappers for deterministic cache hashing by [@fortmarek](https://github.com/fortmarek)
* limit concurrency of buildable folder resolution to avoid FD exhaustion by [@fortmarek](https://github.com/fortmarek)
* add validation folder exists for BuildableFolder by [@ivan-gaydamakin](https://github.com/ivan-gaydamakin)
* prune static xcframework deps from dynamic xcframeworks for hostless unit tests by [@pepicrft](https://github.com/pepicrft)
* upload APK files directly instead of wrapping in zip by [@fortmarek](https://github.com/fortmarek)
* populate explicitFolders for excluded directories in buildable folders by [@fortmarek](https://github.com/fortmarek)
### 🚜 Refactor

* migrate acceptance tests to Swift Testing by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.151.1...4.154.0

## What's Changed in 4.151.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* replace deprecated tuist build recommendation in previews by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.151.0...4.151.1

## What's Changed in 4.151.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* expand glob patterns in buildable folder exclusions by [@InderKumarRathore](https://github.com/InderKumarRathore)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.150.1...4.151.0

## What's Changed in 4.150.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* expanding folder to input inner files when used as input in foreign build phase script by [@scarayaa](https://github.com/scarayaa)
* place precompiled dependencies from SPM build directory in frameworks group by [@JanC](https://github.com/JanC)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.150.0...4.150.1

## What's Changed in 4.150.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add platformFilters for buildable folder exceptions by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.149.1...4.150.0

## What's Changed in 4.149.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Use latest Gradle plugin version in init and add takeaways by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.149.0...4.149.1

## What's Changed in 4.149.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Android APK previews with cross-platform share and run by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* Prioritize local packages over registry versions by [@fdiaz](https://github.com/fdiaz)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.148.4...4.149.0

## What's Changed in 4.148.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* apply PackageSettings.baseSettings.defaultSettings to SPM targets by [@hiltonc](https://github.com/hiltonc)
* restore SRCROOT path resolution for cached target settings by [@fortmarek](https://github.com/fortmarek)
* respect custom server url by [@yusufozgul](https://github.com/yusufozgul)
* include buildable folder resources in Target.containsResources by [@hiltonc](https://github.com/hiltonc)
* use product name as module name for SPM wrapper targets by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.148.1...4.148.4

## What's Changed in 4.148.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Android bundle support (AAB + APK) by [@fortmarek](https://github.com/fortmarek)
* crash stack traces with formatted frames, attachments, and download URLs by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* pass jsonThroughNoora to Noora on Linux by [@fortmarek](https://github.com/fortmarek)
* bump xcode version release by [@fortmarek](https://github.com/fortmarek)
* preserve JSON logger for non-Noora commands on Linux by [@fortmarek](https://github.com/fortmarek)
* don't run foreign build script when target is served from binary cache by [@fortmarek](https://github.com/fortmarek)
* sanitize + character in intra-package target dependency names by [@pepicrft](https://github.com/pepicrft)
* warn when skip test targets don't intersect by [@pepicrft](https://github.com/pepicrft)
* add Swift toolchain library search path for ObjC targets linking static Swift dependencies by [@pepicrft](https://github.com/pepicrft)
* resolve static ObjC xcframework search paths without Package.swift by [@pepicrft](https://github.com/pepicrft)
* enable HTTP logging and server warnings on Linux by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.146.1...4.148.1

## What's Changed in 4.146.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix cache building unnecessary Catalyst scheme for external dependencies by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.146.0...4.146.1

## What's Changed in 4.146.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add foreign build system dependencies by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* restore TuistSimulator to macOS-only block in Package.swift by [@fortmarek](https://github.com/fortmarek)
* increase inspect build activity log timeout and make it configurable by [@fortmarek](https://github.com/fortmarek)
* fix CLI release (static linking, Musl imports, Bundle(for:)) by [@fortmarek](https://github.com/fortmarek)
* use canImport(Musl) for Static Linux SDK compatibility by [@fortmarek](https://github.com/fortmarek)
* remove OpenAPIURLSession from cross-platform targets for Linux static SDK by [@fortmarek](https://github.com/fortmarek)
* restore cache run analytics on dashboard by [@fortmarek](https://github.com/fortmarek)
* only cache dependency checkouts in Linux CI jobs by [@fortmarek](https://github.com/fortmarek)
* add missing tree-shake after focus targets in automation mapper chain by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.145.0...4.146.0

## What's Changed in 4.145.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* support build system selection in project create by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* remove unused CacheBuiltArtifactsFetcher from CacheWarmCommandService by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.4...4.145.0

## What's Changed in 4.144.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fall back to BUILD_DIR for derived data resolution by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.3...4.144.4

## What's Changed in 4.144.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* embed cached static xcframeworks with resources transitively by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.2...4.144.3

## What's Changed in 4.144.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* run StaticXCFrameworkModuleMapGraphMapper after cache replacement by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.1...4.144.2

## What's Changed in 4.144.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix flaky tests caused by Matcher.register race and TOCTOU in CachedManifestLoader by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.0...4.144.1

## What's Changed in 4.144.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Gradle project integration to tuist init by [@fortmarek](https://github.com/fortmarek)
* add test case show and run commands with fix-flaky-tests skill by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* resolve derived data path from DERIVED_DATA_DIR env in inspect commands by [@fortmarek](https://github.com/fortmarek)
* use correct TUIST_URL key for env variable lookup in login command by [@fortmarek](https://github.com/fortmarek)
* strip debug symbols (dSYM/DWARF) from cached XCFrameworks by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.142.1...4.144.0

## What's Changed in 4.142.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* make server commands available on Linux by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* don't retry non-retryable errors in module cache download by [@fortmarek](https://github.com/fortmarek)
* restore asset symbol generation for external static frameworks by [@pepicrft](https://github.com/pepicrft)
* use correct bundle accessor for external dynamic frameworks with resources by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.141.1...4.142.1

## What's Changed in 4.141.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add debug logging to inspect build and test commands by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.141.0...4.141.1

## What's Changed in 4.141.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add tuist.toml support by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.140.2...4.141.0

## What's Changed in 4.140.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* skip macro targets in static dependency traversal by [@pepicrft](https://github.com/pepicrft)
* add retry logic to OIDC authentication flow by [@fortmarek](https://github.com/fortmarek)
* fix CI environment variable filtering by [@ivan-gaydamakin](https://github.com/ivan-gaydamakin)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.140.1...4.140.2

## What's Changed in 4.140.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Linux support for auth and cache commands by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* fix `tuist version` producing no output on Linux by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.139.1...4.140.1

## What's Changed in 4.139.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't embed static precompiled xcframeworks by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.139.0...4.139.1

## What's Changed in 4.139.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add configurable cache push policy by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* deduplicate plugins with the same name in tuist edit by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.138.1...4.139.0

## What's Changed in 4.138.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add extension bundle search paths for resource accessors by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.138.0...4.138.1

## What's Changed in 4.138.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add custom metadata and tags to build runs by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.137.1...4.138.0

## What's Changed in 4.137.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* guard log file creation for Noora by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.137.0...4.137.1

## What's Changed in 4.137.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* record network requests to HAR files for debugging by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.136.0...4.137.0

## What's Changed in 4.136.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add generations and cache runs API endpoints and CLI commands by [@pepicrft](https://github.com/pepicrft)
### 🐛 Bug Fixes

* embed static frameworks with buildable-folder resources by [@pepicrft](https://github.com/pepicrft)
* skip config loading for inspect commands by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.135.2...4.136.0

## What's Changed in 4.135.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* avoid stale auth token cache during long uploads



**Full Changelog**: https://github.com/tuist/tuist/compare/4.135.1...4.135.2

## What's Changed in 4.135.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generate registry config before resolving Swift packages by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.135.0...4.135.1

## What's Changed in 4.135.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* auto-skip quarantined tests in tuist test by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.134.1...4.135.0

## What's Changed in 4.134.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Bump cache version for static framework copy layout by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.134.0...4.134.1

## What's Changed in 4.134.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add build list and build show commands by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.4...4.134.0

## What's Changed in 4.133.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle Metal files in buildable folders for resource bundle generation by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.3...4.133.4

## What's Changed in 4.133.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* propagate .bundle resource files from external static frameworks to host app by [@pepicrft](https://github.com/pepicrft)
* search host bundle paths in ObjC resource bundle accessor by [@pepicrft](https://github.com/pepicrft)
* harden log cleanup by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.2...4.133.3

## What's Changed in 4.133.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* eagerly compute conditional targets to prevent thread starvation during generation by [@pepicrft](https://github.com/pepicrft)
* only embed static XCFrameworks containing .framework bundles by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.0...4.133.2

## What's Changed in 4.133.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add TUIST_CACHE_ENDPOINT environment variable override by [@fortmarek](https://github.com/fortmarek)
* add debug logging to diagnose generation hangs by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.132.1...4.133.0

## What's Changed in 4.132.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add authentication failure error for cache
* update FileSystem to fix intermittent crash on startup by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.132.0...4.132.1

## What's Changed in 4.132.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add registryEnabled generation option by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.131.2...4.132.0

## What's Changed in 4.131.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* revert swift-protobuf to GitHub URL to fix manifest issue by [@pepicrft](https://github.com/pepicrft)
* set default cache concurrency limit to 100 by [@fortmarek](https://github.com/fortmarek)
* support BITRISE_IDENTITY_TOKEN env var for Bitrise OIDC auth by [@pepicrft](https://github.com/pepicrft)
* embed static XCFrameworks to support resources by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.131.1...4.131.2

## What's Changed in 4.131.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* restore mapper order for selective testing and fix parseAsRoot by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.131.0...4.131.1

## What's Changed in 4.131.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add test quarantine and automations settings by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.130.3...4.131.0

## What's Changed in 4.130.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* ensure consistent mapper order between automation and cache pipelines by [@fortmarek](https://github.com/fortmarek)
* use patched swift-openapi-urlsession to fix crash by [@fortmarek](https://github.com/fortmarek)
* filter out dependencies with unsatisfied trait conditions by [@pepicrft](https://github.com/pepicrft)
* fix bundle accessor for Obj-C external static frameworks with resources by [@pepicrft](https://github.com/pepicrft)
### 📚 Documentation

* add intent layer nodes by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.130.1...4.130.3

## What's Changed in 4.130.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* correct static xcframework paths when depending on cached targets by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.130.0...4.130.1

## What's Changed in 4.130.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add debug logs to project generation by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.129.2...4.130.0

## What's Changed in 4.129.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle race condition when creating logs directory by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.129.1...4.129.2

## What's Changed in 4.129.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* prevent race condition when creating logs directory by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.129.0...4.129.1

## What's Changed in 4.129.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* enable local CAS when enableCaching is true and Tuist project is not configured by [@danieleformichelli](https://github.com/danieleformichelli)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.128.3...4.129.0

## What's Changed in 4.128.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix acceptance tests
* External resources failing at runtime unable to find their associated bundle by [@pepicrft](https://github.com/pepicrft)
* only emit a public import when public symbols are present by [@JimRoepcke](https://github.com/JimRoepcke)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.128.0...4.128.3

## What's Changed in 4.128.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* make new module cache default
* add support for flaky tests detection by [@fortmarek](https://github.com/fortmarek)
* implement remote cache cleaning
### 🐛 Bug Fixes

* Compilation errors when a static framework contains resources by [@pepicrft](https://github.com/pepicrft)
* remove selective testing support for vanilla Xcode projects by [@fortmarek](https://github.com/fortmarek)
* update inspect acceptance tests for new output format by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.125.0...4.128.0

## What's Changed in 4.125.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add unified inspect dependencies command by [@hiltonc](https://github.com/hiltonc)
* Add exceptTargetQueries to cache profiles by [@hiltonc](https://github.com/hiltonc)
### 🐛 Bug Fixes

* Static framework bundles for tests and metal by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.124.1...4.125.0

## What's Changed in 4.124.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* disable Swift debug serialization to prevent LLDB warnings by [@pepicrft](https://github.com/pepicrft)
* update XcodeGraph to 1.30.10 to fix CLI resource bundles by [@pepicrft](https://github.com/pepicrft)
* fix flaky DumpServiceIntegrationTests for package manifests by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.124.0...4.124.1

## What's Changed in 4.124.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add support for SwiftPM package traits by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.123.0...4.124.0

## What's Changed in 4.123.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* show deprecation notice for CLI < 4.56.1



**Full Changelog**: https://github.com/tuist/tuist/compare/4.122.2...4.123.0

## What's Changed in 4.122.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* restore static framework resources without regressions by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.122.1...4.122.2

## What's Changed in 4.122.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add excluding parameter to FileElement glob by [@fortmarek](https://github.com/fortmarek)
* Add tuist:synthesized tag to synthesized resource bundles by [@pepicrft](https://github.com/pepicrft)
### 🐛 Bug Fixes

* preserve -enable-upcoming-feature flags in OTHER_SWIFT_FLAGS deduplication by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.120.0...4.122.1

## What's Changed in 4.120.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* export hashed graph to file via env variable by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.4...4.120.0

## What's Changed in 4.119.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* exclude __MACOSX folders for remote binary targets by [@mo5tone](https://github.com/mo5tone)
* ensure consistent graph mapper order for cache hashing by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.3...4.119.4

## What's Changed in 4.119.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* filter Catalyst destinations for external dependencies by [@pepicrft](https://github.com/pepicrft)
* handle multi-byte UTF-8 characters in xcresult parsing by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.1...4.119.3

## What's Changed in 4.119.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use generic destination for Mac Catalyst cache builds by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.0...4.119.1

## What's Changed in 4.119.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* custom cache endpoints
### 🐛 Bug Fixes

* Generate TuistBundle if buildableFolders contains synthesized file by [@denisgaskov](https://github.com/denisgaskov)
* Include Mac Catalyst slice when building XCFrameworks for cache by [@pepicrft](https://github.com/pepicrft)
### 🚜 Refactor

* rename fixtures to examples and simplify fixture handling by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.118.1...4.119.0

## What's Changed in 4.118.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* module cache
### 🐛 Bug Fixes

* fix selective testing when experimental cache enabled



**Full Changelog**: https://github.com/tuist/tuist/compare/4.117.0...4.118.1

## What's Changed in 4.117.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* preview tracks by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* handle cross-project dependencies in redundant import inspection by [@hiltonc](https://github.com/hiltonc)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.116.2...4.117.0

## What's Changed in 4.116.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* require previews to have unique binary id and bundle version by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.116.1...4.116.2

## What's Changed in 4.116.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* compute binary id as part of tuist share by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* add support for the new mise bin path by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.115.1...4.116.1

## What's Changed in 4.115.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* migrate Fixtures - Tuist initializer with .project by [@2sem](https://github.com/2sem)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.115.0...4.115.1

## What's Changed in 4.115.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload command run analytics in the background by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.114.0...4.115.0

## What's Changed in 4.114.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* OIDC support Bitrise and CircleCI by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* parsing XCActivityLog on Xcode 26.2 and newer by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.113.0...4.114.0

## What's Changed in 4.113.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* OIDC token support for GitHub Actions by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.112.0...4.113.0

## What's Changed in 4.112.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* account tokens by [@fortmarek](https://github.com/fortmarek)
* report module cache subhashes by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* respect explicit cache profile none with target focus by [@hiltonc](https://github.com/hiltonc)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.3...4.112.0

## What's Changed in 4.110.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle skipped tests due to a failed build by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.2...4.110.3

## What's Changed in 4.110.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* false positive for a .uiTests implicit import of .app by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.1...4.110.2

## What's Changed in 4.110.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* duration for test cases with custom label by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.0...4.110.1

## What's Changed in 4.110.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* deprecate tuist build command by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.109.2...4.110.0

## What's Changed in 4.109.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* relegate test result upload error to a warning by [@fortmarek](https://github.com/fortmarek)
* Don't replace targeted external dependencies with cached binary by [@hiltonc](https://github.com/hiltonc)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.109.0...4.109.2

## What's Changed in 4.109.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* link tests to builds by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* Remove CLANG_CXX_LIBRARY essential build setting by [@alexmx](https://github.com/alexmx)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.108.0...4.109.0

## What's Changed in 4.108.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track CI run id for test insights by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.107.2...4.108.0

## What's Changed in 4.107.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove fullHandle requirement for tuist registry setup by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.107.1...4.107.2

## What's Changed in 4.107.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add test insights by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* duplicated XCFrameworks in embed phase by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.106.3...4.107.1

## What's Changed in 4.106.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* pin swift-collections below 1.3.0 by [@fortmarek](https://github.com/fortmarek)
* skip warning Swift flags when hashing by [@fortmarek](https://github.com/fortmarek)
* prefer products with matching casing by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.106.1...4.106.3

## What's Changed in 4.106.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* open registry by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* external dependency case insensitive lookup by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.105.1...4.106.1

## What's Changed in 4.105.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix false negative implicit import detection of transitive local dependencies by [@Kolos65](https://github.com/Kolos65)
* refreshing token data race by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.105.0...4.105.1

## What's Changed in 4.105.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* improve error message of tuist inspect implicit-imports by [@n-zaitsev](https://github.com/n-zaitsev)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.7...4.105.0

## What's Changed in 4.104.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resolve token refresh data race in ServerAuthenticationController by [@fortmarek](https://github.com/fortmarek)
* skip hashing Xcode version by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.5...4.104.7

## What's Changed in 4.104.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add Emerge Tools SnapshottingTests to the list of targets that depend on XCTest by [@duarteich](https://github.com/duarteich)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.4...4.104.5

## What's Changed in 4.104.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* respect xcframework status by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.3...4.104.4

## What's Changed in 4.104.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* duplicate CAS outputs by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.2...4.104.3

## What's Changed in 4.104.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* skip hashing lockfiles by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.1...4.104.2

## What's Changed in 4.104.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* misreported Xcode cache analytics by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.0...4.104.1

## What's Changed in 4.104.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* connect directly to the cache endpoint by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.103.0...4.104.0

## What's Changed in 4.103.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track cas outputs type and cacheable task description by [@fortmarek](https://github.com/fortmarek)
* track cacheable task description by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* Add extended string delimiter to Strings value in PlistsTemplate by [@ast3150](https://github.com/ast3150)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.101.0...4.103.0

## What's Changed in 4.101.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track cache key read/write latency by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.100.0...4.101.0

## What's Changed in 4.100.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* cas output analytics by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.99.2...4.100.0

## What's Changed in 4.99.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* ensure disableSandbox config is used when dumping package manifests by [@pepicrft](https://github.com/pepicrft)
* support import kind declarations in inspect by [@hiltonc](https://github.com/hiltonc)
* cache Config manifest to improve performance by [@hiltonc](https://github.com/hiltonc)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.99.1...4.99.2

## What's Changed in 4.99.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix buildable folder resource placement for static targets by [@natanrolnik](https://github.com/natanrolnik)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.99.0...4.99.1

## What's Changed in 4.99.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* optimize Xcode cache by compressing CAS artifacts by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.98.0...4.99.0

## What's Changed in 4.98.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Optimize cache hit detection and add diagnostic remarks by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.97.2...4.98.0

## What's Changed in 4.97.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* clean up warnings by [@waltflanagan](https://github.com/waltflanagan)
* fix content hashing to use relative path when file does not exist by [@waltflanagan](https://github.com/waltflanagan)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.97.0...4.97.2

## What's Changed in 4.97.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add cache profiles to fine tune cached binary replacement by [@hiltonc](https://github.com/hiltonc)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.96.0...4.97.0

## What's Changed in 4.96.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for SwiftPM disableWarning setting by [@pepicrft](https://github.com/pepicrft)
* improve upload error handling for cache artifacts by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.95.1...4.96.0

## What's Changed in 4.95.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* downgrade duplicated product name linting from error to warning by [@n-zaitsev](https://github.com/n-zaitsev)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.95.0...4.95.1

## What's Changed in 4.95.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for passing arguments to SwiftPM by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.94.0...4.95.0

## What's Changed in 4.94.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add support for Swift Package Manager strictMemorySafety setting by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.93.0...4.94.0

## What's Changed in 4.93.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* xcode cache analytics by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.92.1...4.93.0

## What's Changed in 4.92.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Add support for Internal Imports By Default for Asset accessors by [@PSKuznetsov](https://github.com/PSKuznetsov)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.92.0...4.92.1

## What's Changed in 4.92.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add cache daemon logs by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.91.1...4.92.0

## What's Changed in 4.91.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Multiple targets with same hash by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.91.0...4.91.1

## What's Changed in 4.91.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Default to no concurrency limit when doing cache uploads and downloads by [@pepicrft](https://github.com/pepicrft)
### 🐛 Bug Fixes

* Bundle accessor not being generated for txt, js or json resources by [@natanrolnik](https://github.com/natanrolnik)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.90.0...4.91.0

## What's Changed in 4.90.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add support for TUIST_-prefixed XDG environment variables by [@pepicrft](https://github.com/pepicrft)
### 🐛 Bug Fixes

* improve error messages of cache daemon by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.89.1...4.90.0

## What's Changed in 4.89.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use TUIST_CONFIG_TOKEN when launching the cache daemon by [@fortmarek](https://github.com/fortmarek)
* ignore macros in inspect redundant dependencies by [@hiltonc](https://github.com/hiltonc)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.89.0...4.89.1

## What's Changed in 4.89.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Only use binaries for external dependencies when no focus target is passed to `tuist generate` by [@pepicrft](https://github.com/pepicrft)
* Add --skip-unit-tests parameter to tuist test command by [@RomanAnpilov](https://github.com/RomanAnpilov)
### 🐛 Bug Fixes

* ignore unit test host app in inspect redundant dependencies by [@hiltonc](https://github.com/hiltonc)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.88.0...4.89.0

## What's Changed in 4.88.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* don't restrict which kind of token is used based on the environment by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.87.0...4.88.0

## What's Changed in 4.87.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* tuist setup cache command by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.4...4.87.0

## What's Changed in 4.86.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add individual target sub-hashes for debugging by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.3...4.86.4

## What's Changed in 4.86.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Add support for `.xcdatamodel` opaque directories by [@MouadBenjrinija](https://github.com/MouadBenjrinija)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.2...4.86.3

## What's Changed in 4.86.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't throw file not found when hashing generated source files by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.1...4.86.2

## What's Changed in 4.86.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* mysteriously vanished binaries by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.0...4.86.1

## What's Changed in 4.86.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Xcode cache server by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.85.2...4.86.0

## What's Changed in 4.85.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* extend inspect build to 5 seconds by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.85.1...4.85.2

## What's Changed in 4.85.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Generated projects with binaries not replacing some targets with macros as transitive dependencies by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.85.0...4.85.1

## What's Changed in 4.85.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Optimize resource interface synthesis through parallelization by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.3...4.85.0

## What's Changed in 4.84.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't report clean action by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.2...4.84.3

## What's Changed in 4.84.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Handle target action input and output file paths that contain variables by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.1...4.84.2

## What's Changed in 4.84.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* align 'tuist hash cache' to use same generator as cache warming by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.0...4.84.1

## What's Changed in 4.84.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Improve remote cache error handling by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.83.0...4.84.0

## What's Changed in 4.83.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Support the `defaultIsolation` setting when integrating packages using native Xcode project targets by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.82.3...4.83.0

## What's Changed in 4.82.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* clean up downloaded binary artifacts from temporary directory by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.82.2...4.82.3

## What's Changed in 4.82.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't convert script input and output file list paths relative to manifest paths or with build variables to absolute by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.82.1...4.82.2

## What's Changed in 4.82.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add bundle type by [@fortmarek](https://github.com/fortmarek)
### 🐛 Bug Fixes

* Ensure buildableFolder resources are handled with project-defined resourceSynthesizers. by [@Monsteel](https://github.com/Monsteel)
* align with the latest Tuist API by [@fortmarek](https://github.com/fortmarek)
* path to the PackageDescription in projects generated by tuist edit by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.81.0...4.82.1

## What's Changed in 4.81.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Make implicit import detection work with buildable folders by [@pepicrft](https://github.com/pepicrft)
* add CI run reference to build runs by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.80.0...4.81.0

## What's Changed in 4.80.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Report server-side payment-required responses as warnings by [@pepicrft](https://github.com/pepicrft)
* add configuration to build insights by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.7...4.80.0

## What's Changed in 4.79.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Only validate cache signatures on successful responses by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.6...4.79.7

## What's Changed in 4.79.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix cache warming when external targets are excluded by platform conditions by [@pepicrft](https://github.com/pepicrft)
* don't mark inspected build as failed when it has warnings only by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.4...4.79.6

## What's Changed in 4.79.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Add support for headers in buildable folders by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.3...4.79.4

## What's Changed in 4.79.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix synthesized bundle interfaces not generated for `.xcassets` in buildable folders by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.2...4.79.3

## What's Changed in 4.79.2<!-- RELEASE NOTES START -->

### 🧪 Testing

* fix acceptance tests by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.1...4.79.2

## What's Changed in 4.79.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Make `excluded` optional in buildable folder exceptions by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.0...4.79.1

## What's Changed in 4.79.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Support exclusion of files and configuration of compiler flags for files in buildable folders by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.4...4.79.0

## What's Changed in 4.78.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Downgrade ProjectDescription Swift version to 6.1 by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.3...4.78.4

## What's Changed in 4.78.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* show Products file group in Xcode navigator by [@YIshihara11201](https://github.com/YIshihara11201)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.2...4.78.3

## What's Changed in 4.78.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* adjust NIOFileSystem references by [@fortmarek](https://github.com/fortmarek)
* handle warnings from the underlying assetutil info when inspecting bundles by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.1...4.78.2

## What's Changed in 4.78.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add default.metallib in static framework by [@bilousoleksandr](https://github.com/bilousoleksandr)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.0...4.78.1

## What's Changed in 4.78.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* change sandbox to be opt-in by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.77.0...4.78.0

## What's Changed in 4.77.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Increase the security of the cache surface by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.76.1...4.77.0

## What's Changed in 4.76.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Invalid generated projects when projects are generated with binaries keeping sources and targets by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.76.0...4.76.1

## What's Changed in 4.76.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add SE-0162 support for custom SPM target layouts by [@devyhan](https://github.com/devyhan)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.75.0...4.76.0

## What's Changed in 4.75.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add unordered xcodebuild command support by [@yusufozgul](https://github.com/yusufozgul)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.74.1...4.75.0

## What's Changed in 4.74.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Increase the refresh token timeout period by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.74.0...4.74.1

## What's Changed in 4.74.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Verbose-log the concurrency limit used by the cache for network connections by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.73.0...4.74.0

## What's Changed in 4.73.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for configuring the cache request concurrency limit by [@pepicrft](https://github.com/pepicrft)
### 🐛 Bug Fixes

* tuist cache failing due to the new BuildOperationMetrics attachment type by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.72.0...4.73.0

## What's Changed in 4.72.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Remove user credentials when the token sent on refresh is invalid by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.71.0...4.72.0

## What's Changed in 4.71.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* generate tests using Swift Testing instead of XCTest by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.70.0...4.71.0

## What's Changed in 4.70.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Don't focus when keeping the sources for targets replaced by binaries by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.69.0...4.70.0

## What's Changed in 4.69.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* update Swift package resolution to use -scmProvider system by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.68.0...4.69.0

## What's Changed in 4.68.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add additionalPackageResolutionArguments for xcodebuild by [@ichikmarev](https://github.com/ichikmarev)
### 🐛 Bug Fixes

* not generate bundle accessors in when buildable folders don't resolve to any resources by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.67.2...4.68.0

## What's Changed in 4.67.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generate bundle accessor when a module has only buildable folders by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.67.1...4.67.2

## What's Changed in 4.67.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* default to caching the manifests by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.67.0...4.67.1

## What's Changed in 4.67.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* optimize dependency conditions calculation by [@mikhailmulyar](https://github.com/mikhailmulyar)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.66.1...4.67.0

## What's Changed in 4.66.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* XCFramework signature by [@mikhailmulyar](https://github.com/mikhailmulyar)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.66.0...4.66.1

## What's Changed in 4.66.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* skip remote cache downloads on failure by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.7...4.66.0

## What's Changed in 4.65.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generate bundle accessor for modules with metal files by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.6...4.65.7

## What's Changed in 4.65.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* missing bundle accessor when the target uses buildable folders by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.5...4.65.6

## What's Changed in 4.65.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* unable to create account tokens to access the registry by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.4...4.65.5

## What's Changed in 4.65.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* CocoaPods unable to install dependencies due to project's `objectVersion` by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.3...4.65.4

## What's Changed in 4.65.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* arch incompatibilities when using the cache by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.2...4.65.3

## What's Changed in 4.65.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* caching issues due to incompatible architectures by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.1...4.65.2

## What's Changed in 4.65.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* revert caching only the default architecture by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.0...4.65.1

## What's Changed in 4.65.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add filePath and customWorkingDirectory support to RunAction by [@plu](https://github.com/plu)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.64.2...4.65.0

## What's Changed in 4.64.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use XcodeGraph for XcodeKit SDK support by [@navtoj](https://github.com/navtoj)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.64.1...4.64.2

## What's Changed in 4.64.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* relative path for local package by [@mikhailmulyar](https://github.com/mikhailmulyar)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.64.0...4.64.1

## What's Changed in 4.64.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* improve passthrough argument documentation with usage examples by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.3...4.64.0

## What's Changed in 4.63.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* include pagination data when listing the bundles as a json by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.2...4.63.3

## What's Changed in 4.63.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* `bundle show` failing due to wrong data passed by the cli by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.1...4.63.2

## What's Changed in 4.63.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* `tuist run` fails to run a scheme even though it has runnable targets by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.0...4.63.1

## What's Changed in 4.63.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add commands to list and read bundles by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.62.0...4.63.0

## What's Changed in 4.62.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for buildable folders by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.61.2...4.62.0

## What's Changed in 4.61.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* platform conditions not applied for binary dependencies in external packages by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.61.1...4.61.2

## What's Changed in 4.61.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generation regression by [@pepicrft](https://github.com/pepicrft)
* fetching devices when running previews by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.61.0...4.61.1

## What's Changed in 4.61.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for keeping the sources of the targets replaced by binaries by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.60.0...4.61.0

## What's Changed in 4.60.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* support hashing transitive `.xcconfig` files by [@mikhailmulyar](https://github.com/mikhailmulyar)
* add support for XcodeKit SDK by [@navtoj](https://github.com/navtoj)
### 🐛 Bug Fixes

* use Xcode default for which architectures are built by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.59.2...4.60.0

## What's Changed in 4.59.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* unexpected behaviours when renaming resources in cached targets by [@mikhailmulyar](https://github.com/mikhailmulyar)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.59.1...4.59.2

## What's Changed in 4.59.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* prevent metal files from being processed as resources. by [@DenTelezhkin](https://github.com/DenTelezhkin)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.59.0...4.59.1

## What's Changed in 4.59.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* cache binaries by default for arm64 only, add --architectures option to specify architectures by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.58.1...4.59.0

## What's Changed in 4.58.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* include project settings hash in target hash by [@mikhailmulyar](https://github.com/mikhailmulyar)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.58.0...4.58.1

## What's Changed in 4.58.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* print the full sandbox command when a system command fails by [@hiltonc](https://github.com/hiltonc)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.57.1...4.58.0

## What's Changed in 4.57.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* treat the new .icon asset as an opaque directory by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.57.0...4.57.1

## What's Changed in 4.57.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for running macOS app via `tuist run` by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.56.1...4.57.0

## What's Changed in 4.56.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* auto-generated *-Workspace scheme not getting generated by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.56.0...4.56.1

## What's Changed in 4.56.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Ignore internal server errors when interating with the cache by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.9...4.56.0

## What's Changed in 4.55.9<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* do not link cached frameworks with linking status .none by [@fortmarek](https://github.com/fortmarek)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.8...4.55.9

## What's Changed in 4.55.8<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* 'tuist version' shows the optional string by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.7...4.55.8

## What's Changed in 4.55.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix cli not launching because ProjectAutomation's dynamic framework can't be found by [@pepicrft](https://github.com/pepicrft)
* token refresh race condition by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.6...4.55.7

<!-- generated by git-cliff -->
