# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.20.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.19.4...mbx-cache-rustc-v0.20.0) - 2026-10-08

### Added

- *(clean)* add --under to clean every workspace below a root ([#668](https://github.com/jdx/mr-boxington/pull/668))

### Fixed

- *(cache)* do not reuse file digests recorded within a timestamp tick ([#674](https://github.com/jdx/mr-boxington/pull/674))
- *(cache)* invalidate Rust compilations when build-script inputs change ([#667](https://github.com/jdx/mr-boxington/pull/667))
- *(cache)* cache builds with synchronous unwind tables ([#655](https://github.com/jdx/mr-boxington/pull/655))

## [0.19.4](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.19.3...mbx-cache-rustc-v0.19.4) - 2026-10-03

### Other

- correct outdated guides and CLI help, and reorganize the docs site ([#637](https://github.com/jdx/mr-boxington/pull/637))

## [0.19.3](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.19.2...mbx-cache-rustc-v0.19.3) - 2026-10-02

### Fixed

- *(cache)* cache Windows proc macros and build scripts linked with /STACK or /Brepro ([#619](https://github.com/jdx/mr-boxington/pull/619))
- *(cache)* keep private incremental state for crates with uncacheable native search paths ([#617](https://github.com/jdx/mr-boxington/pull/617))

## [0.19.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.19.0...mbx-cache-rustc-v0.19.1) - 2026-09-28

### Fixed

- *(cache)* track external native library inputs ([#595](https://github.com/jdx/mr-boxington/pull/595))
- *(cache)* model rustc codegen backend selection ([#592](https://github.com/jdx/mr-boxington/pull/592))
- *(cache)* avoid stale rlibs from external native archives ([#589](https://github.com/jdx/mr-boxington/pull/589))

## [0.19.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.18.2...mbx-cache-rustc-v0.19.0) - 2026-09-27

### Fixed

- *(rustc)* cache -Zbuild-std standard library units instead of bypassing them ([#566](https://github.com/jdx/mr-boxington/pull/566))

### Other

- *(cache)* cache Linux links that pass -z keyword flags ([#580](https://github.com/jdx/mr-boxington/pull/580))
- *(cache)* cache cdylib links on Linux ([#579](https://github.com/jdx/mr-boxington/pull/579))
- redesign the Mr Boxington logo and animated build mascot ([#558](https://github.com/jdx/mr-boxington/pull/558))

## [0.18.2](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.18.1...mbx-cache-rustc-v0.18.2) - 2026-09-25

### Added

- *(target)* adopt an existing target/ on the first build without prompting ([#545](https://github.com/jdx/mr-boxington/pull/545))

## [0.18.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.18.0...mbx-cache-rustc-v0.18.1) - 2026-09-23

### Fixed

- *(cache)* only treat Cargo build scripts as build scripts ([#528](https://github.com/jdx/mr-boxington/pull/528))
- *(cache)* replay build scripts declared with a custom path ([#526](https://github.com/jdx/mr-boxington/pull/526))

## [0.17.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.17.0...mbx-cache-rustc-v0.17.1) - 2026-09-20

### Added

- *(target)* adopt existing target directories without deleting outputs ([#499](https://github.com/jdx/mr-boxington/pull/499))

## [0.17.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.16.4...mbx-cache-rustc-v0.17.0) - 2026-09-18

### Added

- *(cache)* cache library compiles that name a native library ([#490](https://github.com/jdx/mr-boxington/pull/490))

## [0.16.4](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.16.3...mbx-cache-rustc-v0.16.4) - 2026-09-17

### Other

- clarify cache behavior and organize setup guides ([#483](https://github.com/jdx/mr-boxington/pull/483))

## [0.16.3](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.16.2...mbx-cache-rustc-v0.16.3) - 2026-09-15

### Fixed

- bind compiler input digests to validated file identities ([#433](https://github.com/jdx/mr-boxington/pull/433))

## [0.16.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.16.0...mbx-cache-rustc-v0.16.1) - 2026-09-11

### Added

- *(cli)* adapt cargo-pretty with live cache statistics ([#435](https://github.com/jdx/mr-boxington/pull/435))

### Fixed

- *(cache)* cover dependency debug paths in macOS links ([#430](https://github.com/jdx/mr-boxington/pull/430))
- *(cache)* stabilize macOS proc macro install names ([#427](https://github.com/jdx/mr-boxington/pull/427))

## [0.15.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.14.0...mbx-cache-rustc-v0.15.0) - 2026-09-08

### Other

- adopt native mise Rust integration for setup ([#400](https://github.com/jdx/mr-boxington/pull/400))

## [0.14.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.13.1...mbx-cache-rustc-v0.14.0) - 2026-09-06

### Added

- *(tui)* add cache insights and lifetime statistics ([#389](https://github.com/jdx/mr-boxington/pull/389))

### Other

- refresh guides and redesign the documentation site ([#395](https://github.com/jdx/mr-boxington/pull/395))
- generate page-specific social preview images ([#374](https://github.com/jdx/mr-boxington/pull/374))

## [0.13.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.12.0...mbx-cache-rustc-v0.13.0) - 2026-09-05

### Other

- take the bookkeeping out of the hot edit loop ([#362](https://github.com/jdx/mr-boxington/pull/362))

## [0.12.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.11.5...mbx-cache-rustc-v0.12.0) - 2026-09-05

### Fixed

- restore NFS digest reuse without read storms ([#341](https://github.com/jdx/mr-boxington/pull/341))

## [0.11.5](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.11.4...mbx-cache-rustc-v0.11.5) - 2026-09-04

### Fixed

- verify NFS compiler inputs by content ([#338](https://github.com/jdx/mr-boxington/pull/338))

## [0.11.3](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.11.2...mbx-cache-rustc-v0.11.3) - 2026-09-03

### Added

- manage profile-specific linkers ([#319](https://github.com/jdx/mr-boxington/pull/319))

### Fixed

- verify compiler inputs across clock domains ([#318](https://github.com/jdx/mr-boxington/pull/318))

## [0.11.2](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.11.1...mbx-cache-rustc-v0.11.2) - 2026-09-02

### Fixed

- cache dependencies of LTO builds ([#286](https://github.com/jdx/mr-boxington/pull/286))

### Other

- verify compiler inputs by identity after compiling ([#284](https://github.com/jdx/mr-boxington/pull/284))

## [0.11.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.11.0...mbx-cache-rustc-v0.11.1) - 2026-09-02

### Other

- trim the README and correct link caching claims ([#277](https://github.com/jdx/mr-boxington/pull/277))

## [0.11.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.10.3...mbx-cache-rustc-v0.11.0) - 2026-09-02

### Fixed

- fix managed target lifecycle edges ([#269](https://github.com/jdx/mr-boxington/pull/269))
- release cache pinned by phantom checkouts ([#270](https://github.com/jdx/mr-boxington/pull/270))
- cache clippy workspace compilations ([#273](https://github.com/jdx/mr-boxington/pull/273))

## [0.10.3](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.10.2...mbx-cache-rustc-v0.10.3) - 2026-09-01

### Added

- *(cache)* model -fuse-ld linker selection for native links ([#254](https://github.com/jdx/mr-boxington/pull/254))

## [0.10.2](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.10.1...mbx-cache-rustc-v0.10.2) - 2026-08-31

### Added

- *(setup)* use mise command wrappers ([#249](https://github.com/jdx/mr-boxington/pull/249))

## [0.10.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.10.0...mbx-cache-rustc-v0.10.1) - 2026-08-31

### Fixed

- *(cache)* model rustc frontend parallelism flags ([#238](https://github.com/jdx/mr-boxington/pull/238))
- document Cargo shim activation for agents ([#233](https://github.com/jdx/mr-boxington/pull/233))

## [0.10.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.9.4...mbx-cache-rustc-v0.10.0) - 2026-08-30

### Added

- cache build script execution ([#225](https://github.com/jdx/mr-boxington/pull/225))
- *(cache)* deduplicate in-flight work across runners ([#223](https://github.com/jdx/mr-boxington/pull/223))
- cache Windows links and MSVC compiles ([#224](https://github.com/jdx/mr-boxington/pull/224))
- cache rustdoc actions ([#226](https://github.com/jdx/mr-boxington/pull/226))
- *(mbx)* prescribe fixes for cache bypasses ([#222](https://github.com/jdx/mr-boxington/pull/222))

### Fixed

- *(rustc)* compact large action predictions ([#218](https://github.com/jdx/mr-boxington/pull/218))

### Other

- remove pre-v1 format fallbacks ([#219](https://github.com/jdx/mr-boxington/pull/219))
- share cache path mapping ([#215](https://github.com/jdx/mr-boxington/pull/215))

## [0.9.4](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.9.3...mbx-cache-rustc-v0.9.4) - 2026-08-29

### Other

- recognize Cargo, sccache, and kache ([#205](https://github.com/jdx/mr-boxington/pull/205))

## [0.9.3](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.9.2...mbx-cache-rustc-v0.9.3) - 2026-08-29

### Other

- lead the landing page with three feature cards ([#198](https://github.com/jdx/mr-boxington/pull/198))
- cache linked proc macros ([#197](https://github.com/jdx/mr-boxington/pull/197))
- corrections, editorial rebalance, and a CI anchor check ([#195](https://github.com/jdx/mr-boxington/pull/195))
- *(benchmarks)* demonstrate parallel lint scheduling ([#191](https://github.com/jdx/mr-boxington/pull/191))

## [0.9.2](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.9.1...mbx-cache-rustc-v0.9.2) - 2026-08-29

### Fixed

- allow caching release-marked builds ([#194](https://github.com/jdx/mr-boxington/pull/194))

## [0.9.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.9.0...mbx-cache-rustc-v0.9.1) - 2026-08-29

### Added

- *(release)* add GNU Linux artifacts ([#181](https://github.com/jdx/mr-boxington/pull/181))
- *(rustc)* cache the compilations that never link ([#177](https://github.com/jdx/mr-boxington/pull/177))

## [0.9.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.8.0...mbx-cache-rustc-v0.9.0) - 2026-08-29

### Added

- *(cache-rustc)* cache macOS debug links behind an oso_prefix the shim appends ([#166](https://github.com/jdx/mr-boxington/pull/166))

### Fixed

- *(cache-rustc)* predict a native search directory by name, not by its contents ([#162](https://github.com/jdx/mr-boxington/pull/162))
- *(cache-rustc)* model -C link-arg where nothing links ([#161](https://github.com/jdx/mr-boxington/pull/161))

### Other

- [**breaking**] stop rehashing inputs the session already read in full ([#164](https://github.com/jdx/mr-boxington/pull/164))

## [0.8.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.7.1...mbx-cache-rustc-v0.8.0) - 2026-08-28

### Fixed

- *(cache-rustc)* key inert native search directories by path ([#153](https://github.com/jdx/mr-boxington/pull/153))

## [0.7.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.7.0...mbx-cache-rustc-v0.7.1) - 2026-08-28

### Added

- add Windows ARM64 support ([#147](https://github.com/jdx/mr-boxington/pull/147))

## [0.7.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.5.1...mbx-cache-rustc-v0.7.0) - 2026-08-27

### Added

- cache natively linked test binaries ([#129](https://github.com/jdx/mr-boxington/pull/129))
- *(cache)* expose shared Cargo cache integration ([#130](https://github.com/jdx/mr-boxington/pull/130))
- compile churning crates incrementally ([#127](https://github.com/jdx/mr-boxington/pull/127))
- mbx tui, a live view of every build's cache activity ([#128](https://github.com/jdx/mr-boxington/pull/128))

### Fixed

- *(rustc)* restore results into the checkout that asked for them ([#141](https://github.com/jdx/mr-boxington/pull/141))

## [0.5.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.5.0...mbx-cache-rustc-v0.5.1) - 2026-08-26

### Fixed

- cache libraries with native search paths ([#120](https://github.com/jdx/mr-boxington/pull/120))

## [0.5.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.4.0...mbx-cache-rustc-v0.5.0) - 2026-08-26

### Added

- [**breaking**] open the extensible public types to extension ([#103](https://github.com/jdx/mr-boxington/pull/103))

### Other

- simplify the landing page for 1.0 ([#96](https://github.com/jdx/mr-boxington/pull/96))
- give every published crate its crates.io metadata ([#97](https://github.com/jdx/mr-boxington/pull/97))
- version each crate by what it promises ([#100](https://github.com/jdx/mr-boxington/pull/100))

## [0.4.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.3.0...mbx-cache-rustc-v0.4.0) - 2026-08-25

### Added

- report compiler time saved and spent ([#59](https://github.com/jdx/mr-boxington/pull/59))
- support rustc response files ([#65](https://github.com/jdx/mr-boxington/pull/65))
- cache compiler-bundled WebAssembly links ([#66](https://github.com/jdx/mr-boxington/pull/66))
- *(protocol)* share remote cache contract ([#68](https://github.com/jdx/mr-boxington/pull/68))
- cache compiler-linked wasm outputs ([#45](https://github.com/jdx/mr-boxington/pull/45))
- cache plain cargo commands after setup ([#40](https://github.com/jdx/mr-boxington/pull/40))

### Other

- give every crate one synchronized version ([#86](https://github.com/jdx/mr-boxington/pull/86))
- establish compatibility and security policy ([#37](https://github.com/jdx/mr-boxington/pull/37))
- move inline tests into focused modules ([#42](https://github.com/jdx/mr-boxington/pull/42))
- define published Rust API surface ([#41](https://github.com/jdx/mr-boxington/pull/41))

## [0.2.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.1.0...mbx-cache-rustc-v0.2.0) - 2026-08-22

### Added

- *(session)* share compilations that read OUT_DIR across checkouts ([#21](https://github.com/jdx/mr-boxington/pull/21))

## [0.1.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-rustc-v0.0.0...mbx-cache-rustc-v0.1.0) - 2026-08-21

### Added

- *(release)* publish prebuilt binaries on a tag ([#14](https://github.com/jdx/mr-boxington/pull/14))
- *(session)* log why each compilation was not cached ([#11](https://github.com/jdx/mr-boxington/pull/11))
- *(session)* count compilations the cache declined ([#10](https://github.com/jdx/mr-boxington/pull/10))
- *(cache-rustc)* add rustc action analysis ([#5](https://github.com/jdx/mr-boxington/pull/5))
