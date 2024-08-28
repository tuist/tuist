---
title: Continuous Integration (CI)
titleTemplate: ":title | Develop | Tuist"
description: Learn how to use Tuist in your CI workflows.
---

# Continuous Integration (CI)

You can use Tuist in [continuous integration](https://en.wikipedia.org/wiki/Continuous_integration) environments. The following sections provide examples of how to do this on different CI platforms.

## Examples

To run Tuist commands in your CI workflows, you’ll need to install it in your CI environment.

### Xcode Cloud

In [Xcode Cloud](https://developer.apple.com/xcode-cloud/), which uses Xcode projects as the source of truth, you'll need to add a [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) script to install Tuist and run the commands you need, for example `tuist generate`:

:::code-group

```bash [Mise]
#!/bin/sh
curl https://mise.jdx.dev/install.sh | sh
mise install # Installs the version from .mise.toml

# Runs the version of Tuist indicated in the .mise.toml file
mise x tuist generate
```
```bash [Homebrew]
#!/bin/sh
brew install --formula tuist@x.y.z

tuist generate
```
:::
### Codemagic

In [Codemagic](https://codemagic.io), you can add an additional step to your workflow to install Tuist:

::: code-group
```yaml [Mise]
workflows:
  lint:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
    scripts:
      - name: Install Mise
        script: |
          curl https://mise.jdx.dev/install.sh | sh
          mise install # Installs the version from .mise.toml
      - name: Build
        script: mise x tuist build
```
```yaml [Homebrew]
workflows:
  lint:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
    scripts:
      - name: Install Tuist
        script: |
          brew install --formula tuist@x.y.z
      - name: Build
        script: tuist build
```
:::

### GitHub Actions

On [GitHub Actions](https://docs.github.com/en/actions) you can an additional step to install Tuist, and in the case of managing the installation of Mise, you can use the [mise-action](https://github.com/jdx/mise-action), which abstracts the installation of Mise and Tuist:

::: code-group
```yaml [Mise]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: jdx/mise-action@v2
      - run: tuist build
```
```yaml [Homebrew]
name: test
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main
jobs:
  lint:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - run: brew install --formula tuist@x.y.z
      - run: tuist build
```
:::

::: tip
We recommend using `mise use --pin` in your Tuist projects to pin the version of Tuist across environments. The command will create a `.tool-versions` file containing the version of Tuist.
:::

## Authentication

When using server-side features such as [cache](/guides/develop/build/cache), you'll need a way to authenticate requests going from your CI workflows to the server. For that, you can generate a project-scoped token by running the following command:

```bash
tuist project tokens create my-handle/MyApp
```

The command will generate a token for the project with full handle `my-account/my-project`. Set the value to the environment variable 
`TUIST_CONFIG_TOKEN` in your CI environment ensuring it's configured as a secret so it's not exposed.

> [!IMPORTANT] CI ENVIRONMENT DETECTION
> Tuist only uses the token when it detects it's running on a CI environment. If your CI environment is not detected, you can force the token usage by setting the environment variable `CI` to `1`.