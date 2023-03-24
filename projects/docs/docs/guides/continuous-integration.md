---
title: Continuous integration
slug: '/guides/continuous-integration'
description: Learn how to use Tuist from your continuous integration pipelines.
---

Tuist projects might need Tuist to be present in their continuous integration (CI) environments to generate, build, and test the projects.
To do so, we recommend using pipeline steps designed by us. It's more convenient, and you'll benefit from optimizations and integrations with the underlying CI provider that otherwise you'd have to build yourself.

### GitHub Actions

If your CI provider is [GitHub Actions](https://github.com/features/actions), you can run Tuist through the [tuist-action](https://github.com/tuist/tuist-action) GitHub Action. The action takes a `command` argument, which represents the Tuist command that will executed, for example, `generate`, and `arguments`, a string that contains all the arguments that will be passed alongside the command.

```yaml
# .github/workflows/my-project.yml
name: My project

on:
  push:
    branches:
      - main
  pull_request:

jobs:
  build:
    name: Build
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: tuist/tuist-action@0.13.0
        with:
          command: 'build'
          arguments: ''
```

### Bitrise

If your CI provider is [Bitrise](https://www.bitrise.io), we provide a plug-and-play [Bitrise Step](https://github.com/tuist/bitrise-step-tuist). The code snippet below shows an example of a `bitrise.yml` pipeline that builds a project using the step:

```yaml
format_version: 4

workflows:
  build:
    steps:
      - git::https://github.com/tuist/bitrise-step-tuist.git:
          title: Build project
          inputs:
            - command: build
```

### Others

If your CI provider is not supported yet, you can still use Tuist by adding the required steps to install and run it.

Here are a number of best practice you can follow:

- Define your local version in the `.tuist-version` file (for example, running `tuist local 3.0.0`)
  - This makes sure the same version of Tuist is used across all machines, both locally and in CI
- Install tuist unzipping the `tuist.zip` downloaded directly from the GitHub releases, using the version defined in the `.tuist-version` file (for example, [link for 3.0.0](https://github.com/tuist/tuist/releases/download/3.0.0/tuist.zip))
  - Make sure to cache the unzipped folder across CI runs to avoid having to download it over and over again
- Keep Tuist caches across CI runs to avoid having to recompute everything in every run
  - Use both the `Project.swift` and the dependencies lockfiles in `Tuist/Dependencies/Lockfiles/` as part of the cache key, so that the cache is invalidated if important project configuration changes
  - Make sure you cache the following folders:
    - Tuist/Dependencies/Carthage
    - Tuist/Dependencies/SwiftPackageManager
    - Tuist/Dependencies/graph.json
    - ~/.tuist/Cache
