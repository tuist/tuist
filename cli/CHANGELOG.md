# Changelog

All notable changes to this project will be documented in this file.
## What's Changed in 4.195.17<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* stream xcodebuild test output with NSUnbufferedIO ([#11046](https://github.com/tuist/tuist/pull/11046))
* preserve active session logs during cleanup ([#11083](https://github.com/tuist/tuist/pull/11083))
* move framework search path setup into a graph mapper ([#11054](https://github.com/tuist/tuist/pull/11054))
* generate foreign build aggregates as scripts ([#11030](https://github.com/tuist/tuist/pull/11030))
* inherit canary fixture feature flags ([#11050](https://github.com/tuist/tuist/pull/11050))
* always expose -Swift.h for Swift-only SPM frameworks ([#11007](https://github.com/tuist/tuist/pull/11007)) ([#11012](https://github.com/tuist/tuist/pull/11012))
* pass precompiled framework search paths to Swift inline, not via @resp ([#11033](https://github.com/tuist/tuist/pull/11033))
* keep test target buildable when only a test-case-level skip matches ([#11032](https://github.com/tuist/tuist/pull/11032))
* use AsyncParsableCommand for plugin run and test commands ([#10603](https://github.com/tuist/tuist/pull/10603))
* infer DerivedData location for inspect build and tests ([#11015](https://github.com/tuist/tuist/pull/11015))
* stop emitting -Xcc @resp into OTHER_SWIFT_FLAGS (Xcode 26 "expected exactly one compiler job") ([#11023](https://github.com/tuist/tuist/pull/11023))
* finish test command early when every test target is filtered out ([#11010](https://github.com/tuist/tuist/pull/11010))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.195.11...4.195.17

## What's Changed in 4.195.11<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* hash the resolved embedded product closure into the cache content hash ([#10984](https://github.com/tuist/tuist/pull/10984))
* pass explicit working directory to manifest evaluation ([#10996](https://github.com/tuist/tuist/pull/10996))
* isolate acceptance fixtures from feature flags ([#10993](https://github.com/tuist/tuist/pull/10993))
* Fix Swift-only package framework modulemaps ([#10971](https://github.com/tuist/tuist/pull/10971))
* avoid checkout cwd for SwiftPM package dumps ([#10966](https://github.com/tuist/tuist/pull/10966))
* avoid expanding recursive exclusion globs ([#10957](https://github.com/tuist/tuist/pull/10957))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.195.7...4.195.11

## What's Changed in 4.195.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use combined module map to avoid argument list too long errors ([#10228](https://github.com/tuist/tuist/pull/10228))
* anchor SwiftPM module-map flags on absolute derived-dir to survive symlinked .build/checkouts ([#10945](https://github.com/tuist/tuist/pull/10945))
* preserve module names for xcframework wrappers ([#10938](https://github.com/tuist/tuist/pull/10938))
* stop duplicating SwiftPM output during tuist install ([#10931](https://github.com/tuist/tuist/pull/10931))
* respect configured SwiftPM scratch paths ([#9253](https://github.com/tuist/tuist/pull/9253))
* canonicalize xcodebuild analytics metadata ([#10920](https://github.com/tuist/tuist/pull/10920))
* ignore embeddable watch apps in redundant dependency inspection ([#10771](https://github.com/tuist/tuist/pull/10771))
* preserve asset symbol generation for buildable-folder xcassets ([#10911](https://github.com/tuist/tuist/pull/10911))
* emit cross-project PBXTargetDependency for foreign build consumers ([#10885](https://github.com/tuist/tuist/pull/10885))
* pass explicit workingDirectory to swift package commands ([#10891](https://github.com/tuist/tuist/pull/10891))
* keep tuist dump stdout machine-readable ([#10874](https://github.com/tuist/tuist/pull/10874))
* re-run foreign build script when inputs cannot be tracked ([#10872](https://github.com/tuist/tuist/pull/10872))
* align tuist hash selective-testing with the test pipeline ([#10870](https://github.com/tuist/tuist/pull/10870))
* apply test quarantine to --without-building and shard runs ([#10864](https://github.com/tuist/tuist/pull/10864))
* Indentation in StringsTemplate.swift ([#10853](https://github.com/tuist/tuist/pull/10853))
* retry run metadata upload on transient errors ([#10842](https://github.com/tuist/tuist/pull/10842))
### ⚡ Performance

* use Set for project path lookups in tree-shake mapper ([#10033](https://github.com/tuist/tuist/pull/10033))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.195.0...4.195.7

## What's Changed in 4.195.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* expose is_quarantined on test case run API ([#10785](https://github.com/tuist/tuist/pull/10785))
* add onOutdatedDependencies action to GenerationOptions ([#10715](https://github.com/tuist/tuist/pull/10715))
### 🐛 Bug Fixes

* deduplicate conditioned xcframework search paths ([#10813](https://github.com/tuist/tuist/pull/10813))
* bind shard reference across split build/test jobs ([#10805](https://github.com/tuist/tuist/pull/10805))
* avoid collecting large verbose HTTP bodies ([#10795](https://github.com/tuist/tuist/pull/10795))
* map default actor isolation to MainActor ([#10779](https://github.com/tuist/tuist/pull/10779))
* synthesize Bundle.module for static frameworks with .metal in buildable folders ([#10746](https://github.com/tuist/tuist/pull/10746))
* release SwiftPM lock before invoking manifest subprocesses ([#10758](https://github.com/tuist/tuist/pull/10758))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.193.3...4.195.0

## What's Changed in 4.193.3<!-- RELEASE NOTES START -->

### ⛰️  Features

* allow forwarding extra env vars to manifest evaluation ([#10705](https://github.com/tuist/tuist/pull/10705))
### 🐛 Bug Fixes

* coordinate SwiftPM graph reads
* propagate selective testing and module cache analytics across --build-only / --without-building ([#10672](https://github.com/tuist/tuist/pull/10672))
* avoid invalidating shared URLSession on no-op HTTPSettings writes ([#10727](https://github.com/tuist/tuist/pull/10727))
* handle nested buildable folder xcstrings ([#10721](https://github.com/tuist/tuist/pull/10721))
* make metadata upload non-fatal ([#10696](https://github.com/tuist/tuist/pull/10696))
* rewrite dangling pre/post-action targets at prune time ([#10654](https://github.com/tuist/tuist/pull/10654))
* allow folder resources to overlap sources ([#10692](https://github.com/tuist/tuist/pull/10692))
* route static xcframeworks behind dynamic via search paths, not relink ([#10704](https://github.com/tuist/tuist/pull/10704))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.192.3...4.193.3

## What's Changed in 4.192.3<!-- RELEASE NOTES START -->

### ⛰️  Features

* rename Tuist `cache` to `xcodeCache` ([#10663](https://github.com/tuist/tuist/pull/10663))
* add tuist test case update command ([#10450](https://github.com/tuist/tuist/pull/10450))
### 🐛 Bug Fixes

* remove noisy transport-level HTTP error logging ([#10699](https://github.com/tuist/tuist/pull/10699))
* limit implicit import source scans ([#10693](https://github.com/tuist/tuist/pull/10693))
* CLI hangs running processes concurrently ([#10682](https://github.com/tuist/tuist/pull/10682))
* resolve race condition in CachedManifestLoader parallel writes ([#10662](https://github.com/tuist/tuist/pull/10662))
* duplicate selective testing log messages and improve skip reason clarity ([#10637](https://github.com/tuist/tuist/pull/10637))
* skip run metadata upload when no auth is available ([#10649](https://github.com/tuist/tuist/pull/10649))
* make multi-process token refresh resilient to slow peers and rotation races ([#10650](https://github.com/tuist/tuist/pull/10650))
* support PackageDescription context ([#10622](https://github.com/tuist/tuist/pull/10622))
* respect disabled autogenerated workspace schemes ([#10631](https://github.com/tuist/tuist/pull/10631))
* treat non-source files in buildable folders as resources ([#10645](https://github.com/tuist/tuist/pull/10645))
* preserve whitespace in plist template for Array-root scalars ([#10614](https://github.com/tuist/tuist/pull/10614))
* preserve pruned test plan metadata ([#10611](https://github.com/tuist/tuist/pull/10611))
* include macOS SDK version in ProjectDescriptionHelpers cache key ([#10598](https://github.com/tuist/tuist/pull/10598))
* skip fully cached missing test plans ([#10582](https://github.com/tuist/tuist/pull/10582))
* disable HAR recording for cache daemon ([#10589](https://github.com/tuist/tuist/pull/10589))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.191.5...4.192.3

## What's Changed in 4.191.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use stamp file for macro copy phase to keep incremental rebuilds ([#10576](https://github.com/tuist/tuist/pull/10576))
* fix macro copy phase output collision on macOS consumer targets ([#10566](https://github.com/tuist/tuist/pull/10566))
* intersect linkable dep destinations for orphan local SPM tests ([#10554](https://github.com/tuist/tuist/pull/10554))
* re-embed test target frameworks not embedded in host ([#10504](https://github.com/tuist/tuist/pull/10504))
* make shared cache and state writes safe across concurrent processes ([#10562](https://github.com/tuist/tuist/pull/10562))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.191.1...4.191.5

## What's Changed in 4.191.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* stabilize cache EE canary acceptance test ([#10549](https://github.com/tuist/tuist/pull/10549))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.191.0...4.191.1

## What's Changed in 4.191.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add --skip-macro-support-targets flag to tuist graph ([#10300](https://github.com/tuist/tuist/pull/10300))
* re-add config-driven network proxy opt-out ([#10513](https://github.com/tuist/tuist/pull/10513))
* add "Skip" quarantine mode for test cases ([#10429](https://github.com/tuist/tuist/pull/10429))
### 🐛 Bug Fixes

* keep static framework xcstrings on main target Resources phase ([#10532](https://github.com/tuist/tuist/pull/10532))
* refresh expired tokens under optionalAuthentication ([#10537](https://github.com/tuist/tuist/pull/10537))
* add TuistHTTP to TuistConfigLoader cross-platform deps ([#10531](https://github.com/tuist/tuist/pull/10531))
* bump tuist.Command to 0.14.1 to surface xcodebuild stderr ([#10508](https://github.com/tuist/tuist/pull/10508))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.188.5...4.191.0

## What's Changed in 4.188.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* update xcactivitylog_nif package path after processor consolidation ([#10507](https://github.com/tuist/tuist/pull/10507))
* honor #if guards in inspect dependencies --only implicit ([#10474](https://github.com/tuist/tuist/pull/10474))
* restore [Path] overload of TestAction.testPlans as deprecated ([#10488](https://github.com/tuist/tuist/pull/10488))
* sanitize target name in generated Obj-C bundle accessor identifiers ([#10482](https://github.com/tuist/tuist/pull/10482))
### ⚡ Performance

* lower URLSession resource timeout from 300s to 90s ([#10503](https://github.com/tuist/tuist/pull/10503))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.188.2...4.188.5

## What's Changed in 4.188.2<!-- RELEASE NOTES START -->

### ⛰️  Features

* add CopyFileElement.buildProduct for embedding target products in Copy Files phases ([#10467](https://github.com/tuist/tuist/pull/10467))
* generate .xctestplan files from ProjectDescription ([#10426](https://github.com/tuist/tuist/pull/10426))
* add 'tuist teardown cache' command ([#10421](https://github.com/tuist/tuist/pull/10421))
* add --inspect-mode off to skip result bundle upload ([#10447](https://github.com/tuist/tuist/pull/10447))
### 🐛 Bug Fixes

* upload build run when -derivedDataPath is passed via passthrough ([#10478](https://github.com/tuist/tuist/pull/10478))
* include source filename in selective testing hash ([#10475](https://github.com/tuist/tuist/pull/10475))
* preserve bundle directory in AppleArchive uploads ([#10460](https://github.com/tuist/tuist/pull/10460))
* handle buildable-folder xcstrings stale analysis ([#10445](https://github.com/tuist/tuist/pull/10445))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.186.2...4.188.2

## What's Changed in 4.186.2<!-- RELEASE NOTES START -->

### ⛰️  Features

* AppleArchive for xcresult upload + respect --inspect-mode remote ([#10416](https://github.com/tuist/tuist/pull/10416))
### 🐛 Bug Fixes

* skip xcodebuild when -skip-testing clears selective tests ([#10433](https://github.com/tuist/tuist/pull/10433))
* respect repo optional auth in command tracking ([#10387](https://github.com/tuist/tuist/pull/10387))
* scope cache warm target selection to non-test roots ([#10398](https://github.com/tuist/tuist/pull/10398))
* make swift-file-system the default filesystem backend ([#10418](https://github.com/tuist/tuist/pull/10418))
* restore static framework .xcstrings localization ([#10423](https://github.com/tuist/tuist/pull/10423))
* propagate default-enabled Swift package traits ([#10403](https://github.com/tuist/tuist/pull/10403))
* add muted/unmuted test case event types ([#10417](https://github.com/tuist/tuist/pull/10417))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.185.1...4.186.2

## What's Changed in 4.185.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* support config-driven network proxy opt-out ([#10334](https://github.com/tuist/tuist/pull/10334))
### 🐛 Bug Fixes

* skip result bundle upload when --inspect-mode local ([#10401](https://github.com/tuist/tuist/pull/10401))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.184.2...4.185.1

## What's Changed in 4.184.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Support  optional Buildable Folders ([#9974](https://github.com/tuist/tuist/pull/9974))
* error instead of silently ignoring mismatched test shard flags ([#10392](https://github.com/tuist/tuist/pull/10392))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.184.1...4.184.2

## What's Changed in 4.184.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add feature flag headers ([#10382](https://github.com/tuist/tuist/pull/10382))
### 🐛 Bug Fixes

* map static library dependencies in XcodeGraph ([#10358](https://github.com/tuist/tuist/pull/10358))
* ensure package product dependencies are initialized ([#10370](https://github.com/tuist/tuist/pull/10370))
* preserve scheme buildAction targets in `tuist test <scheme>` focus ([#10367](https://github.com/tuist/tuist/pull/10367))
### 🚜 Refactor

* deprecate unused `swiftVersion` on `TuistProject.tuist(...)` ([#10381](https://github.com/tuist/tuist/pull/10381))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.183.0...4.184.1

## What's Changed in 4.183.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add paginated test case events endpoint ([#10117](https://github.com/tuist/tuist/pull/10117))
### 🐛 Bug Fixes

* scope `tuist test <scheme>` to the scheme's test plan targets ([#10339](https://github.com/tuist/tuist/pull/10339))
* Fix xcstrings handling in buildable folders ([#10332](https://github.com/tuist/tuist/pull/10332))
* handle strictMemorySafety with empty dump-package JSON ([#10308](https://github.com/tuist/tuist/pull/10308))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.182.0...4.183.0

## What's Changed in 4.182.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* preserve test targets for local SPM packages ([#10268](https://github.com/tuist/tuist/pull/10268))
* resolve inspect bundle app names like share ([#9916](https://github.com/tuist/tuist/pull/9916))
* drop fd-limit caps when swift-file-system backend is enabled ([#10314](https://github.com/tuist/tuist/pull/10314))
### 🐛 Bug Fixes

* clear pruned expandVariableFromTarget instead of dropping the scheme ([#10310](https://github.com/tuist/tuist/pull/10310))
* use literal string matching in ManifestLoader to fix hang on large output ([#10288](https://github.com/tuist/tuist/pull/10288))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.181.1...4.182.0

## What's Changed in 4.181.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* reject xcodebuild action verbs in passthrough arguments ([#10303](https://github.com/tuist/tuist/pull/10303))
* use proxy-aware URLSession for cache endpoint latency checks ([#10307](https://github.com/tuist/tuist/pull/10307))
* handle binary wrapper xcframework name collisions for Singular and Firebase patterns ([#10309](https://github.com/tuist/tuist/pull/10309))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.181.0...4.181.1

## What's Changed in 4.181.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* auto-detect HTTP proxy from HTTPS_PROXY/HTTP_PROXY ([#10261](https://github.com/tuist/tuist/pull/10261))
### 🐛 Bug Fixes

* stop excluding transitive deps from cache hashing for positional targets ([#10301](https://github.com/tuist/tuist/pull/10301))
* Catalyst should use macosx sdk ([#10298](https://github.com/tuist/tuist/pull/10298))
* Make StringProtocol.range(of:) scan UTF-8 bytes ([#10295](https://github.com/tuist/tuist/pull/10295))
* resolve bare "container:" xctestplan target references ([#10290](https://github.com/tuist/tuist/pull/10290))
* Add warning for missing xctestplan files ([#10282](https://github.com/tuist/tuist/pull/10282))
* bump FileSystem to 0.16.1 for Musl support ([#10277](https://github.com/tuist/tuist/pull/10277))
* preserve original error when test result parsing fails ([#10275](https://github.com/tuist/tuist/pull/10275))
* fix synthesized resource interface generation for numeric target names ([#10266](https://github.com/tuist/tuist/pull/10266))
* skip token refresh when optionalAuthentication is enabled ([#10260](https://github.com/tuist/tuist/pull/10260))
* keep xcstrings in Resources phase for static framework stale detection ([#10247](https://github.com/tuist/tuist/pull/10247))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.180.0...4.181.0

## What's Changed in 4.180.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* process test insights remotely ([#10243](https://github.com/tuist/tuist/pull/10243))
### 🐛 Bug Fixes

* ignore .DS_Store files when hashing buildable folders ([#10240](https://github.com/tuist/tuist/pull/10240))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.179.3...4.180.0

## What's Changed in 4.179.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* skip embedding extensions in unit test targets ([#10224](https://github.com/tuist/tuist/pull/10224))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.179.2...4.179.3

## What's Changed in 4.179.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add retry middleware for OpenAPI requests ([#10233](https://github.com/tuist/tuist/pull/10233))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.179.1...4.179.2

## What's Changed in 4.179.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resolve StoreKit configuration paths relative to the xcworkspace bundle ([#10179](https://github.com/tuist/tuist/pull/10179))
* use Modules include path for source-built ProjectDescription ([#10181](https://github.com/tuist/tuist/pull/10181))
* resolve relative -testProductsPath when writing selective testing graph ([#10239](https://github.com/tuist/tuist/pull/10239))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.179.0...4.179.1

## What's Changed in 4.179.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add parameterized test argument support ([#10127](https://github.com/tuist/tuist/pull/10127))
### 🐛 Bug Fixes

* mark generated bundle accessors as nonisolated ([#10065](https://github.com/tuist/tuist/pull/10065))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.178.1...4.179.0

## What's Changed in 4.178.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* support self-managed shard archives ([#10169](https://github.com/tuist/tuist/pull/10169))
### 🐛 Bug Fixes

* avoid duplicate App Intents dependency file list outputs ([#10235](https://github.com/tuist/tuist/pull/10235))
* link test runs to builds and fix command event metadata ([#10234](https://github.com/tuist/tuist/pull/10234))
* declare symlink target in macro copy script input paths for sandbox compatibility ([#10116](https://github.com/tuist/tuist/pull/10116))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.177.0...4.178.1

## What's Changed in 4.177.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add --cache-profile option to cache warm with profile-driven exclusions ([#9946](https://github.com/tuist/tuist/pull/9946))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.176.4...4.177.0

## What's Changed in 4.176.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* write empty shard matrix on all early return paths ([#10220](https://github.com/tuist/tuist/pull/10220))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.176.3...4.176.4

## What's Changed in 4.176.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use overwrite option when writing module maps ([#10218](https://github.com/tuist/tuist/pull/10218))
* update Package.resolved to match current dependencies ([#10216](https://github.com/tuist/tuist/pull/10216))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.176.2...4.176.3

## What's Changed in 4.176.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix xcstrings stale-string detection for multiplatform static frameworks ([#10155](https://github.com/tuist/tuist/pull/10155))
* mkdir data race ([#10211](https://github.com/tuist/tuist/pull/10211))
* write empty shard matrix output when selective testing skips all tests ([#10205](https://github.com/tuist/tuist/pull/10205))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.176.1...4.176.2

## What's Changed in 4.176.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add workspace-level DerivedData location support ([#9693](https://github.com/tuist/tuist/pull/9693))
### 🐛 Bug Fixes

* add retry logic to build uploads ([#10210](https://github.com/tuist/tuist/pull/10210))
* add nonisolated(unsafe) to generated plist accessors with Any type ([#10195](https://github.com/tuist/tuist/pull/10195))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.175.0...4.176.1

## What's Changed in 4.175.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* fix App Intents metadata for cached xcframeworks ([#10168](https://github.com/tuist/tuist/pull/10168))
* upload build data from tuist xcodebuild build ([#10186](https://github.com/tuist/tuist/pull/10186))
### 🐛 Bug Fixes

* handle existing files during shard xctestrun write ([#10188](https://github.com/tuist/tuist/pull/10188))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.7...4.175.0

## What's Changed in 4.174.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* namespace dependency-derived artifacts ([#10166](https://github.com/tuist/tuist/pull/10166))
* fix cross-project test host embed and TEST_HOST settings ([#10139](https://github.com/tuist/tuist/pull/10139))
### 🚜 Refactor

* remove local MCP command ([#10171](https://github.com/tuist/tuist/pull/10171))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.4...4.174.7

## What's Changed in 4.174.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add missing TuistTesting dependency to TuistCASTests ([#10182](https://github.com/tuist/tuist/pull/10182))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.3...4.174.4

## What's Changed in 4.174.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix selective testing not skipping unchanged test targets ([#10173](https://github.com/tuist/tuist/pull/10173))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.2...4.174.3

## What's Changed in 4.174.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* deduplicate entries during Apple Archive compression ([#10164](https://github.com/tuist/tuist/pull/10164))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.1...4.174.2

## What's Changed in 4.174.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* dereference symlinks during Apple Archive compression ([#10163](https://github.com/tuist/tuist/pull/10163))
* resolve result bundle symlink before remote upload ([#10161](https://github.com/tuist/tuist/pull/10161))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.174.0...4.174.1

## What's Changed in 4.174.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add defaultSwiftVersion generation option and respect package-declared Swift versions ([#10151](https://github.com/tuist/tuist/pull/10151))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.173.1...4.174.0

## What's Changed in 4.173.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resource/file glob excluding with ** pattern incorrectly excludes all sibling files ([#10114](https://github.com/tuist/tuist/pull/10114))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.173.0...4.173.1

## What's Changed in 4.173.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add --inspect-mode flag for remote xcresult processing ([#10145](https://github.com/tuist/tuist/pull/10145))
* support shared volumes for test shard distribution ([#10144](https://github.com/tuist/tuist/pull/10144))
### 🐛 Bug Fixes

* preserve .swiftmodule directories in shard archives ([#10137](https://github.com/tuist/tuist/pull/10137))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.172.0...4.173.0

## What's Changed in 4.172.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add remote processing mode for tuist inspect test ([#10094](https://github.com/tuist/tuist/pull/10094))
### 🐛 Bug Fixes

* focus to scope to scheme test targets ([#10131](https://github.com/tuist/tuist/pull/10131))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.171.5...4.172.0

## What's Changed in 4.171.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix xctestproducts lookup after AppleArchive extraction ([#10126](https://github.com/tuist/tuist/pull/10126))
* resolve incorrect storeKitConfigurationPath and GPX paths in generated xcschemes ([#10122](https://github.com/tuist/tuist/pull/10122))
* embed App Intents metadata in cached xcframeworks ([#10120](https://github.com/tuist/tuist/pull/10120))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.171.3...4.171.5

## What's Changed in 4.171.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* archive shard bundle directly from source with exclude patterns ([#10121](https://github.com/tuist/tuist/pull/10121))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.171.2...4.171.3

## What's Changed in 4.171.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* preserve external static xcframework deps for cached dynamics ([#10089](https://github.com/tuist/tuist/pull/10089))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.171.1...4.171.2

## What's Changed in 4.171.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* strip dSYMs and compress shard bundle before upload ([#10112](https://github.com/tuist/tuist/pull/10112))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.171.0...4.171.1

## What's Changed in 4.171.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add retries for OIDC token failures ([#10085](https://github.com/tuist/tuist/pull/10085))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.170.1...4.171.0

## What's Changed in 4.170.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add selective testing observability via MCP, API, CLI, and skills ([#10013](https://github.com/tuist/tuist/pull/10013))
### 🐛 Bug Fixes

* replace file-based CAS analytics with SQLite for faster inspect build ([#10062](https://github.com/tuist/tuist/pull/10062))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.169.2...4.170.1

## What's Changed in 4.169.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle remote binary wrapper xcframework name collisions ([#10054](https://github.com/tuist/tuist/pull/10054))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.169.1...4.169.2

## What's Changed in 4.169.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* honor explicit run executable for extension schemes ([#10057](https://github.com/tuist/tuist/pull/10057))
* preserve input order in bounded concurrentMap ([#10041](https://github.com/tuist/tuist/pull/10041))
### 🚜 Refactor

* replace FileHandler with FileSystem ([#10040](https://github.com/tuist/tuist/pull/10040))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.169.0...4.169.1

## What's Changed in 4.169.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* link build runs to shard plans ([#10032](https://github.com/tuist/tuist/pull/10032))
* resolving SPM Targets with automatic product type using baseProductType ([#9809](https://github.com/tuist/tuist/pull/9809))
### 🐛 Bug Fixes

* support .tbd stub files in xcframeworks ([#9992](https://github.com/tuist/tuist/pull/9992))
* add missing macOS platforms to mise.lock ([#10030](https://github.com/tuist/tuist/pull/10030))
### ⚡ Performance

* use dictionary lookup for target resolution in PackageInfoMapper ([#10021](https://github.com/tuist/tuist/pull/10021))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.167.0...4.169.0

## What's Changed in 4.167.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add native shard matrix output for all CI providers ([#10009](https://github.com/tuist/tuist/pull/10009))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.166.2...4.167.0

## What's Changed in 4.166.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* show suite names in shard log for suite granularity ([#10008](https://github.com/tuist/tuist/pull/10008))
* use structural action log timing for test run duration reporting ([#10007](https://github.com/tuist/tuist/pull/10007))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.166.0...4.166.2

## What's Changed in 4.166.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Allow configuring expected signatures for XCFrameworks exposed by Swift packages ([#9914](https://github.com/tuist/tuist/pull/9914))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.165.0...4.166.0

## What's Changed in 4.165.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* run quarantined tests instead of skipping them ([#9978](https://github.com/tuist/tuist/pull/9978))
### 🐛 Bug Fixes

* remove containsResources special-casing for static frameworks ([#10003](https://github.com/tuist/tuist/pull/10003))
* sort concurrentMap results in content hashers for determinism ([#9998](https://github.com/tuist/tuist/pull/9998))
* infer platform destination for shard enumeration from graph ([#9997](https://github.com/tuist/tuist/pull/9997))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.164.1...4.165.0

## What's Changed in 4.164.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* pass destination to test enumeration for suite sharding ([#9986](https://github.com/tuist/tuist/pull/9986))
* fix macro copy script failing on clean builds ([#9995](https://github.com/tuist/tuist/pull/9995))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.164.0...4.164.1

## What's Changed in 4.164.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* skip project generation for --without-building with embedded selective testing graph ([#9987](https://github.com/tuist/tuist/pull/9987))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.163.1...4.164.0

## What's Changed in 4.163.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add test sharding support ([#9796](https://github.com/tuist/tuist/pull/9796))
### 🐛 Bug Fixes

* support macOS app bundle layout ([#9849](https://github.com/tuist/tuist/pull/9849))
* always copy macro executable on incremental builds ([#9962](https://github.com/tuist/tuist/pull/9962))
* fix static framework resource bundle crash when using xcstrings ([#9953](https://github.com/tuist/tuist/pull/9953))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.162.0...4.163.1

## What's Changed in 4.162.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add storages option to cache configuration ([#9938](https://github.com/tuist/tuist/pull/9938))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.161.4...4.162.0

## What's Changed in 4.161.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove unsupported DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER build setting ([#9940](https://github.com/tuist/tuist/pull/9940))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.161.3...4.161.4

## What's Changed in 4.161.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* increase URLSession max connections per host to 20 ([#9931](https://github.com/tuist/tuist/pull/9931))
* normalize swift package target names with spaces ([#9928](https://github.com/tuist/tuist/pull/9928))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.161.1...4.161.3

## What's Changed in 4.161.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* process builds remotely ([#9911](https://github.com/tuist/tuist/pull/9911))
### 🐛 Bug Fixes

* prevent xcstrings stale extraction state in static targets ([#9907](https://github.com/tuist/tuist/pull/9907))
* use SDK-conditioned FRAMEWORK_SEARCH_PATHS for xcframeworks ([#9902](https://github.com/tuist/tuist/pull/9902))
* resolve merge commit to actual PR head SHA ([#9905](https://github.com/tuist/tuist/pull/9905))
* only record /cache/ac hashes for test targets, not their deps ([#9909](https://github.com/tuist/tuist/pull/9909))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.160.3...4.161.1

## What's Changed in 4.160.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* redact sensitive headers in verbose HTTP logs ([#9906](https://github.com/tuist/tuist/pull/9906))
* restore TuistCacheEE submodule pointer to include empty graph fix ([#9904](https://github.com/tuist/tuist/pull/9904))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.160.1...4.160.3

## What's Changed in 4.160.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* log test targets that will be tested ([#9731](https://github.com/tuist/tuist/pull/9731))
### 🐛 Bug Fixes

* use xcactivitylog UUID as build ID for remote processing ([#9897](https://github.com/tuist/tuist/pull/9897))
* allow iOS bundle targets to have dependencies ([#9883](https://github.com/tuist/tuist/pull/9883))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.159.0...4.160.1

## What's Changed in 4.159.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload CLI session to S3 after command event creation ([#9870](https://github.com/tuist/tuist/pull/9870))
### 🐛 Bug Fixes

* add audio and video file extensions to validResourceExtensions ([#9800](https://github.com/tuist/tuist/pull/9800))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.158.2...4.159.0

## What's Changed in 4.158.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use CFBundleExecutable for binary lookup in tuist share ([#9840](https://github.com/tuist/tuist/pull/9840))
* correct SYMROOT path in cache warm builds ([#9833](https://github.com/tuist/tuist/pull/9833))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.158.0...4.158.2

## What's Changed in 4.158.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* server-side xcactivitylog processing ([#9752](https://github.com/tuist/tuist/pull/9752))
### 🐛 Bug Fixes

* filter pruned test targets from -only-testing flags ([#9823](https://github.com/tuist/tuist/pull/9823))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.157.4...4.158.0

## What's Changed in 4.157.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resolve --path flag not working for tuist setup cache ([#9826](https://github.com/tuist/tuist/pull/9826))
* use modern launchctl bootstrap/bootout for cache daemon ([#9819](https://github.com/tuist/tuist/pull/9819))
* use modern launchctl bootstrap/bootout for cache daemon ([#9815](https://github.com/tuist/tuist/pull/9815))
* skip binary cache mapping when graph is empty after selective testing ([#9814](https://github.com/tuist/tuist/pull/9814))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.157.1...4.157.4

## What's Changed in 4.157.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add watch2AppContainer product type for watchOS-only apps ([#9648](https://github.com/tuist/tuist/pull/9648))
### 🐛 Bug Fixes

* resolve missing module dependencies with cached local frameworks ([#9805](https://github.com/tuist/tuist/pull/9805))
* override SYMROOT in cache warm builds to prevent custom build location mismatch ([#9803](https://github.com/tuist/tuist/pull/9803))
* restore generate run analytics on dashboard ([#9795](https://github.com/tuist/tuist/pull/9795))
* handle selectively-pruned targets in --test-targets validation ([#9783](https://github.com/tuist/tuist/pull/9783))
* include all platform-matching xcframework slices in FRAMEWORK_SEARCH_PATHS ([#9730](https://github.com/tuist/tuist/pull/9730))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.156.0...4.157.1

## What's Changed in 4.156.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track machine metrics ([#9760](https://github.com/tuist/tuist/pull/9760))
### 🐛 Bug Fixes

* support OIDC account tokens for registry login on CI ([#9769](https://github.com/tuist/tuist/pull/9769))
* fix build category detection for Xcode 26.3+ with compilation cache ([#9762](https://github.com/tuist/tuist/pull/9762))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.4...4.156.0

## What's Changed in 4.155.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* archive builds for static targets with xcassets ([#9722](https://github.com/tuist/tuist/pull/9722))
* prevent multiple commands produce when static product depends on same-named xcframework ([#9758](https://github.com/tuist/tuist/pull/9758))
* exclude non-test-dependency targets from workspace scheme build action ([#9741](https://github.com/tuist/tuist/pull/9741))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.2...4.155.4

## What's Changed in 4.155.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* expose ProjectDescription product on Linux for DocC generation ([#9745](https://github.com/tuist/tuist/pull/9745))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.1...4.155.2

## What's Changed in 4.155.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* correctly detect incremental builds with Xcode compilation cache ([#9725](https://github.com/tuist/tuist/pull/9725))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.155.0...4.155.1

## What's Changed in 4.155.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* group test attachments by repetition ([#9714](https://github.com/tuist/tuist/pull/9714))
### 🐛 Bug Fixes

* bump Rosalind to 0.7.22 and restore dependency versions ([#9720](https://github.com/tuist/tuist/pull/9720))
* propagate module map flags to configuration-level setting overrides ([#9692](https://github.com/tuist/tuist/pull/9692))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.154.4...4.155.0

## What's Changed in 4.154.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* bump Rosalind to 0.7.22 and swift-protobuf to 1.35.1 ([#9701](https://github.com/tuist/tuist/pull/9701))
* fix build categorization for Xcode 26+ compilation cache ([#9689](https://github.com/tuist/tuist/pull/9689))
* bump XCLogParser to 0.2.46 and improve activity log error messages ([#9691](https://github.com/tuist/tuist/pull/9691))
### 📚 Documentation

* replace SourceDocs ProjectDescription reference with DocC ([#9637](https://github.com/tuist/tuist/pull/9637))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.154.1...4.154.4

## What's Changed in 4.154.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix buildable-folder header visibility and generation crash ([#9604](https://github.com/tuist/tuist/pull/9604))
* treat opaque directories as files in buildable folder resolution ([#9683](https://github.com/tuist/tuist/pull/9683))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.154.0...4.154.1

## What's Changed in 4.154.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload and display all test attachments from xcresult bundles ([#9630](https://github.com/tuist/tuist/pull/9630))
* make tuist inspect bundle available on Linux ([#9644](https://github.com/tuist/tuist/pull/9644))
* prune old binary cache entries on startup ([#9423](https://github.com/tuist/tuist/pull/9423))
* vendor XcodeGraph into tuist and reconcile dependency graphs ([#9616](https://github.com/tuist/tuist/pull/9616))
* add "Ask on Launch" executable option for scheme actions ([#9373](https://github.com/tuist/tuist/pull/9373))
* add warningsAsErrors generation option ([#9574](https://github.com/tuist/tuist/pull/9574))
### 🐛 Bug Fixes

* include transitive search paths through dynamic framework dependencies ([#9681](https://github.com/tuist/tuist/pull/9681))
* exclude directories from buildable folder resolved files ([#9678](https://github.com/tuist/tuist/pull/9678))
* cap concurrency to avoid file descriptor exhaustion ([#9677](https://github.com/tuist/tuist/pull/9677))
* Fix case-insensitive prioritize local packages over registry ([#9673](https://github.com/tuist/tuist/pull/9673))
* add xcassets and xcstrings to sources build phase for static targets ([#9666](https://github.com/tuist/tuist/pull/9666))
* update Command package to 0.14.0 ([#9657](https://github.com/tuist/tuist/pull/9657))
* make CacheLocalStorage.clean public ([#9647](https://github.com/tuist/tuist/pull/9647))
* bump FileSystem to 0.15.0 for setFileTimes support ([#9646](https://github.com/tuist/tuist/pull/9646))
* sort Set iterations in graph mappers for deterministic cache hashing ([#9629](https://github.com/tuist/tuist/pull/9629))
* limit concurrency of buildable folder resolution to avoid FD exhaustion ([#9626](https://github.com/tuist/tuist/pull/9626))
* add validation folder exists for BuildableFolder ([#9609](https://github.com/tuist/tuist/pull/9609))
* prune static xcframework deps from dynamic xcframeworks for hostless unit tests ([#9602](https://github.com/tuist/tuist/pull/9602))
* upload APK files directly instead of wrapping in zip ([#9581](https://github.com/tuist/tuist/pull/9581))
* populate explicitFolders for excluded directories in buildable folders ([#9578](https://github.com/tuist/tuist/pull/9578))
### 🚜 Refactor

* migrate acceptance tests to Swift Testing ([#9352](https://github.com/tuist/tuist/pull/9352))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.151.1...4.154.0

## What's Changed in 4.151.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* replace deprecated tuist build recommendation in previews ([#9562](https://github.com/tuist/tuist/pull/9562))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.151.0...4.151.1

## What's Changed in 4.151.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* expand glob patterns in buildable folder exclusions  ([#9552](https://github.com/tuist/tuist/pull/9552))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.150.1...4.151.0

## What's Changed in 4.150.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* expanding folder to input inner files when used as input in foreign build phase script ([#9556](https://github.com/tuist/tuist/pull/9556))
* place precompiled dependencies from SPM build directory in frameworks group ([#9555](https://github.com/tuist/tuist/pull/9555))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.150.0...4.150.1

## What's Changed in 4.150.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add platformFilters for buildable folder exceptions ([#9545](https://github.com/tuist/tuist/pull/9545))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.149.1...4.150.0

## What's Changed in 4.149.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Use latest Gradle plugin version in init and add takeaways ([#9543](https://github.com/tuist/tuist/pull/9543))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.149.0...4.149.1

## What's Changed in 4.149.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Android APK previews with cross-platform share and run ([#9509](https://github.com/tuist/tuist/pull/9509))
### 🐛 Bug Fixes

* Prioritize local packages over registry versions ([#9540](https://github.com/tuist/tuist/pull/9540))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.148.4...4.149.0

## What's Changed in 4.148.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* apply PackageSettings.baseSettings.defaultSettings to SPM targets ([#9301](https://github.com/tuist/tuist/pull/9301))
* restore SRCROOT path resolution for cached target settings ([#9531](https://github.com/tuist/tuist/pull/9531))
* respect custom server url ([#9524](https://github.com/tuist/tuist/pull/9524))
* include buildable folder resources in Target.containsResources ([#9290](https://github.com/tuist/tuist/pull/9290))
* use product name as module name for SPM wrapper targets ([#9370](https://github.com/tuist/tuist/pull/9370))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.148.1...4.148.4

## What's Changed in 4.148.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Android bundle support (AAB + APK) ([#9506](https://github.com/tuist/tuist/pull/9506))
* crash stack traces with formatted frames, attachments, and download URLs ([#9436](https://github.com/tuist/tuist/pull/9436))
### 🐛 Bug Fixes

* pass jsonThroughNoora to Noora on Linux ([#9516](https://github.com/tuist/tuist/pull/9516))
* bump xcode version release ([#9511](https://github.com/tuist/tuist/pull/9511))
* preserve JSON logger for non-Noora commands on Linux ([#9510](https://github.com/tuist/tuist/pull/9510))
* don't run foreign build script when target is served from binary cache ([#9501](https://github.com/tuist/tuist/pull/9501))
* sanitize + character in intra-package target dependency names ([#9437](https://github.com/tuist/tuist/pull/9437))
* warn when skip test targets don't intersect ([#9487](https://github.com/tuist/tuist/pull/9487))
* add Swift toolchain library search path for ObjC targets linking static Swift dependencies ([#9483](https://github.com/tuist/tuist/pull/9483))
* resolve static ObjC xcframework search paths without Package.swift ([#9440](https://github.com/tuist/tuist/pull/9440))
* enable HTTP logging and server warnings on Linux ([#9479](https://github.com/tuist/tuist/pull/9479))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.146.1...4.148.1

## What's Changed in 4.146.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix cache building unnecessary Catalyst scheme for external dependencies ([#9476](https://github.com/tuist/tuist/pull/9476))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.146.0...4.146.1

## What's Changed in 4.146.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add foreign build system dependencies ([#9400](https://github.com/tuist/tuist/pull/9400))
### 🐛 Bug Fixes

* restore TuistSimulator to macOS-only block in Package.swift ([#9468](https://github.com/tuist/tuist/pull/9468))
* increase inspect build activity log timeout and make it configurable ([#9465](https://github.com/tuist/tuist/pull/9465))
* fix CLI release (static linking, Musl imports, Bundle(for:)) ([#9459](https://github.com/tuist/tuist/pull/9459))
* use canImport(Musl) for Static Linux SDK compatibility ([#9457](https://github.com/tuist/tuist/pull/9457))
* remove OpenAPIURLSession from cross-platform targets for Linux static SDK ([#9456](https://github.com/tuist/tuist/pull/9456))
* restore cache run analytics on dashboard ([#9451](https://github.com/tuist/tuist/pull/9451))
* only cache dependency checkouts in Linux CI jobs ([#9447](https://github.com/tuist/tuist/pull/9447))
* add missing tree-shake after focus targets in automation mapper chain ([#9443](https://github.com/tuist/tuist/pull/9443))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.145.0...4.146.0

## What's Changed in 4.145.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* support build system selection in project create ([#9432](https://github.com/tuist/tuist/pull/9432))
### 🐛 Bug Fixes

* remove unused CacheBuiltArtifactsFetcher from CacheWarmCommandService ([#9434](https://github.com/tuist/tuist/pull/9434))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.4...4.145.0

## What's Changed in 4.144.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fall back to BUILD_DIR for derived data resolution ([#9429](https://github.com/tuist/tuist/pull/9429))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.3...4.144.4

## What's Changed in 4.144.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* embed cached static xcframeworks with resources transitively ([#9419](https://github.com/tuist/tuist/pull/9419))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.2...4.144.3

## What's Changed in 4.144.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* run StaticXCFrameworkModuleMapGraphMapper after cache replacement ([#9427](https://github.com/tuist/tuist/pull/9427))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.1...4.144.2

## What's Changed in 4.144.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix flaky tests caused by Matcher.register race and TOCTOU in CachedManifestLoader ([#9424](https://github.com/tuist/tuist/pull/9424))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.144.0...4.144.1

## What's Changed in 4.144.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Gradle project integration to tuist init ([#9422](https://github.com/tuist/tuist/pull/9422))
* add test case show and run commands with fix-flaky-tests skill ([#9379](https://github.com/tuist/tuist/pull/9379))
### 🐛 Bug Fixes

* resolve derived data path from DERIVED_DATA_DIR env in inspect commands ([#9396](https://github.com/tuist/tuist/pull/9396))
* use correct TUIST_URL key for env variable lookup in login command ([#9398](https://github.com/tuist/tuist/pull/9398))
* strip debug symbols (dSYM/DWARF) from cached XCFrameworks ([#9287](https://github.com/tuist/tuist/pull/9287))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.142.1...4.144.0

## What's Changed in 4.142.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* make server commands available on Linux ([#9377](https://github.com/tuist/tuist/pull/9377))
### 🐛 Bug Fixes

* don't retry non-retryable errors in module cache download ([#9394](https://github.com/tuist/tuist/pull/9394))
* restore asset symbol generation for external static frameworks ([#9382](https://github.com/tuist/tuist/pull/9382))
* use correct bundle accessor for external dynamic frameworks with resources ([#9381](https://github.com/tuist/tuist/pull/9381))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.141.1...4.142.1

## What's Changed in 4.141.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add debug logging to inspect build and test commands ([#9384](https://github.com/tuist/tuist/pull/9384))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.141.0...4.141.1

## What's Changed in 4.141.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add tuist.toml support ([#9368](https://github.com/tuist/tuist/pull/9368))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.140.2...4.141.0

## What's Changed in 4.140.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* skip macro targets in static dependency traversal ([#9337](https://github.com/tuist/tuist/pull/9337))
* add retry logic to OIDC authentication flow ([#9365](https://github.com/tuist/tuist/pull/9365))
* fix CI environment variable filtering ([#9369](https://github.com/tuist/tuist/pull/9369))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.140.1...4.140.2

## What's Changed in 4.140.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Linux support for auth and cache commands ([#9291](https://github.com/tuist/tuist/pull/9291))
### 🐛 Bug Fixes

* fix `tuist version` producing no output on Linux ([#9364](https://github.com/tuist/tuist/pull/9364))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.139.1...4.140.1

## What's Changed in 4.139.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't embed static precompiled xcframeworks ([#9356](https://github.com/tuist/tuist/pull/9356))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.139.0...4.139.1

## What's Changed in 4.139.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add configurable cache push policy ([#9348](https://github.com/tuist/tuist/pull/9348))
### 🐛 Bug Fixes

* deduplicate plugins with the same name in tuist edit ([#9354](https://github.com/tuist/tuist/pull/9354))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.138.1...4.139.0

## What's Changed in 4.138.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add extension bundle search paths for resource accessors ([#9344](https://github.com/tuist/tuist/pull/9344))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.138.0...4.138.1

## What's Changed in 4.138.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add custom metadata and tags to build runs ([#9310](https://github.com/tuist/tuist/pull/9310))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.137.1...4.138.0

## What's Changed in 4.137.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* guard log file creation for Noora ([#9324](https://github.com/tuist/tuist/pull/9324))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.137.0...4.137.1

## What's Changed in 4.137.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* record network requests to HAR files for debugging ([#9192](https://github.com/tuist/tuist/pull/9192))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.136.0...4.137.0

## What's Changed in 4.136.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add generations and cache runs API endpoints and CLI commands ([#9277](https://github.com/tuist/tuist/pull/9277))
### 🐛 Bug Fixes

* embed static frameworks with buildable-folder resources ([#9317](https://github.com/tuist/tuist/pull/9317))
* skip config loading for inspect commands ([#9315](https://github.com/tuist/tuist/pull/9315))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.135.2...4.136.0

## What's Changed in 4.135.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* avoid stale auth token cache during long uploads ([#9314](https://github.com/tuist/tuist/pull/9314))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.135.1...4.135.2

## What's Changed in 4.135.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generate registry config before resolving Swift packages ([#9311](https://github.com/tuist/tuist/pull/9311))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.135.0...4.135.1

## What's Changed in 4.135.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* auto-skip quarantined tests in tuist test ([#9306](https://github.com/tuist/tuist/pull/9306))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.134.1...4.135.0

## What's Changed in 4.134.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Bump cache version for static framework copy layout ([#9309](https://github.com/tuist/tuist/pull/9309))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.134.0...4.134.1

## What's Changed in 4.134.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add build list and build show commands ([#9272](https://github.com/tuist/tuist/pull/9272))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.4...4.134.0

## What's Changed in 4.133.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle Metal files in buildable folders for resource bundle generation ([#9298](https://github.com/tuist/tuist/pull/9298))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.3...4.133.4

## What's Changed in 4.133.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* propagate .bundle resource files from external static frameworks to host app ([#9294](https://github.com/tuist/tuist/pull/9294))
* search host bundle paths in ObjC resource bundle accessor ([#9295](https://github.com/tuist/tuist/pull/9295))
* harden log cleanup ([#9296](https://github.com/tuist/tuist/pull/9296))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.2...4.133.3

## What's Changed in 4.133.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* eagerly compute conditional targets to prevent thread starvation during generation ([#9292](https://github.com/tuist/tuist/pull/9292))
* only embed static XCFrameworks containing .framework bundles ([#9288](https://github.com/tuist/tuist/pull/9288))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.133.0...4.133.2

## What's Changed in 4.133.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add TUIST_CACHE_ENDPOINT environment variable override ([#9282](https://github.com/tuist/tuist/pull/9282))
* add debug logging to diagnose generation hangs ([#9284](https://github.com/tuist/tuist/pull/9284))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.132.1...4.133.0

## What's Changed in 4.132.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add authentication failure error for cache ([#9280](https://github.com/tuist/tuist/pull/9280))
* update FileSystem to fix intermittent crash on startup ([#9276](https://github.com/tuist/tuist/pull/9276))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.132.0...4.132.1

## What's Changed in 4.132.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add registryEnabled generation option ([#9258](https://github.com/tuist/tuist/pull/9258))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.131.2...4.132.0

## What's Changed in 4.131.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* revert swift-protobuf to GitHub URL to fix manifest issue ([#9267](https://github.com/tuist/tuist/pull/9267))
* set default cache concurrency limit to 100 ([#9235](https://github.com/tuist/tuist/pull/9235))
* support BITRISE_IDENTITY_TOKEN env var for Bitrise OIDC auth ([#9257](https://github.com/tuist/tuist/pull/9257))
* embed static XCFrameworks to support resources ([#9240](https://github.com/tuist/tuist/pull/9240))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.131.1...4.131.2

## What's Changed in 4.131.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* restore mapper order for selective testing and fix parseAsRoot ([#9234](https://github.com/tuist/tuist/pull/9234))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.131.0...4.131.1

## What's Changed in 4.131.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add test quarantine and automations settings ([#9175](https://github.com/tuist/tuist/pull/9175))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.130.3...4.131.0

## What's Changed in 4.130.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* ensure consistent mapper order between automation and cache pipelines ([#9228](https://github.com/tuist/tuist/pull/9228))
* use patched swift-openapi-urlsession to fix crash ([#9229](https://github.com/tuist/tuist/pull/9229))
* filter out dependencies with unsatisfied trait conditions ([#9219](https://github.com/tuist/tuist/pull/9219))
* fix bundle accessor for Obj-C external static frameworks with resources ([#9210](https://github.com/tuist/tuist/pull/9210))
### 📚 Documentation

* add intent layer nodes ([#9042](https://github.com/tuist/tuist/pull/9042))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.130.1...4.130.3

## What's Changed in 4.130.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* correct static xcframework paths when depending on cached targets ([#9203](https://github.com/tuist/tuist/pull/9203))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.130.0...4.130.1

## What's Changed in 4.130.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add debug logs to project generation ([#9199](https://github.com/tuist/tuist/pull/9199))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.129.2...4.130.0

## What's Changed in 4.129.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle race condition when creating logs directory



**Full Changelog**: https://github.com/tuist/tuist/compare/4.129.1...4.129.2

## What's Changed in 4.129.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* prevent race condition when creating logs directory ([#9191](https://github.com/tuist/tuist/pull/9191))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.129.0...4.129.1

## What's Changed in 4.129.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* enable local CAS when enableCaching is true and Tuist project is not configured ([#9157](https://github.com/tuist/tuist/pull/9157))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.128.3...4.129.0

## What's Changed in 4.128.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix acceptance tests ([#9150](https://github.com/tuist/tuist/pull/9150))
* External resources failing at runtime unable to find their associated bundle ([#9148](https://github.com/tuist/tuist/pull/9148))
* only emit a public import when public symbols are present ([#9129](https://github.com/tuist/tuist/pull/9129))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.128.0...4.128.3

## What's Changed in 4.128.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* make new module cache default ([#9094](https://github.com/tuist/tuist/pull/9094))
* add support for flaky tests detection ([#9098](https://github.com/tuist/tuist/pull/9098))
* implement remote cache cleaning ([#9124](https://github.com/tuist/tuist/pull/9124))
### 🐛 Bug Fixes

* Compilation errors when a static framework contains resources ([#9141](https://github.com/tuist/tuist/pull/9141))
* remove selective testing support for vanilla Xcode projects ([#9126](https://github.com/tuist/tuist/pull/9126))
* update inspect acceptance tests for new output format ([#9125](https://github.com/tuist/tuist/pull/9125))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.125.0...4.128.0

## What's Changed in 4.125.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add unified inspect dependencies command ([#8887](https://github.com/tuist/tuist/pull/8887))
* Add exceptTargetQueries to cache profiles ([#8761](https://github.com/tuist/tuist/pull/8761))
### 🐛 Bug Fixes

* Static framework bundles for tests and metal ([#9123](https://github.com/tuist/tuist/pull/9123))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.124.1...4.125.0

## What's Changed in 4.124.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* disable Swift debug serialization to prevent LLDB warnings ([#9116](https://github.com/tuist/tuist/pull/9116))
* update XcodeGraph to 1.30.10 to fix CLI resource bundles ([#9115](https://github.com/tuist/tuist/pull/9115))
* fix flaky DumpServiceIntegrationTests for package manifests ([#9113](https://github.com/tuist/tuist/pull/9113))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.124.0...4.124.1

## What's Changed in 4.124.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add support for SwiftPM package traits ([#8535](https://github.com/tuist/tuist/pull/8535))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.123.0...4.124.0

## What's Changed in 4.123.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* show deprecation notice for CLI < 4.56.1 ([#9110](https://github.com/tuist/tuist/pull/9110))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.122.2...4.123.0

## What's Changed in 4.122.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* restore static framework resources without regressions ([#9081](https://github.com/tuist/tuist/pull/9081))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.122.1...4.122.2

## What's Changed in 4.122.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add excluding parameter to FileElement glob ([#9087](https://github.com/tuist/tuist/pull/9087))
* Add tuist:synthesized tag to synthesized resource bundles ([#8983](https://github.com/tuist/tuist/pull/8983))
### 🐛 Bug Fixes

* preserve -enable-upcoming-feature flags in OTHER_SWIFT_FLAGS deduplication ([#9106](https://github.com/tuist/tuist/pull/9106))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.120.0...4.122.1

## What's Changed in 4.120.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* export hashed graph to file via env variable ([#9078](https://github.com/tuist/tuist/pull/9078))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.4...4.120.0

## What's Changed in 4.119.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* exclude __MACOSX folders for remote binary targets ([#9075](https://github.com/tuist/tuist/pull/9075))
* ensure consistent graph mapper order for cache hashing ([#9077](https://github.com/tuist/tuist/pull/9077))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.3...4.119.4

## What's Changed in 4.119.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* filter Catalyst destinations for external dependencies ([#9067](https://github.com/tuist/tuist/pull/9067))
* handle multi-byte UTF-8 characters in xcresult parsing ([#9061](https://github.com/tuist/tuist/pull/9061))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.1...4.119.3

## What's Changed in 4.119.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use generic destination for Mac Catalyst cache builds ([#9038](https://github.com/tuist/tuist/pull/9038))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.0...4.119.1

## What's Changed in 4.119.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* custom cache endpoints ([#8980](https://github.com/tuist/tuist/pull/8980))
### 🐛 Bug Fixes

* Generate TuistBundle if buildableFolders contains synthesized file ([#8998](https://github.com/tuist/tuist/pull/8998))
* Include Mac Catalyst slice when building XCFrameworks for cache ([#9028](https://github.com/tuist/tuist/pull/9028))
### 🚜 Refactor

* rename fixtures to examples and simplify fixture handling ([#8962](https://github.com/tuist/tuist/pull/8962))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.118.1...4.119.0

## What's Changed in 4.118.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* module cache ([#8931](https://github.com/tuist/tuist/pull/8931))
### 🐛 Bug Fixes

* fix selective testing when experimental cache enabled ([#8981](https://github.com/tuist/tuist/pull/8981))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.117.0...4.118.1

## What's Changed in 4.117.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* preview tracks ([#8939](https://github.com/tuist/tuist/pull/8939))
### 🐛 Bug Fixes

* handle cross-project dependencies in redundant import inspection ([#8862](https://github.com/tuist/tuist/pull/8862))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.116.2...4.117.0

## What's Changed in 4.116.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* require previews to have unique binary id and bundle version ([#8944](https://github.com/tuist/tuist/pull/8944))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.116.1...4.116.2

## What's Changed in 4.116.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* compute binary id as part of tuist share ([#8912](https://github.com/tuist/tuist/pull/8912))
### 🐛 Bug Fixes

* add support for the new mise bin path ([#8929](https://github.com/tuist/tuist/pull/8929))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.115.1...4.116.1

## What's Changed in 4.115.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* migrate Fixtures - Tuist initializer with .project ([#8886](https://github.com/tuist/tuist/pull/8886))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.115.0...4.115.1

## What's Changed in 4.115.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload command run analytics in the background ([#8883](https://github.com/tuist/tuist/pull/8883))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.114.0...4.115.0

## What's Changed in 4.114.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* OIDC support Bitrise and CircleCI ([#8878](https://github.com/tuist/tuist/pull/8878))
### 🐛 Bug Fixes

* parsing XCActivityLog on Xcode 26.2 and newer ([#8866](https://github.com/tuist/tuist/pull/8866))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.113.0...4.114.0

## What's Changed in 4.113.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* OIDC token support for GitHub Actions ([#8858](https://github.com/tuist/tuist/pull/8858))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.112.0...4.113.0

## What's Changed in 4.112.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* account tokens ([#8834](https://github.com/tuist/tuist/pull/8834))
* report module cache subhashes ([#8822](https://github.com/tuist/tuist/pull/8822))
### 🐛 Bug Fixes

* respect explicit cache profile none with target focus ([#8830](https://github.com/tuist/tuist/pull/8830))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.3...4.112.0

## What's Changed in 4.110.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle skipped tests due to a failed build ([#8808](https://github.com/tuist/tuist/pull/8808))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.2...4.110.3

## What's Changed in 4.110.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* false positive for a .uiTests implicit import of .app ([#8811](https://github.com/tuist/tuist/pull/8811))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.1...4.110.2

## What's Changed in 4.110.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* duration for test cases with custom label ([#8800](https://github.com/tuist/tuist/pull/8800))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.110.0...4.110.1

## What's Changed in 4.110.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* deprecate tuist build command ([#8401](https://github.com/tuist/tuist/pull/8401))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.109.2...4.110.0

## What's Changed in 4.109.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* relegate test result upload error to a warning ([#8790](https://github.com/tuist/tuist/pull/8790))
* Don't replace targeted external dependencies with cached binary ([#8731](https://github.com/tuist/tuist/pull/8731))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.109.0...4.109.2

## What's Changed in 4.109.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* link tests to builds ([#8771](https://github.com/tuist/tuist/pull/8771))
### 🐛 Bug Fixes

* Remove CLANG_CXX_LIBRARY essential build setting ([#8763](https://github.com/tuist/tuist/pull/8763))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.108.0...4.109.0

## What's Changed in 4.108.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track CI run id for test insights ([#8769](https://github.com/tuist/tuist/pull/8769))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.107.2...4.108.0

## What's Changed in 4.107.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove fullHandle requirement for tuist registry setup ([#8750](https://github.com/tuist/tuist/pull/8750))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.107.1...4.107.2

## What's Changed in 4.107.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add test insights ([#8347](https://github.com/tuist/tuist/pull/8347))
### 🐛 Bug Fixes

* duplicated XCFrameworks in embed phase ([#8736](https://github.com/tuist/tuist/pull/8736))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.106.3...4.107.1

## What's Changed in 4.106.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* pin swift-collections below 1.3.0 ([#8730](https://github.com/tuist/tuist/pull/8730))
* skip warning Swift flags when hashing ([#8728](https://github.com/tuist/tuist/pull/8728))
* prefer products with matching casing ([#8717](https://github.com/tuist/tuist/pull/8717))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.106.1...4.106.3

## What's Changed in 4.106.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* open registry ([#8708](https://github.com/tuist/tuist/pull/8708))
### 🐛 Bug Fixes

* external dependency case insensitive lookup ([#8714](https://github.com/tuist/tuist/pull/8714))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.105.1...4.106.1

## What's Changed in 4.105.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix false negative implicit import detection of transitive local dependencies ([#8665](https://github.com/tuist/tuist/pull/8665))
* refreshing token data race ([#8706](https://github.com/tuist/tuist/pull/8706))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.105.0...4.105.1

## What's Changed in 4.105.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* improve error message of tuist inspect implicit-imports ([#8604](https://github.com/tuist/tuist/pull/8604))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.7...4.105.0

## What's Changed in 4.104.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resolve token refresh data race in ServerAuthenticationController ([#8692](https://github.com/tuist/tuist/pull/8692))
* skip hashing Xcode version ([#8658](https://github.com/tuist/tuist/pull/8658))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.5...4.104.7

## What's Changed in 4.104.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add Emerge Tools SnapshottingTests to the list of targets that depend on XCTest ([#8653](https://github.com/tuist/tuist/pull/8653))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.4...4.104.5

## What's Changed in 4.104.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* respect xcframework status ([#8651](https://github.com/tuist/tuist/pull/8651))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.3...4.104.4

## What's Changed in 4.104.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* duplicate CAS outputs ([#8646](https://github.com/tuist/tuist/pull/8646))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.2...4.104.3

## What's Changed in 4.104.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* skip hashing lockfiles ([#8650](https://github.com/tuist/tuist/pull/8650))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.1...4.104.2

## What's Changed in 4.104.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* misreported Xcode cache analytics ([#8638](https://github.com/tuist/tuist/pull/8638))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.104.0...4.104.1

## What's Changed in 4.104.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* connect directly to the cache endpoint ([#8628](https://github.com/tuist/tuist/pull/8628))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.103.0...4.104.0

## What's Changed in 4.103.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track cas outputs type and cacheable task description ([#8609](https://github.com/tuist/tuist/pull/8609))
* track cacheable task description ([#8603](https://github.com/tuist/tuist/pull/8603))
### 🐛 Bug Fixes

* Add extended string delimiter to Strings value in PlistsTemplate ([#8607](https://github.com/tuist/tuist/pull/8607))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.101.0...4.103.0

## What's Changed in 4.101.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track cache key read/write latency ([#8598](https://github.com/tuist/tuist/pull/8598))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.100.0...4.101.0

## What's Changed in 4.100.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* cas output analytics ([#8584](https://github.com/tuist/tuist/pull/8584))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.99.2...4.100.0

## What's Changed in 4.99.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* ensure disableSandbox config is used when dumping package manifests ([#8475](https://github.com/tuist/tuist/pull/8475))
* support import kind declarations in inspect ([#8455](https://github.com/tuist/tuist/pull/8455))
* cache Config manifest to improve performance ([#8561](https://github.com/tuist/tuist/pull/8561))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.99.1...4.99.2

## What's Changed in 4.99.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix buildable folder resource placement for static targets ([#8548](https://github.com/tuist/tuist/pull/8548))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.99.0...4.99.1

## What's Changed in 4.99.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* optimize Xcode cache by compressing CAS artifacts ([#8565](https://github.com/tuist/tuist/pull/8565))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.98.0...4.99.0

## What's Changed in 4.98.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Optimize cache hit detection and add diagnostic remarks ([#8556](https://github.com/tuist/tuist/pull/8556))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.97.2...4.98.0

## What's Changed in 4.97.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* clean up warnings ([#7666](https://github.com/tuist/tuist/pull/7666))
* fix content hashing to use relative path when file does not exist ([#8557](https://github.com/tuist/tuist/pull/8557))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.97.0...4.97.2

## What's Changed in 4.97.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add cache profiles to fine tune cached binary replacement ([#8122](https://github.com/tuist/tuist/pull/8122))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.96.0...4.97.0

## What's Changed in 4.96.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for SwiftPM disableWarning setting ([#8549](https://github.com/tuist/tuist/pull/8549))
* improve upload error handling for cache artifacts ([#8553](https://github.com/tuist/tuist/pull/8553))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.95.1...4.96.0

## What's Changed in 4.95.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* downgrade duplicated product name linting from error to warning ([#8540](https://github.com/tuist/tuist/pull/8540))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.95.0...4.95.1

## What's Changed in 4.95.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for passing arguments to SwiftPM ([#8544](https://github.com/tuist/tuist/pull/8544))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.94.0...4.95.0

## What's Changed in 4.94.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add support for Swift Package Manager strictMemorySafety setting ([#8539](https://github.com/tuist/tuist/pull/8539))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.93.0...4.94.0

## What's Changed in 4.93.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* xcode cache analytics ([#8534](https://github.com/tuist/tuist/pull/8534))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.92.1...4.93.0

## What's Changed in 4.92.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Add support for Internal Imports By Default for Asset accessors ([#8241](https://github.com/tuist/tuist/pull/8241))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.92.0...4.92.1

## What's Changed in 4.92.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add cache daemon logs ([#8520](https://github.com/tuist/tuist/pull/8520))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.91.1...4.92.0

## What's Changed in 4.91.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Multiple targets with same hash ([#8533](https://github.com/tuist/tuist/pull/8533))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.91.0...4.91.1

## What's Changed in 4.91.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Default to no concurrency limit when doing cache uploads and downloads ([#8527](https://github.com/tuist/tuist/pull/8527))
### 🐛 Bug Fixes

* Bundle accessor not being generated for txt, js or json resources ([#8532](https://github.com/tuist/tuist/pull/8532))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.90.0...4.91.0

## What's Changed in 4.90.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add support for TUIST_-prefixed XDG environment variables ([#8508](https://github.com/tuist/tuist/pull/8508))
### 🐛 Bug Fixes

* improve error messages of cache daemon ([#8509](https://github.com/tuist/tuist/pull/8509))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.89.1...4.90.0

## What's Changed in 4.89.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use TUIST_CONFIG_TOKEN when launching the cache daemon ([#8506](https://github.com/tuist/tuist/pull/8506))
* ignore macros in inspect redundant dependencies ([#8457](https://github.com/tuist/tuist/pull/8457))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.89.0...4.89.1

## What's Changed in 4.89.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Only use binaries for external dependencies when no focus target is passed to `tuist generate` ([#8478](https://github.com/tuist/tuist/pull/8478))
* Add --skip-unit-tests parameter to tuist test command ([#8291](https://github.com/tuist/tuist/pull/8291))
### 🐛 Bug Fixes

* ignore unit test host app in inspect redundant dependencies ([#8456](https://github.com/tuist/tuist/pull/8456))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.88.0...4.89.0

## What's Changed in 4.88.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* don't restrict which kind of token is used based on the environment ([#8464](https://github.com/tuist/tuist/pull/8464))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.87.0...4.88.0

## What's Changed in 4.87.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* tuist setup cache command ([#8450](https://github.com/tuist/tuist/pull/8450))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.4...4.87.0

## What's Changed in 4.86.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add individual target sub-hashes for debugging ([#8460](https://github.com/tuist/tuist/pull/8460))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.3...4.86.4

## What's Changed in 4.86.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Add support for `.xcdatamodel` opaque directories ([#8445](https://github.com/tuist/tuist/pull/8445))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.2...4.86.3

## What's Changed in 4.86.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't throw file not found when hashing generated source files ([#8449](https://github.com/tuist/tuist/pull/8449))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.1...4.86.2

## What's Changed in 4.86.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* mysteriously vanished binaries ([#8447](https://github.com/tuist/tuist/pull/8447))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.86.0...4.86.1

## What's Changed in 4.86.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Xcode cache server ([#8420](https://github.com/tuist/tuist/pull/8420))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.85.2...4.86.0

## What's Changed in 4.85.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* extend inspect build to 5 seconds ([#8446](https://github.com/tuist/tuist/pull/8446))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.85.1...4.85.2

## What's Changed in 4.85.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Generated projects with binaries not replacing some targets with macros as transitive dependencies ([#8444](https://github.com/tuist/tuist/pull/8444))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.85.0...4.85.1

## What's Changed in 4.85.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Optimize resource interface synthesis through parallelization ([#8436](https://github.com/tuist/tuist/pull/8436))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.3...4.85.0

## What's Changed in 4.84.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't report clean action ([#8439](https://github.com/tuist/tuist/pull/8439))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.2...4.84.3

## What's Changed in 4.84.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Handle target action input and output file paths that contain variables ([#8432](https://github.com/tuist/tuist/pull/8432))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.1...4.84.2

## What's Changed in 4.84.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* align 'tuist hash cache' to use same generator as cache warming ([#8427](https://github.com/tuist/tuist/pull/8427))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.84.0...4.84.1

## What's Changed in 4.84.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Improve remote cache error handling ([#8413](https://github.com/tuist/tuist/pull/8413))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.83.0...4.84.0

## What's Changed in 4.83.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Support the `defaultIsolation` setting when integrating packages using native Xcode project targets ([#8372](https://github.com/tuist/tuist/pull/8372))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.82.3...4.83.0

## What's Changed in 4.82.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* clean up downloaded binary artifacts from temporary directory ([#8402](https://github.com/tuist/tuist/pull/8402))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.82.2...4.82.3

## What's Changed in 4.82.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't convert script input and output file list paths relative to manifest paths or with build variables to absolute ([#8397](https://github.com/tuist/tuist/pull/8397))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.82.1...4.82.2

## What's Changed in 4.82.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add bundle type ([#8363](https://github.com/tuist/tuist/pull/8363))
### 🐛 Bug Fixes

* Ensure buildableFolder resources are handled with project-defined resourceSynthesizers. ([#8369](https://github.com/tuist/tuist/pull/8369))
* align with the latest Tuist API ([#8393](https://github.com/tuist/tuist/pull/8393))
* path to the PackageDescription in projects generated by tuist edit ([#8357](https://github.com/tuist/tuist/pull/8357))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.81.0...4.82.1

## What's Changed in 4.81.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Make implicit import detection work with buildable folders ([#8358](https://github.com/tuist/tuist/pull/8358))
* add CI run reference to build runs ([#8356](https://github.com/tuist/tuist/pull/8356))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.80.0...4.81.0

## What's Changed in 4.80.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Report server-side payment-required responses as warnings ([#8338](https://github.com/tuist/tuist/pull/8338))
* add configuration to build insights ([#8330](https://github.com/tuist/tuist/pull/8330))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.7...4.80.0

## What's Changed in 4.79.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Only validate cache signatures on successful responses ([#8315](https://github.com/tuist/tuist/pull/8315))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.6...4.79.7

## What's Changed in 4.79.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix cache warming when external targets are excluded by platform conditions ([#8308](https://github.com/tuist/tuist/pull/8308))
* don't mark inspected build as failed when it has warnings only ([#8276](https://github.com/tuist/tuist/pull/8276))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.4...4.79.6

## What's Changed in 4.79.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Add support for headers in buildable folders ([#8298](https://github.com/tuist/tuist/pull/8298))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.3...4.79.4

## What's Changed in 4.79.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix synthesized bundle interfaces not generated for `.xcassets` in buildable folders ([#8292](https://github.com/tuist/tuist/pull/8292))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.2...4.79.3

## What's Changed in 4.79.2<!-- RELEASE NOTES START -->

### 🧪 Testing

* fix acceptance tests ([#8288](https://github.com/tuist/tuist/pull/8288))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.1...4.79.2

## What's Changed in 4.79.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Make `excluded` optional in buildable folder exceptions ([#8293](https://github.com/tuist/tuist/pull/8293))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.79.0...4.79.1

## What's Changed in 4.79.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Support exclusion of files and configuration of compiler flags for files in buildable folders ([#8254](https://github.com/tuist/tuist/pull/8254))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.4...4.79.0

## What's Changed in 4.78.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Downgrade ProjectDescription Swift version to 6.1 ([#8283](https://github.com/tuist/tuist/pull/8283))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.3...4.78.4

## What's Changed in 4.78.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* show Products file group in Xcode navigator ([#8267](https://github.com/tuist/tuist/pull/8267))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.2...4.78.3

## What's Changed in 4.78.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* adjust NIOFileSystem references ([#8273](https://github.com/tuist/tuist/pull/8273))
* handle warnings from the underlying assetutil info when inspecting bundles ([#8268](https://github.com/tuist/tuist/pull/8268))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.1...4.78.2

## What's Changed in 4.78.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add default.metallib in static framework ([#8207](https://github.com/tuist/tuist/pull/8207))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.0...4.78.1

## What's Changed in 4.78.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* change sandbox to be opt-in ([#8244](https://github.com/tuist/tuist/pull/8244))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.77.0...4.78.0

## What's Changed in 4.77.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Increase the security of the cache surface ([#8220](https://github.com/tuist/tuist/pull/8220))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.76.1...4.77.0

## What's Changed in 4.76.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Invalid generated projects when projects are generated with binaries keeping sources and targets ([#8227](https://github.com/tuist/tuist/pull/8227))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.76.0...4.76.1

## What's Changed in 4.76.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add SE-0162 support for custom SPM target layouts ([#8191](https://github.com/tuist/tuist/pull/8191))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.75.0...4.76.0

## What's Changed in 4.75.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add unordered xcodebuild command support ([#8170](https://github.com/tuist/tuist/pull/8170))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.74.1...4.75.0

## What's Changed in 4.74.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Increase the refresh token timeout period



**Full Changelog**: https://github.com/tuist/tuist/compare/4.74.0...4.74.1

## What's Changed in 4.74.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Verbose-log the concurrency limit used by the cache for network connections ([#8217](https://github.com/tuist/tuist/pull/8217))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.73.0...4.74.0

## What's Changed in 4.73.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for configuring the cache request concurrency limit ([#8203](https://github.com/tuist/tuist/pull/8203))
### 🐛 Bug Fixes

* tuist cache failing due to the new BuildOperationMetrics attachment type ([#8201](https://github.com/tuist/tuist/pull/8201))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.72.0...4.73.0

## What's Changed in 4.72.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Remove user credentials when the token sent on refresh is invalid ([#8173](https://github.com/tuist/tuist/pull/8173))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.71.0...4.72.0

## What's Changed in 4.71.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* generate tests using Swift Testing instead of XCTest ([#8184](https://github.com/tuist/tuist/pull/8184))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.70.0...4.71.0

## What's Changed in 4.70.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Don't focus when keeping the sources for targets replaced by binaries ([#8180](https://github.com/tuist/tuist/pull/8180))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.69.0...4.70.0

## What's Changed in 4.69.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* update Swift package resolution to use -scmProvider system



**Full Changelog**: https://github.com/tuist/tuist/compare/4.68.0...4.69.0

## What's Changed in 4.68.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add additionalPackageResolutionArguments for xcodebuild ([#8099](https://github.com/tuist/tuist/pull/8099))
### 🐛 Bug Fixes

* not generate bundle accessors in when buildable folders don't resolve to any resources ([#8158](https://github.com/tuist/tuist/pull/8158))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.67.2...4.68.0

## What's Changed in 4.67.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generate bundle accessor when a module has only buildable folders ([#8156](https://github.com/tuist/tuist/pull/8156))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.67.1...4.67.2

## What's Changed in 4.67.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* default to caching the manifests ([#8116](https://github.com/tuist/tuist/pull/8116))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.67.0...4.67.1

## What's Changed in 4.67.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* optimize dependency conditions calculation ([#8146](https://github.com/tuist/tuist/pull/8146))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.66.1...4.67.0

## What's Changed in 4.66.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* XCFramework signature ([#7999](https://github.com/tuist/tuist/pull/7999))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.66.0...4.66.1

## What's Changed in 4.66.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* skip remote cache downloads on failure ([#8135](https://github.com/tuist/tuist/pull/8135))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.7...4.66.0

## What's Changed in 4.65.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generate bundle accessor for modules with metal files ([#8125](https://github.com/tuist/tuist/pull/8125))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.6...4.65.7

## What's Changed in 4.65.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* missing bundle accessor when the target uses buildable folders ([#8092](https://github.com/tuist/tuist/pull/8092))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.5...4.65.6

## What's Changed in 4.65.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* unable to create account tokens to access the registry ([#8115](https://github.com/tuist/tuist/pull/8115))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.4...4.65.5

## What's Changed in 4.65.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* CocoaPods unable to install dependencies due to project's `objectVersion` ([#8051](https://github.com/tuist/tuist/pull/8051))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.3...4.65.4

## What's Changed in 4.65.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* arch incompatibilities when using the cache ([#8096](https://github.com/tuist/tuist/pull/8096))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.2...4.65.3

## What's Changed in 4.65.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* caching issues due to incompatible architectures ([#8094](https://github.com/tuist/tuist/pull/8094))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.1...4.65.2

## What's Changed in 4.65.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* revert caching only the default architecture ([#8048](https://github.com/tuist/tuist/pull/8048))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.65.0...4.65.1

## What's Changed in 4.65.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add filePath and customWorkingDirectory support to RunAction ([#8071](https://github.com/tuist/tuist/pull/8071))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.64.2...4.65.0

## What's Changed in 4.64.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use XcodeGraph for XcodeKit SDK support ([#8029](https://github.com/tuist/tuist/pull/8029))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.64.1...4.64.2

## What's Changed in 4.64.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* relative path for local package ([#8059](https://github.com/tuist/tuist/pull/8059))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.64.0...4.64.1

## What's Changed in 4.64.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* improve passthrough argument documentation with usage examples ([#8047](https://github.com/tuist/tuist/pull/8047))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.3...4.64.0

## What's Changed in 4.63.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* include pagination data when listing the bundles as a json ([#8041](https://github.com/tuist/tuist/pull/8041))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.2...4.63.3

## What's Changed in 4.63.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* `bundle show` failing due to wrong data passed by the cli ([#8037](https://github.com/tuist/tuist/pull/8037))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.1...4.63.2

## What's Changed in 4.63.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* `tuist run` fails to run a scheme even though it has runnable targets ([#7989](https://github.com/tuist/tuist/pull/7989))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.0...4.63.1

## What's Changed in 4.63.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add commands to list and read bundles ([#7893](https://github.com/tuist/tuist/pull/7893))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.62.0...4.63.0

## What's Changed in 4.62.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for buildable folders ([#7984](https://github.com/tuist/tuist/pull/7984))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.61.2...4.62.0

## What's Changed in 4.61.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* platform conditions not applied for binary dependencies in external packages ([#7991](https://github.com/tuist/tuist/pull/7991))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.61.1...4.61.2

## What's Changed in 4.61.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generation regression ([#8011](https://github.com/tuist/tuist/pull/8011))
* fetching devices when running previews ([#8010](https://github.com/tuist/tuist/pull/8010))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.61.0...4.61.1

## What's Changed in 4.61.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for keeping the sources of the targets replaced by binaries ([#8000](https://github.com/tuist/tuist/pull/8000))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.60.0...4.61.0

## What's Changed in 4.60.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* support hashing transitive `.xcconfig` files ([#7961](https://github.com/tuist/tuist/pull/7961))
* add support for XcodeKit SDK ([#7993](https://github.com/tuist/tuist/pull/7993))
### 🐛 Bug Fixes

* use Xcode default for which architectures are built ([#8007](https://github.com/tuist/tuist/pull/8007))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.59.2...4.60.0

## What's Changed in 4.59.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* unexpected behaviours when renaming resources in cached targets ([#7988](https://github.com/tuist/tuist/pull/7988))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.59.1...4.59.2

## What's Changed in 4.59.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* prevent metal files from being processed as resources. ([#7976](https://github.com/tuist/tuist/pull/7976))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.59.0...4.59.1

## What's Changed in 4.59.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* cache binaries by default for arm64 only, add --architectures option to specify architectures ([#7977](https://github.com/tuist/tuist/pull/7977))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.58.1...4.59.0

## What's Changed in 4.58.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* include project settings hash in target hash ([#7962](https://github.com/tuist/tuist/pull/7962))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.58.0...4.58.1

## What's Changed in 4.58.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* print the full sandbox command when a system command fails ([#7972](https://github.com/tuist/tuist/pull/7972))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.57.1...4.58.0

## What's Changed in 4.57.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* treat the new .icon asset as an opaque directory ([#7965](https://github.com/tuist/tuist/pull/7965))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.57.0...4.57.1

## What's Changed in 4.57.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for running macOS app via `tuist run` ([#7956](https://github.com/tuist/tuist/pull/7956))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.56.1...4.57.0

## What's Changed in 4.56.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* auto-generated *-Workspace scheme not getting generated ([#7932](https://github.com/tuist/tuist/pull/7932))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.56.0...4.56.1

## What's Changed in 4.56.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Ignore internal server errors when interating with the cache ([#7924](https://github.com/tuist/tuist/pull/7924))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.9...4.56.0

## What's Changed in 4.55.9<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* do not link cached frameworks with linking status .none ([#7918](https://github.com/tuist/tuist/pull/7918))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.8...4.55.9

## What's Changed in 4.55.8<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* 'tuist version' shows the optional string



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.7...4.55.8

## What's Changed in 4.55.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix cli not launching because ProjectAutomation's dynamic framework can't be found
* token refresh race condition ([#7907](https://github.com/tuist/tuist/pull/7907))



**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.6...4.55.7

<!-- generated by git-cliff -->
