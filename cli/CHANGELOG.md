# Changelog

All notable changes to this project will be documented in this file.
## What's Changed in 4.178.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* support self-managed shard archives
### 🐛 Bug Fixes

* declare symlink target in macro copy script input paths for sandbox compatibility



**Full Changelog**: https://github.com/tuist/tuist/compare/4.177.0...4.178.0

## What's Changed in 4.177.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add --cache-profile option to cache warm with profile-driven exclusions



**Full Changelog**: https://github.com/tuist/tuist/compare/4.176.4...4.177.0

## What's Changed in 4.176.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* write empty shard matrix on all early return paths



**Full Changelog**: https://github.com/tuist/tuist/compare/4.176.3...4.176.4

## What's Changed in 4.176.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use overwrite option when writing module maps
* update Package.resolved to match current dependencies



**Full Changelog**: https://github.com/tuist/tuist/compare/4.176.2...4.176.3

## What's Changed in 4.176.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix xcstrings stale-string detection for multiplatform static frameworks
* mkdir data race
* write empty shard matrix output when selective testing skips all tests



**Full Changelog**: https://github.com/tuist/tuist/compare/4.176.1...4.176.2

## What's Changed in 4.176.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add workspace-level DerivedData location support
### 🐛 Bug Fixes

* add retry logic to build uploads
* add nonisolated(unsafe) to generated plist accessors with Any type



**Full Changelog**: https://github.com/tuist/tuist/compare/4.175.0...4.176.1

## What's Changed in 4.175.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* fix App Intents metadata for cached xcframeworks
* upload build data from tuist xcodebuild build
### 🐛 Bug Fixes

* handle existing files during shard xctestrun write



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.7...4.175.0

## What's Changed in 4.174.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* namespace dependency-derived artifacts
* fix cross-project test host embed and TEST_HOST settings
### 🚜 Refactor

* remove local MCP command



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.4...4.174.7

## What's Changed in 4.174.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add missing TuistTesting dependency to TuistCASTests



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.3...4.174.4

## What's Changed in 4.174.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix selective testing not skipping unchanged test targets



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.2...4.174.3

## What's Changed in 4.174.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* deduplicate entries during Apple Archive compression



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.1...4.174.2

## What's Changed in 4.174.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* dereference symlinks during Apple Archive compression
* resolve result bundle symlink before remote upload



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.0...4.174.1

## What's Changed in 4.174.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add defaultSwiftVersion generation option and respect package-declared Swift versions



**Full Changelog**: https://github.com/tuist/tuist/compare/4.173.1...4.174.0

## What's Changed in 4.173.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resource/file glob excluding with ** pattern incorrectly excludes all sibling files



**Full Changelog**: https://github.com/tuist/tuist/compare/4.173.0...4.173.1

## What's Changed in 4.173.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add --inspect-mode flag for remote xcresult processing
* support shared volumes for test shard distribution
### 🐛 Bug Fixes

* preserve .swiftmodule directories in shard archives



**Full Changelog**: https://github.com/tuist/tuist/compare/4.172.0...4.173.0

## What's Changed in 4.172.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add remote processing mode for tuist inspect test
### 🐛 Bug Fixes

* focus to scope to scheme test targets



**Full Changelog**: https://github.com/tuist/tuist/compare/4.171.5...4.172.0

## What's Changed in 4.171.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix xctestproducts lookup after AppleArchive extraction
* resolve incorrect storeKitConfigurationPath and GPX paths in generated xcschemes
* embed App Intents metadata in cached xcframeworks



**Full Changelog**: https://github.com/tuist/tuist/compare/4.171.3...4.171.5

## What's Changed in 4.171.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* archive shard bundle directly from source with exclude patterns



**Full Changelog**: https://github.com/tuist/tuist/compare/4.171.2...4.171.3

## What's Changed in 4.171.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* preserve external static xcframework deps for cached dynamics



**Full Changelog**: https://github.com/tuist/tuist/compare/4.171.1...4.171.2

## What's Changed in 4.171.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* strip dSYMs and compress shard bundle before upload



**Full Changelog**: https://github.com/tuist/tuist/compare/4.171.0...4.171.1

## What's Changed in 4.171.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add retries for OIDC token failures



**Full Changelog**: https://github.com/tuist/tuist/compare/4.170.1...4.171.0

## What's Changed in 4.170.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add selective testing observability via MCP, API, CLI, and skills
### 🐛 Bug Fixes

* replace file-based CAS analytics with SQLite for faster inspect build



**Full Changelog**: https://github.com/tuist/tuist/compare/4.169.2...4.170.1

## What's Changed in 4.169.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle remote binary wrapper xcframework name collisions



**Full Changelog**: https://github.com/tuist/tuist/compare/4.169.1...4.169.2

## What's Changed in 4.169.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* honor explicit run executable for extension schemes
* preserve input order in bounded concurrentMap
### 🚜 Refactor

* replace FileHandler with FileSystem



**Full Changelog**: https://github.com/tuist/tuist/compare/4.169.0...4.169.1

## What's Changed in 4.169.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* link build runs to shard plans
* resolving SPM Targets with automatic product type using baseProductType
### 🐛 Bug Fixes

* support .tbd stub files in xcframeworks
* add missing macOS platforms to mise.lock
### ⚡ Performance

* use dictionary lookup for target resolution in PackageInfoMapper



**Full Changelog**: https://github.com/tuist/tuist/compare/4.167.0...4.169.0

## What's Changed in 4.167.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add native shard matrix output for all CI providers



**Full Changelog**: https://github.com/tuist/tuist/compare/4.166.2...4.167.0

## What's Changed in 4.166.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* show suite names in shard log for suite granularity
* use structural action log timing for test run duration reporting



**Full Changelog**: https://github.com/tuist/tuist/compare/4.166.0...4.166.2

## What's Changed in 4.166.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Allow configuring expected signatures for XCFrameworks exposed by Swift packages



**Full Changelog**: https://github.com/tuist/tuist/compare/4.165.0...4.166.0

## What's Changed in 4.165.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* run quarantined tests instead of skipping them
### 🐛 Bug Fixes

* remove containsResources special-casing for static frameworks
* sort concurrentMap results in content hashers for determinism
* infer platform destination for shard enumeration from graph



**Full Changelog**: https://github.com/tuist/tuist/compare/4.164.1...4.165.0

## What's Changed in 4.164.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* pass destination to test enumeration for suite sharding
* fix macro copy script failing on clean builds



**Full Changelog**: https://github.com/tuist/tuist/compare/4.164.0...4.164.1

## What's Changed in 4.164.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* skip project generation for --without-building with embedded selective testing graph



**Full Changelog**: https://github.com/tuist/tuist/compare/4.163.1...4.164.0

## What's Changed in 4.163.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add test sharding support
### 🐛 Bug Fixes

* support macOS app bundle layout
* always copy macro executable on incremental builds
* fix static framework resource bundle crash when using xcstrings



**Full Changelog**: https://github.com/tuist/tuist/compare/4.162.0...4.163.1

## What's Changed in 4.162.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add storages option to cache configuration



**Full Changelog**: https://github.com/tuist/tuist/compare/4.161.4...4.162.0

## What's Changed in 4.161.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove unsupported DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER build setting



**Full Changelog**: https://github.com/tuist/tuist/compare/4.161.3...4.161.4

## What's Changed in 4.161.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* increase URLSession max connections per host to 20
* normalize swift package target names with spaces



**Full Changelog**: https://github.com/tuist/tuist/compare/4.161.1...4.161.3

## What's Changed in 4.161.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* process builds remotely
### 🐛 Bug Fixes

* prevent xcstrings stale extraction state in static targets
* use SDK-conditioned FRAMEWORK_SEARCH_PATHS for xcframeworks
* resolve merge commit to actual PR head SHA
* only record /cache/ac hashes for test targets, not their deps



**Full Changelog**: https://github.com/tuist/tuist/compare/4.160.3...4.161.1

## What's Changed in 4.160.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* redact sensitive headers in verbose HTTP logs
* restore TuistCacheEE submodule pointer to include empty graph fix



**Full Changelog**: https://github.com/tuist/tuist/compare/4.160.1...4.160.3

## What's Changed in 4.160.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* log test targets that will be tested
### 🐛 Bug Fixes

* use xcactivitylog UUID as build ID for remote processing
* allow iOS bundle targets to have dependencies



**Full Changelog**: https://github.com/tuist/tuist/compare/4.159.0...4.160.1

## What's Changed in 4.159.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload CLI session to S3 after command event creation
### 🐛 Bug Fixes

* add audio and video file extensions to validResourceExtensions



**Full Changelog**: https://github.com/tuist/tuist/compare/4.158.2...4.159.0

## What's Changed in 4.158.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use CFBundleExecutable for binary lookup in tuist share
* correct SYMROOT path in cache warm builds



**Full Changelog**: https://github.com/tuist/tuist/compare/4.158.0...4.158.2

## What's Changed in 4.158.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* server-side xcactivitylog processing
### 🐛 Bug Fixes

* filter pruned test targets from -only-testing flags



**Full Changelog**: https://github.com/tuist/tuist/compare/4.157.4...4.158.0

## What's Changed in 4.157.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resolve --path flag not working for tuist setup cache
* use modern launchctl bootstrap/bootout for cache daemon
* use modern launchctl bootstrap/bootout for cache daemon
* skip binary cache mapping when graph is empty after selective testing



**Full Changelog**: https://github.com/tuist/tuist/compare/4.157.1...4.157.4

## What's Changed in 4.157.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add watch2AppContainer product type for watchOS-only apps
### 🐛 Bug Fixes

* resolve missing module dependencies with cached local frameworks
* override SYMROOT in cache warm builds to prevent custom build location mismatch
* restore generate run analytics on dashboard
* handle selectively-pruned targets in --test-targets validation
* include all platform-matching xcframework slices in FRAMEWORK_SEARCH_PATHS



**Full Changelog**: https://github.com/tuist/tuist/compare/4.156.0...4.157.1

## What's Changed in 4.156.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track machine metrics
### 🐛 Bug Fixes

* support OIDC account tokens for registry login on CI
* fix build category detection for Xcode 26.3+ with compilation cache



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.4...4.156.0

## What's Changed in 4.155.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* archive builds for static targets with xcassets
* prevent multiple commands produce when static product depends on same-named xcframework
* exclude non-test-dependency targets from workspace scheme build action



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.2...4.155.4

## What's Changed in 4.155.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* expose ProjectDescription product on Linux for DocC generation



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.1...4.155.2

## What's Changed in 4.155.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* correctly detect incremental builds with Xcode compilation cache



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.0...4.155.1

## What's Changed in 4.155.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* group test attachments by repetition
### 🐛 Bug Fixes

* bump Rosalind to 0.7.22 and restore dependency versions
* propagate module map flags to configuration-level setting overrides



**Full Changelog**: https://github.com/tuist/tuist/compare/4.154.4...4.155.0

## What's Changed in 4.154.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* bump Rosalind to 0.7.22 and swift-protobuf to 1.35.1
* fix build categorization for Xcode 26+ compilation cache
* bump XCLogParser to 0.2.46 and improve activity log error messages
### 📚 Documentation

* replace SourceDocs ProjectDescription reference with DocC



**Full Changelog**: https://github.com/tuist/tuist/compare/4.154.1...4.154.4

## What's Changed in 4.154.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix buildable-folder header visibility and generation crash
* treat opaque directories as files in buildable folder resolution



**Full Changelog**: https://github.com/tuist/tuist/compare/4.154.0...4.154.1

## What's Changed in 4.154.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload and display all test attachments from xcresult bundles
* make tuist inspect bundle available on Linux
* prune old binary cache entries on startup
* vendor XcodeGraph into tuist and reconcile dependency graphs
* add "Ask on Launch" executable option for scheme actions
* add warningsAsErrors generation option
### 🐛 Bug Fixes

* include transitive search paths through dynamic framework dependencies
* exclude directories from buildable folder resolved files
* cap concurrency to avoid file descriptor exhaustion
* Fix case-insensitive prioritize local packages over registry
* add xcassets and xcstrings to sources build phase for static targets
* update Command package to 0.14.0
* make CacheLocalStorage.clean public
* bump FileSystem to 0.15.0 for setFileTimes support
* sort Set iterations in graph mappers for deterministic cache hashing
* limit concurrency of buildable folder resolution to avoid FD exhaustion
* add validation folder exists for BuildableFolder
* prune static xcframework deps from dynamic xcframeworks for hostless unit tests
* upload APK files directly instead of wrapping in zip
* populate explicitFolders for excluded directories in buildable folders
### 🚜 Refactor

* migrate acceptance tests to Swift Testing



**Full Changelog**: https://github.com/tuist/tuist/compare/4.151.1...4.154.0

## What's Changed in 4.151.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* replace deprecated tuist build recommendation in previews



**Full Changelog**: https://github.com/tuist/tuist/compare/4.151.0...4.151.1

## What's Changed in 4.151.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* expand glob patterns in buildable folder exclusions



**Full Changelog**: https://github.com/tuist/tuist/compare/4.150.1...4.151.0

## What's Changed in 4.150.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* expanding folder to input inner files when used as input in foreign build phase script
* place precompiled dependencies from SPM build directory in frameworks group



**Full Changelog**: https://github.com/tuist/tuist/compare/4.150.0...4.150.1

## What's Changed in 4.150.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add platformFilters for buildable folder exceptions



**Full Changelog**: https://github.com/tuist/tuist/compare/4.149.1...4.150.0

## What's Changed in 4.149.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Use latest Gradle plugin version in init and add takeaways



**Full Changelog**: https://github.com/tuist/tuist/compare/4.149.0...4.149.1

## What's Changed in 4.149.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Android APK previews with cross-platform share and run
### 🐛 Bug Fixes

* Prioritize local packages over registry versions



**Full Changelog**: https://github.com/tuist/tuist/compare/4.148.4...4.149.0

## What's Changed in 4.148.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* apply PackageSettings.baseSettings.defaultSettings to SPM targets
* restore SRCROOT path resolution for cached target settings
* respect custom server url
* include buildable folder resources in Target.containsResources
* use product name as module name for SPM wrapper targets



**Full Changelog**: https://github.com/tuist/tuist/compare/4.148.1...4.148.4

## What's Changed in 4.148.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Android bundle support (AAB + APK)
* crash stack traces with formatted frames, attachments, and download URLs
### 🐛 Bug Fixes

* pass jsonThroughNoora to Noora on Linux
* bump xcode version release
* preserve JSON logger for non-Noora commands on Linux
* don't run foreign build script when target is served from binary cache
* sanitize + character in intra-package target dependency names
* warn when skip test targets don't intersect
* add Swift toolchain library search path for ObjC targets linking static Swift dependencies
* resolve static ObjC xcframework search paths without Package.swift
* enable HTTP logging and server warnings on Linux



**Full Changelog**: https://github.com/tuist/tuist/compare/4.146.1...4.148.1

## What's Changed in 4.146.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix cache building unnecessary Catalyst scheme for external dependencies



**Full Changelog**: https://github.com/tuist/tuist/compare/4.146.0...4.146.1

## What's Changed in 4.146.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add foreign build system dependencies
### 🐛 Bug Fixes

* restore TuistSimulator to macOS-only block in Package.swift
* increase inspect build activity log timeout and make it configurable
* fix CLI release (static linking, Musl imports, Bundle(for:))
* use canImport(Musl) for Static Linux SDK compatibility
* remove OpenAPIURLSession from cross-platform targets for Linux static SDK
* restore cache run analytics on dashboard
* only cache dependency checkouts in Linux CI jobs
* add missing tree-shake after focus targets in automation mapper chain



**Full Changelog**: https://github.com/tuist/tuist/compare/4.145.0...4.146.0

## What's Changed in 4.145.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* support build system selection in project create
### 🐛 Bug Fixes

* remove unused CacheBuiltArtifactsFetcher from CacheWarmCommandService



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.4...4.145.0

## What's Changed in 4.144.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fall back to BUILD_DIR for derived data resolution



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.3...4.144.4

## What's Changed in 4.144.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* embed cached static xcframeworks with resources transitively



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.2...4.144.3

## What's Changed in 4.144.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* run StaticXCFrameworkModuleMapGraphMapper after cache replacement



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.1...4.144.2

## What's Changed in 4.144.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix flaky tests caused by Matcher.register race and TOCTOU in CachedManifestLoader



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.0...4.144.1

## What's Changed in 4.144.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Gradle project integration to tuist init
* add test case show and run commands with fix-flaky-tests skill
### 🐛 Bug Fixes

* resolve derived data path from DERIVED_DATA_DIR env in inspect commands
* use correct TUIST_URL key for env variable lookup in login command
* strip debug symbols (dSYM/DWARF) from cached XCFrameworks



**Full Changelog**: https://github.com/tuist/tuist/compare/4.142.1...4.144.0

## What's Changed in 4.142.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* make server commands available on Linux
### 🐛 Bug Fixes

* don't retry non-retryable errors in module cache download
* restore asset symbol generation for external static frameworks
* use correct bundle accessor for external dynamic frameworks with resources



**Full Changelog**: https://github.com/tuist/tuist/compare/4.141.1...4.142.1

## What's Changed in 4.141.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add debug logging to inspect build and test commands



**Full Changelog**: https://github.com/tuist/tuist/compare/4.141.0...4.141.1

## What's Changed in 4.141.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add tuist.toml support



**Full Changelog**: https://github.com/tuist/tuist/compare/4.140.2...4.141.0

## What's Changed in 4.140.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* skip macro targets in static dependency traversal
* add retry logic to OIDC authentication flow
* fix CI environment variable filtering



**Full Changelog**: https://github.com/tuist/tuist/compare/4.140.1...4.140.2

## What's Changed in 4.140.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Linux support for auth and cache commands
### 🐛 Bug Fixes

* fix `tuist version` producing no output on Linux



**Full Changelog**: https://github.com/tuist/tuist/compare/4.139.1...4.140.1

## What's Changed in 4.139.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't embed static precompiled xcframeworks



**Full Changelog**: https://github.com/tuist/tuist/compare/4.139.0...4.139.1

## What's Changed in 4.139.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add configurable cache push policy
### 🐛 Bug Fixes

* deduplicate plugins with the same name in tuist edit



**Full Changelog**: https://github.com/tuist/tuist/compare/4.138.1...4.139.0

## What's Changed in 4.138.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add extension bundle search paths for resource accessors



**Full Changelog**: https://github.com/tuist/tuist/compare/4.138.0...4.138.1

## What's Changed in 4.138.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add custom metadata and tags to build runs



**Full Changelog**: https://github.com/tuist/tuist/compare/4.137.1...4.138.0

## What's Changed in 4.137.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* guard log file creation for Noora



**Full Changelog**: https://github.com/tuist/tuist/compare/4.137.0...4.137.1

## What's Changed in 4.137.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* record network requests to HAR files for debugging



**Full Changelog**: https://github.com/tuist/tuist/compare/4.136.0...4.137.0

## What's Changed in 4.136.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add generations and cache runs API endpoints and CLI commands
### 🐛 Bug Fixes

* embed static frameworks with buildable-folder resources
* skip config loading for inspect commands



**Full Changelog**: https://github.com/tuist/tuist/compare/4.135.2...4.136.0

## What's Changed in 4.135.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* avoid stale auth token cache during long uploads



**Full Changelog**: https://github.com/tuist/tuist/compare/4.135.1...4.135.2

## What's Changed in 4.135.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generate registry config before resolving Swift packages



**Full Changelog**: https://github.com/tuist/tuist/compare/4.135.0...4.135.1

## What's Changed in 4.135.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* auto-skip quarantined tests in tuist test



**Full Changelog**: https://github.com/tuist/tuist/compare/4.134.1...4.135.0

## What's Changed in 4.134.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Bump cache version for static framework copy layout



**Full Changelog**: https://github.com/tuist/tuist/compare/4.134.0...4.134.1

## What's Changed in 4.134.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add build list and build show commands



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.4...4.134.0

## What's Changed in 4.133.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle Metal files in buildable folders for resource bundle generation



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.3...4.133.4

## What's Changed in 4.133.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* propagate .bundle resource files from external static frameworks to host app
* search host bundle paths in ObjC resource bundle accessor
* harden log cleanup



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.2...4.133.3

## What's Changed in 4.133.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* eagerly compute conditional targets to prevent thread starvation during generation
* only embed static XCFrameworks containing .framework bundles



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.0...4.133.2

## What's Changed in 4.133.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add TUIST_CACHE_ENDPOINT environment variable override
* add debug logging to diagnose generation hangs



**Full Changelog**: https://github.com/tuist/tuist/compare/4.132.1...4.133.0

## What's Changed in 4.132.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add authentication failure error for cache
* update FileSystem to fix intermittent crash on startup



**Full Changelog**: https://github.com/tuist/tuist/compare/4.132.0...4.132.1

## What's Changed in 4.132.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add registryEnabled generation option



**Full Changelog**: https://github.com/tuist/tuist/compare/4.131.2...4.132.0

## What's Changed in 4.131.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* revert swift-protobuf to GitHub URL to fix manifest issue
* set default cache concurrency limit to 100
* support BITRISE_IDENTITY_TOKEN env var for Bitrise OIDC auth
* embed static XCFrameworks to support resources



**Full Changelog**: https://github.com/tuist/tuist/compare/4.131.1...4.131.2

## What's Changed in 4.131.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* restore mapper order for selective testing and fix parseAsRoot



**Full Changelog**: https://github.com/tuist/tuist/compare/4.131.0...4.131.1

## What's Changed in 4.131.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add test quarantine and automations settings



**Full Changelog**: https://github.com/tuist/tuist/compare/4.130.3...4.131.0

## What's Changed in 4.130.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* ensure consistent mapper order between automation and cache pipelines
* use patched swift-openapi-urlsession to fix crash
* filter out dependencies with unsatisfied trait conditions
* fix bundle accessor for Obj-C external static frameworks with resources
### 📚 Documentation

* add intent layer nodes



**Full Changelog**: https://github.com/tuist/tuist/compare/4.130.1...4.130.3

## What's Changed in 4.130.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* correct static xcframework paths when depending on cached targets



**Full Changelog**: https://github.com/tuist/tuist/compare/4.130.0...4.130.1

## What's Changed in 4.130.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add debug logs to project generation



**Full Changelog**: https://github.com/tuist/tuist/compare/4.129.2...4.130.0

## What's Changed in 4.129.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle race condition when creating logs directory



**Full Changelog**: https://github.com/tuist/tuist/compare/4.129.1...4.129.2

## What's Changed in 4.129.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* prevent race condition when creating logs directory



**Full Changelog**: https://github.com/tuist/tuist/compare/4.129.0...4.129.1

## What's Changed in 4.129.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* enable local CAS when enableCaching is true and Tuist project is not configured



**Full Changelog**: https://github.com/tuist/tuist/compare/4.128.3...4.129.0

## What's Changed in 4.128.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix acceptance tests
* External resources failing at runtime unable to find their associated bundle
* only emit a public import when public symbols are present



**Full Changelog**: https://github.com/tuist/tuist/compare/4.128.0...4.128.3

## What's Changed in 4.128.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* make new module cache default
* add support for flaky tests detection
* implement remote cache cleaning
### 🐛 Bug Fixes

* Compilation errors when a static framework contains resources
* remove selective testing support for vanilla Xcode projects
* update inspect acceptance tests for new output format



**Full Changelog**: https://github.com/tuist/tuist/compare/4.125.0...4.128.0

## What's Changed in 4.125.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add unified inspect dependencies command
* Add exceptTargetQueries to cache profiles
### 🐛 Bug Fixes

* Static framework bundles for tests and metal



**Full Changelog**: https://github.com/tuist/tuist/compare/4.124.1...4.125.0

## What's Changed in 4.124.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* disable Swift debug serialization to prevent LLDB warnings
* update XcodeGraph to 1.30.10 to fix CLI resource bundles
* fix flaky DumpServiceIntegrationTests for package manifests



**Full Changelog**: https://github.com/tuist/tuist/compare/4.124.0...4.124.1

## What's Changed in 4.124.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add support for SwiftPM package traits



**Full Changelog**: https://github.com/tuist/tuist/compare/4.123.0...4.124.0

## What's Changed in 4.123.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* show deprecation notice for CLI < 4.56.1



**Full Changelog**: https://github.com/tuist/tuist/compare/4.122.2...4.123.0

## What's Changed in 4.122.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* restore static framework resources without regressions



**Full Changelog**: https://github.com/tuist/tuist/compare/4.122.1...4.122.2

## What's Changed in 4.122.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add excluding parameter to FileElement glob
* Add tuist:synthesized tag to synthesized resource bundles
### 🐛 Bug Fixes

* preserve -enable-upcoming-feature flags in OTHER_SWIFT_FLAGS deduplication



**Full Changelog**: https://github.com/tuist/tuist/compare/4.120.0...4.122.1

## What's Changed in 4.120.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* export hashed graph to file via env variable



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.4...4.120.0

## What's Changed in 4.119.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* exclude __MACOSX folders for remote binary targets
* ensure consistent graph mapper order for cache hashing



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.3...4.119.4

## What's Changed in 4.119.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* filter Catalyst destinations for external dependencies
* handle multi-byte UTF-8 characters in xcresult parsing



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.1...4.119.3

## What's Changed in 4.119.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use generic destination for Mac Catalyst cache builds



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.0...4.119.1

## What's Changed in 4.119.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* custom cache endpoints
### 🐛 Bug Fixes

* Generate TuistBundle if buildableFolders contains synthesized file
* Include Mac Catalyst slice when building XCFrameworks for cache
### 🚜 Refactor

* rename fixtures to examples and simplify fixture handling



**Full Changelog**: https://github.com/tuist/tuist/compare/4.118.1...4.119.0

## What's Changed in 4.118.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* module cache
### 🐛 Bug Fixes

* fix selective testing when experimental cache enabled



**Full Changelog**: https://github.com/tuist/tuist/compare/4.117.0...4.118.1

## What's Changed in 4.117.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* preview tracks
### 🐛 Bug Fixes

* handle cross-project dependencies in redundant import inspection



**Full Changelog**: https://github.com/tuist/tuist/compare/4.116.2...4.117.0

## What's Changed in 4.116.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* require previews to have unique binary id and bundle version



**Full Changelog**: https://github.com/tuist/tuist/compare/4.116.1...4.116.2

## What's Changed in 4.116.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* compute binary id as part of tuist share
### 🐛 Bug Fixes

* add support for the new mise bin path



**Full Changelog**: https://github.com/tuist/tuist/compare/4.115.1...4.116.1

## What's Changed in 4.115.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* migrate Fixtures - Tuist initializer with .project



**Full Changelog**: https://github.com/tuist/tuist/compare/4.115.0...4.115.1

## What's Changed in 4.115.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload command run analytics in the background



**Full Changelog**: https://github.com/tuist/tuist/compare/4.114.0...4.115.0

## What's Changed in 4.114.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* OIDC support Bitrise and CircleCI
### 🐛 Bug Fixes

* parsing XCActivityLog on Xcode 26.2 and newer



**Full Changelog**: https://github.com/tuist/tuist/compare/4.113.0...4.114.0

## What's Changed in 4.113.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* OIDC token support for GitHub Actions



**Full Changelog**: https://github.com/tuist/tuist/compare/4.112.0...4.113.0

## What's Changed in 4.112.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* account tokens
* report module cache subhashes
### 🐛 Bug Fixes

* respect explicit cache profile none with target focus



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.3...4.112.0

## What's Changed in 4.110.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle skipped tests due to a failed build



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.2...4.110.3

## What's Changed in 4.110.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* false positive for a .uiTests implicit import of .app



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.1...4.110.2

## What's Changed in 4.110.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* duration for test cases with custom label



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.0...4.110.1

## What's Changed in 4.110.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* deprecate tuist build command



**Full Changelog**: https://github.com/tuist/tuist/compare/4.109.2...4.110.0

## What's Changed in 4.109.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* relegate test result upload error to a warning
* Don't replace targeted external dependencies with cached binary



**Full Changelog**: https://github.com/tuist/tuist/compare/4.109.0...4.109.2

## What's Changed in 4.109.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* link tests to builds
### 🐛 Bug Fixes

* Remove CLANG_CXX_LIBRARY essential build setting



**Full Changelog**: https://github.com/tuist/tuist/compare/4.108.0...4.109.0

## What's Changed in 4.108.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track CI run id for test insights



**Full Changelog**: https://github.com/tuist/tuist/compare/4.107.2...4.108.0

## What's Changed in 4.107.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove fullHandle requirement for tuist registry setup



**Full Changelog**: https://github.com/tuist/tuist/compare/4.107.1...4.107.2

## What's Changed in 4.107.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add test insights
### 🐛 Bug Fixes

* duplicated XCFrameworks in embed phase



**Full Changelog**: https://github.com/tuist/tuist/compare/4.106.3...4.107.1

## What's Changed in 4.106.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* pin swift-collections below 1.3.0
* skip warning Swift flags when hashing
* prefer products with matching casing



**Full Changelog**: https://github.com/tuist/tuist/compare/4.106.1...4.106.3

## What's Changed in 4.106.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* open registry
### 🐛 Bug Fixes

* external dependency case insensitive lookup



**Full Changelog**: https://github.com/tuist/tuist/compare/4.105.1...4.106.1

## What's Changed in 4.105.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix false negative implicit import detection of transitive local dependencies
* refreshing token data race



**Full Changelog**: https://github.com/tuist/tuist/compare/4.105.0...4.105.1

## What's Changed in 4.105.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* improve error message of tuist inspect implicit-imports



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.7...4.105.0

## What's Changed in 4.104.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resolve token refresh data race in ServerAuthenticationController
* skip hashing Xcode version



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.5...4.104.7

## What's Changed in 4.104.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add Emerge Tools SnapshottingTests to the list of targets that depend on XCTest



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.4...4.104.5

## What's Changed in 4.104.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* respect xcframework status



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.3...4.104.4

## What's Changed in 4.104.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* duplicate CAS outputs



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.2...4.104.3

## What's Changed in 4.104.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* skip hashing lockfiles



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.1...4.104.2

## What's Changed in 4.104.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* misreported Xcode cache analytics



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.0...4.104.1

## What's Changed in 4.104.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* connect directly to the cache endpoint



**Full Changelog**: https://github.com/tuist/tuist/compare/4.103.0...4.104.0

## What's Changed in 4.103.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track cas outputs type and cacheable task description
* track cacheable task description
### 🐛 Bug Fixes

* Add extended string delimiter to Strings value in PlistsTemplate



**Full Changelog**: https://github.com/tuist/tuist/compare/4.101.0...4.103.0

## What's Changed in 4.101.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track cache key read/write latency



**Full Changelog**: https://github.com/tuist/tuist/compare/4.100.0...4.101.0

## What's Changed in 4.100.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* cas output analytics



**Full Changelog**: https://github.com/tuist/tuist/compare/4.99.2...4.100.0

## What's Changed in 4.99.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* ensure disableSandbox config is used when dumping package manifests
* support import kind declarations in inspect
* cache Config manifest to improve performance



**Full Changelog**: https://github.com/tuist/tuist/compare/4.99.1...4.99.2

## What's Changed in 4.99.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix buildable folder resource placement for static targets



**Full Changelog**: https://github.com/tuist/tuist/compare/4.99.0...4.99.1

## What's Changed in 4.99.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* optimize Xcode cache by compressing CAS artifacts



**Full Changelog**: https://github.com/tuist/tuist/compare/4.98.0...4.99.0

## What's Changed in 4.98.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Optimize cache hit detection and add diagnostic remarks



**Full Changelog**: https://github.com/tuist/tuist/compare/4.97.2...4.98.0

## What's Changed in 4.97.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* clean up warnings
* fix content hashing to use relative path when file does not exist



**Full Changelog**: https://github.com/tuist/tuist/compare/4.97.0...4.97.2

## What's Changed in 4.97.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add cache profiles to fine tune cached binary replacement



**Full Changelog**: https://github.com/tuist/tuist/compare/4.96.0...4.97.0

## What's Changed in 4.96.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for SwiftPM disableWarning setting
* improve upload error handling for cache artifacts



**Full Changelog**: https://github.com/tuist/tuist/compare/4.95.1...4.96.0

## What's Changed in 4.95.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* downgrade duplicated product name linting from error to warning



**Full Changelog**: https://github.com/tuist/tuist/compare/4.95.0...4.95.1

## What's Changed in 4.95.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for passing arguments to SwiftPM



**Full Changelog**: https://github.com/tuist/tuist/compare/4.94.0...4.95.0

## What's Changed in 4.94.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add support for Swift Package Manager strictMemorySafety setting



**Full Changelog**: https://github.com/tuist/tuist/compare/4.93.0...4.94.0

## What's Changed in 4.93.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* xcode cache analytics



**Full Changelog**: https://github.com/tuist/tuist/compare/4.92.1...4.93.0

## What's Changed in 4.92.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Add support for Internal Imports By Default for Asset accessors



**Full Changelog**: https://github.com/tuist/tuist/compare/4.92.0...4.92.1

## What's Changed in 4.92.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add cache daemon logs



**Full Changelog**: https://github.com/tuist/tuist/compare/4.91.1...4.92.0

## What's Changed in 4.91.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Multiple targets with same hash



**Full Changelog**: https://github.com/tuist/tuist/compare/4.91.0...4.91.1

## What's Changed in 4.91.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Default to no concurrency limit when doing cache uploads and downloads
### 🐛 Bug Fixes

* Bundle accessor not being generated for txt, js or json resources



**Full Changelog**: https://github.com/tuist/tuist/compare/4.90.0...4.91.0

## What's Changed in 4.90.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add support for TUIST_-prefixed XDG environment variables
### 🐛 Bug Fixes

* improve error messages of cache daemon



**Full Changelog**: https://github.com/tuist/tuist/compare/4.89.1...4.90.0

## What's Changed in 4.89.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use TUIST_CONFIG_TOKEN when launching the cache daemon
* ignore macros in inspect redundant dependencies



**Full Changelog**: https://github.com/tuist/tuist/compare/4.89.0...4.89.1

## What's Changed in 4.89.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Only use binaries for external dependencies when no focus target is passed to `tuist generate`
* Add --skip-unit-tests parameter to tuist test command
### 🐛 Bug Fixes

* ignore unit test host app in inspect redundant dependencies



**Full Changelog**: https://github.com/tuist/tuist/compare/4.88.0...4.89.0

## What's Changed in 4.88.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* don't restrict which kind of token is used based on the environment



**Full Changelog**: https://github.com/tuist/tuist/compare/4.87.0...4.88.0

## What's Changed in 4.87.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* tuist setup cache command



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.4...4.87.0

## What's Changed in 4.86.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add individual target sub-hashes for debugging



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.3...4.86.4

## What's Changed in 4.86.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Add support for `.xcdatamodel` opaque directories



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.2...4.86.3

## What's Changed in 4.86.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't throw file not found when hashing generated source files



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.1...4.86.2

## What's Changed in 4.86.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* mysteriously vanished binaries



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.0...4.86.1

## What's Changed in 4.86.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Xcode cache server



**Full Changelog**: https://github.com/tuist/tuist/compare/4.85.2...4.86.0

## What's Changed in 4.85.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* extend inspect build to 5 seconds



**Full Changelog**: https://github.com/tuist/tuist/compare/4.85.1...4.85.2

## What's Changed in 4.85.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Generated projects with binaries not replacing some targets with macros as transitive dependencies



**Full Changelog**: https://github.com/tuist/tuist/compare/4.85.0...4.85.1

## What's Changed in 4.85.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Optimize resource interface synthesis through parallelization



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.3...4.85.0

## What's Changed in 4.84.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't report clean action



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.2...4.84.3

## What's Changed in 4.84.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Handle target action input and output file paths that contain variables



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.1...4.84.2

## What's Changed in 4.84.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* align 'tuist hash cache' to use same generator as cache warming



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.0...4.84.1

## What's Changed in 4.84.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Improve remote cache error handling



**Full Changelog**: https://github.com/tuist/tuist/compare/4.83.0...4.84.0

## What's Changed in 4.83.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Support the `defaultIsolation` setting when integrating packages using native Xcode project targets



**Full Changelog**: https://github.com/tuist/tuist/compare/4.82.3...4.83.0

## What's Changed in 4.82.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* clean up downloaded binary artifacts from temporary directory



**Full Changelog**: https://github.com/tuist/tuist/compare/4.82.2...4.82.3

## What's Changed in 4.82.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't convert script input and output file list paths relative to manifest paths or with build variables to absolute



**Full Changelog**: https://github.com/tuist/tuist/compare/4.82.1...4.82.2

## What's Changed in 4.82.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add bundle type
### 🐛 Bug Fixes

* Ensure buildableFolder resources are handled with project-defined resourceSynthesizers.
* align with the latest Tuist API
* path to the PackageDescription in projects generated by tuist edit



**Full Changelog**: https://github.com/tuist/tuist/compare/4.81.0...4.82.1

## What's Changed in 4.81.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Make implicit import detection work with buildable folders
* add CI run reference to build runs



**Full Changelog**: https://github.com/tuist/tuist/compare/4.80.0...4.81.0

## What's Changed in 4.80.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Report server-side payment-required responses as warnings
* add configuration to build insights



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.7...4.80.0

## What's Changed in 4.79.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Only validate cache signatures on successful responses



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.6...4.79.7

## What's Changed in 4.79.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix cache warming when external targets are excluded by platform conditions
* don't mark inspected build as failed when it has warnings only



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.4...4.79.6

## What's Changed in 4.79.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Add support for headers in buildable folders



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.3...4.79.4

## What's Changed in 4.79.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix synthesized bundle interfaces not generated for `.xcassets` in buildable folders



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.2...4.79.3

## What's Changed in 4.79.2<!-- RELEASE NOTES START -->

### 🧪 Testing

* fix acceptance tests



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.1...4.79.2

## What's Changed in 4.79.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Make `excluded` optional in buildable folder exceptions



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.0...4.79.1

## What's Changed in 4.79.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Support exclusion of files and configuration of compiler flags for files in buildable folders



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.4...4.79.0

## What's Changed in 4.78.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Downgrade ProjectDescription Swift version to 6.1



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.3...4.78.4

## What's Changed in 4.78.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* show Products file group in Xcode navigator



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.2...4.78.3

## What's Changed in 4.78.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* adjust NIOFileSystem references
* handle warnings from the underlying assetutil info when inspecting bundles



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.1...4.78.2

## What's Changed in 4.78.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add default.metallib in static framework



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.0...4.78.1

## What's Changed in 4.78.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* change sandbox to be opt-in



**Full Changelog**: https://github.com/tuist/tuist/compare/4.77.0...4.78.0

## What's Changed in 4.77.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Increase the security of the cache surface



**Full Changelog**: https://github.com/tuist/tuist/compare/4.76.1...4.77.0

## What's Changed in 4.76.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Invalid generated projects when projects are generated with binaries keeping sources and targets



**Full Changelog**: https://github.com/tuist/tuist/compare/4.76.0...4.76.1

## What's Changed in 4.76.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add SE-0162 support for custom SPM target layouts



**Full Changelog**: https://github.com/tuist/tuist/compare/4.75.0...4.76.0

## What's Changed in 4.75.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add unordered xcodebuild command support



**Full Changelog**: https://github.com/tuist/tuist/compare/4.74.1...4.75.0

## What's Changed in 4.74.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Increase the refresh token timeout period



**Full Changelog**: https://github.com/tuist/tuist/compare/4.74.0...4.74.1

## What's Changed in 4.74.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Verbose-log the concurrency limit used by the cache for network connections



**Full Changelog**: https://github.com/tuist/tuist/compare/4.73.0...4.74.0

## What's Changed in 4.73.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for configuring the cache request concurrency limit
### 🐛 Bug Fixes

* tuist cache failing due to the new BuildOperationMetrics attachment type



**Full Changelog**: https://github.com/tuist/tuist/compare/4.72.0...4.73.0

## What's Changed in 4.72.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Remove user credentials when the token sent on refresh is invalid



**Full Changelog**: https://github.com/tuist/tuist/compare/4.71.0...4.72.0

## What's Changed in 4.71.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* generate tests using Swift Testing instead of XCTest



**Full Changelog**: https://github.com/tuist/tuist/compare/4.70.0...4.71.0

## What's Changed in 4.70.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Don't focus when keeping the sources for targets replaced by binaries



**Full Changelog**: https://github.com/tuist/tuist/compare/4.69.0...4.70.0

## What's Changed in 4.69.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* update Swift package resolution to use -scmProvider system



**Full Changelog**: https://github.com/tuist/tuist/compare/4.68.0...4.69.0

## What's Changed in 4.68.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add additionalPackageResolutionArguments for xcodebuild
### 🐛 Bug Fixes

* not generate bundle accessors in when buildable folders don't resolve to any resources



**Full Changelog**: https://github.com/tuist/tuist/compare/4.67.2...4.68.0

## What's Changed in 4.67.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generate bundle accessor when a module has only buildable folders



**Full Changelog**: https://github.com/tuist/tuist/compare/4.67.1...4.67.2

## What's Changed in 4.67.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* default to caching the manifests



**Full Changelog**: https://github.com/tuist/tuist/compare/4.67.0...4.67.1

## What's Changed in 4.67.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* optimize dependency conditions calculation



**Full Changelog**: https://github.com/tuist/tuist/compare/4.66.1...4.67.0

## What's Changed in 4.66.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* XCFramework signature



**Full Changelog**: https://github.com/tuist/tuist/compare/4.66.0...4.66.1

## What's Changed in 4.66.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* skip remote cache downloads on failure



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.7...4.66.0

## What's Changed in 4.65.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generate bundle accessor for modules with metal files



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.6...4.65.7

## What's Changed in 4.65.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* missing bundle accessor when the target uses buildable folders



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.5...4.65.6

## What's Changed in 4.65.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* unable to create account tokens to access the registry



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.4...4.65.5

## What's Changed in 4.65.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* CocoaPods unable to install dependencies due to project's `objectVersion`



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.3...4.65.4

## What's Changed in 4.65.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* arch incompatibilities when using the cache



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.2...4.65.3

## What's Changed in 4.65.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* caching issues due to incompatible architectures



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.1...4.65.2

## What's Changed in 4.65.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* revert caching only the default architecture



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.0...4.65.1

## What's Changed in 4.65.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add filePath and customWorkingDirectory support to RunAction



**Full Changelog**: https://github.com/tuist/tuist/compare/4.64.2...4.65.0

## What's Changed in 4.64.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use XcodeGraph for XcodeKit SDK support



**Full Changelog**: https://github.com/tuist/tuist/compare/4.64.1...4.64.2

## What's Changed in 4.64.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* relative path for local package



**Full Changelog**: https://github.com/tuist/tuist/compare/4.64.0...4.64.1

## What's Changed in 4.64.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* improve passthrough argument documentation with usage examples



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.3...4.64.0

## What's Changed in 4.63.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* include pagination data when listing the bundles as a json



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.2...4.63.3

## What's Changed in 4.63.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* `bundle show` failing due to wrong data passed by the cli



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.1...4.63.2

## What's Changed in 4.63.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* `tuist run` fails to run a scheme even though it has runnable targets



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.0...4.63.1

## What's Changed in 4.63.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add commands to list and read bundles



**Full Changelog**: https://github.com/tuist/tuist/compare/4.62.0...4.63.0

## What's Changed in 4.62.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for buildable folders



**Full Changelog**: https://github.com/tuist/tuist/compare/4.61.2...4.62.0

## What's Changed in 4.61.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* platform conditions not applied for binary dependencies in external packages



**Full Changelog**: https://github.com/tuist/tuist/compare/4.61.1...4.61.2

## What's Changed in 4.61.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generation regression
* fetching devices when running previews



**Full Changelog**: https://github.com/tuist/tuist/compare/4.61.0...4.61.1

## What's Changed in 4.61.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for keeping the sources of the targets replaced by binaries



**Full Changelog**: https://github.com/tuist/tuist/compare/4.60.0...4.61.0

## What's Changed in 4.60.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* support hashing transitive `.xcconfig` files
* add support for XcodeKit SDK
### 🐛 Bug Fixes

* use Xcode default for which architectures are built



**Full Changelog**: https://github.com/tuist/tuist/compare/4.59.2...4.60.0

## What's Changed in 4.59.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* unexpected behaviours when renaming resources in cached targets



**Full Changelog**: https://github.com/tuist/tuist/compare/4.59.1...4.59.2

## What's Changed in 4.59.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* prevent metal files from being processed as resources.



**Full Changelog**: https://github.com/tuist/tuist/compare/4.59.0...4.59.1

## What's Changed in 4.59.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* cache binaries by default for arm64 only, add --architectures option to specify architectures



**Full Changelog**: https://github.com/tuist/tuist/compare/4.58.1...4.59.0

## What's Changed in 4.58.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* include project settings hash in target hash



**Full Changelog**: https://github.com/tuist/tuist/compare/4.58.0...4.58.1

## What's Changed in 4.58.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* print the full sandbox command when a system command fails



**Full Changelog**: https://github.com/tuist/tuist/compare/4.57.1...4.58.0

## What's Changed in 4.57.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* treat the new .icon asset as an opaque directory



**Full Changelog**: https://github.com/tuist/tuist/compare/4.57.0...4.57.1

## What's Changed in 4.57.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for running macOS app via `tuist run`



**Full Changelog**: https://github.com/tuist/tuist/compare/4.56.1...4.57.0

## What's Changed in 4.56.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* auto-generated *-Workspace scheme not getting generated



**Full Changelog**: https://github.com/tuist/tuist/compare/4.56.0...4.56.1

## What's Changed in 4.56.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Ignore internal server errors when interating with the cache



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.9...4.56.0

## What's Changed in 4.55.9<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* do not link cached frameworks with linking status .none



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.8...4.55.9

## What's Changed in 4.55.8<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* 'tuist version' shows the optional string



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.7...4.55.8

## What's Changed in 4.55.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix cli not launching because ProjectAutomation's dynamic framework can't be found
* token refresh race condition



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.6...4.55.7

<!-- generated by git-cliff -->
