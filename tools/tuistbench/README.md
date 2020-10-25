# Tuist Benchmark

A tool to time & benchmark tuist's commands against a set of fixtures

## Usage

**Measurement (single fixture):**

```sh
swift run tuistbench --binary /path/to/local/tuist --fixture /path/to/fixture
```

**Benchmark (single fixture):**

```sh
swift run tuistbench --binary /path/to/local/tuist --reference-binary /path/to/master/tuist --fixture /path/to/fixture
```

**Benchmark (multiple fixtures):**

```sh
swift run tuistbench --binary /path/to/local/tuist --reference-binary /path/to/master/tuist --fixture-list /path/to/fixtures.json
```

`fixtures.json` example:

```json
{
  "paths": ["/path/to/fixtures/fixture_a", "/path/to/fixtures/fixture_b"]
}
```

**Options:**

- `--binary`,`-b`: Path to the tuist binary (usually the local one)
- `--reference-binary`, `-r`: Path to the reference tuist binary to benchmark against (usually master or latest release)
- `--fixture`, `-f`: Path to the fixture to use for benchmarking (The directory that contains the project or workspace manifest)
- `--fixture-list`, `-l`: Path to the fixture list json file (this contains a list of fixture paths)
- `--format`: The output format (`console` or `markdown`)
- `--config`, `-c`: Path the configuration override json file.
  - `arguments`: The arguments to use when invoking the binary (eg. `[generate]`)
  - `runs`: The number of times to perform a measurement (final results are the average of those runs)
  - `deltaThreshold`: The time interval threshold that measurements must exceed to be considered different (unit is `TimeInterval` / `Double` seconds)

`deltaThreshold` example:

When `deltaThreshold` is `0.02`

- new measurement: `1.20`s
- old measurement: `1.21`s
- The results consider those measurements approximately equal `≈`

- new measurement: `1.20`s
- old measurement: `1.23`s
- The results will display a delta of `-0.03`s

`config.json` example:

```
{
    "arguments": ["generate"],
    "runs": 5,
    "deltaThreshold": 0.02
}
```

## Example Output

**Measurement (single fixture):**

Console:

```sh
$ swift run tuistbench -b $(which tuist) -f /path/to/fixtures/ios_app_with_tests

Fixture       : ios_app_with_tests
Runs          : 5
Result
    - cold : 0.72s
    - warm : 0.74s

```

Markdown:

```sh
$ swift run tuistbench -b $(which tuist) -f /path/to/ios_app_with_tests --format markdown
```

| Fixture            | Cold  | Warm  |
| ------------------ | ----- | ----- |
| ios_app_with_tests | 0.72s | 0.72s |

**Benchmark (multiple fixtures):**

`fixtures.json`:

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
$ swift run tuistbench -b /path/to/tuist/.build/release/tuist -r $(which tuist) -l fixtures.json

Fixture       : ios_app_with_tests
Runs          : 5
Result
    - cold : 0.79s  vs  0.80s (≈)
    - warm : 0.75s  vs  0.79s (⬇︎ 0.04s 5.63%)


Fixture       : ios_app_with_helpers
Runs          : 5
Result
    - cold : 2.24s  vs  2.37s (⬇︎ 0.12s 5.18%)
    - warm : 2.03s  vs  2.11s (⬇︎ 0.07s 3.55%)

```

Markdown:

```sh
$ swift run tuistbench -b /path/to/tuist/.build/release/tuist -r $(which tuist) -l fixtures.json --format markdown
```

| Fixture                        | New   | Old   | Delta    |
| ------------------------------ | ----- | ----- | -------- |
| ios*app_with_tests *(cold)\_   | 0.73s | 0.79s | ⬇︎ 7.92% |
| ios*app_with_tests *(warm)\_   | 0.79s | 0.79s | ≈        |
| ios*app_with_helpers *(cold)\_ | 2.29s | 2.43s | ⬇︎ 5.80% |
| ios*app_with_helpers *(warm)\_ | 1.97s | 2.15s | ⬇︎ 8.05% |

## Features

- [x] Measure cold and warm runs for `tuist generate`
- [x] Specify individual fixture paths
- [x] Specify multiple fixture paths (via `.json` file)
- [x] Basic console results output
- [x] Markdown results output (for use on GitHub)
- [x] Custom configuration to tweak tuist command, number of runs and delta threshold
- [x] Average cold and warm runs
