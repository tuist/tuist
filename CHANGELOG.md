# Changelog

Please, check out guidelines: https://keepachangelog.com/en/1.0.0/

## Next

### Fixed

- Missing schemes in generated project for editing [#1467](https://github.com/tuist/tuist/pull/1467) by [@fortmarek](https://github.com/fortmarek)
- `tuist build` cleaning even if the `--clean` argument is not passed [#1458](https://github.com/tuist/tuist/pull/1458) by [@pepibumur](https://github.com/pepibumur).

### Changed

- Use `LD_RUNPATH_SEARCH_PATHS` instead of embedding dynamic frameworks for unit test targets [#1463](https://github.com/tuist/tuist/pull/1463) by [@fortmarek](https://github.com/fortmarek)

## 1.11.0 - Volare

### Added

- Signing feature [#1186](https://github.com/tuist/tuist/pull/1186) by [@fortmarek](https://github.com/fortmarek)
- Add support for watch architectures [#1417](https://github.com/tuist/tuist/pull/1417) by [@davidbrunow](https://github.com/davidbrunow)
- Add method to XcodeBuildController to show the build settings of a project [#1422](https://github.com/tuist/tuist/pull/1422) by [@pepibumur](https://github.com/pepibumur)
- Support for passing the configuration to the `tuist build` command [#1422](https://github.com/tuist/tuist/pull/1442) by [@pepibumur](https://github.com/pepibumur)

### Fixed

- Fix `tuist build` building a wrong workspace [#1427](https://github.com/tuist/tuist/pull/1427) by [@fortmarek](https://github.com/fortmarek)
- `tuist edit` always creates a project in a new temp dir [#1424](https://github.com/tuist/tuist/pull/1424) by [@fortmarek](https://github.com/fortmarek)
- Fix `tuist init` and `tuist scaffold` with new ArgumentParser version [#1425](https://github.com/tuist/tuist/pull/1425) by [@fortmarek](https://github.com/fortmarek)
- `--clean` argument ot the build command [#1421](https://github.com/tuist/tuist/pull/1421) by [@pepibumur](https://github.com/pepibumur)

### Changed

- Extend `CloudInsightsGraphMapper` to support mapping the value graph [#1380](https://github.com/tuist/tuist/pull/1380) by [@pepibumur](https://github.com/pepibumur)

## 1.10.0 - Alma

### Added

- Build command [#1412](https://github.com/tuist/tuist/pull/1412) by [@pepibumur](https://github.com/pepibumur)
- Adds a possibility to set Options > Application Language and Application Region for a `TestAction` on a scheme [#1055](https://github.com/tuist/tuist/pull/1055) by [@paciej00](https://github.com/paciej00)

### Changed

- Removed filtering of the environment variables exposed to shell commands [#1416](https://github.com/tuist/tuist/pull/1416) by [@kalkwarf](https://github.com/kalkwarf)
- Upgrade XcodeProj to 7.11.0 [#1398](https://github.com/tuist/tuist/pull/1398) by [@pepibumur](https://github.com/pepibumur)
- Move the auto-generation of schemes to a model mapper [#1357](https://github.com/tuist/tuist/pull/1357) by [@pepibumur](https://github.com/pepibumur)

## 1.9.0 - Speedy Gonzales

### Added

- Support for enabling the cloud insights feature [#1335](https://github.com/tuist/tuist/pull/1335) by [@pepibumur](https://github.com/pepibumur)
- Value graph model [#1336](https://github.com/tuist/tuist/pull/1336) by [@pepibumur](https://github.com/pepibumur)
- **Breaking** Support for setting diagnostics options to the test and run actions [#1382](https://github.com/tuist/tuist/pull/1382) by [@pepibumur](https://github.com/pepibumur)

### Fixed

- Storing the cloud credentials failed because the Keychain syncing was enabled [#1355](https://github.com/tuist/tuist/pull/1355) by [@pepibumur](https://github.com/pepibumur).
- `tuist edit` doesn't wait while the user edits the project in Xcode [#1650](https://github.com/Shopify/react-native/pull/1650) by [@pepibumur](https://github.com/pepibumur).
- Remove CFBundleExecutable from iOS resource bundle target plists [#1361](https://github.com/tuist/tuist/pull/1361) by [@kwridan](https://github.com/kwridan).

### Changed

- **Breaking** Inherit defaultSettings from the project when the target's defaultSettings is nil [#1138](https://github.com/tuist/tuist/pull/1338) by [@pepibumur](https://github.com/pepibumur)
- Manifests are now cached to speed up generation times _(opt out via setting `TUIST_CACHE_MANIFESTS=0`)_ [1341](https://github.com/tuist/tuist/pull/1341) by [@kwridan](https://github.com/kwridan)

## 1.8.0

### Changed

- Read the Swift version from the environment [#1317](https://github.com/tuist/tuist/pull/1317) by [@pepibumur](https://github.com/pepibumur)

### Added

- Support for localized sources(e.g., .intentdefinition) [#1269](https://github.com/tuist/tuist/pull/1269) by [@Rag0n](https://github.com/Rag0n)

### Removed

- Don't set the main and launch storyboard when using the default `InfoPlist` [#1289](https://github.com/tuist/tuist/pull/1289) by [@pepibumur](https://github.com/pepibumur)

### Fixed

- Fix example in documentation for `scaffold` [#1273](https://github.com/tuist/tuist/pull/1273) by [@fortmarek](https://github.com/fortmarek)
- Fix help commands (argument parser regression) [#1250](https://github.com/tuist/tuist/pull/1250) by [@fortmarek](https://github.com/fortmarek)

## 1.7.1

### Fixed

- Critical bug caused by a missing `SwiftToolsSupport` dynamic library by [@pepibumur](https://github.com/pepibumur).

## 1.7.0

### Changed

- Point swift tools support repo instead of SPM [#1230](https://github.com/tuist/tuist/pull/1230) by [@fortmarek](https://github.com/fortmarek)
- Migrate to new argument parser [#1154](https://github.com/tuist/tuist/pull/1154) by [@fortmarek](https://github.com/fortmarek)
- Only warn about copying Info.plist when it's the target's Info.plist [#1203](https://github.com/tuist/tuist/pull/1203) by @sgrgrsn
- `tuist edit` now edits all project manifest [#1231](https://github.com/tuist/tuist/pull/1231/) by [@julianalonso](https://github.com/julianalonso)

### Added

- Support for setting the project id when configuring the cloud server [#1247](https://github.com/tuist/tuist/pull/1247) by [@pepibumur](https://github.com/pepibumur).
- Support for returning `SideEffectDescriptor`s from the graph mappers [#1201](https://github.com/tuist/tuist/pull/1201) by [@pepibumur](https://github.com/pepibumur).
- SwiftUI template [#1180](https://github.com/tuist/tuist/pull/1180) by [@fortmarek](https://github.com/fortmarek)
- `SettingsDictionary` is a typealias for `[String: SettingValue]`. [#1229](https://github.com/tuist/tuist/pull/1229) by [@natanrolnik](https://github.com/natanrolnik). Many useful extension methods were added to `SettingsDictionary`, allowing settings to be defined this way:

```swift
let baseSettings = SettingsDictionary()
    .appleGenericVersioningSystem()
    .automaticCodeSigning(devTeam: "TeamID")
    .bitcodeEnabled(true)
    .swiftVersion("5.2")
    .swiftCompilationMode(.wholemodule)
    .versionInfo("500", prefix: "MyPrefix")
```

### Removed

- **Breaking:** Deprecated methods from `ProjectDescription.Settings` [#1202](https://github.com/tuist/tuist/pull/1202) by by [@pepibumur](https://github.com/pepibumur).

## 1.6.0

### Fixed

- Don't try to delete a file if it doesn't exist [#1177](https://github.com/tuist/tuist/pull/1177) by [@pepibumur](https://github.com/pepibumur)

### Changed

- Bump XcodeProj to 7.10.0 [#1182](https://github.com/tuist/tuist/pull/1182) by [@pepibumur](https://github.com/pepibumur)

### Added

- Encrypt/decrypt command [#1127](https://github.com/tuist/tuist/pull/1127) by [@fortmarek](https://github.com/fortmarek)
- A link to the example app in the uFeatures documentation [#1176](https://github.com/tuist/tuist/pull/1176) by [@pepibumur](https://github.com/pepibumur).
- Add ProjectGeneratorGraphMapping protocol and use it from ProjectGenerator [#1178](https://github.com/tuist/tuist/pull/1178) by [@pepibumur](https://github.com/pepibumur)
- `CloudSessionController` component to authenticate users [#1174](https://github.com/tuist/tuist/pull/1174) by [@pepibumur](https://github.com/pepibumur).
- Minor improvements [#1179](https://github.com/tuist/tuist/pull/1179) by [@pepibumur](https://github.com/pepibumur)
- Configuring manifests through environment variables [#1183](https://github.com/tuist/tuist/pull/1183) by [@pepibumur](https://github.com/pepibumur).

## 1.5.4

### Fixed

- Tuist not working with Xcode < 11.4 by [@pepibumur](https://github.com/pepibumur).

## 1.5.3

### Added

- `Derived` to `.gitignore` when running `tuist init` [#1171](https://github.com/tuist/tuist/pull/1171) by [@fortmarek](https://github.com/fortmarek)

### Fixed

- Prevent `Multiple commands produce XXXXX` error produced by multiple test targets using “Embed Precompiled Frameworks” script [#1118](https://github.com/tuist/tuist/pull/1118) by @paulsamuels
- Add possibility to skip generation of default schemes [#1130](https://github.com/tuist/tuist/pull/1130) by @olejnjak
- Errors during the manifest parsing are not printed [#1125](https://github.com/tuist/tuist/pull/1125) by [@pepibumur](https://github.com/pepibumur).
- Warnings because test files are missing in the project scaffolded using the default `framework` template [#1172](https://github.com/tuist/tuist/pull/1172) by [@pepibumur](https://github.com/pepibumur).

## 1.5.2

### Fixed

- Projects generated with the `framework` template generated by the `init` command dont' compile [#1156](https://github.com/tuist/tuist/pull/1156) by [@pepibumur](https://github.com/pepibumur).

### Changed

- Generate only files with `.stencil` extension [#1153](https://github.com/tuist/tuist/pull/1153) by [@fortmarek](https://github.com/fortmarek)

### Added

- Support for Xcode 11.4 [#1152](https://github.com/tuist/tuist/pull/1152) by [@pepibumur](https://github.com/pepibumur).
- `SWIFT_VERSION` is set to 5.2 automatically if it's not set [#1152](https://github.com/tuist/tuist/pull/1152) by [@pepibumur](https://github.com/pepibumur).

## 1.5.1

### Fixed

- Update config name in the default template [#1150](https://github.com/tuist/tuist/pull/1150) by [@pepibumur](https://github.com/pepibumur)
- Fix example framework template not being generated [#1149](https://github.com/tuist/tuist/pull/1149) by [@fortmarek](https://github.com/fortmarek)

## 1.5.0

### Added

- Scaffold init [#1129](https://github.com/tuist/tuist/pull/1129) by [@fortmarek](https://github.com/fortmarek)
- Scaffold generate [#1126](https://github.com/tuist/tuist/pull/1126) by [@fortmarek](https://github.com/fortmarek)
- Scaffold load [#1092](https://github.com/tuist/tuist/pull/1092) by [@fortmarek](https://github.com/fortmarek)
- Add Mint up [#1131](https://github.com/tuist/tuist/pull/1131) [@mollyIV](https://github.com/mollyIV).

### Fixed

- Remove redundant SDK paths from `FRAMEWORK_SEARCH_PATHS` [#1145](https://github.com/tuist/tuist/pull/1145) by [@kwridan](https://github.com/kwridan)

### Removed

- `Graphing` protocol [#1128](https://github.com/tuist/tuist/pull/1128) by [@pepibumur](https://github.com/pepibumur)

### Changed

- Optimize `TargetNode`'s set operations [#1095](https://github.com/tuist/tuist/pull/1095) by [@kwridan](https://github.com/kwridan)
- Optimize `BuildPhaseGenerator`'s method of detecting assets and localized files [#1094](https://github.com/tuist/tuist/pull/1094) by [@kwridan](https://github.com/kwridan)
- Concurrent project generation [#1096](https://github.com/tuist/tuist/pull/1096) by [@kwridan](https://github.com/kwridan)

## 1.4.0

### Fixed

- Fix `TargetAction` when `PROJECT_DIR` includes a space [#1037](https://github.com/tuist/tuist/pull/1037) by [@fortmarek](https://github.com/fortmarek)
- Fix code example compilation issues in "Project description helpers" documentation [#1081](https://github.com/tuist/tuist/pull/1081) by @chojnac

### Added

- `scaffold` command to generate user-defined templates [#1126](https://github.com/tuist/tuist/pull/1126) by [@fortmarek](https://github.com/fortmarek)
- New `ProjectDescription` models for `scaffold` command [#1082](https://github.com/tuist/tuist/pull/1082) by [@fortmarek](https://github.com/fortmarek)
- Allow specifying Project Organization name via new `organizationName` parameter to `Project` initializer or via `Config` new GenerationOption. [#1062](https://github.com/tuist/tuist/pull/1062) by @c0diq
- `tuist lint` command [#1043](https://github.com/tuist/tuist/pull/1043) by [@pepibumur](https://github.com/pepibumur).
- Add `--verbose` [#1027](https://github.com/tuist/tuist/pull/1027) by [@ollieatkinson](https://github.com/ollieatkinson).
- `TuistInsights` target [#1084](https://github.com/tuist/tuist/pull/1084) by [@pepibumur](https://github.com/pepibumur).
- Add `cloudURL` attribute to `Config` [#1085](https://github.com/tuist/tuist/pull/1085) by [@pepibumur](https://github.com/pepibumur).

### Changed

- Rename `TuistConfig.swift` to `Config.swift` [#1083](https://github.com/tuist/tuist/pull/1083) by [@pepibumur](https://github.com/pepibumur).
- Generator update - leveraging intermediate descriptors [#1007](https://github.com/tuist/tuist/pull/1007) by [@kwridan](https://github.com/kwridan)
  - Note: `TuistGenerator.Generator` is now deprecated and will be removed in a future version of Tuist.

## 1.3.0

### Added

- When using `tuist edit` it's possible to run `tuist generate` from Xcode by simply running the target [#958](https://github.com/tuist/tuist/pull/958) by [@vytis](https://github.com/vytis)
- Add FAQ section [@mollyIV](https://github.com/mollyIV).
- Add benchmarking helper tool [#957](https://github.com/tuist/tuist/pull/957) by [@kwridan](https://github.com/kwridan).
- Add metal as a valid source extension [#1023](https://github.com/tuist/tuist/pull/1023) by [@natanrolnik](https://github.com/natanrolnik)
- `XcodeBuildController` utility to `TuistAutomation` [#1019](https://github.com/tuist/tuist/pull/1019) by [@pepibumur](https://github.com/pepibumur).
- Add metal as a valid source extension [#1023](https://github.com/tuist/tuist/pull/1023) by [@natanrolnik](https://github.com/natanrolnik)

### Fixed

- Fix static products false positive lint warning by [#981](https://github.com/tuist/tuist/pull/981) [@kwridan](https://github.com/kwridan).
- TargetAction path without ./ prefix [#997](https://github.com/tuist/tuist/pull/997) by [@fortmarek](https://github.com/fortmarek)
- Preserve xcuserdata when re-generating projects [#1006](https://github.com/tuist/tuist/pull/1006) by [@kwridan](https://github.com/kwridan)
- Stable sort order for bcsymbolmap paths by @paulsamuels

### Changed

- Update XcodeProj to 7.8.0 [#](https://github.com/tuist/tuist/pull/)create?base=tuist%3Amaster&head=tuist%3Atarget-attributes by [@pepibumur](https://github.com/pepibumur).
- Path sorting speed gains [#980](https://github.com/tuist/tuist/pull/980) by [@adamkhazi](https://github.com/adamkhazi).
- Added support for HTTP_PROXY settings from shell environment. [#1015](https://github.com/tuist/tuist/pull/1015) by @aegzorz
- Added "Base" to known regions. [#1021](https://github.com/tuist/tuist/pull/1021) by @aegzorz
- Pull bundles from Google Cloud Storage [#1028](https://github.com/tuist/tuist/pull/1028) by [@pepibumur](https://github.com/pepibumur).

## 1.2.0

### Added

- Best practices page to the documentation [#843](https://github.com/tuist/tuist/pull/843) by [@pepibumur](https://github.com/pepibumur).
- Fail CI if there are broken links on the website [#917](https://github.com/tuist/tuist/pull/917) by [@pepibumur](https://github.com/pepibumur).
- Excluding multiple files from a target [#937](https://github.com/tuist/tuist/pull/937) by @paciej00
- Better SEO to the website [#945](https://github.com/tuist/tuist/pull/945) by [@pepibumur](https://github.com/pepibumur).
- Add fixture generator for stress testing Tuist [#890](https://github.com/tuist/tuist/pull/890) by [@kwridan](https://github.com/kwridan).

### Fixed

- The class name of the source files generated by the init command [#850](https://github.com/tuist/tuist/pull/850) by [@pepibumur](https://github.com/pepibumur).
- Add RemoveHeadersOnCopy attribute for build files in copy files build phases [#886](https://github.com/tuist/tuist/pull/886) by [@marciniwanicki](https://github.com/marciniwanicki)
- Ensure precompiled frameworks of target applications aren't included in UI test targets [#888](https://github.com/tuist/tuist/pull/888) by [@kwridan](https://github.com/kwridan)
- Make the scheme generation with testable targets stable [#892](https://github.com/tuist/tuist/pull/892) by [@marciniwanicki](https://github.com/marciniwanicki)
- Fix project header attributes [#895](https://github.com/tuist/tuist/pull/895) by [@kwridan](https://github.com/kwridan)
- Excluding files from target doesn't work in all cases [#913](https://github.com/tuist/tuist/pull/913) by [@vytis](https://github.com/vytis)
- Support for Core Data mapping modules [#911](https://github.com/tuist/tuist/pull/911) by @andreacipriani
- Deep nested hierarchy in the project generated by `tuist edit` [#923](https://github.com/tuist/tuist/pull/923) by [@pepibumur](https://github.com/pepibumur)

### Changed

- Turn models from `TuistCore` that are clases into structs [#870](https://github.com/tuist/tuist/pull/870) by [@pepibumur](https://github.com/pepibumur).

## 1.1.0

### Changed

- Extracted loading logic into its own framework, `TuistLoader` [#838](https://github.com/tuist/tuist/pull/838) by [@pepibumur](https://github.com/pepibumur).

### Added

- `TuistGalaxy` & `TuistAutomation` targets [#817](https://github.com/tuist/tuist/pull/817) by [@pepibumur](https://github.com/pepibumur).
- Support ignoring specific source file pattern when adding them to the target [#811](https://github.com/tuist/tuist/pull/811) by [@vytis](https://github.com/vytis).
- Made targets testable if there is a corresponding test target [#818](https://github.com/tuist/tuist/pull/818) by [@vytis](https://github.com/vytis).
- Release page to the documentation [#841](https://github.com/tuist/tuist/pull/841) by [@pepibumur](https://github.com/pepibumur).

## 1.0.1

### Fixed

- Pass through `DEVELOPER_DIR` when set by the environment when determining the path to the currently selected Xcode. @ollieatkinson

## 1.0.0

### Changed

- Run pipelines with Xcode 11.2.1 on CI @pepibumur.

### Removed

- **Breaking** Generate manifests target as part of the generated project [#724](https://github.com/tuist/tuist/pull/724) by [@pepibumur](https://github.com/pepibumur).
- The installation no longer checks if the Swift version is compatible [#727](https://github.com/tuist/tuist/pull/727) by [@pepibumur](https://github.com/pepibumur).
- Don't include the manifests in the generated workspace [#754](https://github.com/tuist/tuist/pull/754) by [@pepibumur](https://github.com/pepibumur).

### Added

- Add `ProjectDescription.Settings.defaultSettings` none case that don't override any `Project` or `Target` settings. [#698](https://github.com/tuist/tuist/pull/698) by [@rowwingman](https://github.com/rowwingman).
- `ProjectEditor` utility [#702](https://github.com/tuist/tuist/pull/702) by [@pepibumur](https://github.com/pepibumur).
- Fix warnings in the project, refactor SHA256 diegest code [#704](https://github.com/tuist/tuist/pull/704) by [@rowwingman](https://github.com/rowwingman).
- Define `ArchiveAction` on `Scheme` [#697](https://github.com/tuist/tuist/pull/697) by @grsouza.
- `tuist edit` command [#703](https://github.com/tuist/tuist/pull/703) by [@pepibumur](https://github.com/pepibumur).
- Support interpolating formatted strings in the printer [#726](https://github.com/tuist/tuist/pull/726) by [@pepibumur](https://github.com/pepibumur).
- Support for paths relative to root [#727](https://github.com/tuist/tuist/pull/727) by [@pepibumur](https://github.com/pepibumur).
- Replace `Sheme.testAction.targets` type from `String` to `TestableTarget` is a description of target that adds to the `TestAction`, you can specify execution tests parallelizable, random execution order or skip tests [#728](https://github.com/tuist/tuist/pull/728) by [@rowwingman](https://github.com/rowwingman).
- Galaxy manifest model [#729](https://github.com/tuist/tuist/pull/729) by [@pepibumur](https://github.com/pepibumur).
- Make scheme generation methods more generic [#730](https://github.com/tuist/tuist/pull/730) by [@adamkhazi](https://github.com/adamkhazi). [@kwridan](https://github.com/kwridan).
- Workspace Schemes [#752](https://github.com/tuist/tuist/pull/752) by [@adamkhazi](https://github.com/adamkhazi). [@kwridan](https://github.com/kwridan).
- `SimulatorController` with method to fetch the runtimes [#746](https://github.com/tuist/tuist/pull/746) by [@pepibumur](https://github.com/pepibumur).
- Add RxSwift as a dependency of `TuistKit` [#760](https://github.com/tuist/tuist/pull/760) by [@pepibumur](https://github.com/pepibumur).
- Add cache command [#762](https://github.com/tuist/tuist/pull/762) by [@pepibumur](https://github.com/pepibumur).
- Utility to build xcframeworks [#759](https://github.com/tuist/tuist/pull/759) by [@pepibumur](https://github.com/pepibumur).
- Add `CacheStoraging` protocol and a implementation for a local cache [#763](https://github.com/tuist/tuist/pull/763) by [@pepibumur](https://github.com/pepibumur).
- Add support for changing the cache and versions directory using environment variables [#765](https://github.com/tuist/tuist/pull/765) by [@pepibumur](https://github.com/pepibumur).
- Reactive interface to the System utility [#770](https://github.com/tuist/tuist/pull/770) by [@pepibumur](https://github.com/pepibumur)
- Workflow to make sure that documentation and website build [#783](https://github.com/tuist/tuist/pull/783) by [@pepibumur](https://github.com/pepibumur).
- Support for `xcframework` [#769](https://github.com/tuist/tuist/pull/769) by @lakpa
- Support generating info.plist for Watch Apps & Extensions [#756](https://github.com/tuist/tuist/pull/756) by [@kwridan](https://github.com/kwridan)

### Fixed

- Ensure custom search path settings are included in generated projects [#751](https://github.com/tuist/tuist/pull/751) by [@kwridan](https://github.com/kwridan)
- Remove duplicate HEADER_SEARCH_PATHS [#787](https://github.com/tuist/tuist/pull/787) by [@kwridan](https://github.com/kwridan)
- Fix unstable scheme generation [#790](https://github.com/tuist/tuist/pull/790) by [@marciniwanicki](https://github.com/marciniwanicki)
- Add defaultConfigurationName to generated projects [#793](https://github.com/tuist/tuist/pull/793) by [@kwridan](https://github.com/kwridan)
- Add knownRegions to generated projects [#792](https://github.com/tuist/tuist/pull/792) by [@kwridan](https://github.com/kwridan)

## 0.19.0

### Added

- XCTAssertThrowsSpecific convenient function to test for specific errors [#535](https://github.com/tuist/tuist/pull/535) by [@fortmarek](https://github.com/fortmarek)
- `HTTPClient` utility class to `TuistEnvKit` [#508](https://github.com/tuist/tuist/pull/508) by [@pepibumur](https://github.com/pepibumur).
- **Breaking** Allow specifying a deployment target within project manifests [#541](https://github.com/tuist/tuist/pull/541) [@mollyIV](https://github.com/mollyIV).
- Add support for sticker pack extension & app extension products [#489](https://github.com/tuist/tuist/pull/489) by @Rag0n
- Utility to locate the root directory of a project [#622](https://github.com/tuist/tuist/pull/622) by [@pepibumur](https://github.com/pepibumur).
- Adds `codeCoverageTargets` to `TestAction` to make XCode gather coverage info only for that targets [#619](https://github.com/tuist/tuist/pull/619) by @abbasmousavi
- Enable the library evololution for the ProjectDescription framework [#625](https://github.com/tuist/tuist/pull/625) by [@pepibumur](https://github.com/pepibumur).
- Add support for watchOS apps [#623](https://github.com/tuist/tuist/pull/623) by [@kwridan](https://github.com/kwridan)
- Add linting for duplicate dependencies [#629](https://github.com/tuist/tuist/pull/629) by @lakpa

### Changed

- Change dependencies in `Package.resolved` to version from branch [#631](https://github.com/tuist/tuist/pull/631) by [@fortmarek](https://github.com/fortmarek)
- Rename `TuistCore` to `TuistSupport` [#621](https://github.com/tuist/tuist/pull/621) by [@pepibumur](https://github.com/pepibumur).
- Introduce `Systems.shared`, `TuistTestCase`, and `TuistUnitTestCase` [#519](https://github.com/tuist/tuist/pull/519) by [@pepibumur](https://github.com/pepibumur).
- Change generated object version behaviour to mimic Xcode 11 by [@adamkhazi](https://github.com/adamkhazi).
- **Breaking** Refine API for Swift Packages [#578](https://github.com/tuist/tuist/pull/578) by [@ollieatkinson](https://github.com/ollieatkinson)
- Support ability to locate multiple Tuist directories [#630](https://github.com/tuist/tuist/pull/630) by [@kwridan](https://github.com/kwridan)

### Fixed

- Fix false positive cycle detection [#546](https://github.com/tuist/tuist/pull/546) by [@kwridan](https://github.com/kwridan)
- Fix test target build settings [#661](https://github.com/tuist/tuist/pull/661) by [@kwridan](https://github.com/kwridan)
- Fix hosted unit test dependencies [#664](https://github.com/tuist/tuist/pull/664)/ by [@kwridan](https://github.com/kwridan)

## 0.18.1

### Removed

- Reverting [#494](https://github.com/tuist/tuist/pull/494) using variables in `productName` doesn't evaluate in all usage points within the generated project

## 0.18.0

### Added

- New InfoPlist type, `.extendingDefault([:])` [#448](https://github.com/tuist/tuist/pull/448) by [@pepibumur](https://github.com/pepibumur)
- Forward the output of the `codesign` command to make debugging easier when the copy frameworks command fails [#492](https://github.com/tuist/tuist/pull/492) by [@pepibumur](https://github.com/pepibumur).
- Support for multi-line settings (see [how to migrate](https://github.com/tuist/tuist/pull/464#issuecomment-529673717)) [#464](https://github.com/tuist/tuist/pull/464) by [@marciniwanicki](https://github.com/marciniwanicki)
- Support for SPM [#394](https://github.com/tuist/tuist/pull/394) by [@pepibumur](https://github.com/pepibumur) & @fortmarek & @kwridan & @ollieatkinson
- Xcode 11 Support by [@ollieatkinson](https://github.com/ollieatkinson)

### Fixed

- Transitively link static dependency's dynamic dependencies correctly [#484](https://github.com/tuist/tuist/pull/484) by [@adamkhazi](https://github.com/adamkhazi).
- Prevent embedding static frameworks [#490](https://github.com/tuist/tuist/pull/490) by [@kwridan](https://github.com/kwridan)
- Output losing its format when tuist is run through `tuistenv` [#493](https://github.com/tuist/tuist/pull/493) by [@pepibumur](https://github.com/pepibumur)
- Product name linting failing when it contains variables [#494](https://github.com/tuist/tuist/pull/494) by @dcvz
- Build phases not generated in the right position [#506](https://github.com/tuist/tuist/pull/506) by [@pepibumur](https://github.com/pepibumur)
- Remove \$(SRCROOT) from being included in `Info.plist` path [#511](https://github.com/tuist/tuist/pull/511) by @dcvz
- Prevent generation of redundant file elements [#515](https://github.com/tuist/tuist/pull/515) by [@kwridan](https://github.com/kwridan)

## 0.17.0

### Added

- `tuist graph` command [#427](https://github.com/tuist/tuist/pull/427) by [@pepibumur](https://github.com/pepibumur).
- Allow customisation of `productName` in the project Manifest [#435](https://github.com/tuist/tuist/pull/435) by [@ollieatkinson](https://github.com/ollieatkinson)
- Adding support for static products depending on dynamic frameworks [#439](https://github.com/tuist/tuist/pull/439) by [@kwridan](https://github.com/kwridan)
- Support for executing Tuist by running `swift project ...` [#447](https://github.com/tuist/tuist/pull/447) by [@pepibumur](https://github.com/pepibumur).
- New manifest model, `TuistConfig`, to easily configure Tuist's functionalities [#446](https://github.com/tuist/tuist/pull/446) by [@pepibumur](https://github.com/pepibumur).
- Adding ability to re-generate individual projects [#457](https://github.com/tuist/tuist/pull/457) by [@kwridan](https://github.com/kwridan)
- Support multiple header paths [#459](https://github.com/tuist/tuist/pull/459) by [@adamkhazi](https://github.com/adamkhazi).
- Allow specifying multiple configurations within project manifests [#451](https://github.com/tuist/tuist/pull/451) by [@kwridan](https://github.com/kwridan)
- Add linting for mismatching build configurations in a workspace [#474](https://github.com/tuist/tuist/pull/474) by [@kwridan](https://github.com/kwridan)
- Support for CocoaPods dependencies [#465](https://github.com/tuist/tuist/pull/465) by [@pepibumur](https://github.com/pepibumur)
- Support custom .xcodeproj name at the model level [#462](https://github.com/tuist/tuist/pull/462) by [@adamkhazi](https://github.com/adamkhazi).
- `TuistConfig.compatibleXcodeVersions` support [#476](https://github.com/tuist/tuist/pull/476) by [@pepibumur](https://github.com/pepibumur).
- Expose the `.bundle` product type [#479](https://github.com/tuist/tuist/pull/479) by [@kwridan](https://github.com/kwridan)

### Fixed

- Ensuring transitive SDK dependencies are added correctly [#441](https://github.com/tuist/tuist/pull/441) by [@adamkhazi](https://github.com/adamkhazi).
- Ensuring the correct platform SDK dependencies path is set [#419](https://github.com/tuist/tuist/pull/419) by [@kwridan](https://github.com/kwridan)
- Update manifest target name such that its product has a valid name [#426](https://github.com/tuist/tuist/pull/426) by [@kwridan](https://github.com/kwridan)
- Do not create `Derived/InfoPlists` folder when no InfoPlist dictionary is specified [#456](https://github.com/tuist/tuist/pull/456) by [@adamkhazi](https://github.com/adamkhazi).
- Set the correct lastKnownFileType for localized files [#478](https://github.com/tuist/tuist/pull/478) by [@kwridan](https://github.com/kwridan)

### Changed

- Update XcodeProj to 7.0.0 [#421](https://github.com/tuist/tuist/pull/421) by [@pepibumur](https://github.com/pepibumur).

## 0.16.0

### Added

- `DefaultSettings.none` to disable the generation of default build settings [#395](https://github.com/tuist/tuist/pull/395) by [@pepibumur](https://github.com/pepibumur).
- Version information for tuistenv [#399](https://github.com/tuist/tuist/pull/399) by [@ollieatkinson](https://github.com/ollieatkinson)
- Add input & output paths for target action [#353](https://github.com/tuist/tuist/pull/353) by Rag0n
- Adding support for linking system libraries and frameworks [#353](https://github.com/tuist/tuist/pull/353) by @steprescott
- Support passing the `Info.plist` as a dictionary [#380](https://github.com/tuist/tuist/pull/380) by [@pepibumur](https://github.com/pepibumur).

### Fixed

- Ensuring the correct default settings provider dependency is used [#389](https://github.com/tuist/tuist/pull/389) by [@kwridan](https://github.com/kwridan)
- Fixing build settings repeated same value [#391](https://github.com/tuist/tuist/pull/391) by @platonsi
- Duplicated files in the sources build phase when different glob patterns match the same files [#388](https://github.com/tuist/tuist/pull/388) by [@pepibumur](https://github.com/pepibumur).
- Support `.d` source files [#396](https://github.com/tuist/tuist/pull/396) by [@pepibumur](https://github.com/pepibumur).
- Codesign frameworks when copying during the embed phase [#398](https://github.com/tuist/tuist/pull/398) by [@ollieatkinson](https://github.com/ollieatkinson)
- 'tuist local' failed when trying to install from source [#402](https://github.com/tuist/tuist/pull/402) by [@ollieatkinson](https://github.com/ollieatkinson)
- Omitting unzip logs during installation [#404](https://github.com/tuist/tuist/pull/404) by [@kwridan](https://github.com/kwridan)
- Fix "The file couldn’t be saved." error [#408](https://github.com/tuist/tuist/pull/408) by [@marciniwanicki](https://github.com/marciniwanicki)
- Ensure generated projects are stable [#410](https://github.com/tuist/tuist/pull/410) by [@kwridan](https://github.com/kwridan)
- Stop generating empty `PBXBuildFile` settings [#415](https://github.com/tuist/tuist/pull/415) by [@marciniwanicki](https://github.com/marciniwanicki)

## 0.15.0

### Changed

- Introduce the `InfoPlist` file [#373](https://github.com/tuist/tuist/pull/373) by [@pepibumur](https://github.com/pepibumur).
- Add `defaultSettings` option to `Settings` definition to control default settings generation [#378](https://github.com/tuist/tuist/pull/378) by [@marciniwanicki](https://github.com/marciniwanicki)

### Added

- Adding generate command timer [#335](https://github.com/tuist/tuist/pull/335) by [@kwridan](https://github.com/kwridan)
- Support Scheme manifest with pre/post action [#336](https://github.com/tuist/tuist/pull/336) [@dangthaison91](https://github.com/dangthaison91).
- Support local Scheme (not shared) flag [#341](https://github.com/tuist/tuist/pull/341) [@dangthaison91](https://github.com/dangthaison91).
- Support for compiler flags [#386](https://github.com/tuist/tuist/pull/386) by [@pepibumur](https://github.com/pepibumur).

### Fixed

- Fixing unstable diff (products and embedded frameworks) [#357](https://github.com/tuist/tuist/pull/357) by [@marciniwanicki](https://github.com/marciniwanicki)
- Set Code Sign On Copy to true for Embed Frameworks [#333](https://github.com/tuist/tuist/pull/333) [@dangthaison91](https://github.com/dangthaison91).
- Fixing files getting mistaken for folders [#338](https://github.com/tuist/tuist/pull/338) by [@kwridan](https://github.com/kwridan)
- Updating init template to avoid warnings [#339](https://github.com/tuist/tuist/pull/339) by [@kwridan](https://github.com/kwridan)
- Fixing generation failures due to asset catalog & `**/*.png` glob patterns handling [#346](https://github.com/tuist/tuist/pull/346) by [@kwridan](https://github.com/kwridan)
- Supporting bundle target dependencies that reside in different projects (in `TuistGenerator`) [#348](https://github.com/tuist/tuist/pull/348) by [@kwridan](https://github.com/kwridan)
- Fixing header paths including folders and non-header files [#356](https://github.com/tuist/tuist/pull/356) by [@kwridan](https://github.com/kwridan)
- Fix duplicate localized resource files [#363](https://github.com/tuist/tuist/pull/363) by [@kwridan](https://github.com/kwridan)
- Update static dependency lint rule [#360](https://github.com/tuist/tuist/pull/360) by [@kwridan](https://github.com/kwridan)
- Ensure resource bundles in other projects get built [#374](https://github.com/tuist/tuist/pull/374) by [@kwridan](https://github.com/kwridan)

## 0.14.0

### Changed

### Added

- Adding support for project additional files [#314](https://github.com/tuist/tuist/pull/314) by [@kwridan](https://github.com/kwridan)
- Adding support for resource folder references [#318](https://github.com/tuist/tuist/pull/318) by [@kwridan](https://github.com/kwridan)
- **Breaking** Swift 5 support [#317](https://github.com/tuist/tuist/pull/317) by [@pepibumur](https://github.com/pepibumur).

### Fixed

- Ensuring target product names are consistent with Xcode [#323](https://github.com/tuist/tuist/pull/323) by [@kwridan](https://github.com/kwridan)
- Ensuring generate works on additional disk volumes [#327](https://github.com/tuist/tuist/pull/327) by [@kwridan](https://github.com/kwridan)
- Headers build phase should be put on top of Compile build phase [#332](https://github.com/tuist/tuist/pull/332) [@dangthaison91](https://github.com/dangthaison91).

## 0.13.0

### Added

- Add Homebrew tap up [#281](https://github.com/tuist/tuist/pull/281) by [@pepibumur](https://github.com/pepibumur)
- Create a Setup.swift file when running the init command [#283](https://github.com/tuist/tuist/pull/283) by [@pepibumur](https://github.com/pepibumur)
- Update `tuistenv` when running `tuist update` [#288](https://github.com/tuist/tuist/pull/288) by [@pepibumur](https://github.com/pepibumur).
- Allow linking of static products into dynamic frameworks [#299](https://github.com/tuist/tuist/pull/299) by [@ollieatkinson](https://github.com/ollieatkinson)
- Workspace improvements [#298](https://github.com/tuist/tuist/pull/298) by [@ollieatkinson](https://github.com/ollieatkinson) & [@kwridan](https://github.com/kwridan).

### Removed

- **Breaking** Removed "-Project" shared scheme from being generated [#303](https://github.com/tuist/tuist/pull/303) by [@ollieatkinson](https://github.com/ollieatkinson)

### Fixed

- Fix duplicated embedded frameworks [#280](https://github.com/tuist/tuist/pull/280) by [@pepibumur](https://github.com/pepibumur)
- Fix manifest target linker errors [#287](https://github.com/tuist/tuist/pull/287) by [@kwridan](https://github.com/kwridan)
- Build settings not being generated properly [#282](https://github.com/tuist/tuist/pull/282) by [@pepibumur](https://github.com/pepibumur)
- Fix `instance method nearly matches optional requirements` warning in generated `AppDelegate.swift` in iOS projects [#291](https://github.com/tuist/tuist/pull/291) by @BalestraPatrick
- Fix Header & Framework search paths override project or xcconfig settings [#301](https://github.com/tuist/tuist/pull/301) by [@ollieatkinson](https://github.com/ollieatkinson)
- Unit tests bundle for an app target compile & run [#300](https://github.com/tuist/tuist/pull/300) by [@ollieatkinson](https://github.com/ollieatkinson)
- `LIBRARY_SEARCH_PATHS` and `SWIFT_INCLUDE_PATHS` are now set [#308](https://github.com/tuist/tuist/pull/308) by [@kwridan](https://github.com/kwridan)
- Fix Generation fails in the event an empty .xcworkspace directory exists [#312](https://github.com/tuist/tuist/pull/312) by [@ollieatkinson](https://github.com/ollieatkinson)

## 0.12.0

### Changed

- Rename manifest group to `Manifest` [#227](https://github.com/tuist/tuist/pull/227) by [@pepibumur](https://github.com/pepibumur).
- Rename manifest target to `Project-Manifest` [#227](https://github.com/tuist/tuist/pull/227) by [@pepibumur](https://github.com/pepibumur).
- Replace swiftlint with swiftformat [#239](https://github.com/tuist/tuist/pull/239) by [@pepibumur](https://github.com/pepibumur).
- Bump xcodeproj version to 6.6.0 [#248](https://github.com/tuist/tuist/pull/248) by [@pepibumur](https://github.com/pepibumur).
- Fix an issue with Xcode not being able to reload the projects when they are open [#247](https://github.com/tuist/tuist/pull/247)
- Support array for `sources` and `resources` paths [#201](https://github.com/tuist/tuist/pull/201) [@dangthaison91](https://github.com/dangthaison91).

### Added

- Integration tests for `generate` command [#208](https://github.com/tuist/tuist/pull/208) by [@marciniwanicki](https://github.com/marciniwanicki) & @kwridan
- Frequently asked questions to the documentation [#223](https://github.com/tuist/tuist/pull/223)/ by [@pepibumur](https://github.com/pepibumur).
- Generate a scheme with all the project targets [#226](https://github.com/tuist/tuist/pull/226) by [@pepibumur](https://github.com/pepibumur)
- Documentation for contributors [#229](https://github.com/tuist/tuist/pull/229) by [@pepibumur](https://github.com/pepibumur)
- Support for Static Frameworks [#194](https://github.com/tuist/tuist/pull/194) @ollieatkinson

### Removed

- Up attribute from the `Project` model [#228](https://github.com/tuist/tuist/pull/228) by [@pepibumur](https://github.com/pepibumur).
- Support for YAML and JSON formats as Project specifications [#230](https://github.com/tuist/tuist/pull/230) by [@ollieatkinson](https://github.com/ollieatkinson)

### Fixed

- Changed default value of SWIFT_VERSION to 4.2 @ollieatkinson
- Added fixture tests for ios app with static libraries @ollieatkinson
- Bundle id linting failing when the bundle id contains variables [#252](https://github.com/tuist/tuist/pull/252) by [@pepibumur](https://github.com/pepibumur)
- Include linked library and embed in any top level executable bundle [#259](https://github.com/tuist/tuist/pull/259) by [@ollieatkinson](https://github.com/ollieatkinson)

## 0.11.0

### Added

- **Breaking** Up can now be specified via `Setup.swift` https://github.com/tuist/tuist/issues/203 by [@marciniwanicki](https://github.com/marciniwanicki) & @kwridan
- Schemes generation [#188](https://github.com/tuist/tuist/pull/188) by [@pepibumur](https://github.com/pepibumur).
- Environment variables per target [#189](https://github.com/tuist/tuist/pull/189) by [@pepibumur](https://github.com/pepibumur).
- Danger warn that reminds contributors to update the docuementation [#214](https://github.com/tuist/tuist/pull/214) by [@pepibumur](https://github.com/pepibumur)
- Rubocop [#216](https://github.com/tuist/tuist/pull/216) by [@pepibumur](https://github.com/pepibumur).
- Fail init command if the directory is not empty [#218](https://github.com/tuist/tuist/pull/218) by [@pepibumur](https://github.com/pepibumur).
- Verify that the bundle identifier has only valid characters [#219](https://github.com/tuist/tuist/pull/219) by [@pepibumur](https://github.com/pepibumur).
- Merge documentation from the documentation repository [#222](https://github.com/tuist/tuist/pull/222) by [@pepibumur](https://github.com/pepibumur).
- Danger [#186](https://github.com/tuist/tuist/pull/186) by [@pepibumur](https://github.com/pepibumur).

### Fixed

- Swiftlint style issues [#213](https://github.com/tuist/tuist/pull/213) by [@pepibumur](https://github.com/pepibumur).
- Use environment tuist instead of the absolute path in the embed frameworks build phase [#185](https://github.com/tuist/tuist/pull/185) by [@pepibumur](https://github.com/pepibumur).

### Deprecated

- JSON and YAML manifests [#190](https://github.com/tuist/tuist/pull/190) by [@pepibumur](https://github.com/pepibumur).

## 0.10.2

### Fixed

- Processes not stopping after receiving an interruption signal [#180](https://github.com/tuist/tuist/pull/180) by [@pepibumur](https://github.com/pepibumur).

## 0.10.1

### Changed

- Replace ReactiveTask with SwiftShell [#179](https://github.com/tuist/tuist/pull/179) by [@pepibumur](https://github.com/pepibumur).

### Fixed

- Carthage up command not running when the `Cartfile.resolved` file doesn't exist [#179](https://github.com/tuist/tuist/pull/179) by [@pepibumur](https://github.com/pepibumur).

## 0.10.0

### Fixed

- Don't generate the Playgrounds group if there are no playgrounds [#177](https://github.com/tuist/tuist/pull/177) by [@pepibumur](https://github.com/pepibumur).

### Added

- Tuist up command [#158](https://github.com/tuist/tuist/pull/158) by [@pepibumur](https://github.com/pepibumur).
- Support `.cpp` and `.c` source files [#178](https://github.com/tuist/tuist/pull/178) by [@pepibumur](https://github.com/pepibumur).

## 0.9.0

### Added

- Acceptance tests [#166](https://github.com/tuist/tuist/pull/166) by [@pepibumur](https://github.com/pepibumur).

### Fixed

- Files and groups sort order [#164](https://github.com/tuist/tuist/pull/164) by [@pepibumur](https://github.com/pepibumur).

### Added

- Generate both, the `Debug` and `Release` configurations [#165](https://github.com/tuist/tuist/pull/165) by [@pepibumur](https://github.com/pepibumur).

## 0.8.0

### Added

- Swift 4.2.1 compatibility by [@pepibumur](https://github.com/pepibumur).

### Removed

- Module loader [#150](https://github.com/tuist/tuist/pull/150)/files by [@pepibumur](https://github.com/pepibumur).

### Added

- Geration of projects and workspaces in the `~/.tuist/DerivedProjects` directory [#146](https://github.com/tuist/tuist/pull/146) by pepibumur.

## 0.7.0

### Added

- Support for actions [#136](https://github.com/tuist/tuist/pull/136) by [@pepibumur](https://github.com/pepibumur).

## 0.6.0

### Added

- Check that the local Swift version is compatible with the version that will be installed [#134](https://github.com/tuist/tuist/pull/134) by [@pepibumur](https://github.com/pepibumur).

### Changed

- Bump xcodeproj to 6.0.0 [#133](https://github.com/tuist/tuist/pull/133) by [@pepibumur](https://github.com/pepibumur).

### Removed

- Remove `tuistenv` from the repository [#135](https://github.com/tuist/tuist/pull/135) by [@pepibumur](https://github.com/pepibumur).

## 0.5.0

### Added

- Support for JSON and Yaml manifests [#110](https://github.com/tuist/tuist/pull/110) by [@pepibumur](https://github.com/pepibumur).
- Generate `.gitignore` file when running init command [#118](https://github.com/tuist/tuist/pull/118) by [@pepibumur](https://github.com/pepibumur).
- Git ignore Xcode and macOS files that shouldn't be included on a git repository [#124](https://github.com/tuist/tuist/pull/124) by [@pepibumur](https://github.com/pepibumur).
- Focus command [#129](https://github.com/tuist/tuist/pull/129) by [@pepibumur](https://github.com/pepibumur).

### Fixed

- Snake-cased build settings keys [#107](https://github.com/tuist/tuist/pull/107) by [@pepibumur](https://github.com/pepibumur).

## 0.4.0

### Added

- Throw an error if a library target contains resources [#98](https://github.com/tuist/tuist/pull/98) by [@pepibumur](https://github.com/pepibumur).
- Playgrounds support [#103](https://github.com/tuist/tuist/pull/103) by [@pepibumur](https://github.com/pepibumur).
- Faster installation using bundled releases [#104](https://github.com/tuist/tuist/pull/104) by [@pepibumur](https://github.com/pepibumur).

### Changed

- Don't fail if a Carthage framework doesn't exist. Print a warning instead [#96](https://github.com/tuist/tuist/pull/96) by [@pepibumur](https://github.com/pepibumur).
- Missing file errors are printed together [#98](https://github.com/tuist/tuist/pull/98) by [@pepibumur](https://github.com/pepibumur).

## 0.3.0

### Added

- Homebrew formula https://github.com/tuist/tuist/commit/0ab1c6e109134337d4a5e074d77bd305520a935d by [@pepibumur](https://github.com/pepibumur).

## Changed

- Replaced ssh links with the https version of them [#91](https://github.com/tuist/tuist/pull/91) by [@pepibumur](https://github.com/pepibumur).

## Fixed

- `FRAMEWORK_SEARCH_PATHS` build setting not being set for precompiled frameworks dependencies [#87](https://github.com/tuist/tuist/pull/87) by [@pepibumur](https://github.com/pepibumur).

## 0.2.0

### Added

- Install command [#83](https://github.com/tuist/tuist/pull/83) by [@pepibumur](https://github.com/pepibumur).
- `--help-env` command to tuistenv by [@pepibumur](https://github.com/pepibumur).

### Fixed

- Fix missing target dependencies by [@pepibumur](https://github.com/pepibumur).

### Removed

- Internal deprecation warnings by [@pepibumur](https://github.com/pepibumur).

## 0.1.0

### Added

- Local command prints all the local versions if no argument is given [#79](https://github.com/tuist/tuist/pull/79) by [@pepibumur](https://github.com/pepibumur).
- Platform, product, path and name arguments to the init command [#64](https://github.com/tuist/tuist/pull/64) by [@pepibumur](https://github.com/pepibumur).
- Lint that `Info.plist` and `.entitlements` files are not copied into the target products [#65](https://github.com/tuist/tuist/pull/65) by [@pepibumur](https://github.com/pepibumur)
- Lint that there's only one resources build phase [#65](https://github.com/tuist/tuist/pull/65) by [@pepibumur](https://github.com/pepibumur).
- Command runner [#81](https://github.com/tuist/tuist/pull/81)/ by [@pepibumur](https://github.com/pepibumur).

### Added

- Sources, resources, headers and coreDataModels property to the `Target` model [#67](https://github.com/tuist/tuist/pull/67) by [@pepibumur](https://github.com/pepibumur).

### Changed

- `JSON` and `JSONConvertible` replaced with Swift's `Codable` conformance.

### Removed

- The scheme attribute from the `Project` model [#67](https://github.com/tuist/tuist/pull/67) by [@pepibumur](https://github.com/pepibumur).
- Build phases and build files [#67](https://github.com/tuist/tuist/pull/67) by [@pepibumur](https://github.com/pepibumur).
