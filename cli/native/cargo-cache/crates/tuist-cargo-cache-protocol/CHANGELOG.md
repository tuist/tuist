# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.22](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.21...mbx-cache-protocol-v0.5.22) - 2026-10-08

### Added

- *(clean)* add --under to clean every workspace below a root ([#668](https://github.com/jdx/mr-boxington/pull/668))

## [0.5.21](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.20...mbx-cache-protocol-v0.5.21) - 2026-10-03

### Other

- correct outdated guides and CLI help, and reorganize the docs site ([#637](https://github.com/jdx/mr-boxington/pull/637))

## [0.5.20](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.19...mbx-cache-protocol-v0.5.20) - 2026-09-27

### Other

- redesign the Mr Boxington logo and animated build mascot ([#558](https://github.com/jdx/mr-boxington/pull/558))

## [0.5.19](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.18...mbx-cache-protocol-v0.5.19) - 2026-09-25

### Added

- *(target)* adopt an existing target/ on the first build without prompting ([#545](https://github.com/jdx/mr-boxington/pull/545))

### Other

- *(protocol)* verify byte digests without allocating hex strings ([#544](https://github.com/jdx/mr-boxington/pull/544))

## [0.5.18](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.17...mbx-cache-protocol-v0.5.18) - 2026-09-20

### Added

- *(target)* adopt existing target directories without deleting outputs ([#499](https://github.com/jdx/mr-boxington/pull/499))

## [0.5.17](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.16...mbx-cache-protocol-v0.5.17) - 2026-09-17

### Other

- clarify cache behavior and organize setup guides ([#483](https://github.com/jdx/mr-boxington/pull/483))

## [0.5.16](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.15...mbx-cache-protocol-v0.5.16) - 2026-09-11

### Added

- *(cli)* adapt cargo-pretty with live cache statistics ([#435](https://github.com/jdx/mr-boxington/pull/435))

## [0.5.15](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.14...mbx-cache-protocol-v0.5.15) - 2026-09-08

### Other

- adopt native mise Rust integration for setup ([#400](https://github.com/jdx/mr-boxington/pull/400))

## [0.5.14](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.13...mbx-cache-protocol-v0.5.14) - 2026-09-06

### Added

- *(tui)* add cache insights and lifetime statistics ([#389](https://github.com/jdx/mr-boxington/pull/389))

### Other

- refresh guides and redesign the documentation site ([#395](https://github.com/jdx/mr-boxington/pull/395))
- generate page-specific social preview images ([#374](https://github.com/jdx/mr-boxington/pull/374))

## [0.5.13](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.12...mbx-cache-protocol-v0.5.13) - 2026-09-03

### Added

- manage profile-specific linkers ([#319](https://github.com/jdx/mr-boxington/pull/319))

## [0.5.12](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.11...mbx-cache-protocol-v0.5.12) - 2026-09-02

### Other

- trim the README and correct link caching claims ([#277](https://github.com/jdx/mr-boxington/pull/277))

## [0.5.11](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.10...mbx-cache-protocol-v0.5.11) - 2026-09-02

### Fixed

- fix managed target lifecycle edges ([#269](https://github.com/jdx/mr-boxington/pull/269))
- release cache pinned by phantom checkouts ([#270](https://github.com/jdx/mr-boxington/pull/270))

## [0.5.10](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.9...mbx-cache-protocol-v0.5.10) - 2026-08-31

### Added

- *(setup)* use mise command wrappers ([#249](https://github.com/jdx/mr-boxington/pull/249))

## [0.5.9](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.8...mbx-cache-protocol-v0.5.9) - 2026-08-31

### Fixed

- document Cargo shim activation for agents ([#233](https://github.com/jdx/mr-boxington/pull/233))

## [0.5.8](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.7...mbx-cache-protocol-v0.5.8) - 2026-08-30

### Added

- *(cache)* deduplicate in-flight work across runners ([#223](https://github.com/jdx/mr-boxington/pull/223))
- cache rustdoc actions ([#226](https://github.com/jdx/mr-boxington/pull/226))

## [0.5.7](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.6...mbx-cache-protocol-v0.5.7) - 2026-08-29

### Other

- recognize Cargo, sccache, and kache ([#205](https://github.com/jdx/mr-boxington/pull/205))

## [0.5.6](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.5...mbx-cache-protocol-v0.5.6) - 2026-08-29

### Other

- lead the landing page with three feature cards ([#198](https://github.com/jdx/mr-boxington/pull/198))
- corrections, editorial rebalance, and a CI anchor check ([#195](https://github.com/jdx/mr-boxington/pull/195))
- *(benchmarks)* demonstrate parallel lint scheduling ([#191](https://github.com/jdx/mr-boxington/pull/191))

## [0.5.5](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.4...mbx-cache-protocol-v0.5.5) - 2026-08-29

### Fixed

- allow caching release-marked builds ([#194](https://github.com/jdx/mr-boxington/pull/194))

## [0.5.4](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.3...mbx-cache-protocol-v0.5.4) - 2026-08-29

### Added

- *(release)* add GNU Linux artifacts ([#181](https://github.com/jdx/mr-boxington/pull/181))

## [0.5.3](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.2...mbx-cache-protocol-v0.5.3) - 2026-08-29

### Fixed

- *(cache-rustc)* predict a native search directory by name, not by its contents ([#162](https://github.com/jdx/mr-boxington/pull/162))

## [0.5.2](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.1...mbx-cache-protocol-v0.5.2) - 2026-08-28

### Added

- add Windows ARM64 support ([#147](https://github.com/jdx/mr-boxington/pull/147))

## [0.5.1](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.5.0...mbx-cache-protocol-v0.5.1) - 2026-08-27

### Added

- cache C and C++ compiles from build scripts ([#132](https://github.com/jdx/mr-boxington/pull/132))
- batch remote action lookups and blob uploads ([#131](https://github.com/jdx/mr-boxington/pull/131))
- mbx tui, a live view of every build's cache activity ([#128](https://github.com/jdx/mr-boxington/pull/128))

## [0.5.0](https://github.com/jdx/mr-boxington/compare/mbx-cache-protocol-v0.4.0...mbx-cache-protocol-v0.5.0) - 2026-08-26

### Added

- [**breaking**] open the extensible public types to extension ([#103](https://github.com/jdx/mr-boxington/pull/103))

### Other

- simplify the landing page for 1.0 ([#96](https://github.com/jdx/mr-boxington/pull/96))
- give every published crate its crates.io metadata ([#97](https://github.com/jdx/mr-boxington/pull/97))
- version each crate by what it promises ([#100](https://github.com/jdx/mr-boxington/pull/100))

## [0.4.0](https://github.com/jdx/mr-boxington/releases/tag/mbx-cache-protocol-v0.4.0) - 2026-08-25

### Added

- *(protocol)* share remote cache contract ([#68](https://github.com/jdx/mr-boxington/pull/68))

### Added

- Publish the versioned remote-cache wire types, capability schema, media types,
  headers, and blob-pack framing shared by mbx clients and servers.
