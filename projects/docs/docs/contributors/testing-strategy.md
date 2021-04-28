---
title: Testing strategy
slug: /contributors/testing-strategy
description: This page describes the project's testing strategy and what's the most suitable case for each of them.
---

Tuist employs a diverse suite tests that help ensure it works as intended and prevents regressions as it continues to grow and evolve.

### Acceptance Tests

Acceptance tests run the built `tuist` command line against a wide range of [fixtures](https://github.com/tuist/tuist/tree/main/fixtures) and verify its output and results. They are the slowest to run however provide the most coverage. The idea is to **test a few complete scenarios for each major feature**.

Those are written in [Cucumber](https://cucumber.io/docs) and Ruby and can be found in [features](https://github.com/tuist/tuist/tree/main/features). Those are run when calling `./fourier test tuist acceptance`:

```bash
# 3 is the line where the definition of the test starts
./fourier test tuist acceptance projects/tuist/features/generate-1.feature:3
```

:::note Example

[_generate-1.features_](https://github.com/tuist/tuist/blob/main/projects/tuist/features/generate-1.feature) has several scenarios that run `tuist generate` on a fixture, verify Xcode projects and workspaces are generated and finally verify the generated project build and test successfully.

:::

### Unit Tests

Most of the internal components Tuist uses have unit tests to thoroughly test them. Here dependencies of components are mocked or stubbed appropriately to ensure tests are reliable, test only one component and are fast!

Those are written in Swift and follow the convention of `<ComponentName>Tests`. Those are run when calling `swift test` or from within Xcode.

:::note Example

[TargetLinterTests](https://github.com/tuist/tuist/blob/main/Tests/TuistGeneratorTests/Linter/TargetLinterTests.swift) verifies all the different scenarios the target linter component can flag issues for.

:::

### Integration Tests

There's a small subset of tests that test several components together as a whole to cover hard to orchestrate scenarios within acceptance tests or unit tests. Those stub some but not all dependencies depending on the test case and are slower than unit tests.

Those are written in Swift and are contained within the `Tuist...IntegrationTests` targets. Those are run when calling `swift test` or from within Xcode.

**Example:**

:::note Example
[StableStructureIntegrationTests](https://github.com/tuist/tuist/blob/main/Tests/TuistIntegrationTests/Generator/StableStructureIntegrationTests.swift) dynamically generates projects with several dependencies and files in random orders and verifies the generated project is always the same even after several generation passes.
:::
