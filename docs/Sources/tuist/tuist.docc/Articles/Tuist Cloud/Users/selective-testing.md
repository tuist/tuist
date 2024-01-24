# Selective Testing

Run only tests that have changed since the last successful test run

## Overview

As your project grows, so does the amount of your tests. For a long time, running all tests on every PR or push to `main` takes tens of seconds. But this solution does not scale to thousands of tests your team might have.

On every test run on the CI, you probably build a project with cleaned derived data and re-run all the tests, regardless of the changes. `tuist test` helps you to drastically decrease the build time and then running the tests themselves.

### Using cache binaries

When you call `tuist test`, tuist generates a project focusing on test targets only. It is similar to you running `tuist generate MyTestA MyTestB ...`, and so you automatically get the benefits of the [binary caching](./binary-caching).

### Running tests selectively

To run tests selectively, use the `tuist test` command. This command fingerprints your project the same way it does for [warming the cache](./binary-caching#Cache-warming). If the `tuist test` command succeeds, it will save those fingeprints in the Tuist cache. This effectively marks those as fingerprints as tested and from this point on, tuist will only re-run a test suite if a target's fingerpring the suite depends on is not present in the cache.

For example, if you have test suites `FeatureATests`, `FeatureBTests` which depend on `FeatureA` and `FeatureB`, respectively, and both depend on a module `Core`, `tuist test` will behave as such:
```bash
tuist test # Initial test run, runs for both `FeatureATests` and `FeatureBTests`
# `FeatureA` module is updated
tuist test
# FeatureATests has not changed from last successful run, skipping..
# Testing scheme Tuist-Workspace -> only FeatureBTests will be run

# `Core` module is updated
tuist test
# Both FeatureATests and FeatureBTests will be run
```

The test results used for selective testing can be also shared across environments – this will be done automatically once your project is [set up with Tuist Cloud](./binary-caching#Sharing-binaries-across-environments).

By reusing both binary caching and selective testing across environments, you will be able to dramatically reduce your test runs.
