# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.20.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.19.4...mbx-cache-core-v0.20.0) - 2026-10-08

### Added

- *(clean)* add --under to clean every workspace below a root ([#668](https://github.com/jdx/mr-boxington/pull/668))

### Fixed

- *(cache)* do not reuse file digests recorded within a timestamp tick ([#674](https://github.com/jdx/mr-boxington/pull/674))

## [0.19.4](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.19.3...mbx-cache-core-v0.19.4) - 2026-10-03

### Other

- correct outdated guides and CLI help, and reorganize the docs site ([#637](https://github.com/jdx/mr-boxington/pull/637))

## [0.19.3](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.19.2...mbx-cache-core-v0.19.3) - 2026-10-02

### Fixed

- *(remote)* show credential hints for HTTP 400 token errors ([#621](https://github.com/jdx/mr-boxington/pull/621))
- *(remote)* block the instance role behind AWS profiles and renew credentials in the background ([#609](https://github.com/jdx/mr-boxington/pull/609))

## [0.19.2](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.19.1...mbx-cache-core-v0.19.2) - 2026-09-29

### Added

- *(remote)* use the EC2 instance role for s3 remotes without AWS_* credentials ([#602](https://github.com/jdx/mr-boxington/pull/602))

## [0.19.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.19.0...mbx-cache-core-v0.19.1) - 2026-09-28

### Fixed

- *(cache)* pin linker search directories by absolute path on WSL ([#597](https://github.com/jdx/mr-boxington/pull/597))
- *(stats)* make cache lookups add up to hits plus misses ([#583](https://github.com/jdx/mr-boxington/pull/583))

## [0.19.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.18.2...mbx-cache-core-v0.19.0) - 2026-09-27

### Added

- *(analyze)* show the critical path of the last build ([#570](https://github.com/jdx/mr-boxington/pull/570))
- *(events)* record the crate and compiler time of bypassed compilations ([#568](https://github.com/jdx/mr-boxington/pull/568))

### Other

- redesign the Mr Boxington logo and animated build mascot ([#558](https://github.com/jdx/mr-boxington/pull/558))

## [0.18.2](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.18.1...mbx-cache-core-v0.18.2) - 2026-09-25

### Added

- *(target)* adopt an existing target/ on the first build without prompting ([#545](https://github.com/jdx/mr-boxington/pull/545))

### Fixed

- support Cargo 1.100's build layout and the Rust 1.99 toolchain ([#548](https://github.com/jdx/mr-boxington/pull/548))

### Other

- *(prefetch)* allocate only selected action candidates ([#546](https://github.com/jdx/mr-boxington/pull/546))
- *(prefetch)* rank predictions without building their full JSON trees ([#543](https://github.com/jdx/mr-boxington/pull/543))
- *(cache)* merge task manifests without cloning prediction payloads ([#541](https://github.com/jdx/mr-boxington/pull/541))
- *(prefetch)* avoid repeated copies of blob pack candidates ([#542](https://github.com/jdx/mr-boxington/pull/542))
- *(cc)* accelerate timestamp macro scans during input hashing ([#538](https://github.com/jdx/mr-boxington/pull/538))

## [0.18.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.17.1...mbx-cache-core-v0.18.0) - 2026-09-23

### Added

- *(cache-core)* [**breaking**] account for hard-linked outputs in restore statistics ([#514](https://github.com/jdx/mr-boxington/pull/514))

## [0.17.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.17.0...mbx-cache-core-v0.17.1) - 2026-09-20

### Added

- *(progress)* show friendlier build times and fewer updates on long builds ([#500](https://github.com/jdx/mr-boxington/pull/500))
- *(target)* adopt existing target directories without deleting outputs ([#499](https://github.com/jdx/mr-boxington/pull/499))

## [0.17.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.16.4...mbx-cache-core-v0.17.0) - 2026-09-18

### Added

- *(rustc)* let Cargo pipeline dependents while mbx finishes a miss ([#492](https://github.com/jdx/mr-boxington/pull/492))

### Other

- *(cache)* take two disk round trips off every cache miss ([#491](https://github.com/jdx/mr-boxington/pull/491))

## [0.16.4](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.16.3...mbx-cache-core-v0.16.4) - 2026-09-17

### Fixed

- *(stats)* tell an incremental compilation's lookup apart from its storage ([#482](https://github.com/jdx/mr-boxington/pull/482))
- *(explain)* diagnose cross-checkout misses and name the crate behind them ([#468](https://github.com/jdx/mr-boxington/pull/468))

### Other

- clarify cache behavior and organize setup guides ([#483](https://github.com/jdx/mr-boxington/pull/483))

## [0.16.3](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.16.2...mbx-cache-core-v0.16.3) - 2026-09-15

### Fixed

- bind compiler input digests to validated file identities ([#433](https://github.com/jdx/mr-boxington/pull/433))

## [0.16.2](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.16.1...mbx-cache-core-v0.16.2) - 2026-09-14

### Fixed

- *(store)* keep imported task manifests bounded and ordered ([#456](https://github.com/jdx/mr-boxington/pull/456))
- *(cache)* rotate stale action predictions ([#453](https://github.com/jdx/mr-boxington/pull/453))

### Other

- *(deps)* bump the cargo-dependencies group with 7 updates ([#451](https://github.com/jdx/mr-boxington/pull/451))

## [0.16.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.16.0...mbx-cache-core-v0.16.1) - 2026-09-11

### Added

- *(cli)* adapt cargo-pretty with live cache statistics ([#435](https://github.com/jdx/mr-boxington/pull/435))

## [0.16.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.15.0...mbx-cache-core-v0.16.0) - 2026-09-10

### Fixed

- forward routine shim diagnostics as debug logs ([#417](https://github.com/jdx/mr-boxington/pull/417))
- avoid repeated Nix store scans during C builds ([#414](https://github.com/jdx/mr-boxington/pull/414))

## [0.15.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.14.0...mbx-cache-core-v0.15.0) - 2026-09-08

### Fixed

- keep rustc shim diagnostics out of Cargo fingerprints ([#405](https://github.com/jdx/mr-boxington/pull/405))

### Other

- adopt native mise Rust integration for setup ([#400](https://github.com/jdx/mr-boxington/pull/400))

## [0.14.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.13.1...mbx-cache-core-v0.14.0) - 2026-09-06

### Added

- *(report)* record wrapper phases and export Perfetto traces ([#390](https://github.com/jdx/mr-boxington/pull/390))
- *(tui)* add cache insights and lifetime statistics ([#389](https://github.com/jdx/mr-boxington/pull/389))

### Other

- refresh guides and redesign the documentation site ([#395](https://github.com/jdx/mr-boxington/pull/395))
- generate page-specific social preview images ([#374](https://github.com/jdx/mr-boxington/pull/374))

## [0.13.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.13.0...mbx-cache-core-v0.13.1) - 2026-09-05

### Fixed

- tolerate NFS mtime reconciliation in content snapshots ([#370](https://github.com/jdx/mr-boxington/pull/370))

## [0.13.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.12.0...mbx-cache-core-v0.13.0) - 2026-09-05

### Other

- take the bookkeeping out of the hot edit loop ([#362](https://github.com/jdx/mr-boxington/pull/362))

## [0.12.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.11.5...mbx-cache-core-v0.12.0) - 2026-09-05

### Fixed

- restore NFS digest reuse without read storms ([#341](https://github.com/jdx/mr-boxington/pull/341))

### Other

- *(cache)* avoid redundant import copies and hashes ([#353](https://github.com/jdx/mr-boxington/pull/353))

## [0.11.5](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.11.4...mbx-cache-core-v0.11.5) - 2026-09-04

### Fixed

- verify NFS compiler inputs by content ([#338](https://github.com/jdx/mr-boxington/pull/338))

## [0.11.4](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.11.3...mbx-cache-core-v0.11.4) - 2026-09-03

### Added

- *(cache)* inherit predictions from earlier lockfiles ([#327](https://github.com/jdx/mr-boxington/pull/327))

### Other

- keep hot-edit bookkeeping off the build's critical path ([#331](https://github.com/jdx/mr-boxington/pull/331))
- *(cache)* adopt prefetched blobs into CAS ([#324](https://github.com/jdx/mr-boxington/pull/324))
- *(cache)* download blob packs concurrently ([#323](https://github.com/jdx/mr-boxington/pull/323))
- *(cache)* gate prefetch on matching adapters ([#321](https://github.com/jdx/mr-boxington/pull/321))

## [0.11.3](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.11.2...mbx-cache-core-v0.11.3) - 2026-09-03

### Added

- manage profile-specific linkers ([#319](https://github.com/jdx/mr-boxington/pull/319))

### Other

- *(cache)* complete large remote transfers reliably ([#320](https://github.com/jdx/mr-boxington/pull/320))

## [0.11.2](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.11.1...mbx-cache-core-v0.11.2) - 2026-09-02

### Fixed

- *(remote)* bound what a build loses to failed cache reads ([#292](https://github.com/jdx/mr-boxington/pull/292))

### Other

- verify compiler inputs by identity after compiling ([#284](https://github.com/jdx/mr-boxington/pull/284))
- carry the file-digest ledger across sessions ([#285](https://github.com/jdx/mr-boxington/pull/285))

## [0.11.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.11.0...mbx-cache-core-v0.11.1) - 2026-09-02

### Other

- trim the README and correct link caching claims ([#277](https://github.com/jdx/mr-boxington/pull/277))

## [0.11.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.10.3...mbx-cache-core-v0.11.0) - 2026-09-02

### Added

- explain cache misses from session history ([#274](https://github.com/jdx/mr-boxington/pull/274))

### Fixed

- fix managed target lifecycle edges ([#269](https://github.com/jdx/mr-boxington/pull/269))
- release cache pinned by phantom checkouts ([#270](https://github.com/jdx/mr-boxington/pull/270))
- cache clippy workspace compilations ([#273](https://github.com/jdx/mr-boxington/pull/273))
- *(cache)* include remote error response details ([#275](https://github.com/jdx/mr-boxington/pull/275))

### Other

- preserve Cargo rustc probe cache ([#268](https://github.com/jdx/mr-boxington/pull/268))

## [0.10.3](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.10.2...mbx-cache-core-v0.10.3) - 2026-09-01

### Added

- *(cache)* model -fuse-ld linker selection for native links ([#254](https://github.com/jdx/mr-boxington/pull/254))

## [0.10.2](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.10.1...mbx-cache-core-v0.10.2) - 2026-08-31

### Added

- *(setup)* use mise command wrappers ([#249](https://github.com/jdx/mr-boxington/pull/249))

### Other

- *(cache)* prefetch outputs in progressive waves ([#244](https://github.com/jdx/mr-boxington/pull/244))
- *(cache)* reduce speculative action prefetch ([#242](https://github.com/jdx/mr-boxington/pull/242))

## [0.10.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.10.0...mbx-cache-core-v0.10.1) - 2026-08-31

### Fixed

- document Cargo shim activation for agents ([#233](https://github.com/jdx/mr-boxington/pull/233))

### Other

- bound remote cache prefetch work ([#239](https://github.com/jdx/mr-boxington/pull/239))

## [0.10.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.9.4...mbx-cache-core-v0.10.0) - 2026-08-30

### Added

- *(cache)* deduplicate in-flight work across runners ([#223](https://github.com/jdx/mr-boxington/pull/223))
- cache Windows links and MSVC compiles ([#224](https://github.com/jdx/mr-boxington/pull/224))
- cache rustdoc actions ([#226](https://github.com/jdx/mr-boxington/pull/226))
- *(cache)* export portable build closures ([#227](https://github.com/jdx/mr-boxington/pull/227))

### Other

- *(cache)* start prediction prefetch earlier ([#220](https://github.com/jdx/mr-boxington/pull/220))
- remove pre-v1 format fallbacks ([#219](https://github.com/jdx/mr-boxington/pull/219))
- share cache path mapping ([#215](https://github.com/jdx/mr-boxington/pull/215))
- *(core)* split cache agent modules ([#217](https://github.com/jdx/mr-boxington/pull/217))

## [0.9.4](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.9.3...mbx-cache-core-v0.9.4) - 2026-08-29

### Other

- recognize Cargo, sccache, and kache ([#205](https://github.com/jdx/mr-boxington/pull/205))

## [0.9.3](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.9.2...mbx-cache-core-v0.9.3) - 2026-08-29

### Other

- lead the landing page with three feature cards ([#198](https://github.com/jdx/mr-boxington/pull/198))
- corrections, editorial rebalance, and a CI anchor check ([#195](https://github.com/jdx/mr-boxington/pull/195))
- *(benchmarks)* demonstrate parallel lint scheduling ([#191](https://github.com/jdx/mr-boxington/pull/191))

## [0.9.2](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.9.1...mbx-cache-core-v0.9.2) - 2026-08-29

### Fixed

- allow caching release-marked builds ([#194](https://github.com/jdx/mr-boxington/pull/194))

## [0.9.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.9.0...mbx-cache-core-v0.9.1) - 2026-08-29

### Added

- *(release)* add GNU Linux artifacts ([#181](https://github.com/jdx/mr-boxington/pull/181))

## [0.9.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.8.0...mbx-cache-core-v0.9.0) - 2026-08-29

### Fixed

- *(cache-rustc)* predict a native search directory by name, not by its contents ([#162](https://github.com/jdx/mr-boxington/pull/162))

### Other

- keep outputs that already hold the cached bytes ([#165](https://github.com/jdx/mr-boxington/pull/165))
- [**breaking**] stop rehashing inputs the session already read in full ([#164](https://github.com/jdx/mr-boxington/pull/164))

## [0.8.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.7.1...mbx-cache-core-v0.8.0) - 2026-08-28

### Fixed

- *(cc)* [**breaking**] keep shim diagnostics off the intercepted compiler's stderr ([#154](https://github.com/jdx/mr-boxington/pull/154))
- *(cache-rustc)* key inert native search directories by path ([#153](https://github.com/jdx/mr-boxington/pull/153))

### Other

- stop rereading cached artifacts on warm hits ([#152](https://github.com/jdx/mr-boxington/pull/152))

## [0.7.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.7.0...mbx-cache-core-v0.7.1) - 2026-08-28

### Added

- add Windows ARM64 support ([#147](https://github.com/jdx/mr-boxington/pull/147))

## [0.7.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.5.1...mbx-cache-core-v0.7.0) - 2026-08-27

### Added

- cache C and C++ compiles from build scripts ([#132](https://github.com/jdx/mr-boxington/pull/132))
- cache natively linked test binaries ([#129](https://github.com/jdx/mr-boxington/pull/129))
- cache to an S3-compatible object store ([#140](https://github.com/jdx/mr-boxington/pull/140))
- *(cache)* expose shared Cargo cache integration ([#130](https://github.com/jdx/mr-boxington/pull/130))
- batch remote action lookups and blob uploads ([#131](https://github.com/jdx/mr-boxington/pull/131))
- publish remote objects after the build asks for them ([#126](https://github.com/jdx/mr-boxington/pull/126))
- compile churning crates incrementally ([#127](https://github.com/jdx/mr-boxington/pull/127))
- mbx tui, a live view of every build's cache activity ([#128](https://github.com/jdx/mr-boxington/pull/128))

### Fixed

- bound blob pack members to digest sizes ([#136](https://github.com/jdx/mr-boxington/pull/136))

### Other

- define download_timeout as a whole-download deadline ([#142](https://github.com/jdx/mr-boxington/pull/142))

## [0.5.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.4.0...mbx-cache-core-v0.5.0) - 2026-08-26

### Added

- [**breaking**] open the extensible public types to extension ([#103](https://github.com/jdx/mr-boxington/pull/103))
- count remote cache failures in the summary ([#112](https://github.com/jdx/mr-boxington/pull/112))

### Fixed

- carry manifest entity tags opaquely ([#110](https://github.com/jdx/mr-boxington/pull/110))
- stop timing the runner in the prefetch independence test ([#105](https://github.com/jdx/mr-boxington/pull/105))

### Other

- simplify the landing page for 1.0 ([#96](https://github.com/jdx/mr-boxington/pull/96))
- let the agent's statistics grow without breaking ([#114](https://github.com/jdx/mr-boxington/pull/114))
- give every published crate its crates.io metadata ([#97](https://github.com/jdx/mr-boxington/pull/97))
- version each crate by what it promises ([#100](https://github.com/jdx/mr-boxington/pull/100))

### Security

- bound remote downloads and protect release assets ([#109](https://github.com/jdx/mr-boxington/pull/109))

## [0.4.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.3.0...mbx-cache-core-v0.4.0) - 2026-08-25

### Added

- add installation doctor ([#57](https://github.com/jdx/mr-boxington/pull/57))
- report compiler time saved and spent ([#59](https://github.com/jdx/mr-boxington/pull/59))
- add explicit remote prefetch ([#64](https://github.com/jdx/mr-boxington/pull/64))
- *(protocol)* share remote cache contract ([#68](https://github.com/jdx/mr-boxington/pull/68))
- cache plain cargo commands after setup ([#40](https://github.com/jdx/mr-boxington/pull/40))

### Other

- give every crate one synchronized version ([#86](https://github.com/jdx/mr-boxington/pull/86))
- fuzz untrusted parser inputs ([#38](https://github.com/jdx/mr-boxington/pull/38))
- enforce protocol and API compatibility ([#43](https://github.com/jdx/mr-boxington/pull/43))
- establish compatibility and security policy ([#37](https://github.com/jdx/mr-boxington/pull/37))
- move inline tests into focused modules ([#42](https://github.com/jdx/mr-boxington/pull/42))
- define published Rust API surface ([#41](https://github.com/jdx/mr-boxington/pull/41))
- *(cache)* avoid rereading reflinked outputs ([#44](https://github.com/jdx/mr-boxington/pull/44))

### Changed

- *(protocol)* consume remote wire types and constants from `mbx-cache-protocol`

## [0.3.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.2.0...mbx-cache-core-v0.3.0) - 2026-08-23

### Added

- *(store)* collect automatically, and release deleted checkouts first ([#23](https://github.com/jdx/mr-boxington/pull/23))

## [0.2.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.1.0...mbx-cache-core-v0.2.0) - 2026-08-22

### Added

- *(cache-core)* compress remote transfers with zstd ([#22](https://github.com/jdx/mr-boxington/pull/22))
- *(session)* count the compilations the cache was never asked about ([#18](https://github.com/jdx/mr-boxington/pull/18))

## [0.1.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-core-v0.0.0...mbx-cache-core-v0.1.0) - 2026-08-21

### Added

- *(release)* publish prebuilt binaries on a tag ([#14](https://github.com/jdx/mr-boxington/pull/14))
- *(session)* count compilations the cache declined ([#10](https://github.com/jdx/mr-boxington/pull/10))
- *(cache-core)* add action cache protocol and transport ([#4](https://github.com/jdx/mr-boxington/pull/4))

### Other

- *(cache-core)* stop fsyncing every stored object ([#13](https://github.com/jdx/mr-boxington/pull/13))
