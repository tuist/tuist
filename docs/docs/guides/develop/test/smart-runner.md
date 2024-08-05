---
title: Smart test runner
description: Use smart test selection to run only the tests that need to be run.
---

# Smart test runner

> [!IMPORTANT] REQUIRES AN ACCOUNT
> You need to be authenticated and have and [a project set up](/guides/quick-start/gather-insights) to use the smart test runner across environments.

As your project grows, so does the amount of your tests. For a long time, running all tests on every PR or push to `main` takes tens of seconds. But this solution does not scale to thousands of tests your team might have.

On every test run on the CI, you probably build a project with cleaned derived data and re-run all the tests, regardless of the changes. `tuist test` helps you to drastically decrease the build time and then running the tests themselves.

## Running tests selectively

To run tests selectively, use the `tuist test` command. The command hashes your project the same way it does for [warming the cache](/guides/develop/build/cache#cache-warming), and on success, it persists the hashes on to determine what has changed in future runs.

In future runs `tuist test` transparently uses the hashes to filter down the tests to run only the ones that have changed since the last successful test run.

For example, assuming the following dependency graph:

- `FeatureA` has tests `FeatureATests`, and depends on `Core`
- `FeatureB` has tests `FeatureBTests`, and depends on `Core`
- `Core` has tests `CoreTests`

`tuist test` will behave as such:

| Action | Description | Internal state |
| ---- | --- | ---- |
| `tuist test` invocation | Runs the tests in `CoreTests`, `FeatureATests`, and `FeatureBTests` | The hashes of `FeatureATests`, `FeatureBTests` and `CoreTests` are persisted |
| `FeatureA` is updated | The developer modifies the code of a target | Same as before |
| `tuist test` invocation | Runs the tests in `FeatureATests` because it hash has changed | The new hash of `FeatureATests` is persisted |
| `Core` is updated | The developer modifies the code of a target | Same as before |
| `tuist test` invocation | Runs the tests in `CoreTests`, `FeatureATests`, and `FeatureBTests` | The new hash of `FeatureATests` `FeatureBTests`, and `CoreTests` are persisted |

The combination of selective testing with binary caching can dramatically reduce the time it takes to run tests on your CI.

> [!WARNING] MODULE VS FILE-LEVEL GRANULARITY
> Due to the impossibility of detecting the in-code dependencies between tests and sources, the maximum granularity of selective testing is at the target level. Therefore, we recommend keeping your targets small and focused to maximize the benefits of selective testing.
