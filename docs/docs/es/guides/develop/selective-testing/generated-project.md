---
title: Generated project
titleTemplate: :title · Selective testing · Develop · Guides · Tuist
description: Learn how to leverage selective testing with a generated project.
---

# Generated project {#generated-project}

> [!IMPORTANT] REQUIREMENTS
>
> - A <LocalizedLink href="/guides/develop/projects">generated project</LocalizedLink>
> - A <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist account and project</LocalizedLink>

To run tests selectively with your generated project, use the `tuist test` command. The command <LocalizedLink href="/guides/develop/projects/hashing">hashes</LocalizedLink> your Xcode project the same way it does for <LocalizedLink href="/guides/develop/build/cache#cache-warming">warming the cache</LocalizedLink>, and on success, it persists the hashes on to determine what has changed in future runs.

In future runs `tuist test` transparently uses the hashes to filter down the tests to run only the ones that have changed since the last successful test run.

For example, assuming the following dependency graph:

- `FeatureA` has tests `FeatureATests`, and depends on `Core`
- `FeatureB` has tests `FeatureBTests`, and depends on `Core`
- `Core` has tests `CoreTests`

`tuist test` will behave as such:

| Action                  | Description                                                         | Internal state                                                                 |
| ----------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `tuist test` invocation | Runs the tests in `CoreTests`, `FeatureATests`, and `FeatureBTests` | The hashes of `FeatureATests`, `FeatureBTests` and `CoreTests` are persisted   |
| `FeatureA` is updated   | The developer modifies the code of a target                         | Same as before                                                                 |
| `tuist test` invocation | Runs the tests in `FeatureATests` because it hash has changed       | The new hash of `FeatureATests` is persisted                                   |
| `Core` is updated       | The developer modifies the code of a target                         | Same as before                                                                 |
| `tuist test` invocation | Runs the tests in `CoreTests`, `FeatureATests`, and `FeatureBTests` | The new hash of `FeatureATests` `FeatureBTests`, and `CoreTests` are persisted |

`tuist test` integrates directly with binary caching to use as many binaries from your local or remote storage to improve the build time when running your test suite. The combination of selective testing with binary caching can dramatically reduce the time it takes to run tests on your CI.
