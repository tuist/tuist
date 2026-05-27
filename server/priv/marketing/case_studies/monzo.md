---
title: "Monzo slashed CI pipeline time by 70%"
date: "2026-05-26"
url: "https://monzo.com/"
founded_date: "2015"
company: "Monzo"
excerpt: "Monzo used Tuist project generation, Binary Cache, and selective testing to cut median PR time from 52 minutes to 15 minutes while scaling its iOS codebase to nearly 200 modules."
---

## The challenge

At [Monzo](https://monzo.com/), we had two goals that motivated us to start using Tuist: making it easier to modularise our codebase, and speeding up our CI checks.

When we began our modularisation journey, we had around 50 modules. That has now grown to close to 200. Before Tuist, creating new modules was very manual and error-prone, and keeping consistency across that many modules would have been far more difficult without Tuist's [project generation](https://tuist.dev/en/docs/guides/features/projects).

On the CI side, we have more than 20k unit tests and 8k snapshot tests covering 1.9 million lines of Swift. As our team grew significantly to 45+ iOS engineers, our CI times climbed with it, peaking at over 70 minutes per pull request.

## Choosing Tuist

We chose [Tuist Binary Cache](https://tuist.dev/en/docs/guides/features/cache) because we were already using Tuist for project generation, which we were really happy with. The way the cache integrates with our existing project setup made it a natural fit.

## The approach

Our previous strategy split tests into multiple parallel CI jobs that each ran a subset of the full test suite. This worked initially, but there was significant overhead in having multiple jobs pass data between each other. As we increased the parallelisation, it became increasingly expensive without meaningfully reducing wall-clock time.

We rethought the pipeline around three key principles:

1. Simplify the pipeline
2. Build only what changed
3. Test only what changed

### Binary caching

We periodically warm up the cache on the main branch every 30 minutes. When a PR runs, only the modules that changed, and their downstream dependencies, are compiled from source. Everything else uses pre-built binaries from the cache. To maximise cache hit rates, we merge from the latest cached commit on `main` rather than `HEAD`. Our cache hit rate is around 80%.

### Selective testing

We use `git diff` to identify changed files, map those to build targets, and then use `tuist graph` to traverse the dependency graph and find all downstream targets that could be affected. From there, we use Tuist to generate a dynamic Xcode scheme containing only those targets, with unchanged upstream dependencies replaced by cached XCFrameworks.

For a typical feature module change, this means running around 200 tests instead of the full 23k+ suite.

A couple of things are worth noting:

- We default to dynamic frameworks for all modules when testing, since mixing static and dynamic causes duplicate framework issues, while release builds still use static linking. This was only possible because with Tuist we can apply different build settings across the whole project.
- We also explored using mergeable libraries, but we were not able to get that working with our project structure.
- We never use cache for production builds.

## The results

The improvements were substantial:

- **P50 PR time** dropped from 52 minutes to 15 minutes (-71%)
- **P90 PR time** dropped from 57 minutes to 35 minutes (-39%)
- **PRs with no code changes** such as docs or config complete in about 3 minutes
- **Feature module changes** with around 200 tests complete in around 10 minutes
- **Shared module changes** with around 15k tests complete in around 23 minutes

## What's next

We are extremely happy with the CI improvements. Where we have not yet seen as much benefit is local build times, which have remained fairly similar even with the cache. Enabling binary caching for local development is something we would really like to explore in the future.

We also plan to continue our modularisation journey and optimise the dependency graph further, both of which should improve cache effectiveness even more.
