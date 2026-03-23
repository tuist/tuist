# Changelog

All notable changes to this project will be documented in this file.
## What's Changed in 4.162.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix static framework resource bundle crash when using xcstrings by [@pepicrft](https://github.com/pepicrft) in [#9953](https://github.com/tuist/tuist/pull/9953)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.162.0...4.162.1

## What's Changed in 4.162.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add storages option to cache configuration by [@fortmarek](https://github.com/fortmarek) in [#9938](https://github.com/tuist/tuist/pull/9938)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.161.4...4.162.0

## What's Changed in 4.161.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove unsupported DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER build setting by [@fortmarek](https://github.com/fortmarek) in [#9940](https://github.com/tuist/tuist/pull/9940)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.161.3...4.161.4

## What's Changed in 4.161.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* increase URLSession max connections per host to 20 by [@fortmarek](https://github.com/fortmarek) in [#9931](https://github.com/tuist/tuist/pull/9931)
* normalize swift package target names with spaces by [@pepicrft](https://github.com/pepicrft) in [#9928](https://github.com/tuist/tuist/pull/9928)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.161.1...4.161.3

## What's Changed in 4.161.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* process builds remotely by [@fortmarek](https://github.com/fortmarek) in [#9911](https://github.com/tuist/tuist/pull/9911)
### 🐛 Bug Fixes

* prevent xcstrings stale extraction state in static targets by [@pepicrft](https://github.com/pepicrft) in [#9907](https://github.com/tuist/tuist/pull/9907)
* use SDK-conditioned FRAMEWORK_SEARCH_PATHS for xcframeworks by [@wojmangh](https://github.com/wojmangh) in [#9902](https://github.com/tuist/tuist/pull/9902)
* resolve merge commit to actual PR head SHA by [@fortmarek](https://github.com/fortmarek) in [#9905](https://github.com/tuist/tuist/pull/9905)
* only record /cache/ac hashes for test targets, not their deps by [@fortmarek](https://github.com/fortmarek) in [#9909](https://github.com/tuist/tuist/pull/9909)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.160.3...4.161.1

## What's Changed in 4.160.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* redact sensitive headers in verbose HTTP logs by [@fortmarek](https://github.com/fortmarek) in [#9906](https://github.com/tuist/tuist/pull/9906)
* restore TuistCacheEE submodule pointer to include empty graph fix by [@fortmarek](https://github.com/fortmarek) in [#9904](https://github.com/tuist/tuist/pull/9904)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.160.1...4.160.3

## What's Changed in 4.160.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* log test targets that will be tested by [@pepicrft](https://github.com/pepicrft) in [#9731](https://github.com/tuist/tuist/pull/9731)
### 🐛 Bug Fixes

* use xcactivitylog UUID as build ID for remote processing by [@fortmarek](https://github.com/fortmarek) in [#9897](https://github.com/tuist/tuist/pull/9897)
* allow iOS bundle targets to have dependencies by [@fortmarek](https://github.com/fortmarek) in [#9883](https://github.com/tuist/tuist/pull/9883)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.159.0...4.160.1

## What's Changed in 4.159.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload CLI session to S3 after command event creation by [@fortmarek](https://github.com/fortmarek) in [#9870](https://github.com/tuist/tuist/pull/9870)
### 🐛 Bug Fixes

* add audio and video file extensions to validResourceExtensions by [@natanrolnik](https://github.com/natanrolnik) in [#9800](https://github.com/tuist/tuist/pull/9800)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.158.2...4.159.0

## What's Changed in 4.158.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use CFBundleExecutable for binary lookup in tuist share by [@fortmarek](https://github.com/fortmarek) in [#9840](https://github.com/tuist/tuist/pull/9840)
* correct SYMROOT path in cache warm builds by [@fortmarek](https://github.com/fortmarek) in [#9833](https://github.com/tuist/tuist/pull/9833)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.158.0...4.158.2

## What's Changed in 4.158.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* server-side xcactivitylog processing by [@fortmarek](https://github.com/fortmarek) in [#9752](https://github.com/tuist/tuist/pull/9752)
### 🐛 Bug Fixes

* filter pruned test targets from -only-testing flags by [@fortmarek](https://github.com/fortmarek) in [#9823](https://github.com/tuist/tuist/pull/9823)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.157.4...4.158.0

## What's Changed in 4.157.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resolve --path flag not working for tuist setup cache by [@fortmarek](https://github.com/fortmarek) in [#9826](https://github.com/tuist/tuist/pull/9826)
* use modern launchctl bootstrap/bootout for cache daemon by [@fortmarek](https://github.com/fortmarek) in [#9819](https://github.com/tuist/tuist/pull/9819)
* use modern launchctl bootstrap/bootout for cache daemon by [@fortmarek](https://github.com/fortmarek) in [#9815](https://github.com/tuist/tuist/pull/9815)
* skip binary cache mapping when graph is empty after selective testing by [@fortmarek](https://github.com/fortmarek) in [#9814](https://github.com/tuist/tuist/pull/9814)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.157.1...4.157.4

## What's Changed in 4.157.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add watch2AppContainer product type for watchOS-only apps by [@BugorBN](https://github.com/BugorBN) in [#9648](https://github.com/tuist/tuist/pull/9648)
### 🐛 Bug Fixes

* resolve missing module dependencies with cached local frameworks by [@pepicrft](https://github.com/pepicrft) in [#9805](https://github.com/tuist/tuist/pull/9805)
* override SYMROOT in cache warm builds to prevent custom build location mismatch by [@gnejfejf2](https://github.com/gnejfejf2) in [#9803](https://github.com/tuist/tuist/pull/9803)
* restore generate run analytics on dashboard by [@fortmarek](https://github.com/fortmarek) in [#9795](https://github.com/tuist/tuist/pull/9795)
* handle selectively-pruned targets in --test-targets validation by [@fortmarek](https://github.com/fortmarek) in [#9783](https://github.com/tuist/tuist/pull/9783)
* include all platform-matching xcframework slices in FRAMEWORK_SEARCH_PATHS by [@ngs](https://github.com/ngs) in [#9730](https://github.com/tuist/tuist/pull/9730)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.156.0...4.157.1

## What's Changed in 4.156.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track machine metrics by [@fortmarek](https://github.com/fortmarek) in [#9760](https://github.com/tuist/tuist/pull/9760)
### 🐛 Bug Fixes

* support OIDC account tokens for registry login on CI by [@pepicrft](https://github.com/pepicrft) in [#9769](https://github.com/tuist/tuist/pull/9769)
* fix build category detection for Xcode 26.3+ with compilation cache by [@fortmarek](https://github.com/fortmarek) in [#9762](https://github.com/tuist/tuist/pull/9762)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.4...4.156.0

## What's Changed in 4.155.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* archive builds for static targets with xcassets by [@Iron-Ham](https://github.com/Iron-Ham) in [#9722](https://github.com/tuist/tuist/pull/9722)
* prevent multiple commands produce when static product depends on same-named xcframework by [@pepicrft](https://github.com/pepicrft) in [#9758](https://github.com/tuist/tuist/pull/9758)
* exclude non-test-dependency targets from workspace scheme build action by [@fortmarek](https://github.com/fortmarek) in [#9741](https://github.com/tuist/tuist/pull/9741)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.2...4.155.4

## What's Changed in 4.155.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* expose ProjectDescription product on Linux for DocC generation by [@pepicrft](https://github.com/pepicrft) in [#9745](https://github.com/tuist/tuist/pull/9745)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.1...4.155.2

## What's Changed in 4.155.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* correctly detect incremental builds with Xcode compilation cache by [@fortmarek](https://github.com/fortmarek) in [#9725](https://github.com/tuist/tuist/pull/9725)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.0...4.155.1

## What's Changed in 4.155.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* group test attachments by repetition by [@fortmarek](https://github.com/fortmarek) in [#9714](https://github.com/tuist/tuist/pull/9714)
### 🐛 Bug Fixes

* bump Rosalind to 0.7.22 and restore dependency versions by [@fortmarek](https://github.com/fortmarek) in [#9720](https://github.com/tuist/tuist/pull/9720)
* propagate module map flags to configuration-level setting overrides by [@pepicrft](https://github.com/pepicrft) in [#9692](https://github.com/tuist/tuist/pull/9692)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.154.4...4.155.0

## What's Changed in 4.154.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* bump Rosalind to 0.7.22 and swift-protobuf to 1.35.1 by [@fortmarek](https://github.com/fortmarek) in [#9701](https://github.com/tuist/tuist/pull/9701)
* fix build categorization for Xcode 26+ compilation cache by [@fortmarek](https://github.com/fortmarek) in [#9689](https://github.com/tuist/tuist/pull/9689)
* bump XCLogParser to 0.2.46 and improve activity log error messages by [@fortmarek](https://github.com/fortmarek) in [#9691](https://github.com/tuist/tuist/pull/9691)
### 📚 Documentation

* replace SourceDocs ProjectDescription reference with DocC by [@pepicrft](https://github.com/pepicrft) in [#9637](https://github.com/tuist/tuist/pull/9637)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.154.1...4.154.4

## What's Changed in 4.154.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix buildable-folder header visibility and generation crash by [@pepicrft](https://github.com/pepicrft) in [#9604](https://github.com/tuist/tuist/pull/9604)
* treat opaque directories as files in buildable folder resolution by [@pepicrft](https://github.com/pepicrft) in [#9683](https://github.com/tuist/tuist/pull/9683)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.154.0...4.154.1

## What's Changed in 4.154.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload and display all test attachments from xcresult bundles by [@fortmarek](https://github.com/fortmarek) in [#9630](https://github.com/tuist/tuist/pull/9630)
* make tuist inspect bundle available on Linux by [@fortmarek](https://github.com/fortmarek) in [#9644](https://github.com/tuist/tuist/pull/9644)
* prune old binary cache entries on startup by [@pepicrft](https://github.com/pepicrft)
* vendor XcodeGraph into tuist and reconcile dependency graphs by [@pepicrft](https://github.com/pepicrft) in [#9616](https://github.com/tuist/tuist/pull/9616)
* add "Ask on Launch" executable option for scheme actions by [@FelixLisczyk](https://github.com/FelixLisczyk) in [#9373](https://github.com/tuist/tuist/pull/9373)
* add warningsAsErrors generation option by [@fortmarek](https://github.com/fortmarek) in [#9574](https://github.com/tuist/tuist/pull/9574)
### 🐛 Bug Fixes

* include transitive search paths through dynamic framework dependencies by [@pepicrft](https://github.com/pepicrft) in [#9681](https://github.com/tuist/tuist/pull/9681)
* exclude directories from buildable folder resolved files by [@fortmarek](https://github.com/fortmarek) in [#9678](https://github.com/tuist/tuist/pull/9678)
* cap concurrency to avoid file descriptor exhaustion by [@fortmarek](https://github.com/fortmarek) in [#9677](https://github.com/tuist/tuist/pull/9677)
* Fix case-insensitive prioritize local packages over registry by [@fdiaz](https://github.com/fdiaz) in [#9673](https://github.com/tuist/tuist/pull/9673)
* add xcassets and xcstrings to sources build phase for static targets by [@pepicrft](https://github.com/pepicrft) in [#9666](https://github.com/tuist/tuist/pull/9666)
* update Command package to 0.14.0 by [@fortmarek](https://github.com/fortmarek) in [#9657](https://github.com/tuist/tuist/pull/9657)
* make CacheLocalStorage.clean public by [@fortmarek](https://github.com/fortmarek) in [#9647](https://github.com/tuist/tuist/pull/9647)
* bump FileSystem to 0.15.0 for setFileTimes support by [@fortmarek](https://github.com/fortmarek) in [#9646](https://github.com/tuist/tuist/pull/9646)
* sort Set iterations in graph mappers for deterministic cache hashing by [@fortmarek](https://github.com/fortmarek) in [#9629](https://github.com/tuist/tuist/pull/9629)
* limit concurrency of buildable folder resolution to avoid FD exhaustion by [@fortmarek](https://github.com/fortmarek) in [#9626](https://github.com/tuist/tuist/pull/9626)
* add validation folder exists for BuildableFolder by [@ivan-gaydamakin](https://github.com/ivan-gaydamakin) in [#9609](https://github.com/tuist/tuist/pull/9609)
* prune static xcframework deps from dynamic xcframeworks for hostless unit tests by [@pepicrft](https://github.com/pepicrft) in [#9602](https://github.com/tuist/tuist/pull/9602)
* upload APK files directly instead of wrapping in zip by [@fortmarek](https://github.com/fortmarek) in [#9581](https://github.com/tuist/tuist/pull/9581)
* populate explicitFolders for excluded directories in buildable folders by [@fortmarek](https://github.com/fortmarek) in [#9578](https://github.com/tuist/tuist/pull/9578)
### 🚜 Refactor

* migrate acceptance tests to Swift Testing by [@pepicrft](https://github.com/pepicrft) in [#9352](https://github.com/tuist/tuist/pull/9352)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.151.1...4.154.0

## What's Changed in 4.151.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* replace deprecated tuist build recommendation in previews by [@fortmarek](https://github.com/fortmarek) in [#9562](https://github.com/tuist/tuist/pull/9562)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.151.0...4.151.1

## What's Changed in 4.151.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* expand glob patterns in buildable folder exclusions by [@InderKumarRathore](https://github.com/InderKumarRathore) in [#9552](https://github.com/tuist/tuist/pull/9552)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.150.1...4.151.0

## What's Changed in 4.150.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* expanding folder to input inner files when used as input in foreign build phase script by [@scarayaa](https://github.com/scarayaa) in [#9556](https://github.com/tuist/tuist/pull/9556)
* place precompiled dependencies from SPM build directory in frameworks group by [@JanC](https://github.com/JanC) in [#9555](https://github.com/tuist/tuist/pull/9555)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.150.0...4.150.1

## What's Changed in 4.150.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add platformFilters for buildable folder exceptions by [@fortmarek](https://github.com/fortmarek) in [#9545](https://github.com/tuist/tuist/pull/9545)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.149.1...4.150.0

## What's Changed in 4.149.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Use latest Gradle plugin version in init and add takeaways by [@fortmarek](https://github.com/fortmarek) in [#9543](https://github.com/tuist/tuist/pull/9543)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.149.0...4.149.1

## What's Changed in 4.149.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Android APK previews with cross-platform share and run by [@fortmarek](https://github.com/fortmarek) in [#9509](https://github.com/tuist/tuist/pull/9509)
### 🐛 Bug Fixes

* Prioritize local packages over registry versions by [@fdiaz](https://github.com/fdiaz) in [#9540](https://github.com/tuist/tuist/pull/9540)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.148.4...4.149.0

## What's Changed in 4.148.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* apply PackageSettings.baseSettings.defaultSettings to SPM targets by [@hiltonc](https://github.com/hiltonc) in [#9301](https://github.com/tuist/tuist/pull/9301)
* restore SRCROOT path resolution for cached target settings by [@fortmarek](https://github.com/fortmarek) in [#9531](https://github.com/tuist/tuist/pull/9531)
* respect custom server url by [@yusufozgul](https://github.com/yusufozgul) in [#9524](https://github.com/tuist/tuist/pull/9524)
* include buildable folder resources in Target.containsResources by [@hiltonc](https://github.com/hiltonc) in [#9290](https://github.com/tuist/tuist/pull/9290)
* use product name as module name for SPM wrapper targets by [@pepicrft](https://github.com/pepicrft) in [#9370](https://github.com/tuist/tuist/pull/9370)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.148.1...4.148.4

## What's Changed in 4.148.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Android bundle support (AAB + APK) by [@fortmarek](https://github.com/fortmarek) in [#9506](https://github.com/tuist/tuist/pull/9506)
* crash stack traces with formatted frames, attachments, and download URLs by [@fortmarek](https://github.com/fortmarek) in [#9436](https://github.com/tuist/tuist/pull/9436)
### 🐛 Bug Fixes

* pass jsonThroughNoora to Noora on Linux by [@fortmarek](https://github.com/fortmarek) in [#9516](https://github.com/tuist/tuist/pull/9516)
* bump xcode version release by [@fortmarek](https://github.com/fortmarek) in [#9511](https://github.com/tuist/tuist/pull/9511)
* preserve JSON logger for non-Noora commands on Linux by [@fortmarek](https://github.com/fortmarek) in [#9510](https://github.com/tuist/tuist/pull/9510)
* don't run foreign build script when target is served from binary cache by [@fortmarek](https://github.com/fortmarek) in [#9501](https://github.com/tuist/tuist/pull/9501)
* sanitize + character in intra-package target dependency names by [@pepicrft](https://github.com/pepicrft) in [#9437](https://github.com/tuist/tuist/pull/9437)
* warn when skip test targets don't intersect by [@pepicrft](https://github.com/pepicrft) in [#9487](https://github.com/tuist/tuist/pull/9487)
* add Swift toolchain library search path for ObjC targets linking static Swift dependencies by [@pepicrft](https://github.com/pepicrft) in [#9483](https://github.com/tuist/tuist/pull/9483)
* resolve static ObjC xcframework search paths without Package.swift by [@pepicrft](https://github.com/pepicrft) in [#9440](https://github.com/tuist/tuist/pull/9440)
* enable HTTP logging and server warnings on Linux by [@fortmarek](https://github.com/fortmarek) in [#9479](https://github.com/tuist/tuist/pull/9479)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.146.1...4.148.1

## What's Changed in 4.146.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix cache building unnecessary Catalyst scheme for external dependencies by [@fortmarek](https://github.com/fortmarek) in [#9476](https://github.com/tuist/tuist/pull/9476)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.146.0...4.146.1

## What's Changed in 4.146.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add foreign build system dependencies by [@fortmarek](https://github.com/fortmarek) in [#9400](https://github.com/tuist/tuist/pull/9400)
### 🐛 Bug Fixes

* restore TuistSimulator to macOS-only block in Package.swift by [@fortmarek](https://github.com/fortmarek) in [#9468](https://github.com/tuist/tuist/pull/9468)
* increase inspect build activity log timeout and make it configurable by [@fortmarek](https://github.com/fortmarek) in [#9465](https://github.com/tuist/tuist/pull/9465)
* fix CLI release (static linking, Musl imports, Bundle(for:)) by [@fortmarek](https://github.com/fortmarek) in [#9459](https://github.com/tuist/tuist/pull/9459)
* use canImport(Musl) for Static Linux SDK compatibility by [@fortmarek](https://github.com/fortmarek) in [#9457](https://github.com/tuist/tuist/pull/9457)
* remove OpenAPIURLSession from cross-platform targets for Linux static SDK by [@fortmarek](https://github.com/fortmarek) in [#9456](https://github.com/tuist/tuist/pull/9456)
* restore cache run analytics on dashboard by [@fortmarek](https://github.com/fortmarek) in [#9451](https://github.com/tuist/tuist/pull/9451)
* only cache dependency checkouts in Linux CI jobs by [@fortmarek](https://github.com/fortmarek) in [#9447](https://github.com/tuist/tuist/pull/9447)
* add missing tree-shake after focus targets in automation mapper chain by [@pepicrft](https://github.com/pepicrft) in [#9443](https://github.com/tuist/tuist/pull/9443)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.145.0...4.146.0

## What's Changed in 4.145.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* support build system selection in project create by [@fortmarek](https://github.com/fortmarek) in [#9432](https://github.com/tuist/tuist/pull/9432)
### 🐛 Bug Fixes

* remove unused CacheBuiltArtifactsFetcher from CacheWarmCommandService by [@fortmarek](https://github.com/fortmarek) in [#9434](https://github.com/tuist/tuist/pull/9434)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.4...4.145.0

## What's Changed in 4.144.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fall back to BUILD_DIR for derived data resolution by [@fortmarek](https://github.com/fortmarek) in [#9429](https://github.com/tuist/tuist/pull/9429)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.3...4.144.4

## What's Changed in 4.144.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* embed cached static xcframeworks with resources transitively by [@pepicrft](https://github.com/pepicrft) in [#9419](https://github.com/tuist/tuist/pull/9419)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.2...4.144.3

## What's Changed in 4.144.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* run StaticXCFrameworkModuleMapGraphMapper after cache replacement by [@pepicrft](https://github.com/pepicrft) in [#9427](https://github.com/tuist/tuist/pull/9427)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.1...4.144.2

## What's Changed in 4.144.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix flaky tests caused by Matcher.register race and TOCTOU in CachedManifestLoader by [@fortmarek](https://github.com/fortmarek) in [#9424](https://github.com/tuist/tuist/pull/9424)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.0...4.144.1

## What's Changed in 4.144.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Gradle project integration to tuist init by [@fortmarek](https://github.com/fortmarek) in [#9422](https://github.com/tuist/tuist/pull/9422)
* add test case show and run commands with fix-flaky-tests skill by [@fortmarek](https://github.com/fortmarek) in [#9379](https://github.com/tuist/tuist/pull/9379)
### 🐛 Bug Fixes

* resolve derived data path from DERIVED_DATA_DIR env in inspect commands by [@fortmarek](https://github.com/fortmarek) in [#9396](https://github.com/tuist/tuist/pull/9396)
* use correct TUIST_URL key for env variable lookup in login command by [@fortmarek](https://github.com/fortmarek) in [#9398](https://github.com/tuist/tuist/pull/9398)
* strip debug symbols (dSYM/DWARF) from cached XCFrameworks by [@pepicrft](https://github.com/pepicrft) in [#9287](https://github.com/tuist/tuist/pull/9287)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.142.1...4.144.0

## What's Changed in 4.142.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* make server commands available on Linux by [@fortmarek](https://github.com/fortmarek) in [#9377](https://github.com/tuist/tuist/pull/9377)
### 🐛 Bug Fixes

* don't retry non-retryable errors in module cache download by [@fortmarek](https://github.com/fortmarek) in [#9394](https://github.com/tuist/tuist/pull/9394)
* restore asset symbol generation for external static frameworks by [@pepicrft](https://github.com/pepicrft) in [#9382](https://github.com/tuist/tuist/pull/9382)
* use correct bundle accessor for external dynamic frameworks with resources by [@pepicrft](https://github.com/pepicrft) in [#9381](https://github.com/tuist/tuist/pull/9381)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.141.1...4.142.1

## What's Changed in 4.141.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add debug logging to inspect build and test commands by [@fortmarek](https://github.com/fortmarek) in [#9384](https://github.com/tuist/tuist/pull/9384)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.141.0...4.141.1

## What's Changed in 4.141.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add tuist.toml support by [@fortmarek](https://github.com/fortmarek) in [#9368](https://github.com/tuist/tuist/pull/9368)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.140.2...4.141.0

## What's Changed in 4.140.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* skip macro targets in static dependency traversal by [@pepicrft](https://github.com/pepicrft) in [#9337](https://github.com/tuist/tuist/pull/9337)
* add retry logic to OIDC authentication flow by [@fortmarek](https://github.com/fortmarek) in [#9365](https://github.com/tuist/tuist/pull/9365)
* fix CI environment variable filtering by [@ivan-gaydamakin](https://github.com/ivan-gaydamakin) in [#9369](https://github.com/tuist/tuist/pull/9369)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.140.1...4.140.2

## What's Changed in 4.140.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Linux support for auth and cache commands by [@fortmarek](https://github.com/fortmarek) in [#9291](https://github.com/tuist/tuist/pull/9291)
### 🐛 Bug Fixes

* fix `tuist version` producing no output on Linux by [@fortmarek](https://github.com/fortmarek) in [#9364](https://github.com/tuist/tuist/pull/9364)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.139.1...4.140.1

## What's Changed in 4.139.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't embed static precompiled xcframeworks by [@pepicrft](https://github.com/pepicrft) in [#9356](https://github.com/tuist/tuist/pull/9356)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.139.0...4.139.1

## What's Changed in 4.139.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add configurable cache push policy by [@fortmarek](https://github.com/fortmarek) in [#9348](https://github.com/tuist/tuist/pull/9348)
### 🐛 Bug Fixes

* deduplicate plugins with the same name in tuist edit by [@pepicrft](https://github.com/pepicrft) in [#9354](https://github.com/tuist/tuist/pull/9354)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.138.1...4.139.0

## What's Changed in 4.138.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add extension bundle search paths for resource accessors by [@pepicrft](https://github.com/pepicrft) in [#9344](https://github.com/tuist/tuist/pull/9344)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.138.0...4.138.1

## What's Changed in 4.138.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add custom metadata and tags to build runs by [@fortmarek](https://github.com/fortmarek) in [#9310](https://github.com/tuist/tuist/pull/9310)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.137.1...4.138.0

## What's Changed in 4.137.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* guard log file creation for Noora by [@pepicrft](https://github.com/pepicrft) in [#9324](https://github.com/tuist/tuist/pull/9324)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.137.0...4.137.1

## What's Changed in 4.137.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* record network requests to HAR files for debugging by [@pepicrft](https://github.com/pepicrft) in [#9192](https://github.com/tuist/tuist/pull/9192)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.136.0...4.137.0

## What's Changed in 4.136.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add generations and cache runs API endpoints and CLI commands by [@pepicrft](https://github.com/pepicrft) in [#9277](https://github.com/tuist/tuist/pull/9277)
### 🐛 Bug Fixes

* embed static frameworks with buildable-folder resources by [@pepicrft](https://github.com/pepicrft) in [#9317](https://github.com/tuist/tuist/pull/9317)
* skip config loading for inspect commands by [@fortmarek](https://github.com/fortmarek) in [#9315](https://github.com/tuist/tuist/pull/9315)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.135.2...4.136.0

## What's Changed in 4.135.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* avoid stale auth token cache during long uploads by [@cschmatzler](https://github.com/cschmatzler) in [#9314](https://github.com/tuist/tuist/pull/9314)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.135.1...4.135.2

## What's Changed in 4.135.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generate registry config before resolving Swift packages by [@pepicrft](https://github.com/pepicrft) in [#9311](https://github.com/tuist/tuist/pull/9311)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.135.0...4.135.1

## What's Changed in 4.135.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* auto-skip quarantined tests in tuist test by [@fortmarek](https://github.com/fortmarek) in [#9306](https://github.com/tuist/tuist/pull/9306)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.134.1...4.135.0

## What's Changed in 4.134.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Bump cache version for static framework copy layout by [@pepicrft](https://github.com/pepicrft) in [#9309](https://github.com/tuist/tuist/pull/9309)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.134.0...4.134.1

## What's Changed in 4.134.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add build list and build show commands by [@pepicrft](https://github.com/pepicrft) in [#9272](https://github.com/tuist/tuist/pull/9272)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.4...4.134.0

## What's Changed in 4.133.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle Metal files in buildable folders for resource bundle generation by [@pepicrft](https://github.com/pepicrft) in [#9298](https://github.com/tuist/tuist/pull/9298)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.3...4.133.4

## What's Changed in 4.133.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* propagate .bundle resource files from external static frameworks to host app by [@pepicrft](https://github.com/pepicrft) in [#9294](https://github.com/tuist/tuist/pull/9294)
* search host bundle paths in ObjC resource bundle accessor by [@pepicrft](https://github.com/pepicrft) in [#9295](https://github.com/tuist/tuist/pull/9295)
* harden log cleanup by [@pepicrft](https://github.com/pepicrft) in [#9296](https://github.com/tuist/tuist/pull/9296)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.2...4.133.3

## What's Changed in 4.133.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* eagerly compute conditional targets to prevent thread starvation during generation by [@pepicrft](https://github.com/pepicrft) in [#9292](https://github.com/tuist/tuist/pull/9292)
* only embed static XCFrameworks containing .framework bundles by [@pepicrft](https://github.com/pepicrft) in [#9288](https://github.com/tuist/tuist/pull/9288)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.0...4.133.2

## What's Changed in 4.133.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add TUIST_CACHE_ENDPOINT environment variable override by [@fortmarek](https://github.com/fortmarek) in [#9282](https://github.com/tuist/tuist/pull/9282)
* add debug logging to diagnose generation hangs by [@fortmarek](https://github.com/fortmarek) in [#9284](https://github.com/tuist/tuist/pull/9284)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.132.1...4.133.0

## What's Changed in 4.132.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add authentication failure error for cache by [@cschmatzler](https://github.com/cschmatzler) in [#9280](https://github.com/tuist/tuist/pull/9280)
* update FileSystem to fix intermittent crash on startup by [@pepicrft](https://github.com/pepicrft) in [#9276](https://github.com/tuist/tuist/pull/9276)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.132.0...4.132.1

## What's Changed in 4.132.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add registryEnabled generation option by [@pepicrft](https://github.com/pepicrft) in [#9258](https://github.com/tuist/tuist/pull/9258)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.131.2...4.132.0

## What's Changed in 4.131.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* revert swift-protobuf to GitHub URL to fix manifest issue by [@pepicrft](https://github.com/pepicrft) in [#9267](https://github.com/tuist/tuist/pull/9267)
* set default cache concurrency limit to 100 by [@fortmarek](https://github.com/fortmarek) in [#9235](https://github.com/tuist/tuist/pull/9235)
* support BITRISE_IDENTITY_TOKEN env var for Bitrise OIDC auth by [@pepicrft](https://github.com/pepicrft) in [#9257](https://github.com/tuist/tuist/pull/9257)
* embed static XCFrameworks to support resources by [@pepicrft](https://github.com/pepicrft) in [#9240](https://github.com/tuist/tuist/pull/9240)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.131.1...4.131.2

## What's Changed in 4.131.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* restore mapper order for selective testing and fix parseAsRoot by [@fortmarek](https://github.com/fortmarek) in [#9234](https://github.com/tuist/tuist/pull/9234)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.131.0...4.131.1

## What's Changed in 4.131.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add test quarantine and automations settings by [@fortmarek](https://github.com/fortmarek) in [#9175](https://github.com/tuist/tuist/pull/9175)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.130.3...4.131.0

## What's Changed in 4.130.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* ensure consistent mapper order between automation and cache pipelines by [@fortmarek](https://github.com/fortmarek) in [#9228](https://github.com/tuist/tuist/pull/9228)
* use patched swift-openapi-urlsession to fix crash by [@fortmarek](https://github.com/fortmarek) in [#9229](https://github.com/tuist/tuist/pull/9229)
* filter out dependencies with unsatisfied trait conditions by [@pepicrft](https://github.com/pepicrft) in [#9219](https://github.com/tuist/tuist/pull/9219)
* fix bundle accessor for Obj-C external static frameworks with resources by [@pepicrft](https://github.com/pepicrft) in [#9210](https://github.com/tuist/tuist/pull/9210)
### 📚 Documentation

* add intent layer nodes by [@pepicrft](https://github.com/pepicrft) in [#9042](https://github.com/tuist/tuist/pull/9042)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.130.1...4.130.3

## What's Changed in 4.130.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* correct static xcframework paths when depending on cached targets by [@fortmarek](https://github.com/fortmarek) in [#9203](https://github.com/tuist/tuist/pull/9203)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.130.0...4.130.1

## What's Changed in 4.130.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add debug logs to project generation by [@fortmarek](https://github.com/fortmarek) in [#9199](https://github.com/tuist/tuist/pull/9199)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.129.2...4.130.0

## What's Changed in 4.129.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle race condition when creating logs directory by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.129.1...4.129.2

## What's Changed in 4.129.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* prevent race condition when creating logs directory by [@pepicrft](https://github.com/pepicrft) in [#9191](https://github.com/tuist/tuist/pull/9191)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.129.0...4.129.1

## What's Changed in 4.129.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* enable local CAS when enableCaching is true and Tuist project is not configured by [@danieleformichelli](https://github.com/danieleformichelli) in [#9157](https://github.com/tuist/tuist/pull/9157)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.128.3...4.129.0

## What's Changed in 4.128.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix acceptance tests by [@cschmatzler](https://github.com/cschmatzler) in [#9150](https://github.com/tuist/tuist/pull/9150)
* External resources failing at runtime unable to find their associated bundle by [@pepicrft](https://github.com/pepicrft) in [#9148](https://github.com/tuist/tuist/pull/9148)
* only emit a public import when public symbols are present by [@JimRoepcke](https://github.com/JimRoepcke) in [#9129](https://github.com/tuist/tuist/pull/9129)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.128.0...4.128.3

## What's Changed in 4.128.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* make new module cache default by [@cschmatzler](https://github.com/cschmatzler) in [#9094](https://github.com/tuist/tuist/pull/9094)
* add support for flaky tests detection by [@fortmarek](https://github.com/fortmarek) in [#9098](https://github.com/tuist/tuist/pull/9098)
* implement remote cache cleaning by [@cschmatzler](https://github.com/cschmatzler) in [#9124](https://github.com/tuist/tuist/pull/9124)
### 🐛 Bug Fixes

* Compilation errors when a static framework contains resources by [@pepicrft](https://github.com/pepicrft) in [#9141](https://github.com/tuist/tuist/pull/9141)
* remove selective testing support for vanilla Xcode projects by [@fortmarek](https://github.com/fortmarek) in [#9126](https://github.com/tuist/tuist/pull/9126)
* update inspect acceptance tests for new output format by [@pepicrft](https://github.com/pepicrft) in [#9125](https://github.com/tuist/tuist/pull/9125)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.125.0...4.128.0

## What's Changed in 4.125.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add unified inspect dependencies command by [@hiltonc](https://github.com/hiltonc) in [#8887](https://github.com/tuist/tuist/pull/8887)
* Add exceptTargetQueries to cache profiles by [@hiltonc](https://github.com/hiltonc) in [#8761](https://github.com/tuist/tuist/pull/8761)
### 🐛 Bug Fixes

* Static framework bundles for tests and metal by [@pepicrft](https://github.com/pepicrft) in [#9123](https://github.com/tuist/tuist/pull/9123)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.124.1...4.125.0

## What's Changed in 4.124.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* disable Swift debug serialization to prevent LLDB warnings by [@pepicrft](https://github.com/pepicrft) in [#9116](https://github.com/tuist/tuist/pull/9116)
* update XcodeGraph to 1.30.10 to fix CLI resource bundles by [@pepicrft](https://github.com/pepicrft) in [#9115](https://github.com/tuist/tuist/pull/9115)
* fix flaky DumpServiceIntegrationTests for package manifests by [@pepicrft](https://github.com/pepicrft) in [#9113](https://github.com/tuist/tuist/pull/9113)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.124.0...4.124.1

## What's Changed in 4.124.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add support for SwiftPM package traits by [@pepicrft](https://github.com/pepicrft) in [#8535](https://github.com/tuist/tuist/pull/8535)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.123.0...4.124.0

## What's Changed in 4.123.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* show deprecation notice for CLI < 4.56.1 by [@cschmatzler](https://github.com/cschmatzler) in [#9110](https://github.com/tuist/tuist/pull/9110)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.122.2...4.123.0

## What's Changed in 4.122.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* restore static framework resources without regressions by [@pepicrft](https://github.com/pepicrft) in [#9081](https://github.com/tuist/tuist/pull/9081)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.122.1...4.122.2

## What's Changed in 4.122.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add excluding parameter to FileElement glob by [@fortmarek](https://github.com/fortmarek) in [#9087](https://github.com/tuist/tuist/pull/9087)
* Add tuist:synthesized tag to synthesized resource bundles by [@pepicrft](https://github.com/pepicrft) in [#8983](https://github.com/tuist/tuist/pull/8983)
### 🐛 Bug Fixes

* preserve -enable-upcoming-feature flags in OTHER_SWIFT_FLAGS deduplication by [@fortmarek](https://github.com/fortmarek) in [#9106](https://github.com/tuist/tuist/pull/9106)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.120.0...4.122.1

## What's Changed in 4.120.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* export hashed graph to file via env variable by [@fortmarek](https://github.com/fortmarek) in [#9078](https://github.com/tuist/tuist/pull/9078)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.4...4.120.0

## What's Changed in 4.119.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* exclude __MACOSX folders for remote binary targets by [@mo5tone](https://github.com/mo5tone) in [#9075](https://github.com/tuist/tuist/pull/9075)
* ensure consistent graph mapper order for cache hashing by [@fortmarek](https://github.com/fortmarek) in [#9077](https://github.com/tuist/tuist/pull/9077)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.3...4.119.4

## What's Changed in 4.119.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* filter Catalyst destinations for external dependencies by [@pepicrft](https://github.com/pepicrft) in [#9067](https://github.com/tuist/tuist/pull/9067)
* handle multi-byte UTF-8 characters in xcresult parsing by [@fortmarek](https://github.com/fortmarek) in [#9061](https://github.com/tuist/tuist/pull/9061)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.1...4.119.3

## What's Changed in 4.119.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use generic destination for Mac Catalyst cache builds by [@pepicrft](https://github.com/pepicrft) in [#9038](https://github.com/tuist/tuist/pull/9038)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.0...4.119.1

## What's Changed in 4.119.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* custom cache endpoints by [@cschmatzler](https://github.com/cschmatzler) in [#8980](https://github.com/tuist/tuist/pull/8980)
### 🐛 Bug Fixes

* Generate TuistBundle if buildableFolders contains synthesized file by [@denisgaskov](https://github.com/denisgaskov) in [#8998](https://github.com/tuist/tuist/pull/8998)
* Include Mac Catalyst slice when building XCFrameworks for cache by [@pepicrft](https://github.com/pepicrft) in [#9028](https://github.com/tuist/tuist/pull/9028)
### 🚜 Refactor

* rename fixtures to examples and simplify fixture handling by [@pepicrft](https://github.com/pepicrft) in [#8962](https://github.com/tuist/tuist/pull/8962)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.118.1...4.119.0

## What's Changed in 4.118.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* module cache by [@cschmatzler](https://github.com/cschmatzler) in [#8931](https://github.com/tuist/tuist/pull/8931)
### 🐛 Bug Fixes

* fix selective testing when experimental cache enabled by [@cschmatzler](https://github.com/cschmatzler) in [#8981](https://github.com/tuist/tuist/pull/8981)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.117.0...4.118.1

## What's Changed in 4.117.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* preview tracks by [@fortmarek](https://github.com/fortmarek) in [#8939](https://github.com/tuist/tuist/pull/8939)
### 🐛 Bug Fixes

* handle cross-project dependencies in redundant import inspection by [@hiltonc](https://github.com/hiltonc) in [#8862](https://github.com/tuist/tuist/pull/8862)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.116.2...4.117.0

## What's Changed in 4.116.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* require previews to have unique binary id and bundle version by [@fortmarek](https://github.com/fortmarek) in [#8944](https://github.com/tuist/tuist/pull/8944)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.116.1...4.116.2

## What's Changed in 4.116.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* compute binary id as part of tuist share by [@fortmarek](https://github.com/fortmarek) in [#8912](https://github.com/tuist/tuist/pull/8912)
### 🐛 Bug Fixes

* add support for the new mise bin path by [@fortmarek](https://github.com/fortmarek) in [#8929](https://github.com/tuist/tuist/pull/8929)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.115.1...4.116.1

## What's Changed in 4.115.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* migrate Fixtures - Tuist initializer with .project by [@2sem](https://github.com/2sem) in [#8886](https://github.com/tuist/tuist/pull/8886)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.115.0...4.115.1

## What's Changed in 4.115.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload command run analytics in the background by [@fortmarek](https://github.com/fortmarek) in [#8883](https://github.com/tuist/tuist/pull/8883)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.114.0...4.115.0

## What's Changed in 4.114.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* OIDC support Bitrise and CircleCI by [@fortmarek](https://github.com/fortmarek) in [#8878](https://github.com/tuist/tuist/pull/8878)
### 🐛 Bug Fixes

* parsing XCActivityLog on Xcode 26.2 and newer by [@fortmarek](https://github.com/fortmarek) in [#8866](https://github.com/tuist/tuist/pull/8866)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.113.0...4.114.0

## What's Changed in 4.113.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* OIDC token support for GitHub Actions by [@fortmarek](https://github.com/fortmarek) in [#8858](https://github.com/tuist/tuist/pull/8858)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.112.0...4.113.0

## What's Changed in 4.112.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* account tokens by [@fortmarek](https://github.com/fortmarek) in [#8834](https://github.com/tuist/tuist/pull/8834)
* report module cache subhashes by [@fortmarek](https://github.com/fortmarek) in [#8822](https://github.com/tuist/tuist/pull/8822)
### 🐛 Bug Fixes

* respect explicit cache profile none with target focus by [@hiltonc](https://github.com/hiltonc) in [#8830](https://github.com/tuist/tuist/pull/8830)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.3...4.112.0

## What's Changed in 4.110.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle skipped tests due to a failed build by [@fortmarek](https://github.com/fortmarek) in [#8808](https://github.com/tuist/tuist/pull/8808)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.2...4.110.3

## What's Changed in 4.110.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* false positive for a .uiTests implicit import of .app by [@fortmarek](https://github.com/fortmarek) in [#8811](https://github.com/tuist/tuist/pull/8811)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.1...4.110.2

## What's Changed in 4.110.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* duration for test cases with custom label by [@fortmarek](https://github.com/fortmarek) in [#8800](https://github.com/tuist/tuist/pull/8800)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.0...4.110.1

## What's Changed in 4.110.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* deprecate tuist build command by [@pepicrft](https://github.com/pepicrft) in [#8401](https://github.com/tuist/tuist/pull/8401)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.109.2...4.110.0

## What's Changed in 4.109.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* relegate test result upload error to a warning by [@fortmarek](https://github.com/fortmarek) in [#8790](https://github.com/tuist/tuist/pull/8790)
* Don't replace targeted external dependencies with cached binary by [@hiltonc](https://github.com/hiltonc) in [#8731](https://github.com/tuist/tuist/pull/8731)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.109.0...4.109.2

## What's Changed in 4.109.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* link tests to builds by [@fortmarek](https://github.com/fortmarek) in [#8771](https://github.com/tuist/tuist/pull/8771)
### 🐛 Bug Fixes

* Remove CLANG_CXX_LIBRARY essential build setting by [@alexmx](https://github.com/alexmx) in [#8763](https://github.com/tuist/tuist/pull/8763)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.108.0...4.109.0

## What's Changed in 4.108.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track CI run id for test insights by [@fortmarek](https://github.com/fortmarek) in [#8769](https://github.com/tuist/tuist/pull/8769)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.107.2...4.108.0

## What's Changed in 4.107.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove fullHandle requirement for tuist registry setup by [@fortmarek](https://github.com/fortmarek) in [#8750](https://github.com/tuist/tuist/pull/8750)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.107.1...4.107.2

## What's Changed in 4.107.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add test insights by [@fortmarek](https://github.com/fortmarek) in [#8347](https://github.com/tuist/tuist/pull/8347)
### 🐛 Bug Fixes

* duplicated XCFrameworks in embed phase by [@fortmarek](https://github.com/fortmarek) in [#8736](https://github.com/tuist/tuist/pull/8736)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.106.3...4.107.1

## What's Changed in 4.106.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* pin swift-collections below 1.3.0 by [@fortmarek](https://github.com/fortmarek) in [#8730](https://github.com/tuist/tuist/pull/8730)
* skip warning Swift flags when hashing by [@fortmarek](https://github.com/fortmarek) in [#8728](https://github.com/tuist/tuist/pull/8728)
* prefer products with matching casing by [@fortmarek](https://github.com/fortmarek) in [#8717](https://github.com/tuist/tuist/pull/8717)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.106.1...4.106.3

## What's Changed in 4.106.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* open registry by [@fortmarek](https://github.com/fortmarek) in [#8708](https://github.com/tuist/tuist/pull/8708)
### 🐛 Bug Fixes

* external dependency case insensitive lookup by [@fortmarek](https://github.com/fortmarek) in [#8714](https://github.com/tuist/tuist/pull/8714)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.105.1...4.106.1

## What's Changed in 4.105.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix false negative implicit import detection of transitive local dependencies by [@Kolos65](https://github.com/Kolos65) in [#8665](https://github.com/tuist/tuist/pull/8665)
* refreshing token data race by [@fortmarek](https://github.com/fortmarek) in [#8706](https://github.com/tuist/tuist/pull/8706)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.105.0...4.105.1

## What's Changed in 4.105.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* improve error message of tuist inspect implicit-imports by [@n-zaitsev](https://github.com/n-zaitsev) in [#8604](https://github.com/tuist/tuist/pull/8604)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.7...4.105.0

## What's Changed in 4.104.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resolve token refresh data race in ServerAuthenticationController by [@fortmarek](https://github.com/fortmarek) in [#8692](https://github.com/tuist/tuist/pull/8692)
* skip hashing Xcode version by [@fortmarek](https://github.com/fortmarek) in [#8658](https://github.com/tuist/tuist/pull/8658)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.5...4.104.7

## What's Changed in 4.104.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add Emerge Tools SnapshottingTests to the list of targets that depend on XCTest by [@duarteich](https://github.com/duarteich) in [#8653](https://github.com/tuist/tuist/pull/8653)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.4...4.104.5

## What's Changed in 4.104.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* respect xcframework status by [@fortmarek](https://github.com/fortmarek) in [#8651](https://github.com/tuist/tuist/pull/8651)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.3...4.104.4

## What's Changed in 4.104.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* duplicate CAS outputs by [@fortmarek](https://github.com/fortmarek) in [#8646](https://github.com/tuist/tuist/pull/8646)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.2...4.104.3

## What's Changed in 4.104.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* skip hashing lockfiles by [@fortmarek](https://github.com/fortmarek) in [#8650](https://github.com/tuist/tuist/pull/8650)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.1...4.104.2

## What's Changed in 4.104.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* misreported Xcode cache analytics by [@fortmarek](https://github.com/fortmarek) in [#8638](https://github.com/tuist/tuist/pull/8638)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.0...4.104.1

## What's Changed in 4.104.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* connect directly to the cache endpoint by [@fortmarek](https://github.com/fortmarek) in [#8628](https://github.com/tuist/tuist/pull/8628)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.103.0...4.104.0

## What's Changed in 4.103.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track cas outputs type and cacheable task description by [@fortmarek](https://github.com/fortmarek) in [#8609](https://github.com/tuist/tuist/pull/8609)
* track cacheable task description by [@fortmarek](https://github.com/fortmarek) in [#8603](https://github.com/tuist/tuist/pull/8603)
### 🐛 Bug Fixes

* Add extended string delimiter to Strings value in PlistsTemplate by [@ast3150](https://github.com/ast3150) in [#8607](https://github.com/tuist/tuist/pull/8607)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.101.0...4.103.0

## What's Changed in 4.101.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track cache key read/write latency by [@fortmarek](https://github.com/fortmarek) in [#8598](https://github.com/tuist/tuist/pull/8598)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.100.0...4.101.0

## What's Changed in 4.100.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* cas output analytics by [@fortmarek](https://github.com/fortmarek) in [#8584](https://github.com/tuist/tuist/pull/8584)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.99.2...4.100.0

## What's Changed in 4.99.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* ensure disableSandbox config is used when dumping package manifests by [@pepicrft](https://github.com/pepicrft) in [#8475](https://github.com/tuist/tuist/pull/8475)
* support import kind declarations in inspect by [@hiltonc](https://github.com/hiltonc) in [#8455](https://github.com/tuist/tuist/pull/8455)
* cache Config manifest to improve performance by [@hiltonc](https://github.com/hiltonc) in [#8561](https://github.com/tuist/tuist/pull/8561)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.99.1...4.99.2

## What's Changed in 4.99.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix buildable folder resource placement for static targets by [@natanrolnik](https://github.com/natanrolnik) in [#8548](https://github.com/tuist/tuist/pull/8548)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.99.0...4.99.1

## What's Changed in 4.99.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* optimize Xcode cache by compressing CAS artifacts by [@fortmarek](https://github.com/fortmarek) in [#8565](https://github.com/tuist/tuist/pull/8565)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.98.0...4.99.0

## What's Changed in 4.98.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Optimize cache hit detection and add diagnostic remarks by [@fortmarek](https://github.com/fortmarek) in [#8556](https://github.com/tuist/tuist/pull/8556)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.97.2...4.98.0

## What's Changed in 4.97.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* clean up warnings by [@waltflanagan](https://github.com/waltflanagan) in [#7666](https://github.com/tuist/tuist/pull/7666)
* fix content hashing to use relative path when file does not exist by [@waltflanagan](https://github.com/waltflanagan) in [#8557](https://github.com/tuist/tuist/pull/8557)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.97.0...4.97.2

## What's Changed in 4.97.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add cache profiles to fine tune cached binary replacement by [@hiltonc](https://github.com/hiltonc) in [#8122](https://github.com/tuist/tuist/pull/8122)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.96.0...4.97.0

## What's Changed in 4.96.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for SwiftPM disableWarning setting by [@pepicrft](https://github.com/pepicrft) in [#8549](https://github.com/tuist/tuist/pull/8549)
* improve upload error handling for cache artifacts by [@fortmarek](https://github.com/fortmarek) in [#8553](https://github.com/tuist/tuist/pull/8553)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.95.1...4.96.0

## What's Changed in 4.95.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* downgrade duplicated product name linting from error to warning by [@n-zaitsev](https://github.com/n-zaitsev) in [#8540](https://github.com/tuist/tuist/pull/8540)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.95.0...4.95.1

## What's Changed in 4.95.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for passing arguments to SwiftPM by [@pepicrft](https://github.com/pepicrft) in [#8544](https://github.com/tuist/tuist/pull/8544)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.94.0...4.95.0

## What's Changed in 4.94.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add support for Swift Package Manager strictMemorySafety setting by [@pepicrft](https://github.com/pepicrft) in [#8539](https://github.com/tuist/tuist/pull/8539)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.93.0...4.94.0

## What's Changed in 4.93.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* xcode cache analytics by [@fortmarek](https://github.com/fortmarek) in [#8534](https://github.com/tuist/tuist/pull/8534)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.92.1...4.93.0

## What's Changed in 4.92.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Add support for Internal Imports By Default for Asset accessors by [@PSKuznetsov](https://github.com/PSKuznetsov) in [#8241](https://github.com/tuist/tuist/pull/8241)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.92.0...4.92.1

## What's Changed in 4.92.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add cache daemon logs by [@fortmarek](https://github.com/fortmarek) in [#8520](https://github.com/tuist/tuist/pull/8520)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.91.1...4.92.0

## What's Changed in 4.91.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Multiple targets with same hash by [@pepicrft](https://github.com/pepicrft) in [#8533](https://github.com/tuist/tuist/pull/8533)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.91.0...4.91.1

## What's Changed in 4.91.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Default to no concurrency limit when doing cache uploads and downloads by [@pepicrft](https://github.com/pepicrft) in [#8527](https://github.com/tuist/tuist/pull/8527)
### 🐛 Bug Fixes

* Bundle accessor not being generated for txt, js or json resources by [@natanrolnik](https://github.com/natanrolnik) in [#8532](https://github.com/tuist/tuist/pull/8532)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.90.0...4.91.0

## What's Changed in 4.90.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add support for TUIST_-prefixed XDG environment variables by [@pepicrft](https://github.com/pepicrft) in [#8508](https://github.com/tuist/tuist/pull/8508)
### 🐛 Bug Fixes

* improve error messages of cache daemon by [@fortmarek](https://github.com/fortmarek) in [#8509](https://github.com/tuist/tuist/pull/8509)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.89.1...4.90.0

## What's Changed in 4.89.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use TUIST_CONFIG_TOKEN when launching the cache daemon by [@fortmarek](https://github.com/fortmarek) in [#8506](https://github.com/tuist/tuist/pull/8506)
* ignore macros in inspect redundant dependencies by [@hiltonc](https://github.com/hiltonc) in [#8457](https://github.com/tuist/tuist/pull/8457)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.89.0...4.89.1

## What's Changed in 4.89.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Only use binaries for external dependencies when no focus target is passed to `tuist generate` by [@pepicrft](https://github.com/pepicrft) in [#8478](https://github.com/tuist/tuist/pull/8478)
* Add --skip-unit-tests parameter to tuist test command by [@RomanAnpilov](https://github.com/RomanAnpilov) in [#8291](https://github.com/tuist/tuist/pull/8291)
### 🐛 Bug Fixes

* ignore unit test host app in inspect redundant dependencies by [@hiltonc](https://github.com/hiltonc) in [#8456](https://github.com/tuist/tuist/pull/8456)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.88.0...4.89.0

## What's Changed in 4.88.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* don't restrict which kind of token is used based on the environment by [@fortmarek](https://github.com/fortmarek) in [#8464](https://github.com/tuist/tuist/pull/8464)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.87.0...4.88.0

## What's Changed in 4.87.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* tuist setup cache command by [@fortmarek](https://github.com/fortmarek) in [#8450](https://github.com/tuist/tuist/pull/8450)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.4...4.87.0

## What's Changed in 4.86.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add individual target sub-hashes for debugging by [@fortmarek](https://github.com/fortmarek) in [#8460](https://github.com/tuist/tuist/pull/8460)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.3...4.86.4

## What's Changed in 4.86.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Add support for `.xcdatamodel` opaque directories by [@MouadBenjrinija](https://github.com/MouadBenjrinija) in [#8445](https://github.com/tuist/tuist/pull/8445)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.2...4.86.3

## What's Changed in 4.86.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't throw file not found when hashing generated source files by [@fortmarek](https://github.com/fortmarek) in [#8449](https://github.com/tuist/tuist/pull/8449)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.1...4.86.2

## What's Changed in 4.86.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* mysteriously vanished binaries by [@fortmarek](https://github.com/fortmarek) in [#8447](https://github.com/tuist/tuist/pull/8447)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.0...4.86.1

## What's Changed in 4.86.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Xcode cache server by [@fortmarek](https://github.com/fortmarek) in [#8420](https://github.com/tuist/tuist/pull/8420)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.85.2...4.86.0

## What's Changed in 4.85.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* extend inspect build to 5 seconds by [@fortmarek](https://github.com/fortmarek) in [#8446](https://github.com/tuist/tuist/pull/8446)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.85.1...4.85.2

## What's Changed in 4.85.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Generated projects with binaries not replacing some targets with macros as transitive dependencies by [@pepicrft](https://github.com/pepicrft) in [#8444](https://github.com/tuist/tuist/pull/8444)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.85.0...4.85.1

## What's Changed in 4.85.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Optimize resource interface synthesis through parallelization by [@pepicrft](https://github.com/pepicrft) in [#8436](https://github.com/tuist/tuist/pull/8436)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.3...4.85.0

## What's Changed in 4.84.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't report clean action by [@fortmarek](https://github.com/fortmarek) in [#8439](https://github.com/tuist/tuist/pull/8439)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.2...4.84.3

## What's Changed in 4.84.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Handle target action input and output file paths that contain variables by [@pepicrft](https://github.com/pepicrft) in [#8432](https://github.com/tuist/tuist/pull/8432)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.1...4.84.2

## What's Changed in 4.84.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* align 'tuist hash cache' to use same generator as cache warming by [@pepicrft](https://github.com/pepicrft) in [#8427](https://github.com/tuist/tuist/pull/8427)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.0...4.84.1

## What's Changed in 4.84.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Improve remote cache error handling by [@pepicrft](https://github.com/pepicrft) in [#8413](https://github.com/tuist/tuist/pull/8413)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.83.0...4.84.0

## What's Changed in 4.83.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Support the `defaultIsolation` setting when integrating packages using native Xcode project targets by [@pepicrft](https://github.com/pepicrft) in [#8372](https://github.com/tuist/tuist/pull/8372)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.82.3...4.83.0

## What's Changed in 4.82.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* clean up downloaded binary artifacts from temporary directory by [@fortmarek](https://github.com/fortmarek) in [#8402](https://github.com/tuist/tuist/pull/8402)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.82.2...4.82.3

## What's Changed in 4.82.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't convert script input and output file list paths relative to manifest paths or with build variables to absolute by [@fortmarek](https://github.com/fortmarek) in [#8397](https://github.com/tuist/tuist/pull/8397)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.82.1...4.82.2

## What's Changed in 4.82.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add bundle type by [@fortmarek](https://github.com/fortmarek) in [#8363](https://github.com/tuist/tuist/pull/8363)
### 🐛 Bug Fixes

* Ensure buildableFolder resources are handled with project-defined resourceSynthesizers. by [@Monsteel](https://github.com/Monsteel) in [#8369](https://github.com/tuist/tuist/pull/8369)
* align with the latest Tuist API by [@fortmarek](https://github.com/fortmarek) in [#8393](https://github.com/tuist/tuist/pull/8393)
* path to the PackageDescription in projects generated by tuist edit by [@fortmarek](https://github.com/fortmarek) in [#8357](https://github.com/tuist/tuist/pull/8357)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.81.0...4.82.1

## What's Changed in 4.81.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Make implicit import detection work with buildable folders by [@pepicrft](https://github.com/pepicrft) in [#8358](https://github.com/tuist/tuist/pull/8358)
* add CI run reference to build runs by [@fortmarek](https://github.com/fortmarek) in [#8356](https://github.com/tuist/tuist/pull/8356)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.80.0...4.81.0

## What's Changed in 4.80.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Report server-side payment-required responses as warnings by [@pepicrft](https://github.com/pepicrft) in [#8338](https://github.com/tuist/tuist/pull/8338)
* add configuration to build insights by [@fortmarek](https://github.com/fortmarek) in [#8330](https://github.com/tuist/tuist/pull/8330)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.7...4.80.0

## What's Changed in 4.79.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Only validate cache signatures on successful responses by [@pepicrft](https://github.com/pepicrft) in [#8315](https://github.com/tuist/tuist/pull/8315)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.6...4.79.7

## What's Changed in 4.79.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix cache warming when external targets are excluded by platform conditions by [@pepicrft](https://github.com/pepicrft) in [#8308](https://github.com/tuist/tuist/pull/8308)
* don't mark inspected build as failed when it has warnings only by [@fortmarek](https://github.com/fortmarek) in [#8276](https://github.com/tuist/tuist/pull/8276)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.4...4.79.6

## What's Changed in 4.79.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Add support for headers in buildable folders by [@pepicrft](https://github.com/pepicrft) in [#8298](https://github.com/tuist/tuist/pull/8298)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.3...4.79.4

## What's Changed in 4.79.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix synthesized bundle interfaces not generated for `.xcassets` in buildable folders by [@pepicrft](https://github.com/pepicrft) in [#8292](https://github.com/tuist/tuist/pull/8292)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.2...4.79.3

## What's Changed in 4.79.2<!-- RELEASE NOTES START -->

### 🧪 Testing

* fix acceptance tests by [@fortmarek](https://github.com/fortmarek) in [#8288](https://github.com/tuist/tuist/pull/8288)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.1...4.79.2

## What's Changed in 4.79.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Make `excluded` optional in buildable folder exceptions by [@pepicrft](https://github.com/pepicrft) in [#8293](https://github.com/tuist/tuist/pull/8293)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.0...4.79.1

## What's Changed in 4.79.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Support exclusion of files and configuration of compiler flags for files in buildable folders by [@pepicrft](https://github.com/pepicrft) in [#8254](https://github.com/tuist/tuist/pull/8254)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.4...4.79.0

## What's Changed in 4.78.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Downgrade ProjectDescription Swift version to 6.1 by [@pepicrft](https://github.com/pepicrft) in [#8283](https://github.com/tuist/tuist/pull/8283)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.3...4.78.4

## What's Changed in 4.78.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* show Products file group in Xcode navigator by [@YIshihara11201](https://github.com/YIshihara11201) in [#8267](https://github.com/tuist/tuist/pull/8267)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.2...4.78.3

## What's Changed in 4.78.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* adjust NIOFileSystem references by [@fortmarek](https://github.com/fortmarek) in [#8273](https://github.com/tuist/tuist/pull/8273)
* handle warnings from the underlying assetutil info when inspecting bundles by [@fortmarek](https://github.com/fortmarek) in [#8268](https://github.com/tuist/tuist/pull/8268)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.1...4.78.2

## What's Changed in 4.78.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add default.metallib in static framework by [@bilousoleksandr](https://github.com/bilousoleksandr) in [#8207](https://github.com/tuist/tuist/pull/8207)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.0...4.78.1

## What's Changed in 4.78.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* change sandbox to be opt-in by [@fortmarek](https://github.com/fortmarek) in [#8244](https://github.com/tuist/tuist/pull/8244)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.77.0...4.78.0

## What's Changed in 4.77.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Increase the security of the cache surface by [@pepicrft](https://github.com/pepicrft) in [#8220](https://github.com/tuist/tuist/pull/8220)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.76.1...4.77.0

## What's Changed in 4.76.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Invalid generated projects when projects are generated with binaries keeping sources and targets by [@pepicrft](https://github.com/pepicrft) in [#8227](https://github.com/tuist/tuist/pull/8227)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.76.0...4.76.1

## What's Changed in 4.76.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add SE-0162 support for custom SPM target layouts by [@devyhan](https://github.com/devyhan) in [#8191](https://github.com/tuist/tuist/pull/8191)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.75.0...4.76.0

## What's Changed in 4.75.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add unordered xcodebuild command support by [@yusufozgul](https://github.com/yusufozgul) in [#8170](https://github.com/tuist/tuist/pull/8170)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.74.1...4.75.0

## What's Changed in 4.74.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Increase the refresh token timeout period by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.74.0...4.74.1

## What's Changed in 4.74.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Verbose-log the concurrency limit used by the cache for network connections by [@pepicrft](https://github.com/pepicrft) in [#8217](https://github.com/tuist/tuist/pull/8217)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.73.0...4.74.0

## What's Changed in 4.73.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for configuring the cache request concurrency limit by [@pepicrft](https://github.com/pepicrft) in [#8203](https://github.com/tuist/tuist/pull/8203)
### 🐛 Bug Fixes

* tuist cache failing due to the new BuildOperationMetrics attachment type by [@fortmarek](https://github.com/fortmarek) in [#8201](https://github.com/tuist/tuist/pull/8201)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.72.0...4.73.0

## What's Changed in 4.72.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Remove user credentials when the token sent on refresh is invalid by [@pepicrft](https://github.com/pepicrft) in [#8173](https://github.com/tuist/tuist/pull/8173)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.71.0...4.72.0

## What's Changed in 4.71.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* generate tests using Swift Testing instead of XCTest by [@fortmarek](https://github.com/fortmarek) in [#8184](https://github.com/tuist/tuist/pull/8184)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.70.0...4.71.0

## What's Changed in 4.70.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Don't focus when keeping the sources for targets replaced by binaries by [@pepicrft](https://github.com/pepicrft) in [#8180](https://github.com/tuist/tuist/pull/8180)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.69.0...4.70.0

## What's Changed in 4.69.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* update Swift package resolution to use -scmProvider system by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.68.0...4.69.0

## What's Changed in 4.68.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add additionalPackageResolutionArguments for xcodebuild by [@ichikmarev](https://github.com/ichikmarev) in [#8099](https://github.com/tuist/tuist/pull/8099)
### 🐛 Bug Fixes

* not generate bundle accessors in when buildable folders don't resolve to any resources by [@pepicrft](https://github.com/pepicrft) in [#8158](https://github.com/tuist/tuist/pull/8158)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.67.2...4.68.0

## What's Changed in 4.67.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generate bundle accessor when a module has only buildable folders by [@fortmarek](https://github.com/fortmarek) in [#8156](https://github.com/tuist/tuist/pull/8156)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.67.1...4.67.2

## What's Changed in 4.67.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* default to caching the manifests by [@pepicrft](https://github.com/pepicrft) in [#8116](https://github.com/tuist/tuist/pull/8116)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.67.0...4.67.1

## What's Changed in 4.67.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* optimize dependency conditions calculation by [@mikhailmulyar](https://github.com/mikhailmulyar) in [#8146](https://github.com/tuist/tuist/pull/8146)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.66.1...4.67.0

## What's Changed in 4.66.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* XCFramework signature by [@mikhailmulyar](https://github.com/mikhailmulyar) in [#7999](https://github.com/tuist/tuist/pull/7999)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.66.0...4.66.1

## What's Changed in 4.66.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* skip remote cache downloads on failure by [@fortmarek](https://github.com/fortmarek) in [#8135](https://github.com/tuist/tuist/pull/8135)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.7...4.66.0

## What's Changed in 4.65.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generate bundle accessor for modules with metal files by [@fortmarek](https://github.com/fortmarek) in [#8125](https://github.com/tuist/tuist/pull/8125)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.6...4.65.7

## What's Changed in 4.65.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* missing bundle accessor when the target uses buildable folders by [@pepicrft](https://github.com/pepicrft) in [#8092](https://github.com/tuist/tuist/pull/8092)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.5...4.65.6

## What's Changed in 4.65.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* unable to create account tokens to access the registry by [@pepicrft](https://github.com/pepicrft) in [#8115](https://github.com/tuist/tuist/pull/8115)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.4...4.65.5

## What's Changed in 4.65.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* CocoaPods unable to install dependencies due to project's `objectVersion` by [@pepicrft](https://github.com/pepicrft) in [#8051](https://github.com/tuist/tuist/pull/8051)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.3...4.65.4

## What's Changed in 4.65.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* arch incompatibilities when using the cache by [@pepicrft](https://github.com/pepicrft) in [#8096](https://github.com/tuist/tuist/pull/8096)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.2...4.65.3

## What's Changed in 4.65.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* caching issues due to incompatible architectures by [@pepicrft](https://github.com/pepicrft) in [#8094](https://github.com/tuist/tuist/pull/8094)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.1...4.65.2

## What's Changed in 4.65.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* revert caching only the default architecture by [@pepicrft](https://github.com/pepicrft) in [#8048](https://github.com/tuist/tuist/pull/8048)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.0...4.65.1

## What's Changed in 4.65.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add filePath and customWorkingDirectory support to RunAction by [@plu](https://github.com/plu) in [#8071](https://github.com/tuist/tuist/pull/8071)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.64.2...4.65.0

## What's Changed in 4.64.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use XcodeGraph for XcodeKit SDK support by [@navtoj](https://github.com/navtoj) in [#8029](https://github.com/tuist/tuist/pull/8029)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.64.1...4.64.2

## What's Changed in 4.64.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* relative path for local package by [@mikhailmulyar](https://github.com/mikhailmulyar) in [#8059](https://github.com/tuist/tuist/pull/8059)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.64.0...4.64.1

## What's Changed in 4.64.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* improve passthrough argument documentation with usage examples by [@pepicrft](https://github.com/pepicrft) in [#8047](https://github.com/tuist/tuist/pull/8047)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.3...4.64.0

## What's Changed in 4.63.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* include pagination data when listing the bundles as a json by [@pepicrft](https://github.com/pepicrft) in [#8041](https://github.com/tuist/tuist/pull/8041)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.2...4.63.3

## What's Changed in 4.63.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* `bundle show` failing due to wrong data passed by the cli by [@pepicrft](https://github.com/pepicrft) in [#8037](https://github.com/tuist/tuist/pull/8037)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.1...4.63.2

## What's Changed in 4.63.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* `tuist run` fails to run a scheme even though it has runnable targets by [@pepicrft](https://github.com/pepicrft) in [#7989](https://github.com/tuist/tuist/pull/7989)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.0...4.63.1

## What's Changed in 4.63.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add commands to list and read bundles by [@pepicrft](https://github.com/pepicrft) in [#7893](https://github.com/tuist/tuist/pull/7893)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.62.0...4.63.0

## What's Changed in 4.62.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for buildable folders by [@pepicrft](https://github.com/pepicrft) in [#7984](https://github.com/tuist/tuist/pull/7984)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.61.2...4.62.0

## What's Changed in 4.61.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* platform conditions not applied for binary dependencies in external packages by [@pepicrft](https://github.com/pepicrft) in [#7991](https://github.com/tuist/tuist/pull/7991)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.61.1...4.61.2

## What's Changed in 4.61.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generation regression by [@pepicrft](https://github.com/pepicrft) in [#8011](https://github.com/tuist/tuist/pull/8011)
* fetching devices when running previews by [@fortmarek](https://github.com/fortmarek) in [#8010](https://github.com/tuist/tuist/pull/8010)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.61.0...4.61.1

## What's Changed in 4.61.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for keeping the sources of the targets replaced by binaries by [@pepicrft](https://github.com/pepicrft) in [#8000](https://github.com/tuist/tuist/pull/8000)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.60.0...4.61.0

## What's Changed in 4.60.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* support hashing transitive `.xcconfig` files by [@mikhailmulyar](https://github.com/mikhailmulyar) in [#7961](https://github.com/tuist/tuist/pull/7961)
* add support for XcodeKit SDK by [@navtoj](https://github.com/navtoj) in [#7993](https://github.com/tuist/tuist/pull/7993)
### 🐛 Bug Fixes

* use Xcode default for which architectures are built by [@fortmarek](https://github.com/fortmarek) in [#8007](https://github.com/tuist/tuist/pull/8007)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.59.2...4.60.0

## What's Changed in 4.59.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* unexpected behaviours when renaming resources in cached targets by [@mikhailmulyar](https://github.com/mikhailmulyar) in [#7988](https://github.com/tuist/tuist/pull/7988)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.59.1...4.59.2

## What's Changed in 4.59.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* prevent metal files from being processed as resources. by [@DenTelezhkin](https://github.com/DenTelezhkin) in [#7976](https://github.com/tuist/tuist/pull/7976)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.59.0...4.59.1

## What's Changed in 4.59.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* cache binaries by default for arm64 only, add --architectures option to specify architectures by [@fortmarek](https://github.com/fortmarek) in [#7977](https://github.com/tuist/tuist/pull/7977)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.58.1...4.59.0

## What's Changed in 4.58.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* include project settings hash in target hash by [@mikhailmulyar](https://github.com/mikhailmulyar) in [#7962](https://github.com/tuist/tuist/pull/7962)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.58.0...4.58.1

## What's Changed in 4.58.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* print the full sandbox command when a system command fails by [@hiltonc](https://github.com/hiltonc) in [#7972](https://github.com/tuist/tuist/pull/7972)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.57.1...4.58.0

## What's Changed in 4.57.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* treat the new .icon asset as an opaque directory by [@fortmarek](https://github.com/fortmarek) in [#7965](https://github.com/tuist/tuist/pull/7965)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.57.0...4.57.1

## What's Changed in 4.57.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for running macOS app via `tuist run` by [@pepicrft](https://github.com/pepicrft) in [#7956](https://github.com/tuist/tuist/pull/7956)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.56.1...4.57.0

## What's Changed in 4.56.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* auto-generated *-Workspace scheme not getting generated by [@pepicrft](https://github.com/pepicrft) in [#7932](https://github.com/tuist/tuist/pull/7932)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.56.0...4.56.1

## What's Changed in 4.56.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Ignore internal server errors when interating with the cache by [@pepicrft](https://github.com/pepicrft) in [#7924](https://github.com/tuist/tuist/pull/7924)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.9...4.56.0

## What's Changed in 4.55.9<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* do not link cached frameworks with linking status .none by [@fortmarek](https://github.com/fortmarek) in [#7918](https://github.com/tuist/tuist/pull/7918)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.8...4.55.9

## What's Changed in 4.55.8<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* 'tuist version' shows the optional string by [@pepicrft](https://github.com/pepicrft)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.7...4.55.8

## What's Changed in 4.55.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix cli not launching because ProjectAutomation's dynamic framework can't be found by [@pepicrft](https://github.com/pepicrft)
* token refresh race condition by [@pepicrft](https://github.com/pepicrft) in [#7907](https://github.com/tuist/tuist/pull/7907)



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.6...4.55.7

<!-- generated by git-cliff -->
