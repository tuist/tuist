---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use Tuist Selective Testing to run only the Xcode tests affected by your latest changes."
}
---
# Selective testing {#selective-testing}

As your project grows, so does the amount of your tests. For a long time, running all tests on every PR or push to `main` takes tens of seconds. But this solution does not scale to thousands of tests your team might have.

On every test run on the CI, you most likely re-run all the tests, regardless of the changes. Tuist's selective testing helps you to drastically speed up running the tests themselves by running only the tests that have changed since the last successful test run based on our <.localized_link href="/guides/features/projects/hashing">hashing algorithm</.localized_link>.

To run tests selectively with your <.localized_link href="/guides/features/projects">generated project</.localized_link>, use the `tuist test` command. The command <.localized_link href="/guides/features/projects/hashing">hashes</.localized_link> your project the same way it does for the <.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link>, and on success, it persists the hashes to determine what has changed in future runs. In future runs, `tuist test` transparently uses the hashes to filter down the tests and run only the ones that have changed since the last successful test run.

`tuist test` integrates directly with the <.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link> to use as many binaries from your local or remote storage to improve the build time when running your test suite. The combination of selective testing with module caching can dramatically reduce the time it takes to run tests on your CI.

## Separate build and test jobs {#separate-build-and-test-jobs}

Selective testing supports separate build and test jobs. Run `tuist test --build-only` in the build job so Tuist can persist a `selective-testing-graph.json` file alongside the products the build emits. That graph carries the hashes selective testing needs, so the test job doesn't have to regenerate the project or resolve Swift Package dependencies to figure out which targets to run.

Tuist writes the graph in two places during `--build-only`:

- Inside the `.xctestproducts` bundle when you pass `-testProductsPath`.
- Next to every `.xctestrun` file under the derived data's `Build/Products/` directory.

Cache either output alongside the built products and hand the same path to `--without-building` in the test job. Both forms work:

```sh
# Build job — writes an .xctestproducts bundle with the graph inside it.
tuist test MyScheme \
  --build-only \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'

# Test job — restores the same bundle.
tuist test MyScheme \
  --without-building \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'
```

```sh
# Build job — writes the graph as a sibling of each xctestrun in derived data.
tuist test MyScheme \
  --build-only \
  --derived-data-path artifacts/derived-data

# Test job — points --without-building at any of those xctestrun files.
tuist test MyScheme \
  --without-building \
  --derived-data-path artifacts/derived-data \
  -- \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/derived-data/Build/Products/MyScheme_iphonesimulator.xctestrun
```

When Tuist can't find that graph next to the input (for example, when the build job used plain `xcodebuild build-for-testing` instead of `tuist test --build-only`), it falls back to regenerating the project so it can still compute the affected targets. That fallback needs Swift Package dependencies to be resolved on the test job, so run `tuist install` first or cache `Tuist/.build` between jobs.

The graph reflects the source tree as it was at build time. Run the test job against the same commit as the build job — if the source drifts between the two, the hashes travel out of date and selective testing can skip tests that would actually fail against the newer source.

### Which flag should I use? {#which-flag-should-i-use}

`.xctestrun` and `.xctestproducts` are two different Xcode output formats, and they trade off portability against pipeline convenience:

- **`-testProductsPath` (`.xctestproducts`) — recommended for new pipelines.** It's a self-contained directory: the built `.xctest` binaries and their `.xctestrun` files live inside it with paths made relative to the bundle root, so it stays valid wherever it ends up. It's also the format that has had the selective-testing fast path the longest, so it's the most-exercised path.
- **`-xctestrun` (raw `.xctestrun`) — use it if you already have a pipeline built around derived data.** `xcodebuild build-for-testing` writes an `.xctestrun` at the top of `<derivedData>/Build/Products/` by default and points it at test bundles that live elsewhere in that tree. Reusing it in another job means keeping the paths in `Build/Products/` intact.

If you're starting fresh, prefer `-testProductsPath`. If you're wiring Tuist into an existing pipeline that already caches derived data, `-xctestrun` will now get the same fast path as long as the build job runs through `tuist test --build-only`.

Either input mode is mutually exclusive with `-workspace`/`-project`/`-scheme`, so Tuist skips those flags when the passthrough arguments include `-xctestrun` or `-testProductsPath`, and forwards the selected targets through `-only-testing`.

> [!WARNING]
> **Module Vs File-level Granularity**
>
> Due to the impossibility of detecting the in-code dependencies between tests and sources, the maximum granularity of selective testing is at the target level. Therefore, we recommend keeping your targets small and focused to maximize the benefits of selective testing.


> [!WARNING]
> **Test Coverage**
>
> Test coverage tools assume that the whole test suite runs at once, which makes them incompatible with selective test runs—this means the coverage data might not reflect reality when using test selection. That’s a known limitation, and it doesn’t mean you’re doing anything wrong. We encourage teams to reflect on whether coverage is still bringing meaningful insights in this context, and if it is, rest assured that we’re already thinking about how to make coverage work properly with selective runs in the future.


## Pull/merge request comments {#pullmerge-request-comments}

> [!WARNING]
> **Integration With Git Platform Required**
>
> To get automatic pull/merge request comments, integrate your <.localized_link href="/guides/server/accounts-and-projects">Tuist project</.localized_link> with a <.localized_link href="/guides/server/authentication">Git platform</.localized_link>.


Once your Tuist project is connected with your Git platform such as [GitHub](https://github.com), and you start using `tuist test` as part of your CI workflow, Tuist will post a comment directly in your pull/merge requests, including which tests were run and which skipped:
![GitHub app comment with a Tuist Preview link](/images/guides/features/selective-testing/github-app-comment.png)


## Investigating misses on the dashboard {#investigating-misses-on-the-dashboard}

When a previously cached test target shows up as a miss, the **Selective Testing** tab on a test run page lets you drill into the inputs that produced the hash. Expanding a row reveals the per-component subhashes — sources, dependencies, environment variables, project and target settings, Info.plist, entitlements, headers, and so on — so you can pinpoint the input that drifted between runs.

Use the **Copy as JSON** button at the top of the Selective Testing card to export every selective testing target with its hash and subhashes. Comparing the JSON between two runs is the fastest way to confirm which input changed when the test target's hash drifted.
