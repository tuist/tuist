---
title: xcodebuild
titleTemplate: :title · Selective testing · Develop · Guides · Tuist
description: Learn how to leverage selective testing with `xcodebuild`.
---

# xcodebuild {#xcodebuild}

> [!IMPORTANT] REQUIREMENTS
> - A <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist account and project</LocalizedLink>

To run tests selectively using `xcodebuild`, you can prepend your `xcodebuild` command with `tuist` – for example, `tuist xcodebuild test -scheme App`. The command hashes your project and on success, it persists the hashes to determine what has changed in future runs.

In future runs `tuist xcodebuild test` transparently uses the hashes to filter down the tests to run only the ones that have changed since the last successful test run.

For example, assuming the following dependency graph:

- `FeatureA` has tests `FeatureATests`, and depends on `Core`
- `FeatureB` has tests `FeatureBTests`, and depends on `Core`
- `Core` has tests `CoreTests`

`tuist xcodebuild test` will behave as such:

| Action | Description | Internal state |
| ---- | --- | ---- |
| `tuist xcodebuild test` invocation | Runs the tests in `CoreTests`, `FeatureATests`, and `FeatureBTests` | The hashes of `FeatureATests`, `FeatureBTests` and `CoreTests` are persisted |
| `FeatureA` is updated | The developer modifies the code of a target | Same as before |
| `tuist xcodebuild test` invocation | Runs the tests in `FeatureATests` because it hash has changed | The new hash of `FeatureATests` is persisted |
| `Core` is updated | The developer modifies the code of a target | Same as before |
| `tuist xcodebuild test` invocation | Runs the tests in `CoreTests`, `FeatureATests`, and `FeatureBTests` | The new hash of `FeatureATests` `FeatureBTests`, and `CoreTests` are persisted |

To use `tuist xcodebuild test` on your CI, follow the instructions in the <LocalizedLink href="/guides/automate/continuous-integration">Continuous integration guide</LocalizedLink>.
