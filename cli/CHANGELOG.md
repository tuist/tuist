# Changelog

All notable changes to this project will be documented in this file.
## What's Changed in 4.119.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* filter Catalyst destinations for external dependencies by [@pepicrft](https://github.com/pepicrft) in [#9067](https://github.com/tuist/tuist/pull/9067)
* handle multi-byte UTF-8 characters in xcresult parsing by [@fortmarek](https://github.com/fortmarek) in [#9061](https://github.com/tuist/tuist/pull/9061)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.119.1...4.119.2

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

## New Contributors
* [@denisgaskov](https://github.com/denisgaskov) made their first contribution in [#8998](https://github.com/tuist/tuist/pull/8998)

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

### ⛰️  Features

* compute binary id as part of tuist share by [@fortmarek](https://github.com/fortmarek) in [#8912](https://github.com/tuist/tuist/pull/8912)
### 🐛 Bug Fixes

* require previews to have unique binary id and bundle version by [@fortmarek](https://github.com/fortmarek) in [#8944](https://github.com/tuist/tuist/pull/8944)
* add support for the new mise bin path by [@fortmarek](https://github.com/fortmarek) in [#8929](https://github.com/tuist/tuist/pull/8929)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.115.1...4.116.2

## What's Changed in 4.115.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* migrate Fixtures - Tuist initializer with .project by [@2sem](https://github.com/2sem) in [#8886](https://github.com/tuist/tuist/pull/8886)

## New Contributors
* [@2sem](https://github.com/2sem) made their first contribution in [#8886](https://github.com/tuist/tuist/pull/8886)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.115.0...4.115.1

## What's Changed in 4.115.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload command run analytics in the background by [@fortmarek](https://github.com/fortmarek) in [#8883](https://github.com/tuist/tuist/pull/8883)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.114.0...4.115.0

## What's Changed in 4.114.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* OIDC support Bitrise and CircleCI by [@fortmarek](https://github.com/fortmarek) in [#8878](https://github.com/tuist/tuist/pull/8878)
* OIDC token support for GitHub Actions by [@fortmarek](https://github.com/fortmarek) in [#8858](https://github.com/tuist/tuist/pull/8858)
### 🐛 Bug Fixes

* parsing XCActivityLog on Xcode 26.2 and newer by [@fortmarek](https://github.com/fortmarek) in [#8866](https://github.com/tuist/tuist/pull/8866)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.112.0...4.114.0

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
* skip warning Swift flags when hashing by [@fortmarek](https://github.com/fortmarek) in [#8728](https://github.com/tuist/tuist/pull/8728)
* prefer products with matching casing by [@fortmarek](https://github.com/fortmarek) in [#8717](https://github.com/tuist/tuist/pull/8717)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.106.1...4.107.1

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

## New Contributors
* [@Kolos65](https://github.com/Kolos65) made their first contribution in [#8665](https://github.com/tuist/tuist/pull/8665)

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

## New Contributors
* [@duarteich](https://github.com/duarteich) made their first contribution in [#8653](https://github.com/tuist/tuist/pull/8653)

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

## New Contributors
* [@ast3150](https://github.com/ast3150) made their first contribution in [#8607](https://github.com/tuist/tuist/pull/8607)

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

## New Contributors
* [@RomanAnpilov](https://github.com/RomanAnpilov) made their first contribution in [#8291](https://github.com/tuist/tuist/pull/8291)

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

## New Contributors
* [@MouadBenjrinija](https://github.com/MouadBenjrinija) made their first contribution in [#8445](https://github.com/tuist/tuist/pull/8445)

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

## New Contributors
* [@Monsteel](https://github.com/Monsteel) made their first contribution in [#8369](https://github.com/tuist/tuist/pull/8369)
* [@skalinina](https://github.com/skalinina) made their first contribution in [#8373](https://github.com/tuist/tuist/pull/8373)

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

**Full Changelog**: https://github.com/tuist/tuist/compare/4.78.1...4.78.2

## What's Changed in 4.78.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add default.metallib in static framework by [@bilousoleksandr](https://github.com/bilousoleksandr) in [#8207](https://github.com/tuist/tuist/pull/8207)

## New Contributors
* [@bilousoleksandr](https://github.com/bilousoleksandr) made their first contribution in [#8207](https://github.com/tuist/tuist/pull/8207)

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

## New Contributors
* [@ichikmarev](https://github.com/ichikmarev) made their first contribution in [#8099](https://github.com/tuist/tuist/pull/8099)

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

## New Contributors
* [@DenTelezhkin](https://github.com/DenTelezhkin) made their first contribution in [#7976](https://github.com/tuist/tuist/pull/7976)

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

## New Contributors
* [@ns-vasilev](https://github.com/ns-vasilev) made their first contribution in [#7660](https://github.com/tuist/tuist/pull/7660)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.5...4.55.7

<!-- generated by git-cliff -->
