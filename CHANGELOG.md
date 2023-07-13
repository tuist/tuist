# Changelog

## 3.21.1 - 2023-07-13

### Changed

- Update `TEST_HOST` to use BUNDLE_EXECUTABLE_FOLDER_PATH from Xcode 14 [#5289](https://github.com/tuist/tuist/pull/5289) by [@waltflanagan](https://github.com/waltflanagan)

## Unreleased

### Fixed

- Fix plist code generation for single file case [#5292](https://github.com/tuist/tuist/pull/5292) by [@waltflanagan](https://github.com/waltflanagan).

## 3.21.0 - 2023-07-11

### Changed

- Set BuildIndependentTargetsInParallel setting to true by default [#5225](https://github.com/tuist/tuist/pull/5225) by [@thedavidharris](https://github.com/thedavidharris)
- Update Stencil to 0.15.1 [#5250](https://github.com/tuist/tuist/pull/5250) by [@waltflanagan](https://github.com/waltflanagan)

### Added

- Add support for ExtensionKit extensions [#5005](https://github.com/tuist/tuist/pull/5005) by [@tovkal](https://github.com/tovkal)
- Added support for visionOS [#5251](https://github.com/tuist/tuist/pull/5251) by [@Mstrodl](https://github.com/Mstrodl).

### Fixed

- Mark bundle product type doesn't support sources for all platforms [#5229](https://github.com/tuist/tuist/pull/5229) by [@serejahh](https://github.com/serejahh)
- Fixed a bug where turning on and off the rendering of markdown files in Workspace config wouldn't turn off rendering properly and would stay in read-only mode [#5261](https://github.com/tuist/tuist/pull/5261) by [@Buju77](https://github.com/Buju77).
- Fixed code generation when target name starts with non alphanumeric character [#5256](https://github.com/tuist/tuist/pull/5256) by [@dankinsoid](https://github.com/dankinsoid)

## 3.20.0 - 2023-05-31

### Changed

- Bump minimum required Xcode version to 14.1 for client use and 14.3 for development [#5201](https://github.com/tuist/tuist/pull/5201) by [@thedavidharris](https://github.com/thedavidharris)

### Added

- Allow using a period in a CLI product name [#5178](https://github.com/tuist/tuist/pull/5178) by [@serejahh](https://github.com/serejahh)
- Add support for `docc` documentation in ProjectDescriptionHelpers [#5198](https://github.com/tuist/tuist/pull/5198) by [@waltflanagan](https://github.com/waltflanagan)
- Added cloud clean command [#5211](https://github.com/tuist/tuist/pull/5211) by [@fortmarek](https://github.com/fortmarek)

### Fixed

- chore: Removed `BundleExecutableKey` from Info.plist for watchOS bundles [#5194](https://github.com/tuist/tuist/pull/5194) by [@griches](https://github.com/griches)
- Improve error message when `tuist generate` is called without calling `tuist fetch` first [#5193](https://github.com/tuist/tuist/pull/5193) by [@mustiikhalil](https://github.com/mustiikhalil)

## 3.19.0 - 2023-04-29

### Added

- Add support for watchOS extension to have WidgetKit extension dependencies [#5153](https://github.com/tuist/tuist/pull/5153) by [@griches](https://github.com/griches)
- Support for SwiftUI font in font template [#5168](https://github.com/tuist/tuist/pull/5168) by [@L-j-h-c](https://github.com/L-j-h-c)
- Support for custom shell path in `ExecuteAction` [#5154](https://github.com/tuist/tuist/pull/5154) by [@JCSooHwanCho](https://github.com/JCSooHwanCho)

### Fixed

- Exclude Swift Package build directory from manifest search [#5143](https://github.com/tuist/tuist/pull/5143) by [@ajevans99](https://github.com/ajevans99)
- Fix errors when archiving projects with static XCFrameworks [#5157](https://github.com/tuist/tuist/pull/5157) by [@kwridan](https://github.com/kwridan)

## 3.18.0 - 2023-04-14

### Added

- Add support for disabling `Mac (designed for iOS)` destination for iOS deployment target [#5095](https://github.com/tuist/tuist/pull/5095) by [@TheInkedEngineer](https://github.com/TheInkedEngineer)

### Fixed

- Fix link phase for tvOS top shelf extension [#5119](https://github.com/tuist/tuist/pull/5119) by [@sh-a-n](https://github.com/sh-a-n)
- Ensure static precompiled dependencies are only linked in targets that support linking [#5107](https://github.com/tuist/tuist/pull/5107) by [@kwridan](https://github.com/kwridan)

## 3.17.0 - 2023-03-12

### Added

- Add support for `customLLDBInitFile` settings in `Scheme.RunAction` [#5060](https://github.com/tuist/tuist/pull/5060) by [@oozoofrog](https://github.com/oozoofrog)
- Add support for build rules [#5088](https://github.com/tuist/tuist/pull/5088) by [@MartinStrambach](https://github.com/MartinStrambach)
- Add option to cache as device or simulator xcframeworks [#5075](https://github.com/tuist/tuist/pull/5075) by [@kientux](https://github.com/kientux)
- Support for `xpc` product type on `macOS` [#5077](https://github.com/tuist/tuist/pull/5077) by [@serejahh](https://github.com/serejahh)

### Fixed

- Consider system architecture when computing macOS target hashes [#5064](https://github.com/tuist/tuist/pull/5064) by [@danyf90](https://github.com/danyf90)
- Update the Info.plist default for iOS for Xcode 14.2 [#5067](https://github.com/tuist/tuist/pull/5067) by [@ronanociosoig-200](https://github.com/ronanociosoig-200)
- Fix CoreData model when `xcdatamodel` file has a name different from the `xcdatamodeld` folder [#5049](https://github.com/tuist/tuist/pull/5049) by [@danyf90](https://github.com/danyf90)
- Fix for `tuist fetch` not failing when run outside of a Tuist project [#5082](https://github.com/tuist/tuist/pull/5082) by [@havebeenfitz](https://github.com/havebeenfitz)

## 3.16.0 - 2023-02-09

### Changed

- Sets sending of analytics to cloud dashboard as default behavior [#4942](https://github.com/tuist/tuist/pull/4942) by [@Primecutz](https://github.com/Primecutz)

### Added

- Support for defining a dependency file in run script phases [#4940](https://github.com/tuist/tuist/pull/4940) by [@a-sarris](https://github.com/a-sarris)
- Add cloud init command [#4976](https://github.com/tuist/tuist/pull/4976) by [@fortmarek](https://github.com/fortmarek)
- Add support for language and region to autogenerated schemes [#4983](https://github.com/tuist/tuist/pull/4983) by [@olejnjak](https://github.com/olejnjak)
- Support for custom release URL for remote plugins [#4944](https://github.com/tuist/tuist/pull/4944) by [@mstfy](https://github.com/mstfy)
- Support for embedding a CLI app within a macOS application [#5023](https://github.com/tuist/tuist/pull/5023) by [@serejahh](https://github.com/serejahh)

### Fixed

- Fix Cloud analytics data race [#4945](https://github.com/tuist/tuist/pull/4945) by [@fortmarek](https://github.com/fortmarek)
- Fix support for template attributes located in a remote git repository in `tuist init` [#4971](https://github.com/tuist/tuist/pull/4971) by [@andruvs](https://github.com/andruvs)
- Support for period (`.`) character in `Target.productName` [#4985](https://github.com/tuist/tuist/pull/4985) by [@Lilfaen](https://github.com/Lilfaen)
- Fix xcframeworks caching for frameworks which include documentation catalogs [#4986](https://github.com/tuist/tuist/pull/4986) by [@waltflanagan](https://github.com/waltflanagan)
- Add GraphLinter support for watchOS app appExtension targets [#5025](https://github.com/tuist/tuist/pull/5025) by [@alexanderwe](https://github.com/alexanderwe)
- Fix color accessor when deployment target is below the SwiftUI one [#5035](https://github.com/tuist/tuist/pull/5035) by [@danyf90](https://github.com/danyf90)

## 3.15.0 - 2022-12-19

### Added

- Add support for environment variables and launch arguments in test actions [#4879](https://github.com/tuist/tuist/pull/4879) by [@euriasb](https://github.com/euriasb)
- Add support for `.rcproject` source files [#4925](https://github.com/tuist/tuist/pull/4925) by [@BenjaminPrieur](https://github.com/BenjaminPrieur)
- Add `TargetDependency.target()` helper accepting a target instance [#4930](https://github.com/tuist/tuist/pull/4930) by [@danyf90](https://github.com/danyf90)

### Fixed

- Fix support for custom `applicationIdPrefix` from provisioning profiles [#4888](https://github.com/tuist/tuist/pull/4888) by [@david-all-win-software](https://github.com/david-all-win-software)
- Fix signing when certificate name contains quotes [#4890](https://github.com/tuist/tuist/pull/4890) by [@david-all-win-software](https://github.com/david-all-win-software)
- Fix linting rules for allowing a watchOS as a dependency of a test target [#4908](https://github.com/tuist/tuist/pull/4908) by [@alexanderwe](https://github.com/alexanderwe)
- Fix generation of resource accessor for AR reference images [#4926](https://github.com/tuist/tuist/pull/4926) by [@Tulleb](https://github.com/Tulleb)

## 3.14.0 - 2022-11-18

### Added

- Add default known regions in project options [#4867](https://github.com/tuist/tuist/pull/4867) by [@spqw](https://github.com/spqw)

### Fixed

- Fix concurrency warning in bundle extension [#4878](https://github.com/tuist/tuist/pull/4878) by [@mpodeszwa](https://github.com/mpodeszwa)

## 3.13.0 - 2022-11-05

### Added

- Add SwiftUI support to default assets resource synthesizer [#4838](https://github.com/tuist/tuist/pull/4838) by [@kyungpyoda](https://github.com/kyungpyoda)

### Fixed

- Fix extra Target configurations are generated when Project has custom configurations [#4811](https://github.com/tuist/tuist/pull/4811) by [@francuim-d](https://github.com/francuim-d)
- When tuist chooses a simulator device while building, make sure it's available [#4848](https://github.com/tuist/tuist/pull/4848) by [@ezraberch](https://github.com/ezraberch)
- Fix loading of stencils using `{% extends %}` [#4844](https://github.com/tuist/tuist/pull/4844) by [@devyhan](https://github.com/devyhan)
- Update Community Url in Constants.swift file [#4836](https://github.com/tuist/tuist/pull/4836) by [@shahzadmajeed](https://github.com/shahzadmajeed)

## 3.12.1 - 2022-10-19

### Changed

- Remove backbone [#4817](https://github.com/tuist/tuist/pull/4817) by [@fortmarek](https://github.com/fortmarek)

### Fixed

- Fix support for master.key with final newline [#4782](https://github.com/tuist/tuist/pull/4782) by [@mfcollins3](https://github.com/mfcollins3)
- Make `tuistenv` ignore empty `.tuist-bin` folder [#4793](https://github.com/tuist/tuist/pull/4793) by [@ezraberch](https://github.com/ezraberch)
- Fix `tuist install` when missing trailing zero [#4797](https://github.com/tuist/tuist/pull/4797) by [@danyf90](https://github.com/danyf90)
- Preserve target order defined in `Project.swift` when generating project [#4810](https://github.com/tuist/tuist/pull/4810) by [@moritzsternemann](https://github.com/moritzsternemann)
- Fix for resource synthesizers not added to the `tuist edit` project [#4822](https://github.com/tuist/tuist/pull/4822) by [@devyhan](https://github.com/devyhan)
- Fix parsing of "1" and "0" as String from environment [#4816](https://github.com/tuist/tuist/pull/4816) by [@danyf90](https://github.com/danyf90)
- Use relative path in generated Package.swift [#4815](https://github.com/tuist/tuist/pull/4815) by [@danyf90](https://github.com/danyf90)
- Fix regression on SwiftPackageManager packages defining file resources with copy rule [#4812](https://github.com/tuist/tuist/pull/4812) by [@alexanderwe](https://github.com/alexanderwe)

## 3.12.0 - 2022-09-25

### Added

- Add support for Xcode 14 compatible watch application targets [#4658](https://github.com/tuist/tuist/pull/4658) by [@kwridan](https://github.com/kwridan)
- Add support for watchOS app extension dependencies [#4773](https://github.com/tuist/tuist/pull/4773) by [@kwridan](https://github.com/kwridan)

### Fixed

- Allow AppClip tests and their associated AppClip to include the same static framework [#4766](https://github.com/tuist/tuist/pull/4766) by [@regularberry](https://github.com/regularberry)
- Fix SwiftPackageManager copy rule parsing [#4733](https://github.com/tuist/tuist/pull/4733) by [@alexanderwe](https://github.com/alexanderwe)
- Fix warnings in dependencies project generated with Xcode 14 [#4770](https://github.com/tuist/tuist/pull/4770) by [@danyf90](https://github.com/danyf90)

## 3.11.0 - 2022-09-15

### Added

- Add support for performanceAntipatternChecker SchemeDiagnosticsOptions [#4740](https://github.com/tuist/tuist/pull/4740) by [@danyf90](https://github.com/danyf90)

### Fixed

- Fix `tuist build` failing to build workspaces with watchOS targets [#4466](https://github.com/tuist/tuist/pull/4466) by [@thedavidharris](https://github.com/thedavidharris)
- Fix support for iOS targets supporting iPhone, iPad, and Catalyst [#4710](https://github.com/tuist/tuist/pull/4710) by [@dever25](https://github.com/dever25)
- Fix support for macOS test targets depending on static frameworks [#4739](https://github.com/tuist/tuist/pull/4739) by [@dpliushchaiIOS](https://github.com/dpliushchaiIOS)
- Fix `tuist edit` when project contains a Templates folder [#4744](https://github.com/tuist/tuist/pull/4744) by [@michaelmcguire](https://github.com/michaelmcguire)
- Fix computation of target hash within Xcode beta releases [#4738](https://github.com/tuist/tuist/pull/4738) by [@danyf90](https://github.com/danyf90)

## 3.10.0 - 2022-08-20

### Changed

- Improve default swift version handling [#4679](https://github.com/tuist/tuist/pull/4679) by [@kwridan](https://github.com/kwridan)

### Added

- Add `platform` filtering option to `graph` command [#4656](https://github.com/tuist/tuist/pull/4656) by [@mikchmie](https://github.com/mikchmie)
- Add `--device` and `--os` params to `tuist build` [#4647](https://github.com/tuist/tuist/pull/4647) by [@Killectro](https://github.com/Killectro)
- Add support for `svg` graph format [#4659](https://github.com/tuist/tuist/pull/4659) by [@danyf90](https://github.com/danyf90)
- Support for `mlmodelc` resources [#4685](https://github.com/tuist/tuist/pull/4685) by [@mikchmie](https://github.com/mikchmie)

### Fixed

- Fix for Resource targets not being excluded by caching when focusing on their source target [#4669](https://github.com/tuist/tuist/pull/4669) by [@LorDisturbia](https://github.com/LorDisturbia)
- Fix for computing hash of target scripts with output files [#4670](https://github.com/tuist/tuist/pull/4670) by [@danyf90](https://github.com/danyf90)

## 3.9.0 - 2022-07-30

### Changed

- Update XcodeProj to 8.8.0 [#4629](https://github.com/tuist/tuist/pull/4629) by [@danyf90](https://github.com/danyf90)
- Make `ProjectDescription.TargetDependency` hashable [#4644](https://github.com/tuist/tuist/pull/4644) by [@danyf90](https://github.com/danyf90)
- Remove deprecation from `TargetDependency.package` [#4615](https://github.com/tuist/tuist/pull/4615) by [@danyf90](https://github.com/danyf90)

### Added

- Add multiplatform support for external SPM dependencies [#4570](https://github.com/tuist/tuist/pull/4570) by [@alexanderwe](https://github.com/alexanderwe)
- Add support to enable frame gpu capture [#4623](https://github.com/tuist/tuist/pull/4623) by [@PierreCapo](https://github.com/PierreCapo)
- Add support for `--no-open` flag in `tuist graph` [#4637](https://github.com/tuist/tuist/pull/4637) by [@danrevah](https://github.com/danrevah)
- Add support for `systemLibrary` SwiftPackageManager targets [#4642](https://github.com/tuist/tuist/pull/4642) by [@nivanchikov](https://github.com/nivanchikov)

### Fixed

- Pass system environment variables when executing custom command [#4611](https://github.com/tuist/tuist/pull/4611) by [@woohyunjin06](https://github.com/woohyunjin06)
- Fix for `tuist clean dependencies` cleaning also the `Tuist/Dependencies/Lockfiles` folder [#4646](https://github.com/tuist/tuist/pull/4646) by [@danyf90](https://github.com/danyf90)

## 3.8.0 - 2022-07-03

### Changed

- Retry failed remote cache request once on error [#4569](https://github.com/tuist/tuist/pull/4569) by [@danyf90](https://github.com/danyf90)

### Added

- Support for not generating Info.plist [#4566](https://github.com/tuist/tuist/pull/4566) by [@danyf90](https://github.com/danyf90)
- Support for custom remote plugins location [#4586](https://github.com/tuist/tuist/pull/4586) by [@danyf90](https://github.com/danyf90)

### Fixed

- Fix dispatcher error printed when command execution is short (for example, `tuist version`) [#4565](https://github.com/tuist/tuist/pull/4565) by [@danyf90](https://github.com/danyf90)
- Delete old tuistenv when updating [#4579](https://github.com/tuist/tuist/pull/4579) by [@ezraberch](https://github.com/ezraberch)
- Fetch remote plugins when loading them [#4587](https://github.com/tuist/tuist/pull/4587) by [@danyf90](https://github.com/danyf90)
- Fix resource bundle signing error when archiving with Xcode 14 beta [#4588](https://github.com/tuist/tuist/pull/4588) by [@kwridan](https://github.com/kwridan)

## 3.7.0 - 2022-06-19

### Changed

- Update target resource name [#4542](https://github.com/tuist/tuist/pull/4542) by [@wangjiejacques](https://github.com/wangjiejacques)

### Added

- Send cache hit rate analytics for cache warm command [#4519](https://github.com/tuist/tuist/pull/4519) by [@fortmarek](https://github.com/fortmarek)

### Fixed

- Fix `tuist fetch` for dependencies when using Xcode 14 [#4543](https://github.com/tuist/tuist/pull/4543) by [@danyf90](https://github.com/danyf90)
- Improve cache errors logging [#4555](https://github.com/tuist/tuist/pull/4555) by [@danyf90](https://github.com/danyf90)

## 3.6.0 - 2022-06-11

### Fixed

- Wait for analytics to finish when on CI [#4506](https://github.com/tuist/tuist/pull/4506) by [@fortmarek](https://github.com/fortmarek)
- Fix check for `graphviz` availability when not installed through `brew` [#4516](https://github.com/tuist/tuist/pull/4516) by [@nagra](https://github.com/nagra)
- Fix handling of `--skip-external-dependencies` parameter in `tuist graph` command when `--format json` is specified [#4517](https://github.com/tuist/tuist/pull/4517) by [@GermanVelibekovHouzz](https://github.com/GermanVelibekovHouzz)
- Fix crash during `tuist cache warm` when cloud is configured and a lot of targets are present in the project [#4533](https://github.com/tuist/tuist/pull/4533) by [@danyf90](https://github.com/danyf90)
- Fix XCConfig path for swift package dependencies [#4536](https://github.com/tuist/tuist/pull/4536) by [@shahzadmajeed](https://github.com/shahzadmajeed)
- Fix default resources warnings for local packages [#4530](https://github.com/tuist/tuist/pull/4530) by [@danyf90](https://github.com/danyf90)

## 3.5.0 - 2022-05-29

### Changed

- Avoid generated file name conflicts by prepending Tuist to them [#4478](https://github.com/tuist/tuist/pull/4478) by [@danyf90](https://github.com/danyf90)

### Added

- Feature: Add four new SettingsTransformers [#4427](https://github.com/tuist/tuist/pull/4427) by [@dogo](https://github.com/dogo)
- Support for custom Project.Options for swift packages in Dependencies.swift [#4487](https://github.com/tuist/tuist/pull/4487) by [@shahzadmajeed](https://github.com/shahzadmajeed)

### Fixed

- Fix `selectedLauncherIdentifier` when `attachDebug` is false in `LaunchAction` and `TestAction` [#4458](https://github.com/tuist/tuist/pull/4458) by [@Andrea-Scuderi](https://github.com/Andrea-Scuderi)
- Fix for importing `Firebase 9.x` though `SwiftPackageManger` in `Dependencies.swift` [#4456](https://github.com/tuist/tuist/pull/4456) by [@danyf90](https://github.com/danyf90)
- Fixed rendering of generated `Info.plist` in Xcode [#4493](https://github.com/tuist/tuist/pull/4493) by [@mikchmie](https://github.com/mikchmie)
- Avoid pruning schemes with test plans [#4495](https://github.com/tuist/tuist/pull/4495) by [@danyf90](https://github.com/danyf90)
- Fix showing cloud errors [#4480](https://github.com/tuist/tuist/pull/4480) by [@fortmarek](https://github.com/fortmarek)
- Generate Package.swift with correct format when custom swift version is specified [#4503](https://github.com/tuist/tuist/pull/4503) by [@danyf90](https://github.com/danyf90)

## 3.4.0 - 2022-05-14

### Changed

- Make `TargetReference` conform to `Hashable` [#4407](https://github.com/tuist/tuist/pull/4407) by [@danyf90](https://github.com/danyf90)
- Defer the display of warnings until after project generation [#4387](https://github.com/tuist/tuist/pull/4387) by [@nicholaskim94](https://github.com/nicholaskim94)

### Added

- Support for watchOS UI test targets [#4389](https://github.com/tuist/tuist/pull/4389) by [@Smponias](https://github.com/Smponias)
- Add support for automatic resources in SwiftPackageManager [#4413](https://github.com/tuist/tuist/pull/4413) by [@danyf90](https://github.com/danyf90)
- Add attachDebugger parameter to TestAction.testPlans(...) [#4425](https://github.com/tuist/tuist/pull/4425) by [@Andrea-Scuderi](https://github.com/Andrea-Scuderi)
- Add local Tuist plugin to `tuist init` generated project [#4388](https://github.com/tuist/tuist/pull/4388) by [@leszko11](https://github.com/leszko11)
- Send cache targets hits analytics metadata [#4429](https://github.com/tuist/tuist/pull/4429) by [@fortmarek](https://github.com/fortmarek)

### Fixed

- Fix resource mapping when target name contains hyphens [#4400](https://github.com/tuist/tuist/pull/4400) by [@mangofever](https://github.com/mangofever)
- Fix xcframework import when framework name is different from xcframework name [#4401](https://github.com/tuist/tuist/pull/4401) by [@AlbGarciam](https://github.com/AlbGarciam)
- Allow AppClips to link Static Frameworks [#4420](https://github.com/tuist/tuist/pull/4420) by [@regularberry](https://github.com/regularberry)
- Fix zipping and unzipping cached frameworks with symlinks [#4355](https://github.com/tuist/tuist/pull/4355) by [@fortmarek](https://github.com/fortmarek)
- Fix: swap comments inside generated resources finder file [#4441](https://github.com/tuist/tuist/pull/4441) by [@GermanVelibekovHouzz](https://github.com/GermanVelibekovHouzz)

## 3.3.0 - 2022-04-26

### Added

- Add support for enabling markdown rendering in `Workspace.swift` for README files [#4373](https://github.com/tuist/tuist/pull/4373) by [@jesus-mg-ios](https://github.com/jesus-mg-ios)
- Sending the whole command to tuist analytics [#4383](https://github.com/tuist/tuist/pull/4383) by [@fortmarek](https://github.com/fortmarek)

### Fixed

- Fix support for frameworks as dependency of tvOS frameworks [#4184](https://github.com/tuist/tuist/pull/4184) by [@zdnk](https://github.com/zdnk)
- Fix for mapping excluding of single SwiftPackageManager resources [#4368](https://github.com/tuist/tuist/pull/4368) by [@danyf90](https://github.com/danyf90)

## 3.2.0 - 2022-04-11

### Changed

- Disable autogenerated schemes for SwiftPackageManager dependencies. Configure schemes from your `Project.swift` or from Xcode in case you need them [#4282](https://github.com/tuist/tuist/pull/4282) by [@danyf90](https://github.com/danyf90)

### Fixed

- Fix SwiftPackageManager dependencies mapping when it supports Mac Catalyst [#4309](https://github.com/tuist/tuist/pull/4309) by [@danyf90](https://github.com/danyf90)
- Fix importing `ViewInspector` from `Dependencies.swift` [#4323](https://github.com/tuist/tuist/pull/4323) by [@unxavi](https://github.com/unxavi)
- Fix for duplicated settings (for example, `-Xcc`) incorrectly removed [#4325](https://github.com/tuist/tuist/pull/4325) by [@a-sarris](https://github.com/a-sarris)
- Fix for missing source files when file extension is not lowercase [#4343](https://github.com/tuist/tuist/pull/4343) by [@ffittschen](https://github.com/ffittschen)

## 3.1.0 - 2022-03-28

### Added

- Add `.optional` option to `.cloud` [#4262](https://github.com/tuist/tuist/pull/4262) by [@fortmarek](https://github.com/fortmarek)

### Fixed

- Fix linking of staticFramework in messagesExtensions [#4211](https://github.com/tuist/tuist/pull/4211) by [@paulsamuels](https://github.com/paulsamuels)
- Fix ignored Workspace generation when Project exists on the same directory [#4236](https://github.com/tuist/tuist/pull/4236) by [@adellibovi](https://github.com/adellibovi)
- Fix for incorrect bundle when using generated resource accessors [#4258](https://github.com/tuist/tuist/pull/4258) by [@kwridan](https://github.com/kwridan)
- Fix generating project with custom configurations (other than Debug and Release) via SPM packages [#4259](https://github.com/tuist/tuist/pull/4259) by [@mstfy](https://github.com/mstfy)

## 3.0.1 - Bravissimo

### Added

- Add `marketingVersion(_ version:)` to SettingsDictionary extension to set `MARKETING_VERSION` in Build Settings. [#4194](https://github.com/tuist/tuist/pull/4194) by [@dogo](https://github.com/dogo)
- Add `debugInformationFormat(_ format:)` to SettingsDictionary extension to set `DEBUG_INFORMATION_FORMAT` in Build Settings. [#4194](https://github.com/tuist/tuist/pull/4194) by [@dogo](https://github.com/dogo)

### Fixed

- Fix linking of transitive precompiled static frameworks [#4200](https://github.com/tuist/tuist/pull/4200) by [danyf90](https://github.com/danyf90), [kwridan](https://github.com/kwridan), [adellibovi](https://github.com/adellibovi).
- Fix `Tuist.graph()` command in `ProjectAutomation` [#4204](https://github.com/tuist/tuist/pull/4204) by [@fortmarek](https://github.com/fortmarek)

## 3.0.0 - Bravo

### Changed

- **Breaking** Tuist plugins 2.0 [#3492](https://github.com/tuist/tuist/pull/3492) by [@fortmarek](https://github.com/fortmarek)
- **Breaking** `tuist generate` automatically opens the generated project. [#3912](https://github.com/tuist/tuist/pull/3912) by [@danyf90](https://github.com/danyf90):
- **Motivation:**: Most of the times you want to open the project after generating it.
- **Migration:** If you need to generate the project without opening it, just pass `--no-open` to `tuist generate`.
- **Breaking** add `type` parameter to `TargetDependency.sdk` [#3961](https://github.com/tuist/tuist/pull/3961) by [@danyf90](https://github.com/danyf90)
- **Migration:** Add the `type` parameter where defining `sdk` target dependencies and remove both the extension and the `lib` prefix from the name
- **Breaking** move `disableBundleAccessors` and `disableSynthesizedResourceAccessors` from `Config.swift` to `Project.ProjectOption` [#3963](https://github.com/tuist/tuist/pull/3963) by [@danyf90](https://github.com/danyf90).
- **Motivation**: Being able to define the option at the project level
- **Migration**: Move the `disableBundleAccessors` and `disableSynthesizedResourceAccessors` from `Config.swift` to `Project.ProjectOption`
- **Breaking** replace `SourceFileGlob` initializer with static `.glob` method [#3960](https://github.com/tuist/tuist/pull/3960) by [@danyf90](https://github.com/danyf90)
- **Migration:** Use the `.glob` method instead of the initializer
- **Breaking** minimum Xcode version and macOS version are Xcode 13.0 and macOS 12.0 [#4030](https://github.com/tuist/tuist/pull/4030) by [@adellibovi](https://github.com/adellibovi)
- **Motivation:** Old versions usage is less then 5%.
- **Breaking** `TargetScript.Script` cases `.tool(_ path: String, _ args: [String])` and `.scriptPath(_ path: Path, args: [String])` are now `.tool(path: String, args: [String])` and `.scriptPath(path: Path, args: [String])` [#4030](https://github.com/tuist/tuist/pull/4030) by [@adellibovi](https://github.com/adellibovi)
- **Motivation:** It enabled to get rid of custom Codable conformance.
- **Breaking** the used tuist version and the manifests compilation times are no longer printed at default log level. Use the `--verbose` flag to print them. [#4052](https://github.com/tuist/tuist/pull/4052) by [@danyf90](https://github.com/danyf90)
- **Breaking** rename `*-Project*` autogenerated schemes to `*-Workspace*` [#4089](https://github.com/tuist/tuist/pull/4089) by [@danyf90](https://github.com/danyf90)
- **Motivation**: The schemes are referred to the whole workspace, not to a specific project
- **Migration**: Use the `*-Workspace*` scheme instead
- **Breaking** move `Config.GenerationOptions.autogeneratedSchemes` and `Config.GenerationOptions.enableCodeCoverage` options to `Workspace.GenerationOption.autogeneratedWorkspaceSchemes`
- **Motivation**: They control workspace level options, so they are better suited in the workspace manifest
- **Breaking** change automatic schemes generation to use `ProjectOption.AutomaticSchemesGrouping.byName` grouping
- **Motivation**: Generated schemes now groups targets together better, reducing the number of generated schemes
- **Migration**: If the new default don't fit your needs, manually generate your schemes or try another `ProjectOption.AutomaticSchemesGrouping` option
- **Breaking** refactor `Project.options` to be a `struct` instead of an `enum` [#4104](https://github.com/tuist/tuist/pull/4104) by [@danyf90](https://github.com/danyf90)
- **Motivation**: A struct better represents the semantic of the type
- **Breaking** refactor `Config.generationOptions` to be a `struct` instead of an `enum` [#4109](https://github.com/tuist/tuist/pull/4109) by [@danyf90](https://github.com/danyf90)
- **Motivation**: A struct better represents the semantic of the type
- **Breaking** remove `xcodeProjectName`, `organizationName`, and `developmentRegion` from `Config.GenerationOptions` [#4131](https://github.com/tuist/tuist/pull/4131) by [@danyf90](https://github.com/danyf90)
- **Migration**: Configure them in `Project` instead or define helpers to share the value across projects
- **Breaking** move `Config.GenerationOptions.disableShowEnvironmentVarsInScriptPhases` to `Project.Options` [#4131](https://github.com/tuist/tuist/pull/4131) by [@danyf90](https://github.com/danyf90)
- **Motivation**: It is related to the project generation
- **Migration**: Configure it in `Project.Options` instead
- **Breaking** move `Config.GenerationOptions.lastXcodeUpgradeCheck` to `Workspace.GenerationOptions` [#4131](https://github.com/tuist/tuist/pull/4131) by [@danyf90](https://github.com/danyf90)
- **Motivation**: It is related to the workspace generation
- **Migration**: Configure it in `Worksapace.GenerrationOptions` instead
- Add support for configuring code coverage and testing options at the project level [#4090](https://github.com/tuist/tuist/pull/4090) by [@danyf90](https://github.com/danyf90)
- Add more detailed messaging for errors during manifest loading [#4076](https://github.com/tuist/tuist/pull/4076) by [@luispadron](https://github.com/luispadron)
- Deprecate legacy SPM support via Project.packages [#4112](https://github.com/tuist/tuist/pull/4112) by [@danyf90](https://github.com/danyf90)
- Improve performance of `tuist generate` when cache is used [#4146](https://github.com/tuist/tuist/pull/4146) by [@adellibovi](https://github.com/adellibovi)

### Removed

- **Breaking** remove `focus` command and merge its functionality inside `generate`. [#3912](https://github.com/tuist/tuist/pull/3912) by [@danyf90](https://github.com/danyf90):
- **Motivation:**: The command were sharing a lot of responsibilities, and having a single one provides a cleaner CLI.
- **Migration:** Instead of using focus, just use `generate` passing the targets to it. If you want to avoid using caching, you can pass `--no-cache` to `tuist generate`.
- **Breaking** remove the `tuist lint code` command [#4001](https://github.com/tuist/tuist/pull/4001) by [@laxmorek](https://github.com/laxmorek)
- **Migration:** Use the [swiftlint plugin](https://github.com/tuist/tuist-plugin-swiftlint) instead. Read more about plugins [here](https://docs.tuist.io/plugins/using-plugins).
- **Breaking** remove the `tuist lint project` command [#4001](https://github.com/tuist/tuist/pull/4001) by [@laxmorek](https://github.com/laxmorek)
- **Motivation:** `tuist` manifests/graphs are linted during generation (the `tusit generate` command), no need to keep it separately.
- **Breaking** remove deprecated initializers for `FileLists`, `Headers`, and `HTTPURLResponse` [#3936](https://github.com/tuist/tuist/pull/3936) by [@danyf90](https://github.com/danyf90)
- **Migration:** Use non deprecated initializers

### Fixed

- Fix dependencies not fetching using Swift Package Manager 5.6 [#4078](https://github.com/tuist/tuist/pull/4078) by [mikchmie](https://github.com/mikchmie)
- Fix clean `tuist test` for project with resources [#4091](https://github.com/tuist/tuist/pull/4091) by [@adellibovi](https://github.com/adellibovi)
- Fix `tuist graph --skip-external-dependencies` for `Dependencies.swift` dependencies [#4115](https://github.com/tuist/tuist/pull/4115) by [@danyf90](https://github.com/danyf90) & [#4124](https://github.com/tuist/tuist/pull/4124) by [@laxmorek](https://github.com/laxmorek)
- Fix `envversion` command not printing the tuist env version [#4126](https://github.com/tuist/tuist/pull/4126) by [@takinwande](https://github.com/takinwande)
- Fix warning when importing `ProjectDescription` during `tuist edit`. It was caused by `.swiftsourceinfo` files  being added to the release artifact [#4132](https://github.com/tuist/tuist/pull/4132) by [@luispadron](https://github.com/luispadron)
- Remove default MacCatalyst support when framework deployment target is set to iOS and/or iPad [#4134](https://github.com/tuist/tuist/pull/4134) by [@TheInkedEngineer](https://github.com/TheInkedEngineer)
- Fix loading of external dependencies in nested projects [#4157](https://github.com/tuist/tuist/pull/4157) by [@alexanderwe](https://github.com/alexanderwe)

### Added

- Add support for `umbrellaHeader` parameter to `Headers` to get list of public headers automatically. Also added new static functions in `Headers` for most popular cases with umbrella header [#3884](https://github.com/tuist/tuist/pull/3884) by [@pavel-trafimuk](https://github.com/pavel-trafimuk)
- Add `isExternal` property to `ProjectAutomation.Project` and `TuistGraph.Project` that indicates whether a project is imported through `Dependencies.swift`. [#4155](https://github.com/tuist/tuist/pull/4155) by [@laxmorek](https://github.com/laxmorek)
- Add `swiftOptimizeObjectLifetimes(_ enabled:)` to SettingsDictionary extension to set `SWIFT_OPTIMIZE_OBJECT_LIFETIME` in Build Settings. [#4171](https://github.com/tuist/tuist/pull/4171) by [@kyungpyoda](https://github.com/kyungpyoda)

## 2.7.2

- Fix download of binary artifacts from the remote cache [#4073](https://github.com/tuist/tuist/pull/4073) by [@adellibovi](https://github.com/adellibovi)

## 2.7.1

- Fix `tuistenv` not running `tuist` commands [#4061](https://github.com/tuist/tuist/pull/4061) by [@danyf90](https://github.com/danyf90)

## 2.7.0 - Cancun

### Changed

- Use GitHub tags (via `git ls-remote`) to determine the latest Tuist version when installing/updating Tuist [#3985](https://github.com/tuist/tuist/pull/3985) by [@ezraberch](https://github.com/ezraberch)

### Added

- Add support for `.docc` file types [#3982](https://github.com/tuist/tuist/pull/3982) by [@Jake Prickett](https://github.com/Jake-Prickett)
- Add a new test argument `--retry-count <number>` to retry failed tests <number> of times until success [#4021](https://github.com/tuist/tuist/pull/4021) by [@regularberry](https://github.com/regularberry)
- Add ability to specify as a command line argument, the Xcode version to use when bundling/releasing tuist and its libraries [#3957](https://github.com/tuist/tuist/pull/3957) by [@hisaac](https://github.com/hisaac)
- Add automatic mapping of product and settings for known SwiftPackageManager libraries [#3996](https://github.com/tuist/tuist/pull/3996) by [@danyf90](https://github.com/danyf90)

### Fixed

- Fix issue where test results were not being cached if a scheme was specified in the `tuist test` command [#3952](https://github.com/tuist/tuist/pull/3952) by [@hisaac](https://github.com/hisaac)
- Fix for target references within workspace scheme pre/post actions [#3954](https://github.com/tuist/tuist/pull/3954) by [@kwridan](https://github.com/kwridan)
- Fix SPM mapping for `GCC_PREPROCESSOR_DEFINITIONS` definitions [#3995](https://github.com/tuist/tuist/pull/3995) by [@adellibovi](https://github.com/adellibovi)
- Fix archiving iOS target for Mac Catalyst [#3990](https://github.com/tuist/tuist/pull/3990) by [@orbitekk](https://github.com/orbitekk)
- Fix mark libraries depending on XCTest through `ENABLE_TESTING_SEARCH_PATHS` setting as not cacheable [#4012](https://github.com/tuist/tuist/pull/4012) by [@danyf90](https://github.com/danyf90)
- Fix missing embedded dependencies in App Clip targets [#4033](https://github.com/tuist/tuist/pull/4033) by [@kwridan](https://github.com/kwridan)
- Fix `Dependencies.swift` not able to import plugins [4018](https://github.com/tuist/tuist/pull/4018/) by [@luispadron](https://github.com/luispadron)

## 2.6.0 - Havana

### Changed

- Remove duplicate bundle identifier lint warning [#3914](https://github.com/tuist/tuist/pull/3914) by [@danyf90](https://github.com/danyf90)
- Update version requirement for `swift-argument-parser` package from `.upToNextMajor(from: "0.4.3")` to `.upToNextMajor(from: "1.0.0")` [#3949](https://github.com/tuist/tuist/pull/3949) by [@laxmorek](https://github.com/laxmorek)

### Added

- Add logging when helpers modules are being built [#3913](https://github.com/tuist/tuist/pull/3913) by [@luispadron](https://github.com/luispadron)
- Document how to use the [Bitrise step](https://github.com/tuist/bitrise-step-tuist) [#3921](https://github.com/tuist/tuist/pull/3921) by [@pepicrft](https://github.com/pepicrft)
- Add `.exact`, `.upToNextMajor`, and `.upToNextMinor` options to CompatibleXcodeVersions [#3929](https://github.com/tuist/tuist/pull/3929) by [@ezraberch](https://github.com/ezraberch)

### Fixed

- Improve `tuist focus` execution time by avoiding redundant hashing for target dependencies [#3947](https://github.com/tuist/tuist/pull/3947) by [@adellibovi](https://github.com/adellibovi)
- Avoid building dependent test target when not needed during `tuist cache warm` [#3917](https://github.com/tuist/tuist/pull/3917) by [@danyf90](https://github.com/danyf90)
- Fix unit test failures when test host requires codesigning [#3924](https://github.com/tuist/tuist/pull/3924) by [@hisaac](https://github.com/hisaac)
- Fix circular dependency lint [#3876](https://github.com/tuist/tuist/pull/3876) by [@adellibovi](https://github.com/adellibovi)
- Fix Xcode developer SDK root path for watchOS platform [#3876](https://github.com/tuist/tuist/pull/3932) by [@orbitekk](https://github.com/orbitekk)
- Fix `tuist edit` compilation when building local helper modules that include remote plugins [#3918](https://github.com/tuist/tuist/pull/3918) by [@luispadron](https://github.com/luispadron)

## 2.5.0 - Gestalt

### Changed

- Update SwiftUI template [#3840](https://github.com/tuist/tuist/pull/3840) by [@ezraberch](https://github.com/ezraberch)
- Add `SWIFT_SUPPRESS_WARNINGS` setting to SwiftPackageManager generated project to suppress warnings from dependencies defined in Dependencies.swift [#3852](https://github.com/tuist/tuist/pull/3852) by [@wattson12](https://github.com/wattson12)

### Added

- Add support for `exclusionRule` parameter to `Headers` [#3793](https://github.com/tuist/tuist/pull/3793) by [@pavel-trafimuk](https://github.com/pavel-trafimuk)
- Add generation time for `tuist focus` command [#3872](https://github.com/tuist/tuist/pull/3872) by [@adellibovi](https://github.com/adellibovi)

### Fixed

- Fix shell completion script generated in directory containing `.tuist_version` file [#3804](https://github.com/tuist/tuist/pull/3804) by [@mikchmie](https://github.com/mikchmie)
- `tuist cache print-hashes` not working with relative paths [#3892](https://github.com/tuist/tuist/pull/3892) by [@erkekin](https://github.com/erkekin)
- Fix argument parsing errors handling in `tuistenv` [#3905](https://github.com/tuist/tuist/pull/3905) by [@pepicrft](https://github.com/pepicrft).
- Fix crash when running `tuist build` with `TUIST_CONFIG_VERBOSE=1` [#3752](https://github.com/tuist/tuist/pull/3752) by [@fortmarek](https://github.com/fortmarek)

## 2.4.0 - Lune

### Added

- Add support for `excluding` parameter to `FileList` [#3773](https://github.com/tuist/tuist/pull/3773) by [@pavel-trafimuk](https://github.com/pavel-trafimuk)
- Add ability to define `preActions` and `postActions` for `RunAction` and `ProfileAction` [#3787](https://github.com/tuist/tuist/pull/3787) by [@hisaac](https://github.com/hisaac)
- Add ability to control whether a debugger is attached to an app or test process by setting `attachDebugger` on `RunAction` or `TestAction`, respectively [#3813])https://github.com/tuist/tuist/pull/3813) by [@svenmuennich](https://github.com/svenmuennich/)
- Add support for generating the `WorkspaceSettings.xcsettings` file and explicitly disabling or enabling automatic schema generation. [#3832](https://github.com/tuist/tuist/pull/3832) by [@jakeatoms](https://github.com/jakeatoms)

### Fixed

- Fix default template to work with `tvos` platform [#3759](https://github.com/tuist/tuist/pull/3759) by [@ezraberch](https://github.com/ezraberch)
- Fix curl in the installer script so that it fails if unable to download the Tuist release assets. [#3803](https://github.com/tuist/tuist/pull/3803) by [@luispadron](https://github.com/luispadron)

## 2.3.2 - Discoteque

### Fixed

- Fixed persisting generated `Package.swift` and `Cartfile` [#3729](https://github.com/tuist/tuist/pull/3729) by [@thedavidharris](https://github.com/thedavidharris)
- Improve error message in case `ModuleMapMapper` fails to retrieve a dependency [#3733](https://github.com/tuist/tuist/pull/3733) by [@danyf90](https://github.com/danyf90)
- Fix resolution of external dependencies with products including binary targets [#3737](https://github.com/tuist/tuist/pull/3737) by [@danyf90](https://github.com/danyf90)

### Changed

- Update `swiftlint` to version `0.10.1` [#3744](https://github.com/tuist/tuist/pull/3744) by [@pepibumur](https://github.com/pepibumur)
- Update `xcprettify` to version `0.45.0` [#3744](https://github.com/tuist/tuist/pull/3744) by [@pepibumur](https://github.com/pepibumur)

### Added

- Add `uiTests` target support for `tvOS`. [#3756](https://github.com/tuist/tuist/pull/3756) by [@sujata23](https://github.com/sujata23)
- Added ability to control `parallelizable` and `randomExecutionOrdering` for autogenerated test targets [#3755](https://github.com/tuist/tuist/pull/3755) by [@wattson12](https://github.com/wattson12)

## 2.3.1 - Avantgarde

### Fixed

- Fix release process to make Tuist compatible again with Xcode 12.5 and above [#3731](https://github.com/tuist/tuist/pull/3731) by [@mikchmie](https://github.com/mikchmie)

## 2.3.0 - Bender

### Changed

- Focus on project targets when no targets are passed to `tuist focus` [#3654](https://github.com/tuist/tuist/pull/3654) by [@danyf90](https://github.com/danyf90)
- Make the `cache warm` command significantly faster by avoid recompiling already in-cache dependency targets [#3585](https://github.com/tuist/tuist/pull/3585) by [@danyf90](https://github.com/danyf90)
- Allow overriding `SWIFT_VERSION` [#3644](https://github.com/tuist/tuist/pull/3666) by [@kwridan](https://github.com/kwridan)
- The `SWIFT_VERSION` build setting is now part of the `.essential` [`DefaultSettings`](https://docs.tuist.io/manifests/project#defaultsettings)
- This aligns its behavior with the rest of the default settings, and allows excluding it if necessary via:
- Specifying `DefaultSettings.none` for cases where `xcconfig` files are used to control all build settings
- Explicitly excluding it via:
- `DefaultSettings.recommended(excluding: ["SWIFT_VERSION])`
- `DefaultSettings.essential(excluding: ["SWIFT_VERSION])`
- Additionally for convenience, Tuist will not set a `SWIFT_VERSION` target level setting if a project level setting already exists for it

### Added

- Add support for base settings for SwiftPackageManager generated targets. This allows to specify custom settings configurations. [#3683](https://github.com/tuist/tuist/pull/3683) by [@danyf90](https://github.com/danyf90)
- Test targets in autogenerated scheme updated to run in parallel [#3682](https://github.com/tuist/tuist/pull/3682) by [@wattson12](https://github.com/wattson12)

### Fixed

- Fixed caching of targets with `sdk` dependencies [#3681](https://github.com/tuist/tuist/pull/3681) by [@danyf90](https://github.com/danyf90)

## 2.2.1 - Weg

### Fixed

- Fixed compiled binary for older Xcode versions [#3675](https://github.com/tuist/tuist/pull/3675) by [@luispadron](https://github.com/luispadron)

## 2.2.0 - Jinotaj

### Changed

- **Breaking** Update logic to calculate deployment target for SwiftPackageManager packages not specifying it, and remove no longer used `SwiftPackageManagerDependencies.deploymentTargets` property [#3602](https://github.com/tuist/tuist/pull/3602) by [@danyf90](https://github.com/danyf90)
- **Breaking** Update logic to calculate client ID starting from UUID instead of hostname, to avoid collisions [#3632](https://github.com/tuist/tuist/pull/3632) by [@danyf90](https://github.com/danyf90)
- **Breaking** Removed value for `ENABLE_TESTING_SEARCH_PATHS` in SPM dependencies. If a target requires a non-default value, you can set it using the `targetSettings` property in the `Dependencies.swift` file [#3632](https://github.com/tuist/tuist/pull/3653) by [@wattson12](https://github.com/wattson12)
- `Target`'s initializer now has `InfoPlist.default` set as the default value for the `infoPlist` argument [#3644](https://github.com/tuist/tuist/pull/3644) by [@hisaac](https://github.com/hisaac)

### Added

- Schemes can be hidden from the dropdown menu `Scheme(hidden: true)` [#3598](https://github.com/tuist/tuist/pull/3598) by [@pepibumur](https://github.com/pepibumur)
- Sort schemes alphabetically by default [#3598](https://github.com/tuist/tuist/pull/3598) by [@pepibumur](https://github.com/pepibumur)
- Add automation to release [#3603](https://github.com/tuist/tuist/pull/3603) by [@luispadron](https://github.com/luispadron)
- Support for `json` format in `graph` command [#3617](https://github.com/tuist/tuist/pull/3617) by [@neakor](https://github.com/neakor)
- Persist generated `Package.swift` and `Cartfile` [#3661](https://github.com/tuist/tuist/pull/3661) by [@thedavidharris](https://github.com/thedavidharris)

### Fixed

- Fix handling of `TUIST_CONFIG_COLOURED_OUTPUT` environment variable [#3631](https://github.com/tuist/tuist/pull/3631) by [@danyf90](https://github.com/danyf90)
- Fix `tuist dump config` no longer requires to be executed inside the `Tuist` folder [#3647](https://github.com/tuist/tuist/pull/3647) by [@danyf90](https://github.com/danyf90)

## 2.1.1 - Patenipat

### Fixed

- Fix SwiftPackageManager dependencies mapping when the dependency contains nested umbrella header [#3588](https://github.com/tuist/tuist/pull/3588) by [@danyf90](https://github.com/danyf90)
- Revert [Swift Package Manager default resource handling](https://github.com/tuist/tuist/pull/3594) [#3594](https://github.com/tuist/tuist/pull/3594) by [@danyf90](https://github.com/danyf90)

## 2.1.0 - Coloratura

### Changed

- Use cache version instead of Tuist version in target hash calculation [#3554](https://github.com/tuist/tuist/pull/3554) by [@danyf90](https://github.com/danyf90)
- Perform remote cache download and upload concurrently [#3549](https://github.com/tuist/tuist/pull/3549) by [@danyf90](https://github.com/danyf90)

### Added

- Add `analytics` option to `Config.Cloud` to enable sending analytics event to cloud backend [#3547](https://github.com/tuist/tuist/pull/3547) by [@danyf90](https://github.com/danyf90)
- Add optional `manifest` argument to `tuist dump` command, to allow to dump other kinds of manifests [#3551](https://github.com/tuist/tuist/pull/3551) by [@danyf90](https://github.com/danyf90)
- Add device and os options to caching profiles [#3546](https://github.com/tuist/tuist/pull/3546) by [@mollyIV](https://github.com/mollyIV)
- Add support for configuring the `LastUpgradeCheck` of the `Xcode` project [#3561](https://github.com/tuist/tuist/pull/3561) by [@mollyIV](https://github.com/mollyIV)
- Add arbitrarily high `LastUpgradeCheck` to SwiftPackageManager generated projects to disable warnings [#3569](https://github.com/tuist/tuist/pull/3569) by [@danyf90](https://github.com/danyf90)
- Add `isCI` parameter to analytics events [#3568](https://github.com/tuist/tuist/pull/3568) by [@mollyIV](https://github.com/mollyIV)
- Add Files Resource Synthesizer [#3584](https://github.com/tuist/tuist/pull/3584) by [@mollyIV](https://github.com/mollyIV)
- Add support for additional files at the target level [#3579](https://github.com/tuist/tuist/pull/3579) by [@danyf90](https://github.com/danyf90)

### Fixed

- Fix a focused project issue for which when focusing a tests target, cached resources are not linked to it. [#3571](https://github.com/tuist/tuist/pull/3571) by [@fila95](https://github.com/fila95)
- Fix target caching resources linking for extensions. They are now considered `runnable` targrts (which they are) [#3570](https://github.com/tuist/tuist/pull/3570) by [@fila95](https://github.com/fila95)
- Fix the way a target is known to be supporting resources, excluding `.commandLineTool`s. [#3572](https://github.com/tuist/tuist/pull/3572) by [@fila95](https://github.com/fila95)
- Fix Swift Package Manager default resource handling [#3295](https://github.com/tuist/tuist/pull/3295) by [@mstfy](https://github.com/mstfy)
- If present, use coloured output configuration from environment even if it's false [#3550](https://github.com/tuist/tuist/pull/3550) by [@danyf90](https://github.com/danyf90)
- Fix `tuist generate` performance regression [#3562](https://github.com/tuist/tuist/pull/3562) by [@adellibovi](https://github.com/adellibovi)
- Fix SwiftPackageManager dependencies mapping when the dependency contains nested umbrella header [#3588](https://github.com/tuist/tuist/pull/3588) by [@danyf90](https://github.com/danyf90)

### Removed

- Removed unused `Cloud.Option.insights` case [#3547](https://github.com/tuist/tuist/pull/3547) by [@danyf90](https://github.com/danyf90)

## 2.0.2 - Wald

### Fixed

- Fix caching of targets with module map [#3528](https://github.com/tuist/tuist/pull/3528) by [@danyf90](https://github.com/danyf90)
- Fix SwiftPackageManager local xcframework mapping [#3533](https://github.com/tuist/tuist/pull/3533) by [@danyf90](https://github.com/danyf90)
- Fix mapping of SwiftPackageManager dependencies using alternative default source folders [#3532](https://github.com/tuist/tuist/pull/3532) by [@danyf90](https://github.com/danyf90)

## 2.0.1 - Tarifa

### Fixed

- Fix manifest cache, enabled by default [#3530](https://github.com/tuist/tuist/pull/3530) by [@adellibovi](https://github.com/adellibovi)

## 2.0.0 - Ikigai

### Changed

- **Breaking** made constructors from scheme action models internal and exposed static methods for initializing them instead. For example, `TestAction.init(..)` becomes `TestAction.testAction(...)`. [#3400](https://github.com/tuist/tuist/pull/3400) by [@pepibumur](https://github.com/pepibumur):
- **Motivation:**: Using static initializers gives us the flexibility to introduce improvements without breaking the API.
- **Migration:** Update all the action initializers to use the static methods instead. The name of the static method matches the name of the class but starting with a lowercase.
- **Breaking** `tuist focus` no longer includes automatically related tests and bundle targets as sources. [#3501](https://github.com/tuist/tuist/pull/3501) by [@danyf90](https://github.com/danyf90).
- **Motivation:** the behavior might cause to include unwanted targets in some scenario
- **Migration:** if you need to include tests and bundle targets as sources, specify them as arguments of the `tuist focus` command

### Removed

- **Breaking** `.cocoapods` target dependency
- **Motivation:** `.cocoapods`'s API led users to believe their integration issues were Tuist's fault. Therefore we decided to remove it and make it an explicit action developers need to run after the generation of Xcode projects through Tuist.
- **Migration:** we recommend wrapping the the generation of projects in a script that runs `pod install` right after generating the project: `tuist generate && pod install`. Alternatively, you might consider adopting Swift Package Manager and using our built-in support for package dependencies through the `Dependencies.swift` manifes tfile.
- **Breaking** Support for deprecated `TuistConfig.swift` has been ended. Define your configuration using `Config.swift`. Check [documentation](https://docs.tuist.io/manifests/config) for details. [#3373](https://github.com/tuist/tuist/pull/3373) by [@laxmorek](https://github.com/laxmorek)
- **Breaking** Support for deprecated `Template.swift` has been ended. Define your templates using any name that describes them (`name_of_template.swift`). Check [documentation](https://docs.tuist.io/commands/scaffold) for details. [#3373](https://github.com/tuist/tuist/pull/3373) by [@laxmorek](https://github.com/laxmorek)
- **Migration:** we recommend wrapping the generation of projects in a script that runs `pod install` right after generating the project: `tuist generate && pod install`. Alternatively, you might consider adopting Swift Package Manager and using our built-in support for package dependencies through the `Dependencies.swift` manifest file.
- **Breaking** simplified `TestAction`'s methods for creating an instance. [#3375](https://github.com/tuist/tuist/pull/3375) by [@pepibumur](https://github.com/pepibumur):
- **Motivation:** there was some redundancy across all the methods to initialize a `TestAction`. To ease its usage, we've simplified all of them into a single method. It takes the test plans as an array of `Path`s and the configuration as an instance of `PresetBuildConfiguration`. We've also made the `init` constructor internal to have the flexibility to change the signature without introducing breaking changes.
- **Migration:** In those places where you are initializing a `TestAction`, update the code to use either the `.testActions` or the `.targets` methods.
- **Breaking** removed the `tuist doc` command. [#3401](https://github.com/tuist/tuist/pull/3401) by [@pepibumur](https://github.com/pepibumur)
- **Motivation:** the command was barely used so we are removing it to reduce the maintenance burden and reduce the binary size.
- **Migration:** you can use Tuist tasks or [Fastlane](https://github.com/fastlane/fastlane) to run [swift-doc](https://github.com/SwiftDocOrg/swift-doc) and generate documentation from your generated projects.
- **Breaking** removed `PresetBuildConfiguration` in favour of `ConfigurationName`. [#3400](https://github.com/tuist/tuist/pull/3400) by [@pepibumur](https://github.com/pepibumur):
- **Motivation:** Making the configuration a type gives the developers the flexibility to provide their list of configurations through extensions. For example, `ConfigurationName.beta`.
- **Migration:** Scheme actions are now initialized passing a `configuration` argument of type `ConfigurationName`. Note that it conforms `ExpressibleByStringLiteral` so you can initialize it with a string literal.
- **Breaking** removed the `tuist up` command in favour of a sidecar CLI tool, [`tuist-up`](https://github.com/tuist/tuist-up) that can be installed independently.
- **Motivation:** provisioning environments for working with Xcode projects was outside of the scope of the project. Moreover, it added up to our triaging and maintenace work because errors that bubbled up from underlying commands made people think that they were Tuist bugs.
- **Migration:** as suggested [here](https://github.com/tuist/tuist-up), turn your `Setup.swift` into a `up.toml` and use `tuist-up` instead.
- **Breaking** Scheme `TestAction` options have been consolidated together under a new type `TestActionOptions`.
- **Motivation:** This makes the API consistent with some of the other Scheme actions as well as how it appears in the Scheme editor.
- **Migration:** Use `TestAction.targets(options: .options(language:region:codeCoverage:codeCoverageTargets))`
- `TestAction.language` > `TestActionOptions.language`
- `TestAction.region` > `TestActionOptions.region`
- `TestAction.codeCoverage` > `TestActionOptions.codeCoverage`
- `TestAction.codeCoverageTargets` > `TestActionOptions.codeCoverageTargets`
- **Breaking** removed deprecated `TUIST_*` configuration variables. [#3493](https://github.com/tuist/tuist/pull/3493) by [@danyf90](https://github.com/danyf90).
- **Motivation:**: They have been replaced by the corresponding `TUIST_CONFIG_*` variables instead.
- **Migration:** Use the corresponding `TUIST_CONFIG_*` variables instead.
- **Breaking** `Settings` is now publicly initialized via a new static method `.settings()`.
- **Motivation:** Using static initializers gives us the flexibility to introduce improvements without breaking the API.
- **Migration:** Replace `settings: Settings(base: ["setting": "value"])` with `settings: .settings(base: ["setting": "value"])`
- **Breaking** `CustomConfiguration` has been merged with `Configuration`.
- **Motivation:** Simplify the API and reduce confusion between `Configuration` and `CustomConfiguration`.
- **Migration:** Replace `let configurations: [CustomConfiguration] = [ ... ]` with `let configurations: [Configuration] = [ ... ]`.
- **Breaking** Specifying custom build settings files for default configurations via `Settings(base:debug:release:)` has changed.
- **Motivation:** To support the `CustomConfiguration` API simplification.
- **Breaking** Specifying xcconfig files for default configurations via `Settings(base:debug:release:)` has changed.
- **Motivation:** To support the `CustomConfiguration` API simplification.
- **Breaking** Rename target `actions` to `scripts` to align with Xcode's terminology [#3374](https://github.com/tuist/tuist/pull/3374) by [@pepibumur](https://github.com/pepibumur)
- **Motivation** To align with Xcode's terminology used for the build phase counterpart, `scripts`.

## 1.52.0 - Pelae

### Changed

- Update SwiftGen to support generating custom SF Symbols (a.k.a. `symbolset`). [#3521](https://github.com/tuist/tuist/pull/3521) by [@hisaac](https://github.com/hisaac)
- Improve performance of `tuist dependencies fetch` for SwiftPackageManager by loading Package.swift information in parallel. [#3529](https://github.com/tuist/tuist/pull/3529) by [@danyf90](https://github.com/danyf90)

### Added

- Add `CodeCoverageMode` to `Config` so targets for code coverage data gathering can be specified in autogenerated project scheme [#3267](https://github.com/tuist/tuist/pull/3267) by [@olejnjak](https://github.com/olejnjak)

## 1.51.1

### Added

- Add `name` parameter to remote cache API calls. [#3516](https://github.com/tuist/tuist/pull/3516) by [@danyf90](https://github.com/danyf90)

### Fixed

- Installation failing when intermediate files are present in `/tmp/` [#3502](https://github.com/tuist/tuist/pull/3502) by [@pepibumur](https://github.com/pepibumur)
- Fix SwiftPackageManager dependencies mapping on Xcode 13 [#3499](https://github.com/tuist/tuist/pull/3499) by [@danyf90](https://github.com/danyf90)
- Make cache hashes of SwiftPackageManager dependencies with modulemap independent from the absolute path of the project [#3505](https://github.com/tuist/tuist/pull/3505) by [@danyf90](https://github.com/danyf90).
- Fix SwiftPackageManager dependencies mapping on Xcode 13 [#3507](https://github.com/tuist/tuist/pull/3507) by [@danyf90](https://github.com/danyf90)
- Fix compilation on Xcode 13 by updating Xcodeproj [#3499](https://github.com/tuist/tuist/pull/3499) by [@danyf90](https://github.com/danyf90)
- Make `cache warm` fail if remote cache existence check throws [#3508](https://github.com/tuist/tuist/pull/3508) by [@danyf90](https://github.com/danyf90)

### Changed

- **Breaking** Minimum supported Xcode version for contributors bumped to 12.4. [#3499](https://github.com/tuist/tuist/pull/3499) by [@danyf90](https://github.com/danyf90)

## 1.51.0 - Switch

### Changed

- Improve performance of `tuist cache` avoiding to hit remote cache if not needed. [#3461](https://github.com/tuist/tuist/pull/3461) by [@danyf90](https://github.com/danyf90)
- Improve performance of `tuist cache warm` and `tusit focus` avoiding to compute hashes of targets not going to be cached. [#3464](https://github.com/tuist/tuist/pull/3464) by [@danyf90](https://github.com/danyf90)
- Improve performance of `tuist cache warm` when using remote cache by parallelizing the target cache checks [#3462](https://github.com/tuist/tuist/pull/3462) by [@bolismauro](https://github.com/bolismauro)
- Improve output of `tuist cache warm` command. [#3460](https://github.com/tuist/tuist/pull/3460) by [@danyf90](https://github.com/danyf90)
- Rename internal configuration environment variables to start with `TUIST_CONFIG_` instead of `TUIST_` and ignore them when calculating manifests hashes. The old ones are still read if first ones are not found, but they will be removed in 2.0 [#3479](https://github.com/tuist/tuist/3479) by [@danyf90](https://github.com/danyf90)

### Added

- Add support for `SourceFilesList.codeGen` property. [#3448](https://github.com/tuist/tuist/pull/3448) by [@pavm035](https://github.com/pavm035)
- Add more helpful output when `./fourier swift format` command fails. [#3451](https://github.com/tuist/tuist/pull/3451) by [@hisaac](https://github.com/hisaac)

### Fixed

- Add support for SPM dependencies with `.` and `-` in the target name. [#3449](https://github.com/tuist/tuist/3449) by [@moritzsternemann](https://github.com/moritzsternemann)
- Add swift version to the target hash computation. [#3455](https://github.com/tuist/tuist/3455) by [@danyf90](https://github.com/danyf90)
- Add tuist version to the target hash computation. [#3455](https://github.com/tuist/tuist/3455) by [@danyf90](https://github.com/danyf90)
- Fix unauthenticated cache exists responses interpreted as existing build artifact. [#3480](https://github.com/tuist/tuist/3480) by [@danyf90](https://github.com/danyf90)
- Fix `.tuistignore` not matching relative paths correctly [#3456](https://github.com/tuist/tuist/pull/3456) by [@danyf90](https://github.com/danyf90)

## 1.50.0 - Nature

### Changed

- **Breaking** Minimum supported Xcode version for contributors bumped to 12.4.
- Improve speed of `tuist edit` and improved automatic detection of editable manifests [#3416](https://github.com/tuist/tuist/pull/3416) by [@adellibovi](https://github.com/adellibovi).
- Improve speed of `tuist dependencies fetch` and `tuist dependencies update` by performing the dependencies resolution directly in the `Tuist/Dependencies` folder [#3417](https://github.com/tuist/tuist/pull/3417) by [@danyf90](https://github.com/danyf90).
- Improve speed of `tuist focus` and `tuist cache warm` with a targets list (i.e. `tuist focus frameworkX` and `tuist cache warm frameworkX`) by avoiding calculating hashes for non dependent targets [#3423](https://github.com/tuist/tuist/pull/3423) by [@adellibovi](https://github.com/adellibovi).
- Improve speed of `tuist generate` by updating Xcodeproj [#3444](https://github.com/tuist/tuist/pull/3444) by [@adellibovi](https://github.com/adellibovi).

### Fixed

- settings-to-xcconfig migration command produces correct string format. [#3260](https://github.com/tuist/tuist/3260) by [@saim80](https://github.com/saim80)
- Fix caching of manifests that use plugins [#3370](https://github.com/tuist/tuist/pull/3370) by [@luispadron](https://github.com/luispadron)

### Added

- Allow to pass Cloud authentication token via TUIST_CLOUD_TOKEN even when not CI [#3380](https://github.com/tuist/tuist/pull/3380) by [@danyf90](https://github.com/danyf90)
- Support for cache categories argument in `tuist clean` command [#3407](https://github.com/tuist/tuist/pull/3407) by [@danyf90](https://github.com/danyf90)
- Add `tuist dependencies clean` command [#3417](https://github.com/tuist/tuist/pull/3417) by [@danyf90](https://github.com/danyf90).
- Support for floating number (`real`) value for `InfoPlist` [#3377](https://github.com/tuist/tuist/pull/3377) by [@MarvinNazari](https://github.com/MarvinNazari)
- Support for `shellPath` parameter in `TargetAction` and `TargetScript` to enable `/bin/zsh` as shell. [#3384](https://github.com/tuist/tuist/pull/3384) by [@DarkoDamjanovic](https://github.com/DarkoDamjanovic)

## 1.49.2

### Fixed

- `tuistenv` failing to fetch the latest version from `CHANGELOG.md`

## 1.49.1

### Fixed

- `tuistenv` failing to fetch the latest version from `CHANGELOG.md`

## 1.49.0

### Added

- Add default `Release` caching profile [#3304](https://github.com/tuist/tuist/pull/3304) by [@danyf90](https://github.com/danyf90)
- Add `--dependencies-only` parameter to `tuist cache warm` command [#3334](https://github.com/tuist/tuist/pull/3334) by [@danyf90](https://github.com/danyf90)
- Add support for `excluding` parameter to `ResourceFileElement` [#3363](https://github.com/tuist/tuist/pull/3363) by [@danyf90](https://github.com/danyf90)

### Fixed

- Fix Dependency.swift binary path's with `path` instead of `url`. [#3269](https://github.com/tuist/tuist/pull/3269) by [@apps4everyone](https://github.com/apps4everyone)
- Fix mapping of SPM linker flags [#3276](https://github.com/tuist/tuist/pull/3276) by [@danyf90](https://github.com/danyf90)
- Fix adding `Carthage` dependencies to `Target` using `TargetDepedency.external` [#3300](https://github.com/tuist/tuist/pull/3300) by [@laxmorek](https://github.com/laxmorek)
- Fix for missing transitive precompiled static frameworks [#3296](https://github.com/tuist/tuist/pull/3296) by [@kwridan](https://github.com/kwridan)
- Fix unstable graph dependency reference sort [#3318](https://github.com/tuist/tuist/pull/3318) by [@kwridan](https://github.com/kwridan)
- Fix source glob not following directory symlinks [#3312](https://github.com/tuist/tuist/pull/3312)  by [@LorDisturbia](https://github.com/LorDisturbia).
- Fix for `./fourier bundle` command when `xcodeproj` or `xcworkspace` files are present [#3331](https://github.com/tuist/tuist/pull/3331) by [@danyf90](https://github.com/danyf90)
- Fix for filtering logic for caching dependencies to include dependencies of filtered non-cacheable targets [#3333](https://github.com/tuist/tuist/pull/3333) by [@adellibovi](https://github.com/adellibovi)
- Fix for importing Swift Package Manager binary targets from Dependency.swift [#3352](https://github.com/tuist/tuist/pull/3352) by [@danyf90](https://github.com/danyf90)
- Fix for the `tuist edit` command when the `Tuist/Dependencies` directory contains "manifest-like" files (`Project.swift` or `Plugin.swift`). [#3359](https://github.com/tuist/tuist/pull/3359) by [@laxmorek](https://github.com/laxmorek)

### Changed

- Get the latest available version from GitHub releases instead of the Google Cloud Storage bucket [#3335](https://github.com/tuist/tuist/pull/3335) by [@pepibumur](https://github.com/pepibumur).
- The `install` script has been updated to pull the `tuistenv` binary from the latest GitHub release's assets [#3336](https://github.com/tuist/tuist/pull/3336) by [@pepibumur](https://github.com/pepibumur).
- Remove unneeded `BUILD_LIBRARY_FOR_DISTRIBUTION` setting when building `xcframework` for cache [#3344](https://github.com/tuist/tuist/pull/3344) by [@danyf90](https://github.com/danyf90).

## 1.48.1

### Changed

- The installation of Tuist versions pulls the binaries from the GitHub releases [#3255](https://github.com/tuist/tuist/pull/3255) by [@pepibumur](https://github.com/pepibumur).

### Fixed

- Fixed text settings docs [#3288](https://github.com/tuist/tuist/pull/3288) by [@DimaMishchenko](https://github.com/DimaMishchenko)
- Fix .xcFramework breaking change [#3289](https://github.com/tuist/tuist/pull/3289) by [@kwridan](https://github.com/kwridan)

## 1.48.0 - Packer

### Added

- Support for `Swift Package Manager` in `Dependencies.swift` [#3072](https://github.com/tuist/tuist/pull/3072) by [@danyf90](https://github.com/danyf90)
- Add `cc` as a valid source extension [#3273](https://github.com/tuist/tuist/pull/3273) by [@danyf90](https://github.com/danyf90)
- Add support for localized intent definition files using `.strings`. [#3236](https://github.com/tuist/tuist/pull/3236) by [@dbarden](https://github.com/dbarden)
- Add `TextSettings` configuration into `Project` [#3253](https://github.com/tuist/tuist/pull/3253) by [@DimaMishchenko](https://github.com/DimaMishchenko)
- Add `language` option for `RunAction`, add `SchemeLanguage` [#3231](https://github.com/tuist/tuist/pull/3231) by [@zzzkk](https://github.com/zzzkk)
- Include instructions to create an GitHub issue for unhandled errors [#3278](https://github.com/tuist/tuist/pull/3278) by [@pepibumur](https://github.com/pepibumur).

### Fixed

- Build file of dependencies having the wrong platform filter in iOS targets with Catalyst enabled [#3152](https://github.com/tuist/tuist/pull/3152) by [@pepibumur](https://github.com/pepibumur) and [@sampettersson](https://github.com/sampettersson).

## 1.47.0 - Mirror

### Added

- Caching for static frameworks with resources [#3090](https://github.com/tuist/tuist/pull/3090) by [@mstfy](https://github.com/mstfy)
- Meta tuist support [#3103](https://github.com/tuist/tuist/pull/3103) by [@fortmarek](https://github.com/fortmarek)
- Add `--result-bundle-path` parameter to test command [#3177](https://github.com/tuist/tuist/pull/3177) by [@olejnjak](https://github.com/olejnjak)
- The `tuist dependencies` command prints dependency managers' output to console. [#3185](https://github.com/tuist/tuist/pull/3185) by [@laxmorek](https://github.com/laxmorek)
- CI check to ensure lockfiles are consistent [#3208](https://github.com/tuist/tuist/pull/3208) by by [@pepibumur](https://github.com/pepibumur).

### Removed

- **Breaking** Remove `tuist create-issue` command [#3194](https://github.com/tuist/tuist/pull/3194) by [@pepibumur](https://github.com/pepibumur).
- **Breaking** Remove `tuist secret` command [#3194](https://github.com/tuist/tuist/pull/3194) by [@pepibumur](https://github.com/pepibumur).

### Changed

- Remove the `sudo` requirement for the install and uninstall scripts. [#3056](https://github.com/tuist/tuist/pull/3056) by [@luispadron](https://github.com/luispadron).

### Fixed

- Editing projects in development [#3199](https://github.com/tuist/tuist/pull/3199) by [@pepibumur](https://github.com/pepibumur).

## 1.46.1

### Fixed

- Fix failed `tuist dependencies fetch/update` command when `Carthage` dependency is imported as binary [#3164](https://github.com/tuist/tuist/pull/3164) by [@havebenfitz](https://github.com/havebeenfitz)

## 1.46.0 - Emeuno

### Added

- Native support for ARM architecture [#3010](https://github.com/tuist/tuist/pull/3010) by [@fortmarek](https://github.com/fortmarek) & [@pepibumur](https://github.com/pepibumur).
- Utility for obtaining the system's Git credentials for authenticating with [#3110](https://github.com/tuist/tuist/pull/3110) by [@pepibumur](https://github.com/pepibumur).
- `GitHubClient` to interact with GitHub's API [#3144](https://github.com/tuist/tuist/pull/3144) by [@pepibumur](https://github.com/pepibumur).

### Changed

- **Breaking** Minimum supported Xcode version bumped to 12.2.

## 1.45.1

### Fixed

- Throw error when target given in `tuist focus` is not found. [#3104](https://github.com/tuist/tuist/pull/3104) by [@fortmarek](https://github.com/fortmarek)
- Fixed an issue that the `tuist dependencies` command may fails for some `Carthage` dependencies. [#3108](https://github.com/tuist/tuist/pull/3108) by [@laxmorek](https://github.com/laxmorek)

## 1.45.0 - Jungle

### Added

- Add `tvTopShelfExtension` and `tvIntentsExtension` target product. [#2793](https://github.com/tuist/tuist/pull/2793) by [@rmnblm](https://github.com/rmnblm)
- The `tuist dependencies` command generates a `graph.json` file for the `Carthage` dependencies. [#3043](https://github.com/tuist/tuist/pull/3043) by [@laxmorek](https://github.com/laxmorek)
- Add --skip-ui-tests parameter to tuist test command [#2832](https://github.com/tuist/tuist/pull/2832) by [@mollyIV](https://github.com/mollyIV).
- Add `disableBundleAccessors` generation option which disables generating Bundle extensions [#3088](https://github.com/tuist/tuist/pull/3088) by [@wojciech-kulik](https://github.com/wojciech-kulik).
- Support XCFrameworks with missing architectures [#3095](https://github.com/tuist/tuist/pull/3095) by [@iainsmith](https://github.com/iainsmith).

### Changed

- Improved cold start time of `tuist generate` when having multiple projects [#3092](https://github.com/tuist/tuist/pull/3092) by [@adellibovi](https://github.com/adellibovi)
- Renamed `ValueGraph` to `Graph` [#3083](https://github.com/tuist/tuist/pull/3083) by [@fortmarek](https://github.com/fortmarek)
- Fixed a typo on the `tuist generate` command documentation for argument --skip-test-targets. [#3069](https://github.com/tuist/tuist/pull/3069) by [@mrcloud](https://github.com/mrcloud)
- **breaking** The `tuist dependencies` command requires the `Carthage` version to be at least `0.37.0`. [#3043](https://github.com/tuist/tuist/pull/3043) by [@laxmorek](https://github.com/laxmorek)

### Removed

- **breaking** Remove the `CarthageDependencies.Options` from the `Dependencies.swift` manifest model. [#3043](https://github.com/tuist/tuist/pull/3043) by [@laxmorek](https://github.com/laxmorek)

### Fixed

- `--only-current-directory` flag for `tuist edit` [#3097](https://github.com/tuist/tuist/pull/3097) by [@fortmarek](https://github.com/fortmarek)
- Fixed `tuist bundle` when path has spaces [#3084](https://github.com/tuist/tuist/pull/3084) by [@fortmarek](https://github.com/fortmarek)
- Fix manifest loading when using Swift 5.5 [#3062](https://github.com/tuist/tuist/pull/3062) by [@kwridan](https://github.com/kwridan)
- Fix generation of project groups and build phases for localized Interface Builder files (`.xib` and `.storyboard`) [#3075](https://github.com/tuist/tuist/pull/3075) by [@svenmuennich](https://github.com/svenmuennich/)
- Omit `runPostActionsOnFailure` scheme attribute when not enabled [#3087](https://github.com/tuist/tuist/pull/3087) by [@kwridan](https://github.com/kwridan)

## 1.44.0 - DubDub

### Added

- Add possibility to share tasks via a plugin [#3013](https://github.com/tuist/tuist/pull/3013) by [@fortmarek](https://github.com/fortmarek)
- Add option to `Scaffolding` for copy folder with option `.directory(path: "destinationContainerFolder", sourcePath: "sourceFolder")`. [#2985](https://github.com/tuist/tuist/pull/2985) by [@santi-d](https://github.com/santi-d)
- Add possibility to specify version of Swift in the `Config.swift` manifest file. [#2998](https://github.com/tuist/tuist/pull/2998) by [@laxmorek](https://github.com/laxmorek)
- Add `tuist run` command which allows running schemes of a project. [#2917](https://github.com/tuist/tuist/pull/2917) by [@luispadron](https://github.com/luispadron)

### Changed

- Sort build and testable targets in autogenerated scheme for workspace. [#3019](https://github.com/tuist/tuist/pull/3019) by [@adellibovi](https://github.com/adellibovi)
- Change product name lint severity to warning. [#3018](https://github.com/tuist/tuist/pull/3018) by [@adellibovi](https://github.com/adellibovi)

## 1.43.0 - Peroxide

### Added

- Add Tasks [#2816](https://github.com/tuist/tuist/pull/2816) by [@fortmarek](https://github.com/fortmarek)

### Changed

- Emit warning instead of error when provisioning profiles is expired. [#2919](https://github.com/tuist/tuist/pull/2919) by [@iteracticman](https://github.com/iteracticman)
- Updated the required Ruby version to 3.0.1 [#2961](https://github.com/tuist/tuist/pull/2961) by [@pepibumur](https://github.com/pepibumur)

### Fixed

- `.strings` Localization file synthesizers are now consistent and reproducible across multiple generations using the `developmentRegion` to choose the source one or defaulting to `en`. [#2887](https://github.com/tuist/tuist/pull/2887) by [@fila95](https://github.com/fila95)
- Fix `tuist scaffold list` not listing plugin templates. [#2958](https://github.com/tuist/tuist/pull/2958) by [@danyf90](https://github.com/danyf90).

## 1.42.0 - Builders

### Added

- Add support for `testPlan` initialization with an array of `Path`. [#2837](https://github.com/tuist/tuist/pull/2837) by [@cipolleschi](https://github.com/cipolleschi)
- Add `tuist dependencies update` command. [#2819](https://github.com/tuist/tuist/pull/2819) by [@laxmorek](https://github.com/laxmorek)
- Add `--build-output-path` option to `tuist build` [#2835](https://github.com/tuist/tuist/pull/2835) by [@Luis Padron](https://github.com/luispadron).

### Changed

- **Breaking** For some data types (plist, json, yaml and core data) resource synthesizers now group them and let `SwiftGen` output a single fine instead of one for each resource. [#2887](https://github.com/tuist/tuist/pull/2887) by [@fila95](https://github.com/fila95)
- Warnings for targets with no source files are now suppressed if the target does contain a dependency or action. [#2838](https://github.com/tuist/tuist/pull/2838) by [@jsorge](https://github.com/jsorge)

### Fixed

- `.strings` Localization file synthesizers are now consistent and reproducible across multiple generations using the `developmentRegion` to choose the source one or defaulting to `en`. [#2887](https://github.com/tuist/tuist/pull/2887) by [@fila95](https://github.com/fila95)
- Fix `tuist focus` not excluding targets from `codeCoverageTargets` of custom schemes by [@Luis Padron](https://github.com/luispadron).
- Fix rubocop warnings [#2898](https://github.com/tuist/tuist/pull/2898) by [@fortmarek](https://github.com/fortmarek)
- Add newline to end of generated resource accessor files. [#2895](https://github.com/tuist/tuist/pull/2895) by [@Jake Prickett](https://github.com/Jake-Prickett)

## 1.41.0

### Added

- Add support for `runPostActionsOnFailure` for post build actions. [#2752](https://github.com/tuist/tuist/pull/2752) by [@FranzBusch](https://github.com/FranzBusch)
- Make `ValueGraph` serializable. [#2811](https://github.com/tuist/tuist/pull/2811) by [@laxmorek](https://github.com/laxmorek)
- Add support for configuration of cache directory [#2566](https://github.com/tuist/tuist/pull/2566) by [@adellibovi](https://github.com/adellibovi).
- Add support for `runForInstallBuildsOnly` for build actions by [@StefanFessler](https://github.com/apps4everyone)

### Changed

- Improve performance of `tuist generate` by optimizing up md5 hash generation. [#2815](https://github.com/tuist/tuist/pull/2815) by [@adellibovi](https://github.com/adellibovi)
- Speed up frameworks metadata reading using Mach-o parsing instead of `file`, `lipo` and `dwarfdump` external processes. [#2814](https://github.com/tuist/tuist/pull/2814) by [@adellibovi](https://github.com/adellibovi)

### Fixed

- `tuist generate` your projects without having to re-open them! 🧑‍💻 [#2828] by [@ferologics](https://github.com/ferologics)
- Fix a bug for which when generating a `Resources` target from a `staticLibrary` or `staticFramework`, the parent's deployment target isn't passed to the new target. [#2830](https://github.com/tuist/tuist/pull/2830) by [@fila95](https://github.com/fila95)
- Fix `.messagesExtension` default settings to include the appropriate `LD_RUNPATH_SEARCH_PATHS` [#2824](https://github.com/tuist/tuist/pull/2824) by [@kwridan](https://github.com/kwridan)
- Fix the link to documented guidelines in pull request template [#2833](https://github.com/tuist/tuist/pull/2833) by [@mollyIV](https://github.com/mollyIV).

## 1.40.0

### Added

- Add resource synthesizers [#2746](https://github.com/tuist/tuist/pull/2746) by [@fortmarek](https://github.com/fortmarek)
- **WIP** Support for `SwiftPackageManager` dependencies in `Dependencies.swift` [#2394](https://github.com/tuist/tuist/pull/2394) by [@laxmorek](https://github.com/laxmorek).

### Changed

- Add missing disabling of swiftformat and swift-format [#2795](https://github.com/tuist/tuist/pull/2795) by [@fortmarek](https://github.com/fortmarek)
- Add support for globbing in build phase input file and file lists as well as output and output file lists. [#2686](https://github.com/tuist/tuist/pull/2686) by [@FranzBusch](https://github.com/FranzBusch)
- **breaking** Redesign `ProjectDescription.Dependencies` manifest model. [#2394](https://github.com/tuist/tuist/pull/2394) by [@laxmorek](https://github.com/laxmorek).

### Fixed

- Fixed missing `.resolveDependenciesWithSystemScm` config option in the `PackageDescription` portion of tuist [#2769](https://github.com/tuist/tuist/pull/2769) by [@freak4pc](https://github.com/freak4pc)
- Fixed running `tuist dump` for projects with plugins [#2700](https://github.com/tuist/tuist/pull/2700) by [@danyf90](https://github.com/danyf90)
- Fixed issue where associating potential test targets in a target's auto-generated scheme became more restrictive that previous versions. [#2797](https://github.com/tuist/tuist/pull/2797) by [@jakeatoms](https://github.com/jakeatoms)

## 1.39.1

### Fixed

- Fixed vendor updates not restoring original file permissions [#2743](https://github.com/tuist/tuist/pull/2688) by [@davebcn87](https://github.com/davebcn87)

## 1.39.0 - Innovators

### Added

- Add support for disabling Swift Package locking to speed up project generation when using Swift Package Manager [#2693](https://github.com/tuist/tuist/pull/2693) by [@jsorge](https://github.com/jsorge).
- Added `.precondition` Up to Setup. [#2688](https://github.com/tuist/tuist/pull/2688) by [@kalkwarf](https://github.com/kalkwarf)
- Add support for templates in plugins [#2687](https://github.com/tuist/tuist/pull/2687) by [@luispadron](https://github.com/luispadron)

### Changed

- Add SRCROOT for Info.plist only when necessary [#2706](https://github.com/tuist/tuist/pull/2706) by [@fortmarek](https://github.com/fortmarek)
- Support expand variables configuration in test scheme Environment Variables [#2697](https://github.com/tuist/tuist/pull/2694) by [@davebcn87](https://github.com/davebcn87)
- Support unversioned core data models [#2694](https://github.com/tuist/tuist/pull/2694) by [@freak4pc](https://github.com/freak4pc)
- Remove reference type Graph [#2689](https://github.com/tuist/tuist/pull/2689) by [@fortmarek](https://github.com/fortmarek)
- Migrate mappers to ValueGraph [#2683](https://github.com/tuist/tuist/pull/2683) by [@fortmarek](https://github.com/fortmarek)
- Migrate CacheMapper and CacheGraphMutator to ValueGraph [#2681](https://github.com/tuist/tuist/pull/2681) by [@fortmarek](https://github.com/fortmarek)
- Migrate TestsCacheGraphMapper to ValueGraph [#2674](https://github.com/tuist/tuist/pull/2674) by [@fortmarek](https://github.com/fortmarek)
- Updated swiftlint to 0.43.1 [#2679](https://github.com/tuist/tuist/pull/2679) by [@pepibumur](https://github.com/pepibumur)
- Updated xcbeautify to 0.9.1 [#2679](https://github.com/tuist/tuist/pull/2679) by [@pepibumur](https://github.com/pepibumur)
- Updated swiftlog to 1.4.2 [#2679](https://github.com/tuist/tuist/pull/2679) by [@pepibumur](https://github.com/pepibumur)
- Updated CryptoSwift to 1.3.8 [#2679](https://github.com/tuist/tuist/pull/2679) by [@pepibumur](https://github.com/pepibumur)
- Updated KeychainAccess to 4.2.2 [#2679](https://github.com/tuist/tuist/pull/2679) by [@pepibumur](https://github.com/pepibumur)
- Updated swift-tools-support-core to 0.2.0 [#2679](https://github.com/tuist/tuist/pull/2679) by [@pepibumur](https://github.com/pepibumur)
- Updated swift-argument-parser to 0.4.1 [#2679](https://github.com/tuist/tuist/pull/2679) by [@pepibumur](https://github.com/pepibumur)
- Updated Queuer to 2.1.1 [#2679](https://github.com/tuist/tuist/pull/2679) by [@pepibumur](https://github.com/pepibumur)
- Updated CombineExt to 1.3.0 [#2679](https://github.com/tuist/tuist/pull/2679) by [@pepibumur](https://github.com/pepibumur)

### Fixed

- Run all unit tests [#2739](https://github.com/tuist/tuist/pull/2739) by [@fortmarek](https://github.com/fortmarek)
- Fix false positive duplicate bundle id lint warning [#2707](https://github.com/tuist/tuist/pull/2707) by [@kwridan](https://github.com/kwridan)
- Failing Homebrew runs in M1 environments [#2711](https://github.com/tuist/tuist/pull/2711) by [@pepibumur](https://github.com/pepibumur)
- Installation of Tuist when `/usr/local/bin` doesn't exist [#2710](https://github.com/tuist/tuist/pull/2710) by [@pepibumur](https://github.com/pepibumur)

## 1.38.0 - Cold Waves

### Added

- Add support for `--no-use-binaries` Carthage flag. [#2608](https://github.com/tuist/tuist/pull/2608) by [@laxmorek](https://github.com/laxmorek)
- Add support for `tuist edit` for projects with plugins. [#2642](https://github.com/tuist/tuist/pull/2642) by [@luispadron](https://github.com/luispadron)
- Add support for `--only-current-directory` option to `tuist edit` [#2648](https://github.com/tuist/tuist/pull/2648) by [@pepibumur](https://github.com/pepibumur)

### Changed

- Ensure reusing derived data for `tuist test` [#2563](https://github.com/tuist/tuist/pull/2563) by [@fortmarek](https://github.com/fortmarek)
- **Breaking** Redesign `ProjectDescription.CarthageDependencies` manifest model. [#2608](https://github.com/tuist/tuist/pull/2608) by [@laxmorek](https://github.com/laxmorek)
- Changed the auto generated scheme heuristic to pick test bundles that have a matching name prefixed with either `Tests`, `IntegrationTests` or `UITests`. [#2641](https://github.com/tuist/tuist/pull/2641) by [@FranzBusch](https://github.com/FranzBusch)
- Remove building of ProjectDescriptionHelpers for `Plugin.swift` and `Config.swift` manifests (not supported for these manifests). [#2642](https://github.com/tuist/tuist/pull/2642) by [@luispadron](https://github.com/luispadron)

### Fixed

- Fixed running `tuist test` with `--clean` flag [#2649](https://github.com/tuist/tuist/pull/2649) by [@fortmarek](https://github.com/fortmarek)
- Install script bug fix: Adding bin folder to usr/local/ when it is missing [#2655](https://github.com/tuist/tuist/pull/2655) by [@tiarnann](https://github.com/tiarnann)
- Fixed `Environment` retrieve methods [#2653](https://github.com/tuist/tuist/pull/2653) by [@DimaMishchenko](https://github.com/DimaMishchenko)

### Removed

- Support for Xcode 11.x. [#2651](https://github.com/tuist/tuist/pull/2651) by [@pepibumur](https://github.com/pepibumur)

## 1.37.0 - Twister

### Added

- Allow using system SCM (for example: Git) when resolving SPM dependencies, instead of Xcode's accounts. [#2638](https://github.com/tuist/tuist/pull/2638) by [@freak4pc](https://github.com/freak4pc)
- Add support for simulated location in a run action's options. [#2616](https://github.com/tuist/tuist/pull/2616) by [@freak4pc](https://github.com/freak4pc)
- Add option for enabling XCFrameworks production for Carthage in `Setup.swift`. [#2565](https://github.com/tuist/tuist/pull/2565) by [@laxmorek](https://github.com/laxmorek)
- Add support for custom file header templates that are used for built-in Xcode file templates [#2568](https://github.com/tuist/tuist/pull/2568) by [@olejnjak](https://github.com/olejnjak)

### Changed

- Double-quoted strings in ruby files [#2634](https://github.com/tuist/tuist/pull/2634) by [@fortmarek](https://github.com/fortmarek)
- Improve `tuist generate` performance for projects with large amount of files [#2598](https://github.com/tuist/tuist/pull/2598) by [@adellibovi](https://github.com/adellibovi/)
- Added wrap arguments swiftformat option [#2606](https://github.com/tuist/tuist/pull/2606) by [@fortmarek](https://github.com/fortmarek)
- Remove build action for project generated in `tuist test` [#2592](https://github.com/tuist/tuist/pull/2592) [@fortmarek](https://github.com/fortmarek)
- Change the graph tree-shaker mapper to work with the value graph too [#2545](https://github.com/tuist/tuist/pull/2545) by [@pepibumur](https://github.com/pepibumur).
- Migrate `GraphViz` to `ValueGraph` [#2542](https://github.com/tuist/tuist/pull/2542) by [@fortmarek](https://github.com/fortmarek)
- Rename `TuistGraph.Dependency` to `TuistGraph.TargetDependency`. [#2614](https://github.com/tuist/tuist/pull/2614) by [@laxmorek](https://github.com/laxmorek)

### Fixed

- Fix incorrect detection of current Core Data model version. [#2612](https://github.com/tuist/tuist/pull/2612) by [@freak4pc](https://github.com/freak4pc)
- Ignore `.DS_Store` files when hashing directory contents [#2591](https://github.com/tuist/tuist/pull/2591) by [@natanrolnik](https://github.com/natanrolnik).

## 1.36.0 - Digital Love

### Added

- Support for `staticFramework` dependencies for `appExtension`s [#2559](https://github.com/tuist/tuist/pull/2559) by [@danyf90](https://github.com/danyf90)
- Enable Main Thread Checker by default [#2549](https://github.com/tuist/tuist/pull/2549) by [@myihsan](https://github.com/myihsan)
- Add option for enabling XCFrameworks production for Carthage in `Dependencies.swift`. [#2532](https://github.com/tuist/tuist/pull/2532) by [@laxmorek](https://github.com/laxmorek)
- Add --strict to 'lint code' command [#2534](https://github.com/tuist/tuist/pull/2534) by [@joshdholtz](https://github.com/joshdholtz)

### Fixed

- Fix adding framework targets to AppClip [#2530](https://github.com/tuist/tuist/pull/2530) by [@sampettersson](https://github.com/sampettersson)
- Make sure security and codesign can access certificates in signing.keychain [#2528]((https://github.com/tuist/tuist/pull/2528) by [@rist](https://github.com/rist).
- Expose `ResourceFileElements` initializer [#2541](https://github.com/tuist/tuist/pull/2541) by [@kwridan](https://github.com/kwridan).
- Note: This fixes an issue where `ResourceFileElements` could not be created using variables within helpers

### Changed

- When enabling code coverage, tests targets such as `TestMyFrameworkA` gather coverage for all targets instead of only `TestMyFrameworkA` [#2501](https://github.com/tuist/tuist/pull/2501) by [@adellibovi](https://github.com/adellibovi)
- Improve `tuist generate` speed by caching Swift version fetching [#2546](https://github.com/tuist/tuist/pull/2546) by [@adellibovi](https://github.com/adellibovi/)

## 1.35.0 - Miracle

- Fix missing linkable products for static frameworks with transitive precompiled dependencies [#2500](https://github.com/tuist/tuist/pull/2500) by [@kwridan](https://github.com/kwridan).

### Added

- Add ODR support [#2490](https://github.com/tuist/tuist/pull/2490) by [@DimaMishchenko](https://github.com/DimaMishchenko)
- Add support for StoreKit configuration files [#2524](https://github.com/tuist/tuist/pull/2524) by [@bolismauro](https://github.com/bolismauro)
- Selective tests [#2422](https://github.com/tuist/tuist/pull/2422) by [@fortmarek](https://github.com/fortmarek)
- Installation of `tuist` on Big Sur [#2526](https://github.com/tuist/tuist/pull/2526) by [@pepibumur](https://github.com/pepibumur).

### Fixed

- Fix missing linkable products for static frameworks with transitive precompiled dependencies [#2500](https://github.com/tuist/tuist/pull/2500) by [@kwridan](https://github.com/kwridan).
- Fix crash when using `tuist graph` in a project that leverages plugins [#2507](https://github.com/tuist/tuist/pull/2507) by [@bolismauro](https://github.com/bolismauro).

### Changed

- Migrate `BuildGraphInspector` to `ValueGraph` [#2527](https://github.com/tuist/tuist/pull/2527) by [@fortmarek](https://github.com/fortmarek/)
- Replace `ExpressibleByStringLiteral` with `ExpressibleByStringInterpolation` for `ProjectDescription` objects by [@DimaMishchenko](https://github.com/DimaMishchenko)
- Fix adding framework targets to AppClip by [@sampettersson](https://github.com/sampettersson)

## 1.34.0 - Shipit

### Added

- Add support for `tuist cache warm` to cache a subset of targets via `tuist cache warm FrameworkA FrameworkB` [#2393]((https://github.com/tuist/tuist/pull/2393) by [@adellibovi](https://github.com/adellibovi).
- Add documentation on how to use & create plugins by [@luispadron](https://github.com/luispadron)
- Warn when targets with duplicate bundle identifiers exist per platform [#2444](https://github.com/tuist/tuist/pull/2444) by [@natanrolnik](https://github.com/natanrolnik).

### Fixed

- Fixed code coverage setting for project scheme [#2493](https://github.com/tuist/tuist/pull/2493) by [@adellibovi](https://github.com/adellibovi)
- Fixed a bug in reporting stats event when Queue folder isn't created [#2497](https://github.com/tuist/tuist/pull/2497) by [@andreacipriani](https://github.com/andreacipriani).

### Changed

- Update post-generation interactors to use the graph traverser [#2451](https://github.com/tuist/tuist/pull/2451) by [@pepibumur](https://github.com/pepibumur).

## 1.33.0 - Plugin

### Added

- Add support for `tuist graph` to show the graph of a subset of targets via `tuist graph FrameworkA FrameworkB` [#2434]((https://github.com/tuist/tuist/pull/2434) by [@adellibovi](https://github.com/adellibovi).
- Send Tuist usage analytics event to https://stats.tuist.io/ [#2331](https://github.com/tuist/tuist/pull/2331) by [@andreacipriani](https://github.com/andreacipriani).
- Plugin integration for local and git plugins by [@luispadron](https://github.com/luispadron) and [@kwridan](https://github.com/kwridan).
- Introduce caching profiles [#2356](https://github.com/tuist/tuist/pull/2431) by [@mollyIV](https://github.com/mollyIV).

### Fixed

- Fixed homebrew invocation for `graph` functionality when looking up graphviz installation [#2466](https://github.com/tuist/tuist/pull/2446) by [@thedavidharris](https://github.com/danyf90)
- Fix reading configuration from project if `Target.settings` is nil [#2399](https://github.com/tuist/tuist/pull/2399) by [@danyf90](https://github.com/danyf90).
- Fix CoreData project attributes [#2397](https://github.com/tuist/tuist/pull/2397) by [@kwridan](https://github.com/kwridan).

### Changed

- The parameter `--path` of `tuist graph` now specifies where the manifest is. To specify the output directory of the graph, use `--output-path` [#2434]((https://github.com/tuist/tuist/pull/2434) by [@adellibovi](https://github.com/adellibovi).

## 1.32.0 - Neubau

### Added

- Generate resource mapping and synthesized Bundle accessors for targets with Core Data models [#2376](https://github.com/tuist/tuist/pull/2376) by [@thedavidharris](https://github.com/thedavidharris).
- Support for dynamic library dependencies for command line tool projects [#2332](https://github.com/tuist/tuist/pull/2332) by [@danyf90](https://github.com/danyf90).
- Disable SwiftFormat in the generated synthesized interface for resources [#2328](https://github.com/tuist/tuist/pull/2328) by [@natanrolnik](https://github.com/natanrolnik).
- Implement foundations for caching profiles [#2190](https://github.com/tuist/tuist/issues/2190) by [@mollyIV](https://github.com/mollyIV).

### Fixed

- Fix missing autocompletion link on website [#2396](https://github.com/tuist/tuist/pull/2396) by [@fortmarek](https://github.com/fortmarek).
- Fix memory leak related to xcbeautify [#2380](https://github.com/tuist/tuist/pull/2380) by [@adellibovi](https://github.com/adellibovi).
- Fix autocompletion script output and documentation [#2400](https://github.com/tuist/tuist/pull/2400) by [@danyf90](https://github.com/danyf90).
- Fix cache's hash calculation of resources [#2325](https://github.com/tuist/tuist/pull/2325) by [@natanrolnik](https://github.com/natanrolnik).
- Fixed known issue that causes the `xcodebuild` process hang when running `tuist test` and `tuist build`. [#2297](https://github.com/tuist/tuist/pull/2297) by [@Jake-Prickett](https://github.com/Jake-Prickett).
- Fix missing vendor directory in built from source versions [#2388](https://github.com/tuist/tuist/pull/2388) by [@natanrolnik](https://github.com/natanrolnik).

### Changed

- Improve `tuist migration list-targets` by sorting using topological order [#2383](https://github.com/tuist/tuist/pull/2383) by [@adellibovi](https://github.com/adellibovi).
- Use project generated for automation and always leverage `XXX-Scheme` [#2057](https://github.com/tuist/tuist/pull/2057) by [@fortmarek](https://github.com/fortmarek)
- Improve the cache warm command significantly (around 20-45 seconds per framework) by using `XcodeProjectPathHasher` instead of `CacheBuildPhaseProjectMapper` [#2356](https://github.com/tuist/tuist/pull/2318) by [@natanrolnik](https://github.com/natanrolnik).
- Improve performance of project generation by removing unneeded Glob directory cache [#2318](https://github.com/tuist/tuist/pull/2318) by [@adellibovi](https://github.com/adellibovi).
- Extracted graph models into `TuistGraph` [#2324](https://github.com/tuist/tuist/pull/2324) by [@pepibumur](https://github.com/pepibumur).
- Improved the CI workflows to run only when their logic is impacted by the file changes [#2390](https://github.com/tuist/tuist/pull/2390) by [@pepibumur](https://github.com/pepibumur).

## 1.31.0 - Arctic

### Added

- Add linting for paths of local packages and for URL validity of remote packages [#2255](https://github.com/tuist/tuist/pull/2255) by [@adellibovi](https://github.com/adellibovi).
- Allow use of a single cert for multiple provisioning profiles [#2193](https://github.com/tuist/tuist/pull/2193) by [@rist](https://github.com/rist).

### Fixed

- Update failing trying to create the `swift-project` symbolic link [#2244](https://github.com/tuist/tuist/pull/2244)
- Tuist now correctly parses arm64e architectures in xcframeworks [#2247](https://github.com/tuist/tuist/pull/2247) by [@thedavidharris](https://github.com/thedavidharris).

## 1.30.0 - 2021

### Fixed

- Fix import of multiple signing certificates [#2112](https://github.com/tuist/tuist/pull/2112) by [@rist](https://github.com/rist).
- Fix false positive duplicate static products lint rule [#2201](https://github.com/tuist/tuist/pull/2201) by [@kwridan](https://github.com/kwridan).

### Added

- Add support for embedded scripts in a TargetAction. [#2192](https://github.com/tuist/tuist/pull/2192) by [@jsorge](https://github.com/jsorge)
- Support for `Carthage` dependencies in `Dependencies.swift` [#2060](https://github.com/tuist/tuist/pull/2060) by [@laxmorek](https://github.com/laxmorek).
- Fourier CLI tool to automate development tasks [#2196](https://github.com/tuist/tuist/pull/2196) by [@pepibumur](https://github.com/pepibumur).
- Add support for embedded scripts in a TargetAction. [#2192](https://github.com/tuist/tuist/pull/2192) by [@jsorge](https://github.com/jsorge)
- Support `.s` source files [#2199](https://github.com/tuist/tuist/pull/2199) by [@dcvz](https://github.com/dcvz).
- Support for printing from the manifest files [#2215](https://github.com/tuist/tuist/pull/2215) by [@pepibumur](https://github.com/pepibumur).

### Changed

- Replace `@UIApplicationMain` and `@NSApplicationMain` with `@main` [#2222](https://github.com/tuist/tuist/pull/2222) by [@RomanPodymov](https://github.com/RomanPodymov).

## 1.29.0 - Tutu

### Fixed

- Fix "Embed Frameworks" build phase parameters [#2156](https://github.com/tuist/tuist/pull/2156) by [@kwridan](https://github.com/kwridan).
- Adjust the project generated for editing to not build for the arm64 architecture [#2154](https://github.com/tuist/tuist/pull/2154) by [@pepibumur](https://github.com/pepibumur).
- Project generation failing when the resources glob includes a bundle [#2183](https://github.com/tuist/tuist/pull/2183) by [@pepibumur](https://github.com/pepibumur).

## 1.28.0

### Fixed

- Missing required module 'XXX' when building project with cached dependencies [#2051](https://github.com/tuist/tuist/pull/2051) by [@mollyIV](https://github.com/mollyIV).
- Fix default generated scheme arguments [#2128](https://github.com/tuist/tuist/pull/2128) by [@kwridan](https://github.com/kwridan)
- Playground files matched by the sources wildcards are added as playgrounds and not groups [#2132](https://github.com/tuist/tuist/pull/2132) by [@pepibumur](https://github.com/pepibumur).

### Removed

- **Breaking** The implicit addition of playgrounds under `Playgrounds/` has been removed [#2132](https://github.com/tuist/tuist/pull/2132) by [@pepibumur](https://github.com/pepibumur).

## 1.27.0 - Hawái

### Added

- Add `Plugin.swift` manifest [#2095](https://github.com/tuist/tuist/pull/2095) by [@luispadron](https://github.com/luispadron)
- Add Publisher-based methods to System's API [#2108](https://github.com/tuist/tuist/pull/2108) by [@pepibumur](https://github.com/pepibumur).

### Fixed

- Make watch targets runnable to fix schemes in Xcode 12 [#2096](https://github.com/tuist/tuist/pull/2096) by [@thedavidharris](https://github.com/thedavidharris)
- Fix framework search paths for SDK dependencies [#2097](https://github.com/tuist/tuist/pull/2097) by [@kwridan](https://github.com/kwridan)
- Fix `ValueGraphTraverser.directTargetDependencies` to return local targets only [#2111](https://github.com/tuist/tuist/pull/2111) by [@kwridan](https://github.com/kwridan)
- **Note:** This fixes an issue that previously allowed extension targets to be defined in a separate project (which isn't a supported dependency type)

### Changed

- Generate multiple `XXX-Project` schemes if there are multiple platforms [#2081](https://github.com/tuist/tuist/pull/2081) by [@fortmarek](https://github.com/fortmarek)
- Generators to take in the graph as `GraphTraversing` instead of `Graph` [#2110](https://github.com/tuist/tuist/pull/2110) by [@pepibumur](https://github.com/pepibumur)

## 1.26.0 - New World

### Added

- Extend the tree-shaking logic to include workspace projects and targets [#2056](https://github.com/tuist/tuist/pull/2056) by [@pepibumur](https://github.com/pepibumur).
- Add support for copy files phase [#2077](https://github.com/tuist/tuist/pull/2077) by [@hebertialmeida](https://github.com/hebertialmeida).

### Changed

- Change `launchArguments` of `Target` and `RunAction` to ordered array so order can be preserved [#2052](https://github.com/tuist/tuist/pull/2052) by [@olejnjak](https://github.com/olejnjak).
- Added `Package.swift` to some subdirectories to prevent Xcode from including them in the generated Xcode project [#2058](https://github.com/tuist/tuist/pull/2058) by [@pepibumur](https://github.com/pepibumur).

### Fixed

- Fixed signing linter for target with bundle identifier derived from build settings [#2031](https://github.com/tuist/tuist/pull/2031) by [@leszko11](https://github.com/leszko11).
- Fix hashing preaction with path to nil [#2074](https://github.com/tuist/tuist/pull/2074) by [@fortmarek](https://github.com/fortmarek)
- Correct the `TEST_HOST` path for the macOS Platform [#2034](https://github.com/tuist/tuist/pull/2034) by [@ferologics](https://github.com/ferologics)

## 1.25.0 - Charles

### Added

- Add `enableCodeCoverage` generation option to enable code coverage in automatically generated schemes [#2020](https://github.com/tuist/tuist/pull/2020) by [@frijole](https://github.com/frijole).)
- Add support for Command Line Tool targets [#1941](https://github.com/tuist/tuist/pull/1941) by [@olejnjak](https://github.com/olejnjak).

## 1.24.0 - Sol y sombra

### Added

- Synthesize accessors for stringsdict [#1993](https://github.com/tuist/tuist/pull/1993) by [@fortmarek](https://githubl.com/fortmarek)
- Add support for `StencilSwiftKit`'s additional filters. [#1994](https://github.com/tuist/tuist/pull/1994) by [@svastven](https://github.com/svastven).
- Add `migration list-targets` command to show all targets sorted by number of dependencies [#1732](https://github.com/tuist/tuist/pull/1732) of a given project by [@andreacipriani](https://github.com/andreacipriani).
- Add support for test plans [#1936](https://github.com/tuist/tuist/pull/1936) by [@iteracticman](https://github.com/iteracticman).

### Fixed

- Re-enable tests acceptance tests that were not running on CI [#1999](https://github.com/tuist/tuist/pull/1999) by [@pepibumur](https://github.com/pepibumur).
- Block the process while editing the project and remove the project after the edition finishes [#1999](https://github.com/tuist/tuist/pull/1999) by [@pepibumur](https://github.com/pepibumur).
- Use the simulator udid when building the frameworks for the cache instead of `os=latest` [#2016](https://github.com/tuist/tuist/pull/2016) by [@pepibumur](https://github.com/pepibumur).

## 1.23.0 - Automaton

### Added

- Allow specifying Development Region via new `developmentRegion` parameter in `Config`s GenerationOption. [#1062](https://github.com/tuist/tuist/pull/1867) by [@svastven](https://github.com/svastven).
- Require the `Config.swift` file to be in the Tuist directory [#693](https://github.com/tuist/tuist/issues/693) by [@mollyIV](https://github.com/mollyIV).
- Mapper for the caching logic to locate the built products directory [#1929](https://github.com/tuist/tuist/pull/1929) by [@pepibumur](https://github.com/pepibumur).
- Extended `BuildPhaseGenerator` to generate script build phases [#1932](https://github.com/tuist/tuist/pull/1932) by [@pepibumur](https://github.com/pepibumur).
- Extend the `TargetContentHasher` to account for the `Target.scripts` attribute [#1933](https://github.com/tuist/tuist/pull/1933) by [@pepibumur](https://github.com/pepibumur).
- Extend the `CacheController` to generate projects with the build phase to locate the targets' built products directory [#1933](https://github.com/tuist/tuist/pull/1933) by [@pepibumur](https://github.com/pepibumur).
- Add support for appClip [#1854](https://github.com/tuist/tuist/pull/1854) by [@lakpa](https://github.com/lakpa).

### Fixed

- Fixed non-framework/library targets having a header build phase [#367](https://github.com/tuist/tuist/issues/367) by [@eito](https://github.com/eito).
- Fixed missing profile scheme arguments when specified in manifest [#1543](https://github.com/tuist/tuist/issues/1543) by [@lakpa](https://github.com/lakpa).
- Fixed cache warming exporting unrelated .frameworks [#1939](https://github.com/tuist/tuist/pull/1939) by [@pepibumur](https://github.com/pepibumur).
- Fixed cache warming building from a clean state for every target [#1939](https://github.com/tuist/tuist/pull/1939) by [@pepibumur](https://github.com/pepibumur).
- Updated swift-doc version to 1.0.0-beta.5 by [@facumenzella](https://github.com/facumenzella).

### Changed

- Some renames in the generation logic to make the generation logic easier to reason about [#1942](https://github.com/tuist/tuist/pull/1942) by [@pepibumur](https://github.com/pepibumur).
- Update some Swift dependencies [#1971](https://github.com/tuist/tuist/pull/1971) by [@pepibumur](https://github.com/pepibumur).
- Improve hashing logic to account for files generated by mappers [#1977](https://github.com/tuist/tuist/pull/1977) by [@pepibumur](https://github.com/pepibumur).

## 1.22.0 - Heimat

### Changed

- Autogenerated `xxx-Project` scheme is now shared [#1902](https://github.com/tuist/tuist/pull/1902) by [@fortmarek](https://github.com/fortmarek)

### Added

- Allow build phase scripts to disable dependency analysis [#1883](https://github.com/tuist/tuist/pull/1883) by [@bhuemer](https://github.com/bhuemer).
- The default generated project does not include a LaunchScreen storyboard [#265](https://github.com/tuist/tuist/issues/265) by [@mollyIV](https://github.com/mollyIV).

## 1.21.0 - PBWerk

### Added

- Allow ignoring cache when running tuist focus [#1879](https://github.com/tuist/tuist/pull/1879) by [@natanrolnik](https://github.com/natanrolnik).

### Changed

- Improve error message to have more actionable information [#921](https://github.com/tuist/tuist/issues/921) by [@mollyIV](https://github.com/mollyIV).

### Fixed

- Fix calculation of Settings hash related to Cache commands [#1869](https://github.com/tuist/tuist/pull/1869) by [@natanrolnik](https://github.com/natanrolnik)
- Fixed handling of `.tuist_version` file if the file had a trailing line break [#1900](https://github.com/tuist/tuist/pull/1900) by [@kalkwarf](https://github.com/kalkwarf)

## 1.20.0 - Heideberg

### Changed

- Revert using root `.package.resolved` [#1830](https://github.com/tuist/tuist/pull/1830) by [@fortmarek](https://github.com/fortmarek)

### Added

- Support for caching frameworks instead of xcframeworks [#1851](https://github.com/tuist/tuist/pull/1851)

### Fixed

- Skip synthesizing resource accessors when the file/folder is empty [#1829](https://github.com/tuist/tuist/pull/1829) by [@fortmarek](https://github.com/fortmarek)
- The redirect after the cloud authentication is not being captured from the CLI [#1846](https://github.com/tuist/tuist/pull/1846) by [@pepibumur](https://github.com/pepibumur).

## 1.19.0 - Milano

### Fixed

- Ensure `DEVELOPER_DIR` is used in all `swiftc` calls [#1819](https://github.com/tuist/tuist/pull/1819) by [@kwridan](https://github.com/kwridan)
- Fixed decoding bug on DefaultSettings [#1817](https://github.com/tuist/tuist/issues/1817) by [@jakeatoms](https://github.com/jakeatoms)
- Bool compiler error when generating accessor for plists [#1827](https://github.com/tuist/tuist/pull/1827) by [@fortmarek](https://github.com/fortmarek)

### Added

- Add Workspace Mappers [#1767](https://github.com/tuist/tuist/pull/1767) by [@kwridan](https://github.com/kwridan)
- Extended `Config`'s generationOptions with `.disableShowEnvironmentVarsInScriptPhases`. It does what you'd think. [#1782](https://github.com/tuist/tuist/pull/1782) by [@kalkwarf](https://github.com/kalkwarf)
- Generate `xxx-Project` scheme to build and test all available targets by [#1765](https://github.com/tuist/tuist/pull/1765) by [@fortmarek](https://github.com/fortmarek)

### Changed

- The `tuist edit` command adds `Setup.swift` and `Config.swift` to the generated project if they exist. [#1745](https://github.com/tuist/tuist/pull/1745) by [@laxmorek](https://github.com/laxmorek)

## 1.18.1 - Manaslu

### Fixed

- Added `tuist lint code` support for custom .swiftlint.yml files. [1764](https://github.com/tuist/tuist/pull/1764) by [@facumenzella](https://github.com/facumenzella)
- Fix GenerationOptions decoding [#1781](https://github.com/tuist/tuist/pull/1781) by [@alvarhansen](https://github.com/alvarhansen)

## 1.18.0 - Himalaya

### Fixed

- Support initializing projects with dashes [#1766](https://github.com/tuist/tuist/pull/1766) by [@fortmarek](https://github.com/fortmarek)

### Added

- Possibility to build schemes that are not part of any entry node [#1761](https://github.com/tuist/tuist/pull/1761) by [@fortmarek](htttps://github.com/fortmarek)
- `tuist lint code` - command to lint the Swift code using Swiftlint [#1682](https://github.com/tuist/tuist/pull/1682) by [@laxmorek](https://github.com/laxmorek)
- `tuist doc` - command to generate documentation for your modules using SwiftDoc [#1683](https://github.com/tuist/tuist/pull/1683) by [@facumenzella](https://github.com/facumenzella)

### Changed

- **Breaking** Command for linting a workspace or a project has been renamed from `tuist lint` to `tuist lint project` [#1682](https://github.com/tuist/tuist/pull/1682) by [@laxmorek](https://github.com/laxmorek)
- **Breaking** UpCarthage should perform bootstrap instead of update [#1744](https://github.com/tuist/tuist/pull/1744) by [@softmaxsg](https://github.com/softmaxsg)
- Add excluding argument to `recommended`/`essential` `DefaultSettings` [#1746](https://github.com/tuist/tuist/pull/1739) by [@rist](https://github.com/rist).
- Synthesize resource interface accessors [#1635](https://github.com/tuist/tuist/pull/1635) by [@fortmarek](https://github.com/fortmarek)
- Graph command now adds different colors and shapes for different types of targets and dependencies [#1763](https://github.com/tuist/tuist/pull/1763) by [@natanrolnik](https://github.com/natanrolnik)

## 1.17.0 - Luft

### Changed

- **Breaking** `tuist focus` only works with `Project.swift` [#1739](https://github.com/tuist/tuist/pull/1739) by [@pepibumur](https://github.com/pepibumur).
- **Breaking** a target or a list of targets is required for `tuist focus` [#1739](https://github.com/tuist/tuist/pull/1739) by [@pepibumur](https://github.com/pepibumur).
- **Breaking** cache is enabled by default in `tuist focus` [#1739](https://github.com/tuist/tuist/pull/1739) by [@pepibumur](https://github.com/pepibumur).

### Fixed

- Use relative paths for Local Swift Packages [#1706](https://github.com/tuist/tuist/pull/1706) by [@kwridan](https://github.com/kwridan)

## 1.16.0 - Alhambra

### Removed

- **Breaking** Support for Xcode 11.3.x and Xcode 11.4.x [#1604](https://github.com/tuist/tuist/pull/1604) by [@fortmarek](https://github.com/fortmarek)
- **Breaking** `--cache` & `--include-sources` arguments from `tuist generate` [#1712](https://github.com/tuist/tuist/pull/1712) by [@pepibumur](https://github.com/pepibumur).

### Added

- `--open` argument to the `tuist generate` command [#1712](https://github.com/tuist/tuist/pull/1712) by [@pepibumur](https://github.com/pepibumur).
- `--no-open` argument to the `tuist focus` command to support disabling opening the project [#1712](https://github.com/tuist/tuist/pull/1712) by [@pepibumur](https://github.com/pepibumur).
- Support for running Tuist through `swift project` [#1713](https://github.com/tuist/tuist/pull/1713) by [@pepibumur](https://github.com/pepibumur).

### Fixed

- Generate the default `Info.plist` file for static frameworks that only contain resources [#1661](https://github.com/tuist/tuist/pull/1661) by [@Juanpe](https://github.com/juanpe)
- Fix Carthage support for binary dependencies [#1675](https://github.com/tuist/tuist/pull/1675) by [@softmaxsg](https://github.com/softmaxsg)
- Use profile filename to match targets and configs [#1690](https://github.com/tuist/tuist/pull/1690) by [@rist](https://github.com/rist)

### Changed

- `Target.dependsOnXCTest` returns true if the target is a test bundle [#1679](https://github.com/tuist/tuist/pull/1679) by [@pepibumur](https://github.com/pepibumur)
- Support multiple rendering algorithms in Tuist Graph [#1655](%5B1655%5D(https://github.com/tuist/tuist/pull/1655/)) by [@andreacipriani][https://github.com/andreacipriani]

## 1.15.0 - Riga

### Changed

- Renamed Scale to Cloud [#1633](https://github.com/tuist/tuist/pull/1633) by [@pepibumur](https://github.com/pepibumur)

### Fixed

- Fix name collision when having multiple templates [#1600](https://github.com/tuist/tuist/pull/1600) by [@fortmarek](https://github.com/fortmarek)
- Allow to cache and warm static frameworks too (only dynamic frameworks were cached before) [#1590](https://github.com/tuist/tuist/pull/1590) by [@RomainBoulay](https://github.com/RomainBoulay)
- Add graph visualization in Tuist graph command: "tuist graph --format=png" [#1624](https://github.com/tuist/tuist/pull/1591) by [@AndreaCipriani](https://github.com/andreacipriani)
- Add support for `.xctest` dependency for tvOS targets [#1597](https://github.com/tuist/tuist/pull/1597) by [@kwridan](https://github.com/kwridan).
- Fix missing ui test host applications for apps with "-" characters in their name [#1630](https://github.com/tuist/tuist/pull/1630) by [@kwridan](https://github.com/kwridan).
- Added @Flag in TuistKit.TuistCommand to improve --help-env discoverability by [@facumenzella](https://github.com/facumenzella).

### Added

- Autocompletions support [#1604](https://github.com/tuist/tuist/issues/1592) by [@fortmarek](https://github.com/fortmarek)
- Add an acceptance test suite to cover a `test cache warm` command on a micro-feature architecture kind of application that is fully statically linked [#1594](https://github.com/tuist/tuist/pull/1594) by [@RomainBoulay](https://github.com/RomainBoulay)
- Add support for setting launch arguments at the target level. [#1596](https://github.com/tuist/tuist/pull/1596) by [@jeroenleenarts](https://github.com/jeroenleenarts)
- Add Homebrew cask up [#1601](https://github.com/tuist/tuist/pull/1601) by [@leszko11](https://github.com/leszko11)

## 1.14.0 - Spezi

### Fixed

- Disable SwiftLint in the generated synthesized interface for resources [#1574](https://github.com/tuist/tuist/pull/1574) by [@pepibumur](https://github.com/pepibumur).
- Synthesized accessors for framework targets not resolving the path [#1575](https://github.com/tuist/tuist/pull/1575) by [@pepibumur](https://github.com/pepibumur).
- Read coredata version from /.xccurrentversion file [#1572](https://github.com/tuist/tuist/pull/1572) by [@matiasvillaverde](https://github.com/matiasvillaverde).

### Added

- Support for `--cache` to the `tuist generate` command [#1576](https://github.com/tuist/tuist/pull/1576) by [@pepibumur](https://github.com/pepibumur).
- Included that importing target name in the duplicate dependency warning message [#1573](https://github.com/tuist/tuist/pull/1573) by[ @thedavidharris](https://github.com/thedavidharris)
- Support to build and run the project on Xcode 12 by fixing namespace collisions on Logger [#1579](https://github.com/tuist/tuist/pull/1579) by[ @thedavidharris](https://github.com/thedavidharris)

### Changed

- Change the project name and organization from a mapper [#1577](https://github.com/tuist/tuist/pull/1577) by [@pepibumur](https://github.com/pepibumur).
- Update `ConfigGenerator` to use `ValueGraph` instead [#1583](https://github.com/tuist/tuist/pull/1583) by [@pepibumur](https://github.com/pepibumur).

## 1.13.1 - More Bella Vita

### Fixed

- Camelize the name of the Objective-C synthesized object by [@pepibumur](https://github.com/pepibumur).

## 1.13.0 - Bella Vita

### Fixed

- `tuist focus` creating new `.package.resolved` [#1569](https://github.com/tuist/tuist/pull/1569) by [@fortmarek](https://github.com/fortmarek)
- Delete schemes whose targets have been replaced by .xcframeworks [#1571](https://github.com/tuist/tuist/pull/1571) by [@pepibumur](https://github.com/pepibumur).

### Changed

- Rename cloud to scale [#1571](https://github.com/tuist/tuist/pull/1571) by [@pepibumur](https://github.com/pepibumur).

### Added

- Analytics to the website to better understand the usage of the website in order to optimize it and improve the discoverability of the content [#1571](https://github.com/tuist/tuist/pull/1571) by [@pepibumur](https://github.com/pepibumur).

## 1.12.2 - Waka Waka

### Fixed

- Fix a bug introduced in [#1523](https://github.com/tuist/tuist/pull/1523), when a valid source file would result in throwing an invalid glob error [#1566](https://github.com/tuist/tuist/pull/1566) by [@natanrolnik](https://github.com/natanrolnik)

## 1.12.1 - Waka

### Added

- Add benchmark rake task [#1561](https://github.com/tuist/tuist/pull/1561) by [@kwridan](https://github.com/kwridan).
- Add `--json` flag to `tuist scaffold list` command [#1589](https://github.com/tuist/tuist/issues/1589) by [@mollyIV](https://github.com/mollyIV).

### Fixed

- `UpHomebrew` (`Up.homebrew(packages:)`) in `Setup.swift` correctly checks package installation if the executable doesn't match the package name [#1544](https://github.com/tuist/tuist/pull/1544) by [@MatyasKriz](https://github.com/MatyasKriz).
- Update Package.swift to correctly encode revision kind as "revision" [#1558](https://github.com/tuist/tuist/pull/1558) by [@ollieatkinson](https://github.com/ollieatkinson).
- Treat SceneKit catalog the same way as asset catalog [#1546], by [@natanrolnik](https://github.com/natanrolnik)
- Add core data models to the sources build phase [#1542](https://github.com/tuist/tuist/pull/1542) by [@kwridan](https://github.com/kwridan).
- Improve app extensions autogenerated schemes [#1545](https://github.com/tuist/tuist/pull/1545) by [@kwridan](https://github.com/kwridan).
- Ensure the latest semantic version is used when running via tuistenv [#1562](https://github.com/tuist/tuist/pull/1562) by [@kwridan](https://github.com/kwridan).
- `tuist focus` not working for workspaces [#1565](https://github.com/tuist/tuist/pull/1565) by [@pepibumur](https://github.com/pepibumur).

### Changed

- Add a `sourceRootPath` attribute to `TuistCore.Project` to control where Xcode projects are generated [#1559](https://github.com/tuist/tuist/pull/1559) by [@pepibumur](https://github.com/pepibumur).
- **Breaking** Fail generation if a Source has a non-existent directory in a glob [#1523](https://github.com/tuist/tuist/pull/1523) by [@natanrolnik](https://github.com/natanrolnik).
- Change `tuist scaffold list` output to be readable by grep [#1147](https://github.com/tuist/tuist/issues/1147) by [@mollyIV](https://github.com/mollyIV).

## 1.12.0 - Arabesque

### Changed

- Use the selected Xcode version when editing projects [#1471](https://github.com/tuist/tuist/pull/1511) by [@pepibumur](https://github.com/pepibumur).
- Search the `Setup.swift` file upwards if it doesn't exist in the current directory [#1513](https://github.com/tuist/tuist/pull/1513) by [@pepibumur](https://github.com/pepibumur).
- Added `RxBlocking` to list of dependencies for `TuistGenerator` [#1514](https://github.com/tuist/tuist/pull/1514) by [@fortmarek](https://github.com/fortmarek).
- Uncommented iMessage extension product type [#1515](https://github.com/tuist/tuist/pull/1515) by [@olejnjak](https://github.com/olejnjak).
- Prettify the redirect page [#1521](https://github.com/tuist/tuist/pull/1521) by [@pepibumur](https://github.com/pepibumur).
- Implements two arguments on the `graph` command [#1540](https://github.com/tuist/tuist/pull/1540) by [@jeroenleenarts](https://github.com/jeroenleenarts).

### Added

- `tuist clean` command to delete the local cache [#1516](https://github.com/tuist/tuist/pull/1516) by [@RomainBoulay](https://github.com/RomainBoulay).
- `tuist secret` command to generate cryptographically secure secrets [#1471](https://github.com/tuist/tuist/pull/1471) by [@pepibumur](https://github.com/pepibumur).

## 1.11.1 - Volare far

### Fixed

- Missing schemes in generated project for editing [#1467](https://github.com/tuist/tuist/pull/1467) by [@fortmarek](https://github.com/fortmarek)
- `tuist build` cleaning even if the `--clean` argument is not passed [#1458](https://github.com/tuist/tuist/pull/1458) by [@pepibumur](https://github.com/pepibumur).

### Changed

- Use `LD_RUNPATH_SEARCH_PATHS` instead of embedding dynamic frameworks for unit test targets [#1463](https://github.com/tuist/tuist/pull/1463) by [@fortmarek](https://github.com/fortmarek)
- Migrate info plist generator to a project mapper [#1469](https://github.com/tuist/tuist/pull/1469) by [@kwridan](https://github.com/kwridan).

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
- Manifests are now cached to speed up generation times *(opt out via setting `TUIST_CACHE_MANIFESTS=0`)* [1341](https://github.com/tuist/tuist/pull/1341) by [@kwridan](https://github.com/kwridan)

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
- Adds `codeCoverageTargets` to `TestAction` to make Xcode gather coverage info only for that targets [#619](https://github.com/tuist/tuist/pull/619) by @abbasmousavi
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
- Remove $(SRCROOT) from being included in `Info.plist` path [#511](https://github.com/tuist/tuist/pull/511) by @dcvz
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
