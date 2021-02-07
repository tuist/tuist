---
title: Selective testing
who: @fortmarek
---

## Context

> What motivated us to implement this feature

Re-running all the tests on the CI can take quite a long time on larger projects - we should be able to recognize what has changed and run tests only for those changed modules.

## What

> What's selective testing? Who would benefit from this feature? Why would you use selective testing in your workflows?

Selective testing is bundled in `tuist test` command - it re-runs only tests for the modules (or their transitive dependencies) that have changed. If your tests are taking a long time, you might want to use `test` command to strip the tests time tremendously - although, this will only work effectively if your project is modular as that is the granularity we use.

## How

> Overview of how it's been implemented.

`tuist test` first hashes the graph targets that can be tested (directly or transitively). It then "tree-shakes" the graph removing all the targets from test actions that have not changed from the last successful test run. Afterwards, tests are run. If they are successful, we save the hashes computed early in the process to `$TUIST_CACHE_DIRECTORY/TestsCache` which is by default at `~/.tuist/Cache/TestsCache`. We have been able to reuse a lot of functionality from `tuist cache`.

## Alternatives

> Without selective testing, how can achieve the same results of speeding up test runs?

There are many methods but most are on the side of the users - that is making tests quick (striving for synchronous rather than asynchronous unit tests). What we can do on tuist side is reusing cached modules from `tuist cache`, so they don't have to be rebuilt on the CI - in other words, we can focus on targets that have tests with other targets being taken from cache.
