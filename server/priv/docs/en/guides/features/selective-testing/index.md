---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Run only the tests affected by your latest changes with Tuist Selective Testing, so continuous integration lands feedback in seconds."
}
---
# Selective testing {#selective-testing}

As projects grow, running every test on every push stops being viable. Tuist Selective Testing drastically reduces test time by running only the tests affected by what changed since the last successful run, using our <.localized_link href="/guides/features/projects/hashing">hashing algorithm</.localized_link>. For other ways to cut test time, such as sharding and fixing slow tests, see [Slow tests](https://tuist.dev/solutions/slow-tests).

## Supported build systems {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

Support for other build systems is planned.

## Tracked files {#tracked-files}

Coverage-based selection runs the tests whose recorded coverage includes a changed file, so a changed file no test's coverage includes, such as a README, selects no test. Some files can affect tests without showing up in their coverage: dependency pins, build settings, a fixture a test reads, or a resource loaded at runtime. When a file matching a tracked-file pattern changes, coverage isn't applied and every test runs.

Tuist tracks each build system's manifests, lockfiles and build settings by default. Add your own glob patterns, relative to your project's directory, next to the coverage strategy. A pattern starting with `!` excludes the files it matches, Tuist's defaults included:

- **Generated Xcode project:** `trackedFiles` in `Tuist.swift`, as <.localized_link href="/guides/features/selective-testing/generated-xcode-project#tracked-files">its guide</.localized_link> describes.
- **Mix:** `tracked_files` in `mix.exs`:

```elixir
def project do
  [tuist: [selective_testing: [strategy: :coverage, tracked_files: ["test/fixtures/**", "!config/dev.exs"]]]]
end
```

A test run's Selective Testing tab lists every pattern the run used in its Config tab, with where each one comes from and which one matched a changed file.
