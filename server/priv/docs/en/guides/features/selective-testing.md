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

Selective testing supports separate build and test jobs. If the build job produces an `.xctestrun` file, restore it in the test job and forward it to `tuist test --without-building`:

```sh
tuist test MyScheme \
  --without-building \
  -- \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/MyScheme.xctestrun
```

Tuist generates the project to determine which test targets changed, then forwards those targets through `-only-testing`. It does not pass a project, workspace, or scheme to `xcodebuild` when `-xctestrun` is present because those input modes are mutually exclusive.

Alternatively, build with `tuist test --build-only` and persist the complete `.xctestproducts` bundle:

```sh
tuist test MyScheme \
  --build-only \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'
```

In the test job, restore that complete bundle and pass the same path with `--without-building`:

```sh
tuist test MyScheme \
  --without-building \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'
```

An `.xctestrun` file is the test-run configuration: it identifies the built test bundles and how to launch them. An `.xctestproducts` bundle also contains the built test products and their `.xctestrun` files. Tuist adds the selective-testing graph to that bundle during the build job, letting the test job execute the selected tests without regenerating the project.

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
