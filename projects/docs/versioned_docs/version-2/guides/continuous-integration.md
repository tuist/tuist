---
title: Continuous integration
slug: '/guides/continuous-integration'
description: Learn how to use Tuist from your continuous integration pipelines.
---

Tuist projects might need Tuist to be present in their continuous integration (CI) environments to generate, build, and test the projects.
To do so, you can add a step to your CI pipeline that executes the [installation command](tutorial/get-started.md#install).
However, we recommend using pipeline steps designed by us. It's more convenient, and you'll benefit from optimizations and integrations with the underlying CI provider that otherwise you'd have to build yourself.

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
      - uses: actions/checkout@v1
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