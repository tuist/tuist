---
title: Performance testing
slug: '/contributors/performance-testing'
description: This page describes the project's performance testing strategy.
---

To test out generation speeds and to provide some utilities to aid profiling Tuist a few auxiliary standalone tools are available.

- `fixturegen`: A tool to generate large fixtures
- `tuistbench`: A tool to benchmark Tuist

Those tools are located within the [`projects/`](https://github.com/tuist/tuist/blob/main/projects) directory.

### Benchmarking

As a convenience to automate the benchmarking process which entails leveraging several tools, a rake task is included with Tuist.

```sh
./fourier benchmark
```

This benchmarks the current branch's version of Tuist against the latest published release using the tools described below.

### Fixture Generator

`fixturegen` allows generating large fixtures. For example it can generate a workspace with 10 projects, each project with 10 targets, and each target with 500 source files!

Example:

```sh
./fourier fixture --projects 100 --targets 10 --sources 500
```

Generating those large fixtures can be helpful in profiling Tuist and identifying any hot spots that may otherwise go unnoticed when generating smaller fixtures during development.

### Tuist Benchmark

`tuistbench` has a few modes of operation:

- Measure the generation time of one or more fixtures
- Benchmark two Tuist binaries' generation time of one or more fixtures

The benchmark mode can provide a general idea of how changes impact generation time. For example benchmarking a pull request against master or the latest release.

The results are averaged from several **cold** and **warm** runs where:

- **cold**: Is a generation from a clean slate (no xcodeproj files exist)
- **warm**: Is a re-generation (xcodeproj files already exist)

Here are some example outputs from `tuistbench`.

**Measurement (single fixture):**

Console format:

```sh
swift run tuistbench \
     --binary /path/to/tuist/.build/release/tuist \
     --fixture /path/to/fixtures/ios_app_with_tests

Fixture       : ios_app_with_tests
Runs          : 5
Result
    - cold : 0.72s
    - warm : 0.74s

```

Markdown format:

```sh
swift run tuistbench \
     --binary /path/to/tuist/.build/release/tuist \
     --fixture /path/to/fixtures/ios_app_with_tests \
     --format markdown
```

| Fixture            | Cold  | Warm  |
| ------------------ | ----- | ----- |
| ios_app_with_tests | 0.72s | 0.72s |

**Benchmark (single fixture):**

Console format:

```sh
swift run tuistbench \
     --binary /path/to/tuist/.build/release/tuist \
     --reference-binary $(which tuist) \
     --fixture /path/to/fixtures/ios_app_with_tests

Fixture       : ios_app_with_tests
Runs          : 5
Result
    - cold : 0.79s  vs  0.80s (≈)
    - warm : 0.75s  vs  0.79s (⬇︎ 0.04s 5.63%)
```

Markdown format:

```sh
swift run tuistbench \
     --binary /path/to/tuist/.build/release/tuist \
     --reference-binary $(which tuist) \
     --fixture /path/to/fixtures/ios_app_with_tests \
     --format markdown
```

| Fixture                      | New   | Old   | Delta    |
| ---------------------------- | ----- | ----- | -------- |
| ios*app_with_tests *(cold)\_ | 0.73s | 0.79s | ⬇︎ 7.92% |
| ios*app_with_tests *(warm)\_ | 0.79s | 0.79s | ≈        |

**Benchmark (multiple fixtures):**

A fixture list `json` file is needed to specify multiple fixtures, here's an example:

```json
{
  "paths": [
    "/path/to/fixtures/ios_app_with_tests",
    "/path/to/fixtures/ios_app_with_helpers"
  ]
}
```

Console:

```sh
swift run tuistbench \
     --binary /path/to/tuist/.build/release/tuist \
     --reference-binary $(which tuist) \
     --fixture-list fixtures.json

Fixture       : ios_app_with_tests
Runs          : 5
Result
    - cold : 0.79s  vs  0.80s (≈)
    - warm : 0.75s  vs  0.79s (⬇︎ 0.04s 5.63%)


Fixture       : ios_app_with_carthage_frameworks
Runs          : 5
Result
    - cold : 0.78s  vs  0.86s (⬇︎ 0.08s 8.90%)
    - warm : 0.76s  vs  0.80s (⬇︎ 0.04s 5.05%)


Fixture       : ios_app_with_helpers
Runs          : 5
Result
    - cold : 2.24s  vs  2.37s (⬇︎ 0.12s 5.18%)
    - warm : 2.03s  vs  2.11s (⬇︎ 0.07s 3.55%)

```

Markdown:

```sh
swift run tuistbench \
     --binary /path/to/tuist/.build/release/tuist \
     -reference-binary $(which tuist) \
     --fixture-list fixtures.json \
     --format markdown
```

| Fixture                                    | New   | Old   | Delta    |
| ------------------------------------------ | ----- | ----- | -------- |
| ios*app_with_tests *(cold)\_               | 0.73s | 0.79s | ⬇︎ 7.92% |
| ios*app_with_tests *(warm)\_               | 0.79s | 0.79s | ≈        |
| ios*app_with_carthage_frameworks *(cold)\_ | 0.79s | 0.85s | ⬇︎ 7.36% |
| ios*app_with_carthage_frameworks *(warm)\_ | 0.77s | 0.81s | ⬇︎ 5.26% |
| ios*app_with_helpers *(cold)\_             | 2.29s | 2.43s | ⬇︎ 5.80% |
| ios*app_with_helpers *(warm)\_             | 1.97s | 2.15s | ⬇︎ 8.05% |
