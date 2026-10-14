# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.38](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.37...mbx-cache-store-v0.1.38) - 2026-10-08

### Added

- *(clean)* add --under to clean every workspace below a root ([#668](https://github.com/jdx/mr-boxington/pull/668))

## [0.1.37](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.36...mbx-cache-store-v0.1.37) - 2026-10-03

### Other

- correct outdated guides and CLI help, and reorganize the docs site ([#637](https://github.com/jdx/mr-boxington/pull/637))
- *(stats)* parallelize target and cache scans in mbx stats ([#631](https://github.com/jdx/mr-boxington/pull/631))

## [0.1.36](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.35...mbx-cache-store-v0.1.36) - 2026-10-02

### Fixed

- *(gc)* keep the cache disk above gc.min_free_size during concurrent builds ([#618](https://github.com/jdx/mr-boxington/pull/618))

## [0.1.35](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.34...mbx-cache-store-v0.1.35) - 2026-09-29

### Other

- updated the following local packages: mbx-cache-core

## [0.1.34](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.33...mbx-cache-store-v0.1.34) - 2026-09-28

### Other

- updated the following local packages: mbx-cache-core

## [0.1.33](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.32...mbx-cache-store-v0.1.33) - 2026-09-27

### Other

- *(store)* keep the LRU eviction test independent of runner speed ([#582](https://github.com/jdx/mr-boxington/pull/582))
- redesign the Mr Boxington logo and animated build mascot ([#558](https://github.com/jdx/mr-boxington/pull/558))

## [0.1.32](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.31...mbx-cache-store-v0.1.32) - 2026-09-25

### Added

- *(target)* adopt an existing target/ on the first build without prompting ([#545](https://github.com/jdx/mr-boxington/pull/545))

## [0.1.31](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.30...mbx-cache-store-v0.1.31) - 2026-09-23

### Other

- updated the following local packages: mbx-cache-core

## [0.1.30](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.29...mbx-cache-store-v0.1.30) - 2026-09-23

### Other

- updated the following local packages: mbx-cache-core

## [0.1.29](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.28...mbx-cache-store-v0.1.29) - 2026-09-20

### Added

- *(target)* adopt existing target directories without deleting outputs ([#499](https://github.com/jdx/mr-boxington/pull/499))

### Other

- *(gc)* run the automatic store sweep after the build returns ([#497](https://github.com/jdx/mr-boxington/pull/497))
- *(stats)* make mbx stats about 10x faster on machines with many checkouts ([#495](https://github.com/jdx/mr-boxington/pull/495))

## [0.1.28](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.27...mbx-cache-store-v0.1.28) - 2026-09-18

### Other

- updated the following local packages: mbx-cache-core

## [0.1.27](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.26...mbx-cache-store-v0.1.27) - 2026-09-17

### Other

- clarify cache behavior and organize setup guides ([#483](https://github.com/jdx/mr-boxington/pull/483))

## [0.1.26](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.25...mbx-cache-store-v0.1.26) - 2026-09-15

### Added

- *(cache)* export and import directory-form cache bundles ([#463](https://github.com/jdx/mr-boxington/pull/463))

### Other

- *(cache)* verify imported cache objects in parallel ([#462](https://github.com/jdx/mr-boxington/pull/462))

## [0.1.25](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.24...mbx-cache-store-v0.1.25) - 2026-09-14

### Fixed

- *(store)* keep imported task manifests bounded and ordered ([#456](https://github.com/jdx/mr-boxington/pull/456))

## [0.1.24](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.23...mbx-cache-store-v0.1.24) - 2026-09-11

### Added

- *(cli)* adapt cargo-pretty with live cache statistics ([#435](https://github.com/jdx/mr-boxington/pull/435))

## [0.1.23](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.22...mbx-cache-store-v0.1.23) - 2026-09-10

### Fixed

- *(cache)* retain predictions from every exported command ([#424](https://github.com/jdx/mr-boxington/pull/424))

## [0.1.22](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.21...mbx-cache-store-v0.1.22) - 2026-09-08

### Other

- adopt native mise Rust integration for setup ([#400](https://github.com/jdx/mr-boxington/pull/400))

## [0.1.21](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.20...mbx-cache-store-v0.1.21) - 2026-09-06

### Added

- *(tui)* add cache insights and lifetime statistics ([#389](https://github.com/jdx/mr-boxington/pull/389))

### Other

- refresh guides and redesign the documentation site ([#395](https://github.com/jdx/mr-boxington/pull/395))
- generate page-specific social preview images ([#374](https://github.com/jdx/mr-boxington/pull/374))

## [0.1.20](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.19...mbx-cache-store-v0.1.20) - 2026-09-05

### Other

- updated the following local packages: mbx-cache-core

## [0.1.19](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.18...mbx-cache-store-v0.1.19) - 2026-09-05

### Other

- take the bookkeeping out of the hot edit loop ([#362](https://github.com/jdx/mr-boxington/pull/362))

## [0.1.18](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.17...mbx-cache-store-v0.1.18) - 2026-09-05

### Other

- *(cache)* avoid redundant import copies and hashes ([#353](https://github.com/jdx/mr-boxington/pull/353))

## [0.1.17](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.16...mbx-cache-store-v0.1.17) - 2026-09-04

### Added

- *(cache)* restore Cargo workspace state from exports ([#337](https://github.com/jdx/mr-boxington/pull/337))

## [0.1.16](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.15...mbx-cache-store-v0.1.16) - 2026-09-03

### Other

- keep hot-edit bookkeeping off the build's critical path ([#331](https://github.com/jdx/mr-boxington/pull/331))

## [0.1.15](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.14...mbx-cache-store-v0.1.15) - 2026-09-03

### Added

- manage profile-specific linkers ([#319](https://github.com/jdx/mr-boxington/pull/319))

## [0.1.14](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.13...mbx-cache-store-v0.1.14) - 2026-09-02

### Other

- updated the following local packages: mbx-cache-core

## [0.1.13](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.12...mbx-cache-store-v0.1.13) - 2026-09-02

### Fixed

- *(cache)* preserve grouped exports through collection ([#280](https://github.com/jdx/mr-boxington/pull/280))

### Other

- trim the README and correct link caching claims ([#277](https://github.com/jdx/mr-boxington/pull/277))

## [0.1.12](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.11...mbx-cache-store-v0.1.12) - 2026-09-02

### Fixed

- fix managed target lifecycle edges ([#269](https://github.com/jdx/mr-boxington/pull/269))
- release cache pinned by phantom checkouts ([#270](https://github.com/jdx/mr-boxington/pull/270))

## [0.1.11](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.10...mbx-cache-store-v0.1.11) - 2026-09-01

### Other

- updated the following local packages: mbx-cache-core

## [0.1.10](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.9...mbx-cache-store-v0.1.10) - 2026-08-31

### Added

- *(setup)* use mise command wrappers ([#249](https://github.com/jdx/mr-boxington/pull/249))

## [0.1.9](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.8...mbx-cache-store-v0.1.9) - 2026-08-31

### Fixed

- document Cargo shim activation for agents ([#233](https://github.com/jdx/mr-boxington/pull/233))

## [0.1.8](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.7...mbx-cache-store-v0.1.8) - 2026-08-30

### Added

- *(cache)* deduplicate in-flight work across runners ([#223](https://github.com/jdx/mr-boxington/pull/223))
- cache rustdoc actions ([#226](https://github.com/jdx/mr-boxington/pull/226))
- *(cache)* export portable build closures ([#227](https://github.com/jdx/mr-boxington/pull/227))

### Fixed

- *(cache)* import exported sparse files ([#228](https://github.com/jdx/mr-boxington/pull/228))

## [0.1.7](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.6...mbx-cache-store-v0.1.7) - 2026-08-29

### Other

- recognize Cargo, sccache, and kache ([#205](https://github.com/jdx/mr-boxington/pull/205))

## [0.1.6](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.5...mbx-cache-store-v0.1.6) - 2026-08-29

### Other

- lead the landing page with three feature cards ([#198](https://github.com/jdx/mr-boxington/pull/198))
- corrections, editorial rebalance, and a CI anchor check ([#195](https://github.com/jdx/mr-boxington/pull/195))
- *(benchmarks)* demonstrate parallel lint scheduling ([#191](https://github.com/jdx/mr-boxington/pull/191))

## [0.1.5](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.4...mbx-cache-store-v0.1.5) - 2026-08-29

### Fixed

- allow caching release-marked builds ([#194](https://github.com/jdx/mr-boxington/pull/194))

## [0.1.4](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.3...mbx-cache-store-v0.1.4) - 2026-08-29

### Added

- *(release)* add GNU Linux artifacts ([#181](https://github.com/jdx/mr-boxington/pull/181))

## [0.1.3](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.2...mbx-cache-store-v0.1.3) - 2026-08-29

### Other

- updated the following local packages: mbx-cache-core

## [0.1.2](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.1...mbx-cache-store-v0.1.2) - 2026-08-28

### Other

- updated the following local packages: mbx-cache-core

## [0.1.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-store-v0.1.0...mbx-cache-store-v0.1.1) - 2026-08-28

### Added

- add Windows ARM64 support ([#147](https://github.com/jdx/mr-boxington/pull/147))

## [0.1.0](https://github.com/jdx/mr-boxington/releases/tag/mbx-cache-store-v0.1.0) - 2026-08-27

### Added

- cache standalone C and C++ builds through mbx exec ([#138](https://github.com/jdx/mr-boxington/pull/138))
- *(cache)* expose shared Cargo cache integration ([#130](https://github.com/jdx/mr-boxington/pull/130))
- mbx tui, a live view of every build's cache activity ([#128](https://github.com/jdx/mr-boxington/pull/128))
- [**breaking**] open the extensible public types to extension ([#103](https://github.com/jdx/mr-boxington/pull/103))
- make landing demo interactive and tag output ([#94](https://github.com/jdx/mr-boxington/pull/94))
- make mbx build the golden path and hide setup ([#75](https://github.com/jdx/mr-boxington/pull/75))
- add cache inspection commands ([#63](https://github.com/jdx/mr-boxington/pull/63))
- add managed target retention policies ([#62](https://github.com/jdx/mr-boxington/pull/62))
- cache compiler-bundled WebAssembly links ([#66](https://github.com/jdx/mr-boxington/pull/66))
- add explicit remote prefetch ([#64](https://github.com/jdx/mr-boxington/pull/64))
- cache compiler-linked wasm outputs ([#45](https://github.com/jdx/mr-boxington/pull/45))
- cache plain cargo commands after setup ([#40](https://github.com/jdx/mr-boxington/pull/40))
- add direct cargo wrapper and docs website ([#28](https://github.com/jdx/mr-boxington/pull/28))
- *(target)* place target directories so a deleted checkout frees them ([#24](https://github.com/jdx/mr-boxington/pull/24))
- *(store)* collect automatically, and release deleted checkouts first ([#23](https://github.com/jdx/mr-boxington/pull/23))
- *(session)* share compilations that read OUT_DIR across checkouts ([#21](https://github.com/jdx/mr-boxington/pull/21))
- *(session)* let a build opt into incremental compilation ([#20](https://github.com/jdx/mr-boxington/pull/20))
- *(session)* count the compilations the cache was never asked about ([#18](https://github.com/jdx/mr-boxington/pull/18))
- *(release)* publish prebuilt binaries on a tag ([#14](https://github.com/jdx/mr-boxington/pull/14))
- *(session)* log why each compilation was not cached ([#11](https://github.com/jdx/mr-boxington/pull/11))
- *(session)* count compilations the cache declined ([#10](https://github.com/jdx/mr-boxington/pull/10))

### Other

- simplify the landing page for 1.0 ([#96](https://github.com/jdx/mr-boxington/pull/96))
- stop building macOS x64 releases ([#92](https://github.com/jdx/mr-boxington/pull/92))
- recommend mr-boxington-action ([#54](https://github.com/jdx/mr-boxington/pull/54))
- enforce protocol and API compatibility ([#43](https://github.com/jdx/mr-boxington/pull/43))
- establish compatibility and security policy ([#37](https://github.com/jdx/mr-boxington/pull/37))
- reword tagline to name target/ ([#36](https://github.com/jdx/mr-boxington/pull/36))
- *(release)* hand versioning and publishing to release-plz ([#16](https://github.com/jdx/mr-boxington/pull/16))
- qualify cross-checkout sharing, and test the boundary ([#12](https://github.com/jdx/mr-boxington/pull/12))
- document usage and the standalone-mode blocker ([#8](https://github.com/jdx/mr-boxington/pull/8))
- initial placeholder readme
