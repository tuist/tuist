---
title: "Monzo slashed CI pipeline time by 70%"
date: "2026-03-06"
url: "https://monzo.com/"
onboarded_date: "2025-01-22"
founded_date: "2015"
company: "Monzo"
excerpt: "Monzo cut their P50 PR time from 52 to 15 minutes using Tuist Binary Cache and selective testing. Learn how their 50+ iOS engineer team transformed their CI pipeline."
---

## The challenge

At [Monzo](https://monzo.com), we had two goals that motivated us to start using Tuist: making it easier to modularise our codebase, and speeding up our CI checks. When we began our modularisation journey we had around 50 modules, which has now grown to close to 200. Before Tuist, creating new modules was very manual and error-prone, and keeping consistency across that many would have been far more difficult without Tuist's project generation. On the CI side, we have over 20k unit tests and 8k snapshot tests covering our 1.9 million lines of Swift. As our team grew significantly to 50+ iOS engineers, our CI times climbed with it, peaking at over 70 minutes per pull request.

## Choosing Tuist

We chose Tuist Binary Cache because we were already using Tuist for project generation, which we were really happy with. The way the cache integrates with our existing project setup made it a natural fit. We also evaluated other options such as XCRemoteCache, SPM prebuilt dependencies, Bazel, and building a custom solution, but Tuist Cache offered the best balance of integration and ease of adoption.

> "Tuist Cache offered the best balance of integration and ease of adoption."

## The approach

Our previous strategy split tests into multiple parallel CI jobs that would each run a subset of the full test suite. This worked initially, but there was significant overhead in having multiple jobs passing data between each other. As we increased the parallelisation, it increasingly became more expensive without meaningfully reducing wall-clock time. We rethought the pipeline around three key principles: simplify the pipeline, build only what changed, and test only what changed.

**Binary caching.** We periodically warm up the cache on the main branch every 20 minutes. When a PR runs, only the modules that changed (and their downstream dependents) are compiled from source; everything else uses pre-built binaries from the cache. We analysed our git history and dependency graph to validate the approach before rolling it out and found a cache hit rate of roughly 85%.

**Selective testing.** Tuist offers [selective testing](https://docs.tuist.dev/en/guides/features/selective-testing) out-of-the-box, but we needed stricter control over what gets tested and when. We found the built-in selective testing was running more tests than we would like for our use cases, particularly around skipping monolith tests when we deem it unnecessary (we are not fully modularised but we risk-accept not always running monolith tests when there is low risk to do so), and handling race conditions with the main branch when tests on main have not finished running yet. So we built our own layer on top: we use git diff to identify changed files, map those to build targets, then use tuist graph to traverse the dependency graph and find all downstream targets that could be affected. From there, we use Tuist to generate a dynamic Xcode scheme containing only those targets, with unchanged upstream dependencies replaced by cached XCFrameworks. For a typical feature module change, this means running around 200 tests instead of the full 23k+ suite.

A couple of things worth noting: we default to dynamic frameworks for all modules when testing (since mixing static and dynamic causes duplicate framework issues), while release builds still use static linking. This was only possible because with Tuist we can apply different types of build settings for the whole project. We also explored using mergeable libraries, but were not able to get it working with our project structure. We also never use cache for production builds, and we merge from the latest cached commit rather than HEAD to maximise cache hit rates. Before fully committing to selective testing, we ran it in shadow mode first to validate which tests would be selected.

## The results

The improvements were substantial:

- P50 PR time dropped from 52 minutes to 15 minutes (-71%)
- P90 PR time dropped from 57 minutes to 35 minutes (-39%)
- PRs with no code changes (docs, config): about 3 minutes
- Feature module changes (~200 tests): around 10 minutes
- Shared module changes (~15k tests): around 23 minutes

> "P50 PR time dropped from 52 minutes to 15 minutes."

## What's next

We are extremely happy with the CI improvements. Where we have not yet seen as much benefit is local build times, which with the cache have remained fairly similar. Enabling binary caching for local development is something we would really like to explore in the future.

We also plan to continue our modularisation journey and optimise the dependency graph further, both of which should improve cache effectiveness even more.

One area where we would love to see Tuist evolve is around cache integrity. Currently, changes in the dependency graph can silently break the cache, and we have had to write our own scripts to detect this when updating dependencies. Having Tuist handle that validation automatically would make the experience even smoother.
