# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.23.0](https://github.com/jdx/mr-boxington/compare/v1.22.0...v1.23.0) - 2026-10-08

### Added

- *(clean)* add --under to clean every workspace below a root ([#668](https://github.com/jdx/mr-boxington/pull/668))
- *(cli)* add mbx edit to open the global configuration ([#665](https://github.com/jdx/mr-boxington/pull/665))
- *(target)* seed check lanes and editor checks from other checkouts ([#644](https://github.com/jdx/mr-boxington/pull/644))

### Fixed

- *(cache)* do not reuse file digests recorded within a timestamp tick ([#674](https://github.com/jdx/mr-boxington/pull/674))
- *(scheduler)* stop a lease-name test from colliding with its own leases ([#672](https://github.com/jdx/mr-boxington/pull/672))
- *(scheduler)* stop a release LTO link from slowing dev links ([#670](https://github.com/jdx/mr-boxington/pull/670))
- *(cache)* invalidate Rust compilations when build-script inputs change ([#667](https://github.com/jdx/mr-boxington/pull/667))
- *(scheduler)* record one core for test suites that finish under a second ([#661](https://github.com/jdx/mr-boxington/pull/661))

## [1.22.0](https://github.com/jdx/mr-boxington/compare/v1.21.1...v1.22.0) - 2026-10-03

### Added

- *(scheduler)* reserve capacity for external commands ([#643](https://github.com/jdx/mr-boxington/pull/643))
- *(explain)* name the setting to change when a miss differs from another checkout ([#639](https://github.com/jdx/mr-boxington/pull/639))

### Fixed

- *(cache)* skip caching build scripts that write into their declared inputs ([#640](https://github.com/jdx/mr-boxington/pull/640))
- *(seed)* leave build-script units unseeded when their output files name the donor checkout ([#641](https://github.com/jdx/mr-boxington/pull/641))
- *(stats)* label copying avoided without calling hard links reflinks ([#638](https://github.com/jdx/mr-boxington/pull/638))
- *(cache)* rerun build scripts that link from outside OUT_DIR ([#635](https://github.com/jdx/mr-boxington/pull/635))
- *(scheduler)* keep memory pressure state separate for each container ([#634](https://github.com/jdx/mr-boxington/pull/634))
- *(cache)* retain restored build scripts in CI exports ([#629](https://github.com/jdx/mr-boxington/pull/629))

### Other

- correct outdated guides and CLI help, and reorganize the docs site ([#637](https://github.com/jdx/mr-boxington/pull/637))
- *(stats)* parallelize target and cache scans in mbx stats ([#631](https://github.com/jdx/mr-boxington/pull/631))

## [1.21.1](https://github.com/jdx/mr-boxington/compare/v1.21.0...v1.21.1) - 2026-10-02

### Fixed

- *(gc)* keep the cache disk above gc.min_free_size during concurrent builds ([#618](https://github.com/jdx/mr-boxington/pull/618))
- *(cache)* cache path dependencies outside the workspace and home directory ([#625](https://github.com/jdx/mr-boxington/pull/625))
- *(gc)* keep a running command's test binaries when pruning unused build units ([#623](https://github.com/jdx/mr-boxington/pull/623))
- *(cli)* say when an external cargo command runs without the cache ([#615](https://github.com/jdx/mr-boxington/pull/615))
- *(cache)* keep private incremental state for crates with uncacheable native search paths ([#617](https://github.com/jdx/mr-boxington/pull/617))
- *(cache)* prevent build hangs across PID namespaces ([#611](https://github.com/jdx/mr-boxington/pull/611))
- *(remote)* block the instance role behind AWS profiles and renew credentials in the background ([#609](https://github.com/jdx/mr-boxington/pull/609))

### Other

- handle setup exit codes flagged by Rust 1.100 ([#626](https://github.com/jdx/mr-boxington/pull/626))

## [1.21.0](https://github.com/jdx/mr-boxington/compare/v1.20.0...v1.21.0) - 2026-09-29

### Added

- *(cache)* run check and clippy beside builds without a separate target ([#603](https://github.com/jdx/mr-boxington/pull/603))
- *(remote)* use the EC2 instance role for s3 remotes without AWS_* credentials ([#602](https://github.com/jdx/mr-boxington/pull/602))

### Fixed

- *(cli)* read an empty rustc-wrapper as no wrapper ([#607](https://github.com/jdx/mr-boxington/pull/607))
- *(cli)* keep the progress block on screen while build output scrolls ([#604](https://github.com/jdx/mr-boxington/pull/604))
- *(mbx)* keep the caller's environment in the pretty display on Windows ([#601](https://github.com/jdx/mr-boxington/pull/601))

### Other

- skip cargo-semver-checks for mbx so library-only changes stay minor ([#605](https://github.com/jdx/mr-boxington/pull/605))

## [1.20.0](https://github.com/jdx/mr-boxington/compare/v1.19.0...v1.20.0) - 2026-09-28

### Added

- *(cache)* share one budget across managed build data ([#594](https://github.com/jdx/mr-boxington/pull/594))
- add opt-in eager incremental reuse for workspace builds ([#587](https://github.com/jdx/mr-boxington/pull/587))
- *(cli)* add `mbx settings` to get, set, and unset config values ([#585](https://github.com/jdx/mr-boxington/pull/585))

### Fixed

- *(cache)* pin linker search directories by absolute path on WSL ([#597](https://github.com/jdx/mr-boxington/pull/597))
- *(cache)* keep managed targets while a wrapped command uses them ([#596](https://github.com/jdx/mr-boxington/pull/596))
- *(cache)* track external native library inputs ([#595](https://github.com/jdx/mr-boxington/pull/595))
- *(cache)* model rustc codegen backend selection ([#592](https://github.com/jdx/mr-boxington/pull/592))
- *(stats)* make cache lookups add up to hits plus misses ([#583](https://github.com/jdx/mr-boxington/pull/583))

## [1.19.0](https://github.com/jdx/mr-boxington/compare/v1.18.0...v1.19.0) - 2026-09-27

### Added

- *(target)* keep chosen checkouts' targets and evict others first ([#575](https://github.com/jdx/mr-boxington/pull/575))
- *(gc)* collect sooner and past budgets when the disk runs low ([#574](https://github.com/jdx/mr-boxington/pull/574))
- *(analyze)* show the critical path of the last build ([#570](https://github.com/jdx/mr-boxington/pull/570))
- *(analyze)* rank a build's uncached compiler time by cause ([#569](https://github.com/jdx/mr-boxington/pull/569))
- *(events)* record the crate and compiler time of bypassed compilations ([#568](https://github.com/jdx/mr-boxington/pull/568))
- *(exec)* cache CMake builds through compiler launchers ([#564](https://github.com/jdx/mr-boxington/pull/564))

### Fixed

- *(setup)* report a Cargo shim whose mbx target was removed as outdated ([#576](https://github.com/jdx/mr-boxington/pull/576))
- *(setup)* explain rust-analyzer's overrideCommand warning ([#573](https://github.com/jdx/mr-boxington/pull/573))
- *(pretty)* hide the mascot after a successful build ([#567](https://github.com/jdx/mr-boxington/pull/567))
- *(rustc)* cache -Zbuild-std standard library units instead of bypassing them ([#566](https://github.com/jdx/mr-boxington/pull/566))
- *(pretty)* move mascot right and clarify its animation ([#561](https://github.com/jdx/mr-boxington/pull/561))
- *(pretty)* recognize colored test results on xterm terminals ([#559](https://github.com/jdx/mr-boxington/pull/559))

### Other

- redesign the Mr Boxington logo and animated build mascot ([#558](https://github.com/jdx/mr-boxington/pull/558))

## [1.18.0](https://github.com/jdx/mr-boxington/compare/v1.17.0...v1.18.0) - 2026-09-25

### Added

- *(target)* start a new checkout's build from another checkout's registry units ([#550](https://github.com/jdx/mr-boxington/pull/550))
- *(gc)* remove unused build units from live managed target directories ([#549](https://github.com/jdx/mr-boxington/pull/549))
- *(target)* adopt an existing target/ on the first build without prompting ([#545](https://github.com/jdx/mr-boxington/pull/545))

### Fixed

- support Cargo 1.100's build layout and the Rust 1.99 toolchain ([#548](https://github.com/jdx/mr-boxington/pull/548))
- *(out-dir)* keep OUT_DIR readers fresh on the build after they compile ([#551](https://github.com/jdx/mr-boxington/pull/551))
- *(progress)* stop printing the mascot in plain build output ([#533](https://github.com/jdx/mr-boxington/pull/533))

## [1.17.0](https://github.com/jdx/mr-boxington/compare/v1.16.0...v1.17.0) - 2026-09-23

### Added

- *(scheduler)* suspend opted-in compilers under memory pressure ([#525](https://github.com/jdx/mr-boxington/pull/525))
- *(scheduler)* supervise compiler trees in delegated linux cgroups ([#523](https://github.com/jdx/mr-boxington/pull/523))
- *(scheduler)* throttle new compilations under memory pressure ([#521](https://github.com/jdx/mr-boxington/pull/521))
- *(scheduler)* sample live memory pressure ([#520](https://github.com/jdx/mr-boxington/pull/520))

### Fixed

- *(cache)* only treat Cargo build scripts as build scripts ([#528](https://github.com/jdx/mr-boxington/pull/528))
- *(cache)* replay build scripts declared with a custom path ([#526](https://github.com/jdx/mr-boxington/pull/526))

### Other

- *(materialize)* stop the contended-lock restore test from failing under parallel tests ([#530](https://github.com/jdx/mr-boxington/pull/530))
- *(build)* find cargo outputs under both build-dir layouts and run them on nightly ([#529](https://github.com/jdx/mr-boxington/pull/529))

## [1.16.0](https://github.com/jdx/mr-boxington/compare/v1.15.0...v1.16.0) - 2026-09-23

### Added

- *(scheduler)* run cargo test binaries under the machine-wide permit pool ([#513](https://github.com/jdx/mr-boxington/pull/513))

### Fixed

- *(cc)* stop other mbx installations sharing a cache from breaking C builds ([#516](https://github.com/jdx/mr-boxington/pull/516))
- *(target)* keep view collection's activity window on one clock ([#512](https://github.com/jdx/mr-boxington/pull/512))
- *(cache)* allow private persistent compiler shim directories ([#501](https://github.com/jdx/mr-boxington/pull/501))
- *(cache)* stop native archive timestamps from missing cached actions ([#506](https://github.com/jdx/mr-boxington/pull/506))
- *(gc)* run automatic cleanup from cargo hardlink installations ([#505](https://github.com/jdx/mr-boxington/pull/505))
- *(cc)* stop two mbx installations from picking each other's compiler shims ([#504](https://github.com/jdx/mr-boxington/pull/504))
- *(cargo)* preserve target directories in nested builds ([#502](https://github.com/jdx/mr-boxington/pull/502))

### Other

- *(cache)* hard link cached outputs where the filesystem cannot clone them ([#511](https://github.com/jdx/mr-boxington/pull/511))

## [1.15.0](https://github.com/jdx/mr-boxington/compare/v1.14.0...v1.15.0) - 2026-09-20

### Added

- *(progress)* show friendlier build times and fewer updates on long builds ([#500](https://github.com/jdx/mr-boxington/pull/500))
- *(target)* adopt existing target directories without deleting outputs ([#499](https://github.com/jdx/mr-boxington/pull/499))
- *(cache)* reuse OUT_DIR compilations across checkouts ([#498](https://github.com/jdx/mr-boxington/pull/498))

### Other

- *(gc)* run the automatic store sweep after the build returns ([#497](https://github.com/jdx/mr-boxington/pull/497))
- *(stats)* make mbx stats about 10x faster on machines with many checkouts ([#495](https://github.com/jdx/mr-boxington/pull/495))

## [1.14.0](https://github.com/jdx/mr-boxington/compare/v1.13.0...v1.14.0) - 2026-09-18

### Added

- *(cache)* cache library compiles that name a native library ([#490](https://github.com/jdx/mr-boxington/pull/490))
- *(rustc)* let Cargo pipeline dependents while mbx finishes a miss ([#492](https://github.com/jdx/mr-boxington/pull/492))

### Other

- *(cache)* take two disk round trips off every cache miss ([#491](https://github.com/jdx/mr-boxington/pull/491))

## [1.13.0](https://github.com/jdx/mr-boxington/compare/v1.12.0...v1.13.0) - 2026-09-17

### Added

- *(cache)* share dependents of a crate keyed to its checkout ([#488](https://github.com/jdx/mr-boxington/pull/488))

### Fixed

- *(pretty)* stop an inline view that cannot start from reporting an error ([#487](https://github.com/jdx/mr-boxington/pull/487))
- *(cargo)* restore outside-project commands with lossless alias resolution ([#484](https://github.com/jdx/mr-boxington/pull/484))
- *(stats)* tell an incremental compilation's lookup apart from its storage ([#482](https://github.com/jdx/mr-boxington/pull/482))
- *(cache)* keep a compilation that reads OUT_DIR keyed to its checkout ([#479](https://github.com/jdx/mr-boxington/pull/479))
- *(setup)* put project-scoped rust-analyzer checks back through mbx ([#477](https://github.com/jdx/mr-boxington/pull/477))
- *(explain)* report a build whose history stopped at the size limit ([#475](https://github.com/jdx/mr-boxington/pull/475))
- *(cc)* stop autotools reading the C shim path as a cross-compile triple ([#476](https://github.com/jdx/mr-boxington/pull/476))
- *(explain)* label key-detail changes separately from input changes ([#474](https://github.com/jdx/mr-boxington/pull/474))
- *(explain)* diagnose cross-checkout misses and name the crate behind them ([#468](https://github.com/jdx/mr-boxington/pull/468))
- *(stats)* count one miss per compilation, not one per action-key probe ([#467](https://github.com/jdx/mr-boxington/pull/467))

### Other

- clarify cache behavior and organize setup guides ([#483](https://github.com/jdx/mr-boxington/pull/483))

## [1.12.0](https://github.com/jdx/mr-boxington/compare/v1.11.1...v1.12.0) - 2026-09-15

### Added

- *(cache)* export and import directory-form cache bundles ([#463](https://github.com/jdx/mr-boxington/pull/463))

### Fixed

- bind compiler input digests to validated file identities ([#433](https://github.com/jdx/mr-boxington/pull/433))

### Other

- *(perf)* make instruction counts informational ([#450](https://github.com/jdx/mr-boxington/pull/450))

## [1.11.1](https://github.com/jdx/mr-boxington/compare/v1.11.0...v1.11.1) - 2026-09-14

### Fixed

- reject NFS-backed build storage ([#428](https://github.com/jdx/mr-boxington/pull/428))
- *(cargo)* preserve build fingerprints across path installs ([#455](https://github.com/jdx/mr-boxington/pull/455))
- *(gc)* bound learned incremental storage ([#447](https://github.com/jdx/mr-boxington/pull/447))

### Other

- isolate integration tests from the host mbx config ([#440](https://github.com/jdx/mr-boxington/pull/440))
- *(deps)* bump the cargo-dependencies group with 7 updates ([#451](https://github.com/jdx/mr-boxington/pull/451))

## [1.11.0](https://github.com/jdx/mr-boxington/compare/v1.10.1...v1.11.0) - 2026-09-11

### Added

- animate Boxington in build output ([#441](https://github.com/jdx/mr-boxington/pull/441))
- *(cli)* add append-only progress for agent builds ([#437](https://github.com/jdx/mr-boxington/pull/437))
- *(cli)* adapt cargo-pretty with live cache statistics ([#435](https://github.com/jdx/mr-boxington/pull/435))
- *(cache)* control storage of path-specific C objects ([#432](https://github.com/jdx/mr-boxington/pull/432))

### Fixed

- end build sessions before launching cargo applications ([#436](https://github.com/jdx/mr-boxington/pull/436))
- *(cache)* recover C predictions after stderr-only conflicts ([#431](https://github.com/jdx/mr-boxington/pull/431))
- *(cache)* cover dependency debug paths in macOS links ([#430](https://github.com/jdx/mr-boxington/pull/430))
- *(cache)* stabilize macOS proc macro install names ([#427](https://github.com/jdx/mr-boxington/pull/427))

## [1.10.1](https://github.com/jdx/mr-boxington/compare/v1.10.0...v1.10.1) - 2026-09-10

### Fixed

- *(cc)* report publication failures and require valid snapshots ([#421](https://github.com/jdx/mr-boxington/pull/421))
- *(verify)* identify divergent compilation outputs ([#420](https://github.com/jdx/mr-boxington/pull/420))
- forward routine shim diagnostics as debug logs ([#417](https://github.com/jdx/mr-boxington/pull/417))

## [1.10.0](https://github.com/jdx/mr-boxington/compare/v1.9.0...v1.10.0) - 2026-09-08

### Added

- add interactive cache removal ([#403](https://github.com/jdx/mr-boxington/pull/403))

### Fixed

- keep rustc shim diagnostics out of Cargo fingerprints ([#405](https://github.com/jdx/mr-boxington/pull/405))
- preserve active Cargo targets and check release warnings ([#399](https://github.com/jdx/mr-boxington/pull/399))

### Other

- adopt native mise Rust integration for setup ([#400](https://github.com/jdx/mr-boxington/pull/400))

## [1.9.0](https://github.com/jdx/mr-boxington/compare/v1.8.3...v1.9.0) - 2026-09-06

### Added

- *(verify)* sample compilation identities deterministically ([#391](https://github.com/jdx/mr-boxington/pull/391))
- *(cc)* cache named preprocessor outputs ([#394](https://github.com/jdx/mr-boxington/pull/394))
- *(report)* record wrapper phases and export Perfetto traces ([#390](https://github.com/jdx/mr-boxington/pull/390))
- *(tui)* add cache insights and lifetime statistics ([#389](https://github.com/jdx/mr-boxington/pull/389))
- *(cli)* publish native completions in packslip ([#381](https://github.com/jdx/mr-boxington/pull/381))
- explain object cache results in CI summaries ([#377](https://github.com/jdx/mr-boxington/pull/377))

### Fixed

- *(gc)* distinguish logical removal from physical reclamation ([#392](https://github.com/jdx/mr-boxington/pull/392))
- *(doctor)* probe reflinks from cache to target filesystems ([#387](https://github.com/jdx/mr-boxington/pull/387))
- *(scheduler)* respect nested cgroup memory limits ([#386](https://github.com/jdx/mr-boxington/pull/386))
- *(cc)* cache gdb and full debug compilations portably ([#384](https://github.com/jdx/mr-boxington/pull/384))
- preserve CMake compiler identity across Cargo transitions ([#380](https://github.com/jdx/mr-boxington/pull/380))
- support multiple Cargo targets in linker selection ([#379](https://github.com/jdx/mr-boxington/pull/379))

### Other

- refresh guides and redesign the documentation site ([#395](https://github.com/jdx/mr-boxington/pull/395))
- *(cache)* compare semantic changes against bare rustc ([#393](https://github.com/jdx/mr-boxington/pull/393))
- generate page-specific social preview images ([#374](https://github.com/jdx/mr-boxington/pull/374))

## [1.8.3](https://github.com/jdx/mr-boxington/compare/v1.8.2...v1.8.3) - 2026-09-05

### Other

- updated the following local packages: mbx-cache-core, mbx-cache-cc, mbx-cache-rustc, mbx-cache-cargo, mbx-cache-store

## [1.8.2](https://github.com/jdx/mr-boxington/compare/v1.8.1...v1.8.2) - 2026-09-05

### Other

- take the bookkeeping out of the hot edit loop ([#362](https://github.com/jdx/mr-boxington/pull/362))

## [1.8.1](https://github.com/jdx/mr-boxington/compare/v1.8.0...v1.8.1) - 2026-09-05

### Fixed

- restore NFS digest reuse without read storms ([#341](https://github.com/jdx/mr-boxington/pull/341))

### Other

- share build-script shim binaries per profile ([#351](https://github.com/jdx/mr-boxington/pull/351))
- prevent unbounded test and job hangs ([#343](https://github.com/jdx/mr-boxington/pull/343))

## [1.8.0](https://github.com/jdx/mr-boxington/compare/v1.7.0...v1.8.0) - 2026-09-04

### Added

- *(cache)* restore Cargo workspace state from exports ([#337](https://github.com/jdx/mr-boxington/pull/337))

### Fixed

- verify NFS compiler inputs by content ([#338](https://github.com/jdx/mr-boxington/pull/338))

## [1.7.0](https://github.com/jdx/mr-boxington/compare/v1.6.0...v1.7.0) - 2026-09-03

### Added

- *(cache)* inherit predictions from earlier lockfiles ([#327](https://github.com/jdx/mr-boxington/pull/327))

### Other

- use blocking Windows agent I/O ([#333](https://github.com/jdx/mr-boxington/pull/333))
- keep hot-edit bookkeeping off the build's critical path ([#331](https://github.com/jdx/mr-boxington/pull/331))
- reuse Windows cache agent connections ([#332](https://github.com/jdx/mr-boxington/pull/332))
- keep the cone above an edited crate incremental ([#326](https://github.com/jdx/mr-boxington/pull/326))
- *(cache)* gate prefetch on matching adapters ([#321](https://github.com/jdx/mr-boxington/pull/321))

## [1.6.0](https://github.com/jdx/mr-boxington/compare/v1.5.0...v1.6.0) - 2026-09-03

### Added

- manage profile-specific linkers ([#319](https://github.com/jdx/mr-boxington/pull/319))

### Fixed

- preserve caching when Unix listeners are blocked ([#317](https://github.com/jdx/mr-boxington/pull/317))
- verify compiler inputs across clock domains ([#318](https://github.com/jdx/mr-boxington/pull/318))

## [1.5.0](https://github.com/jdx/mr-boxington/compare/v1.4.1...v1.5.0) - 2026-09-02

### Added

- *(cc)* cache preprocessed assembly ([#291](https://github.com/jdx/mr-boxington/pull/291))
- *(cc)* write the caller's dependency list instead of bypassing it ([#294](https://github.com/jdx/mr-boxington/pull/294))

### Fixed

- stop cache hits from keeping Cargo targets stale ([#300](https://github.com/jdx/mr-boxington/pull/300))
- scale the stale-manifest note to what was predicted ([#289](https://github.com/jdx/mr-boxington/pull/289))
- *(remote)* bound what a build loses to failed cache reads ([#292](https://github.com/jdx/mr-boxington/pull/292))
- keep learned incremental state for large crates ([#282](https://github.com/jdx/mr-boxington/pull/282))
- *(setup)* preserve native compiler path when disabled ([#281](https://github.com/jdx/mr-boxington/pull/281))

### Other

- carry the file-digest ledger across sessions ([#285](https://github.com/jdx/mr-boxington/pull/285))

## [1.4.1](https://github.com/jdx/mr-boxington/compare/v1.4.0...v1.4.1) - 2026-09-02

### Other

- trim the README and correct link caching claims ([#277](https://github.com/jdx/mr-boxington/pull/277))

## [1.4.0](https://github.com/jdx/mr-boxington/compare/v1.3.2...v1.4.0) - 2026-09-02

### Added

- explain cache misses from session history ([#274](https://github.com/jdx/mr-boxington/pull/274))
- add quiet build summaries ([#264](https://github.com/jdx/mr-boxington/pull/264))
- *(scheduler)* respect build CPU limits ([#267](https://github.com/jdx/mr-boxington/pull/267))

### Fixed

- avoid racing persistent Windows shims ([#276](https://github.com/jdx/mr-boxington/pull/276))
- fix managed target lifecycle edges ([#269](https://github.com/jdx/mr-boxington/pull/269))
- release cache pinned by phantom checkouts ([#270](https://github.com/jdx/mr-boxington/pull/270))
- fix build-script caching and doctor toolchain ([#272](https://github.com/jdx/mr-boxington/pull/272))
- *(setup)* isolate rust-analyzer target directory ([#261](https://github.com/jdx/mr-boxington/pull/261))
- cache clippy workspace compilations ([#273](https://github.com/jdx/mr-boxington/pull/273))
- reuse enclosing sessions for nested cargo ([#265](https://github.com/jdx/mr-boxington/pull/265))
- handle rustc workspace wrappers ([#263](https://github.com/jdx/mr-boxington/pull/263))
- *(cache)* map symlinked Cargo registries ([#259](https://github.com/jdx/mr-boxington/pull/259))

### Other

- preserve Cargo rustc probe cache ([#268](https://github.com/jdx/mr-boxington/pull/268))
- make workspace edit loops incremental ([#271](https://github.com/jdx/mr-boxington/pull/271))

## [1.3.2](https://github.com/jdx/mr-boxington/compare/v1.3.1...v1.3.2) - 2026-09-01

### Fixed

- share predictions across Cargo commands ([#256](https://github.com/jdx/mr-boxington/pull/256))

## [1.3.1](https://github.com/jdx/mr-boxington/compare/v1.3.0...v1.3.1) - 2026-09-01

### Fixed

- avoid reentering mise Cargo wrappers ([#252](https://github.com/jdx/mr-boxington/pull/252))

## [1.3.0](https://github.com/jdx/mr-boxington/compare/v1.2.0...v1.3.0) - 2026-08-31

### Added

- *(setup)* use mise command wrappers ([#249](https://github.com/jdx/mr-boxington/pull/249))

### Other

- cache build scripts with Cargo's default inputs ([#245](https://github.com/jdx/mr-boxington/pull/245))

## [1.2.0](https://github.com/jdx/mr-boxington/compare/v1.1.0...v1.2.0) - 2026-08-31

### Added

- support Mercurial and Sapling checkouts ([#232](https://github.com/jdx/mr-boxington/pull/232))

### Fixed

- *(setup)* prevent Cargo shim recursion after HOME changes ([#234](https://github.com/jdx/mr-boxington/pull/234))
- document Cargo shim activation for agents ([#233](https://github.com/jdx/mr-boxington/pull/233))
- support Delta worktrees ([#231](https://github.com/jdx/mr-boxington/pull/231))

### Other

- bound remote cache prefetch work ([#239](https://github.com/jdx/mr-boxington/pull/239))

## [1.1.0](https://github.com/jdx/mr-boxington/compare/v1.0.1...v1.1.0) - 2026-08-30

### Added

- cache build script execution ([#225](https://github.com/jdx/mr-boxington/pull/225))
- *(cache)* deduplicate in-flight work across runners ([#223](https://github.com/jdx/mr-boxington/pull/223))
- cache Windows links and MSVC compiles ([#224](https://github.com/jdx/mr-boxington/pull/224))
- cache rustdoc actions ([#226](https://github.com/jdx/mr-boxington/pull/226))
- *(cache)* export portable build closures ([#227](https://github.com/jdx/mr-boxington/pull/227))
- *(mbx)* prescribe fixes for cache bypasses ([#222](https://github.com/jdx/mr-boxington/pull/222))

### Fixed

- *(rustc)* compact large action predictions ([#218](https://github.com/jdx/mr-boxington/pull/218))

### Other

- remove pre-v1 format fallbacks ([#219](https://github.com/jdx/mr-boxington/pull/219))
- *(mbx)* split session responsibilities ([#216](https://github.com/jdx/mr-boxington/pull/216))
- share cache path mapping ([#215](https://github.com/jdx/mr-boxington/pull/215))
- *(mbx)* split CLI commands into modules ([#212](https://github.com/jdx/mr-boxington/pull/212))

## [1.0.1](https://github.com/jdx/mr-boxington/compare/v1.0.0...v1.0.1) - 2026-08-29

### Fixed

- support Jujutsu repositories in mbx exec ([#207](https://github.com/jdx/mr-boxington/pull/207))

### Other

- recognize Cargo, sccache, and kache ([#205](https://github.com/jdx/mr-boxington/pull/205))

## [1.0.0](https://github.com/jdx/mr-boxington/compare/v0.7.2...v1.0.0) - 2026-08-29

### Other

- lead the landing page with three feature cards ([#198](https://github.com/jdx/mr-boxington/pull/198))
- cache linked proc macros ([#197](https://github.com/jdx/mr-boxington/pull/197))
- corrections, editorial rebalance, and a CI anchor check ([#195](https://github.com/jdx/mr-boxington/pull/195))
- *(benchmarks)* demonstrate parallel lint scheduling ([#191](https://github.com/jdx/mr-boxington/pull/191))

## [0.7.2](https://github.com/jdx/mr-boxington/compare/v0.7.1...v0.7.2) - 2026-08-29

### Fixed

- allow caching release-marked builds ([#194](https://github.com/jdx/mr-boxington/pull/194))

## [0.7.1](https://github.com/jdx/mr-boxington/compare/v0.7.0...v0.7.1) - 2026-08-29

### Added

- *(release)* add GNU Linux artifacts ([#181](https://github.com/jdx/mr-boxington/pull/181))
- *(rustc)* cache native links by default ([#178](https://github.com/jdx/mr-boxington/pull/178))
- *(rustc)* cache the compilations that never link ([#177](https://github.com/jdx/mr-boxington/pull/177))
- a machine-wide, memory-aware compiler scheduler ([#170](https://github.com/jdx/mr-boxington/pull/170))

### Fixed

- *(cc)* make an object independent of the directory it was built in ([#185](https://github.com/jdx/mr-boxington/pull/185))
- *(cc)* say what diverged, and describe when C objects legitimately do ([#182](https://github.com/jdx/mr-boxington/pull/182))

### Other

- *(scheduler)* drop the release watch, which measured as nothing ([#183](https://github.com/jdx/mr-boxington/pull/183))
- *(scheduler)* weigh an unmeasured link by what this machine's links cost ([#180](https://github.com/jdx/mr-boxington/pull/180))
- share OUT_DIR artifacts across worktrees ([#176](https://github.com/jdx/mr-boxington/pull/176))
- *(scheduler)* retire the link guess, and wake waiters on release ([#174](https://github.com/jdx/mr-boxington/pull/174))
- reduce mbx startup relocations ([#175](https://github.com/jdx/mr-boxington/pull/175))

## [0.7.0](https://github.com/jdx/mr-boxington/compare/v0.6.0...v0.7.0) - 2026-08-29

### Added

- *(cache-rustc)* cache macOS debug links behind an oso_prefix the shim appends ([#166](https://github.com/jdx/mr-boxington/pull/166))
- *(cli)* read the toolchain instead of forwarding it ([#159](https://github.com/jdx/mr-boxington/pull/159))

### Fixed

- *(cache-rustc)* predict a native search directory by name, not by its contents ([#162](https://github.com/jdx/mr-boxington/pull/162))

### Other

- keep outputs that already hold the cached bytes ([#165](https://github.com/jdx/mr-boxington/pull/165))
- [**breaking**] stop rehashing inputs the session already read in full ([#164](https://github.com/jdx/mr-boxington/pull/164))
- *(doctor)* reach the failure line without spawning a process ([#163](https://github.com/jdx/mr-boxington/pull/163))

## [0.6.0](https://github.com/jdx/mr-boxington/compare/v0.5.4...v0.6.0) - 2026-08-28

### Fixed

- *(cc)* [**breaking**] keep shim diagnostics off the intercepted compiler's stderr ([#154](https://github.com/jdx/mr-boxington/pull/154))
- *(mbx)* bump the stats report version for the new field ([#157](https://github.com/jdx/mr-boxington/pull/157))
- *(cache-rustc)* key inert native search directories by path ([#153](https://github.com/jdx/mr-boxington/pull/153))

### Other

- stop rereading cached artifacts on warm hits ([#152](https://github.com/jdx/mr-boxington/pull/152))

## [0.5.4](https://github.com/jdx/mr-boxington/compare/v0.5.3...v0.5.4) - 2026-08-28

### Fixed

- *(cc)* keep compiler shims stable across sessions ([#150](https://github.com/jdx/mr-boxington/pull/150))

### Other

- release ([#149](https://github.com/jdx/mr-boxington/pull/149))

## [0.5.3](https://github.com/jdx/mr-boxington/compare/v0.5.2...v0.5.3) - 2026-08-28

### Added

- *(cc)* cache the C and C++ a cross build compiles ([#143](https://github.com/jdx/mr-boxington/pull/143))
- add Windows ARM64 support ([#147](https://github.com/jdx/mr-boxington/pull/147))

### Fixed

- *(exec)* never let a shim stand in for the compiler it shims ([#144](https://github.com/jdx/mr-boxington/pull/144))

### Other

- hand the shim search a PATH instead of setting one ([#146](https://github.com/jdx/mr-boxington/pull/146))

## [0.5.2](https://github.com/jdx/mr-boxington/compare/v0.5.1...v0.5.2) - 2026-08-27

### Added

- cache standalone C and C++ builds through mbx exec ([#138](https://github.com/jdx/mr-boxington/pull/138))
- cache C and C++ compiles from build scripts ([#132](https://github.com/jdx/mr-boxington/pull/132))
- cache natively linked test binaries ([#129](https://github.com/jdx/mr-boxington/pull/129))
- cache to an S3-compatible object store ([#140](https://github.com/jdx/mr-boxington/pull/140))
- *(cache)* expose shared Cargo cache integration ([#130](https://github.com/jdx/mr-boxington/pull/130))
- batch remote action lookups and blob uploads ([#131](https://github.com/jdx/mr-boxington/pull/131))
- publish remote objects after the build asks for them ([#126](https://github.com/jdx/mr-boxington/pull/126))
- compile churning crates incrementally ([#127](https://github.com/jdx/mr-boxington/pull/127))
- mbx tui, a live view of every build's cache activity ([#128](https://github.com/jdx/mr-boxington/pull/128))

### Fixed

- *(rustc)* restore results into the checkout that asked for them ([#141](https://github.com/jdx/mr-boxington/pull/141))
- symlink the session shim so macOS cannot kill it at exec ([#134](https://github.com/jdx/mr-boxington/pull/134))

### Other

- define download_timeout as a whole-download deadline ([#142](https://github.com/jdx/mr-boxington/pull/142))

## [0.5.1](https://github.com/jdx/mr-boxington/compare/v0.5.0...v0.5.1) - 2026-08-26

### Fixed

- cache libraries with native search paths ([#120](https://github.com/jdx/mr-boxington/pull/120))

## [0.5.0](https://github.com/jdx/mr-boxington/compare/v0.4.0...v0.5.0) - 2026-08-26

### Added

- [**breaking**] open the extensible public types to extension ([#103](https://github.com/jdx/mr-boxington/pull/103))
- count remote cache failures in the summary ([#112](https://github.com/jdx/mr-boxington/pull/112))
- make landing demo interactive and tag output ([#94](https://github.com/jdx/mr-boxington/pull/94))

### Other

- document MBX_LOG and how to report a problem ([#99](https://github.com/jdx/mr-boxington/pull/99))
- simplify the landing page for 1.0 ([#96](https://github.com/jdx/mr-boxington/pull/96))
- let the agent's statistics grow without breaking ([#114](https://github.com/jdx/mr-boxington/pull/114))
- give every published crate its crates.io metadata ([#97](https://github.com/jdx/mr-boxington/pull/97))
- version each crate by what it promises ([#100](https://github.com/jdx/mr-boxington/pull/100))

### Security

- bound remote downloads and protect release assets ([#109](https://github.com/jdx/mr-boxington/pull/109))

## [0.4.0](https://github.com/jdx/mr-boxington/compare/v0.3.0...v0.4.0) - 2026-08-25

### Added

- make mbx build the golden path and hide setup ([#75](https://github.com/jdx/mr-boxington/pull/75))
- explain the cache and its caps on the first build ([#74](https://github.com/jdx/mr-boxington/pull/74))
- report what mbx has saved on this machine ([#73](https://github.com/jdx/mr-boxington/pull/73))
- scale disk budgets to the disk and prune idle targets by default ([#72](https://github.com/jdx/mr-boxington/pull/72))
- add cache inspection commands ([#63](https://github.com/jdx/mr-boxington/pull/63))
- add managed target retention policies ([#62](https://github.com/jdx/mr-boxington/pull/62))
- add JSON inspection output ([#60](https://github.com/jdx/mr-boxington/pull/60))
- add installation doctor ([#57](https://github.com/jdx/mr-boxington/pull/57))
- report compiler time saved and spent ([#59](https://github.com/jdx/mr-boxington/pull/59))
- complete setup lifecycle ([#61](https://github.com/jdx/mr-boxington/pull/61))
- add explicit remote prefetch ([#64](https://github.com/jdx/mr-boxington/pull/64))
- *(config)* add safe workspace policy ([#67](https://github.com/jdx/mr-boxington/pull/67))
- *(protocol)* share remote cache contract ([#68](https://github.com/jdx/mr-boxington/pull/68))
- explain cache bypasses ([#58](https://github.com/jdx/mr-boxington/pull/58))
- cache compiler-linked wasm outputs ([#45](https://github.com/jdx/mr-boxington/pull/45))
- cache plain cargo commands after setup ([#40](https://github.com/jdx/mr-boxington/pull/40))
- add direct cargo wrapper and docs website ([#28](https://github.com/jdx/mr-boxington/pull/28))

### Fixed

- probe reflinks across the span the restore actually copies ([#84](https://github.com/jdx/mr-boxington/pull/84))
- deflake two tests that race the machine ([#82](https://github.com/jdx/mr-boxington/pull/82))
- restore the build after a merge skewed a verify call ([#71](https://github.com/jdx/mr-boxington/pull/71))

### Other

- give every crate one synchronized version ([#86](https://github.com/jdx/mr-boxington/pull/86))
- stop checking the CLI library's public API ([#77](https://github.com/jdx/mr-boxington/pull/77))
- wrap project cargo commands with mbx ([#34](https://github.com/jdx/mr-boxington/pull/34))
- *(deps)* bump the cargo-dependencies group across 1 directory with 2 updates ([#55](https://github.com/jdx/mr-boxington/pull/55))
- add Bats end-to-end harness ([#46](https://github.com/jdx/mr-boxington/pull/46))
- establish compatibility and security policy ([#37](https://github.com/jdx/mr-boxington/pull/37))
- move inline tests into focused modules ([#42](https://github.com/jdx/mr-boxington/pull/42))
- define published Rust API surface ([#41](https://github.com/jdx/mr-boxington/pull/41))
- *(cache)* avoid rereading reflinked outputs ([#44](https://github.com/jdx/mr-boxington/pull/44))
- *(config)* generate settings docs with usage-rs ([#30](https://github.com/jdx/mr-boxington/pull/30))

### Added

- *(cli)* run a Cargo command with actionable cache-bypass diagnostics using `mbx explain`

### Changed

- *(cache)* restore verified outputs with observable copy-on-write materialization

## [0.3.0](https://github.com/jdx/mr-boxington/compare/v0.2.0...v0.3.0) - 2026-08-23

### Added

- *(target)* place target directories so a deleted checkout frees them ([#24](https://github.com/jdx/mr-boxington/pull/24))
- *(store)* collect automatically, and release deleted checkouts first ([#23](https://github.com/jdx/mr-boxington/pull/23))

## [0.2.0](https://github.com/jdx/mr-boxington/compare/v0.1.0...v0.2.0) - 2026-08-22

### Added

- *(session)* share compilations that read OUT_DIR across checkouts ([#21](https://github.com/jdx/mr-boxington/pull/21))
- *(session)* let a build opt into incremental compilation ([#20](https://github.com/jdx/mr-boxington/pull/20))
- *(session)* count the compilations the cache was never asked about ([#18](https://github.com/jdx/mr-boxington/pull/18))

## [0.1.0](https://github.com/jdx/mr-boxington/compare/v0.0.0...v0.1.0) - 2026-08-21

### Added

- *(release)* publish prebuilt binaries on a tag ([#14](https://github.com/jdx/mr-boxington/pull/14))
- *(session)* log why each compilation was not cached ([#11](https://github.com/jdx/mr-boxington/pull/11))
- *(session)* count compilations the cache declined ([#10](https://github.com/jdx/mr-boxington/pull/10))
- *(cli)* add build, gc, and cache commands ([#7](https://github.com/jdx/mr-boxington/pull/7))
- *(session)* add the cache session and rustc shim ([#6](https://github.com/jdx/mr-boxington/pull/6))

### Other

- *(cli)* stop the target-dir probe test reading the ambient environment ([#15](https://github.com/jdx/mr-boxington/pull/15))
- qualify cross-checkout sharing, and test the boundary ([#12](https://github.com/jdx/mr-boxington/pull/12))
- *(session)* stop fsyncing restored outputs ([#9](https://github.com/jdx/mr-boxington/pull/9))
- add workspace scaffolding and CI ([#2](https://github.com/jdx/mr-boxington/pull/2))
