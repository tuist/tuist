---
{
  "title": "Module cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Cache compiled binaries and share them across your team with Tuist Module Cache."
}
---

# Module cache {#module-cache}

> [!WARNING]
> **Requirements**
>
> - A <.localized_link href="/guides/features/projects">generated project</.localized_link>
> - A <.localized_link href="/guides/server/accounts-and-projects">Tuist account and project</.localized_link>


Tuist Module Cache provides a powerful way to optimize build times by caching your modules as binaries (`.xcframework`s) and sharing them across different environments. This capability allows you to leverage previously generated binaries, reducing the need for repeated compilation and speeding up the development process.

> [!TIP]
> **Combine with the Xcode cache**
>
> The module cache and the <.localized_link href="/guides/features/cache/xcode-cache">Xcode cache</.localized_link> are complementary because they work at different granularity levels. The module cache replaces whole modules with prebuilt `.xcframework`s before the build runs, while the Xcode cache reuses compilation outputs during the build.


## Warming {#warming}

Tuist efficiently <.localized_link href="/guides/features/projects/hashing">utilizes hashes</.localized_link> for each target in the dependency graph to detect changes. Utilizing this data, it builds and assigns unique identifiers to binaries derived from these targets. At the time of graph generation, Tuist then seamlessly substitutes the original targets with their corresponding binary versions.

This operation, known as *"warming,"* produces binaries for local use or for sharing with teammates and CI environments via Tuist. The process of warming the cache is straightforward and can be initiated with a simple command:


```bash
tuist cache
```

The command re-uses binaries to speed up the process.

### Configuration selection {#configuration-selection}

When warming the cache without passing `--configuration`, Tuist selects the build configuration to use in the following order:

1. The [`defaultConfiguration`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist/generationoptions/defaultconfiguration) set in your manifest's `Project.Options.generationOptions`, if any.
2. Otherwise, the first build configuration of variant `debug`, sorted alphabetically by name.

To warm the cache for a specific configuration, pass it explicitly:

```bash
tuist cache --configuration Release
```

## Usage {#usage}

By default, when Tuist commands necessitate project generation, they automatically substitute dependencies with their binary equivalents from the cache, if available. Additionally, if you specify a list of targets to focus on, Tuist will also replace any dependent targets with their cached binaries, provided they are available. For those who prefer a different approach, there is an option to opt out of this behavior entirely by using a specific flag:

::: code-group
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --cache-profile none # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

> [!WARNING]
> Binary caching is a feature designed for development workflows such as running the app on a simulator or device, or running tests. It is not intended for release builds. When archiving the app, generate a project with the sources by using `--cache-profile none`.


## Cache profiles {#cache-profiles}

Tuist supports cache profiles to control how aggressively targets are replaced with cached binaries when generating projects.

- Built-ins:
  - `only-external`: replace external dependencies only (system default)
  - `all-possible`: replace as many targets as possible (including internal targets)
  - `none`: never replace with cached binaries

Select a profile with `--cache-profile` on `tuist generate`:

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely
tuist generate --cache-profile none
```

> [!NOTE]
> **Deprecated Flag**
>
> The `--no-binary-cache` flag is deprecated. Use `--cache-profile none` instead. The deprecated flag still works for backwards compatibility.


Precedence when resolving the effective behavior (highest to lowest):

1. `--cache-profile none`
2. Target focus (passing targets to `generate`) → profile `all-possible`
3. `--cache-profile <value>`
4. Config default (if set)
5. System default (`only-external`)

## Supported products {#supported-products}

Only the following target products are cacheable by Tuist:

- Frameworks (static and dynamic), including test-support frameworks that depend on [XCTest](https://developer.apple.com/documentation/xctest) or Swift Testing
- Libraries (static and dynamic), including test-support libraries that depend on XCTest or Swift Testing
- Bundles
- Swift Macros

Test bundles remain excluded from the module cache. This means `unitTests` and `uiTests` targets are not cached as binaries, but regular framework and library targets that tests depend on can be cached even when they link XCTest or Swift Testing.

Cached library `.xcframework`s preserve the metadata needed by generated projects to import them, including Swift modules and public C/Objective-C headers when the source target declares public headers.

> [!NOTE]
> **Upstream Dependencies**
>
> When a target is non-cacheable it makes the upstream targets non-cacheable too. For example, if you have the dependency graph `A > B`, where A depends on B, if B is non-cacheable, A will also be non-cacheable.


## Analytics {#analytics}

Open **Module Cache → Modules** in your project's dashboard to find modules with frequent misses. Select the environment you want to improve, such as **CI**, and a date range. The overview shows cache hits, misses, and modules with misses; opening a module shows its history and the reason assigned to each observation.

The **Misses** dropdown selects a count and explanation for one reason. The chart shows the distribution of all four reasons. On a module's page, use the history's **Reason** filter to inspect individual occurrences. Hover over a reason badge, or focus it with the keyboard, for its definition.

### Miss reasons {#miss-reasons}

| Reason | What it means |
| --- | --- |
| **Changed** | The module's own compared inputs changed. These include file hashes, build settings, the resolved configuration, and the compiler identifier. A source edit is only one possible cause. |
| **Upstream** | The module's own compared inputs stayed the same, but its dependency or external-package hash changed. The module's source files can be untouched. |
| **Cold** | There is no earlier module observation to compare with, or the reported inputs do not explain the miss and there is no qualifying evidence of earlier remote availability. Cold does not prove that the module was never cached. |
| **Unavailable** | The exact cache key previously had a remote hit in the same project at the same recorded cache endpoint, but now misses. The **Earlier remote hit** link opens the run used as evidence. |

The cached artifact was most likely evicted. Unavailable establishes prior remote availability, but does not confirm eviction: access problems or a failed download can also produce this result. A previous miss or local-only hit does not establish that the artifact was available remotely.

For example:

| Scenario | Classification |
| --- | --- |
| A module misses with no earlier observation or qualifying remote hit | Cold |
| A changes; B depends on A, and C depends on B; all three keys change | A is Changed; B and C are Upstream |
| The compiler version changes after warming, with sources and settings unchanged | Affected misses are Changed when both observations report the compiler inputs |
| An exact key was downloaded remotely, then misses after its artifact is evicted | Unavailable, when the earlier hit qualifies as evidence |
| A key repeatedly misses and was never successfully warmed | It can remain Cold |

Reasons describe observations; they are not permanent labels attached to a key. For example, the first miss after a compiler upgrade can be Changed, while a later miss for that new key can be Cold if it was never observed as available remotely.

### What the comparison can tell you {#analytics-comparison}

Changed and Upstream compare the same module and product on the same branch, within the selected date range and environment. The previous observation may be a hit or a miss. Changing these filters can change the available comparison history.

Unavailable checks the available 30-day history ending at the selected end date. It can use evidence from another branch or from a local run when inspecting CI, because those runs can share the same remote cache. It requires the same project, full nonempty key, and nonempty recorded endpoint. The earlier remote-hit report must have arrived before the current command started; overlapping or later reports do not establish prior availability.

The CLI does not report every input used to construct the final key. Matching inputs in the dashboard therefore do not prove that the full keys match, and do not rule out a hashing or reporting bug. Older observations may also lack configuration/compiler fingerprints. An artifact successfully uploaded and then evicted before any recorded remote hit can still appear Cold: this classification does not currently use successful-upload evidence.

The **Modules** count describes the latest commit on the default branch; hit and miss totals cover the selected date range and environment. Counts represent reported command observations, not unique artifacts or commits. Older CLI versions can report a build's cache results again when test-only shards restore its metadata, inflating counts and often Cold misses. Update the CLI in both the build and consuming test jobs; existing reports are not rewritten.

### Improving the cache hit rate {#improving-cache-hit-rate}

1. **Choose a consistent baseline.** Start with CI and a representative date range. Sort modules by misses, then consider their hit rates, dependents, and build cost. Fixing a frequently missed, expensive dependency can save more time than improving the hit rate of a tiny module. Compare the same environment and similar workloads after making a change.
2. **Investigate Changed misses.** Open the relevant runs and compare their full keys and reported inputs. Align warming and consuming jobs on the intended Xcode/compiler version, configuration, and target destinations. Warm again after intentional changes. If volatile generated files or environment-dependent settings invalidate otherwise stable modules, investigate those inputs. Keep inputs that affect binary compatibility in the hash.
3. **Follow Upstream misses to the changed dependency.** Inspect its history to find the direct change. Warming the resulting keys can restore reuse. If a frequently changing implementation invalidates many expensive dependents, consider smaller modules or stable interfaces as described under [Efficiency](#efficiency).
4. **Check warming coverage for Cold misses.** Verify that warming selects the required modules, uses the consuming job's configuration and environment, and successfully uploads the artifacts. Check the full keys used by the actual CI jobs. If warming and consumption request different keys, inspect the hashing inputs before assuming the cache was evicted. Repeated misses with no earlier successful upload are possible even when the module's sources have not changed.
5. **Use the evidence for Unavailable misses.** Follow **Earlier remote hit**, confirm the key and endpoint, then inspect the consuming run's cache warnings and the warming job's upload outcome. Check retention or eviction when applicable. Rewarm the required artifacts and verify a subsequent hit. If they still miss, share the two run links and relevant logs with support.

For a hash comparison, run this in each relevant environment, using the configuration you intend to warm and consume:

```bash
tuist hash cache --configuration Debug --verbose
```

Compare the module's full hash and component block. Repeating the command on the same unchanged machine should normally produce the same result; compare the actual warming and consuming environments to investigate a mismatch. Neither command needs to hit the cache. See <.localized_link href="/guides/features/projects/hashing#debugging">hashing diagnostics</.localized_link> for further checks.

## Efficiency {#efficiency}

The level of efficiency that can be achieved with binary caching depends strongly on the graph structure. To achieve the best results, we recommend the following:

1. Avoid very nested dependency graphs. The shallower the graph, the better.
2. Define dependencies with protocol/interface targets instead of implementation ones, and dependency-inject implementations from the top-most targets.
3. Split frequently-modified targets into smaller ones whose likelihood of change is lower.

The above suggestions are part of the <.localized_link href="/guides/features/projects/tma-architecture">The Modular Architecture</.localized_link>, which we propose as a way to structure your projects to maximize the benefits not only of binary caching but also of Xcode's capabilities.

## Recommended setup {#recommended-setup}

We recommend having a CI job that **runs in every commit in the main branch** to warm the cache. This will ensure the cache always contains binaries for the changes in `main` so local and CI branch build incrementally upon them.

> [!TIP]
> **Keep Cache Warming Isolated**
>
> Run `tuist cache` in a dedicated CI step without subsequent steps that depend on the generated workspace. Since `tuist cache` modifies the workspace for cache building purposes, any CI steps that need the workspace should run `tuist generate` first to get a fresh, usable workspace.


> [!TIP]
> **Cache Warming Uses Binaries**
>
> The `tuist cache` command also makes use of the binary cache to speed up the warming.


The following are some examples of common workflows:

### A developer starts to work on a new feature {#a-developer-starts-to-work-on-a-new-feature}

1. They create a new branch from `main`.
2. They run `tuist generate`.
3. Tuist pulls the most recent binaries from `main` and generates the project with them.

### A developer pushes changes upstream {#a-developer-pushes-changes-upstream}

1. The CI pipeline will run `xcodebuild build` or `tuist test` to build or test the project.
2. The workflow will pull the most recent binaries from `main` and generate the project with them.
3. It will then build or test the project incrementally.

## Configuration {#configuration}

### Cache concurrency limit {#cache-concurrency-limit}

By default, Tuist downloads and uploads cache artifacts without any concurrency limit, maximizing throughput. You can control this behavior using the `TUIST_CACHE_CONCURRENCY_LIMIT` environment variable:

```bash
# Set a specific concurrency limit
export TUIST_CACHE_CONCURRENCY_LIMIT=10
tuist generate

# Use "none" for no limit (default behavior)
export TUIST_CACHE_CONCURRENCY_LIMIT=none
tuist generate
```

This can be useful in environments with limited network bandwidth or to reduce system load during cache operations.

### Cache warm scratch directory {#cache-warm-scratch-directory}

By default, `tuist cache` creates a temporary scratch directory for build intermediates and assembled cache artifacts, then removes it when cache warming finishes. To keep those files under a directory you manage, set `TUIST_CACHE_WARM_SCRATCH_DIRECTORY`.

The path can be absolute or relative to the current working directory. Tuist creates the directory when it does not exist. If it already exists, it must be an empty directory.

When this environment variable is set, Tuist leaves the directory and its contents in place after the command finishes. The caller is responsible for cleaning it before the next cache warm. When the variable is unset, Tuist continues to use and remove a temporary directory.

Tuist rejects a caller-owned scratch directory when a foreign build target needs to be warmed. Foreign build scripts control their own output locations, so Tuist cannot guarantee that those outputs stay inside the scratch directory.

## Troubleshooting {#troubleshooting}

### It doesn't use binaries for my targets {#it-doesnt-use-binaries-for-my-targets}

Ensure that the <.localized_link href="/guides/features/projects/hashing#debugging">hashes are deterministic</.localized_link> across environments and runs. This might happen if the project has references to the environment, for example through absolute paths. You can use the `diff` command to compare the projects generated by two consecutive invocations of `tuist generate` or across environments or runs.

Also make sure that the target doesn't depend either directly or indirectly on a <.localized_link href="/guides/features/cache/module-cache#supported-products">non-cacheable target</.localized_link>.

### Missing symbols {#missing-symbols}

When using sources, Xcode's build system, through Derived Data, can resolve dependencies that are not declared explicitly. However, when you rely on the binary cache, dependencies must be declared explicitly; otherwise you'll likely see compilation errors when symbols can't be found. To debug this, we recommend using the <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect dependencies --only implicit`</.localized_link> command and setting it up in CI to prevent regressions in implicit linking.
