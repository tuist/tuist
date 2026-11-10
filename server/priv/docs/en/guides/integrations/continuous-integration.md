---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# Continuous Integration (CI) {#continuous-integration-ci}

To run Tuist commands in your [continuous integration](https://en.wikipedia.org/wiki/Continuous_integration) workflows, you'll need to install it in your CI environment. 

Authentication is optional but required if you want to use server-side features like <.localized_link href="/guides/features/cache">cache</.localized_link>. 

The following sections provide examples of how to do this on different CI platforms. Once connects through its own native Tuist provider; it does not need the Tuist CLI. See [Once](#once) for that workflow.

## Once {#once}

Commit the provider and cache binding from <.localized_link href="/guides/get-started/once-project">Get started with Once</.localized_link>. Install Once in the job using [Once's installation instructions](https://buildonce.dev/docs/guide/getting-started), then authenticate before running cacheable work.

GitHub Actions, CircleCI, and Bitrise support Once's headless OpenID Connect login. Connect the repository to your Tuist project as described in <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC authentication</.localized_link>. On GitHub Actions, grant identity-token permission:

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: jdx/mise-action@v2
      # Pin Once in your repository's mise.toml.
      - run: once auth login --provider tuist --no-browser
      - run: once build MyTarget
      - run: once test
```

Choose an OS with the toolchains your targets require. Replace `MyTarget` with your target, and pin Once through your existing tool-installation workflow. The resulting session is reused for cache access, reporting, and artifact publication during the job.

On other providers, set `TUIST_TOKEN` to an <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> authorized for the operations you need. Store it in the CI secret store, never in `once.toml` or the workflow source. No interactive login step is required when using that token.

For multi-worker suites, follow <.localized_link href="/guides/features/test-sharding/once">Once test sharding</.localized_link>. To publish applications, add an explicit <.localized_link href="/guides/features/previews/once">Once preview publication</.localized_link> step. Ordinary builds do not implicitly publish previews.

## Examples {#examples}

### GitHub Actions {#github-actions}

On [GitHub Actions](https://docs.github.com/en/actions) you can use <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC authentication</.localized_link> for secure, secretless authentication:

::: code-group
```yaml [OIDC (Mise)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist setup cache
```
```yaml [OIDC (Homebrew)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: brew install --formula tuist@x.y.z
      - run: tuist setup cache
```
```yaml [Account token (Mise)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist setup cache
```
```yaml [Account token (Homebrew)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: brew install --formula tuist@x.y.z
      - run: tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **OIDC setup**
>
> Before using OIDC authentication, you need to <.localized_link href="/guides/integrations/gitforge/github">connect your GitHub repository</.localized_link> to your Tuist project. The `permissions: id-token: write` is required for OIDC to work. From Tuist 4.218.0, the CLI exchanges the identity token on its first request, so the workflow needs no `tuist auth login` step; on earlier versions, run `tuist auth login` before other Tuist commands. Alternatively, you can use an <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> with the `TUIST_TOKEN` secret.


> [!TIP]
> We recommend using `mise use --pin` in your Tuist projects to pin the version of Tuist across environments. The command pins the version of Tuist in your `mise.toml` file.


### Xcode Cloud {#xcode-cloud}

In [Xcode Cloud](https://developer.apple.com/xcode-cloud/), which uses Xcode projects as the source of truth, you'll need to add a [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) script to install Tuist and run the commands you need, for example `tuist generate`:

::: code-group

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
export PATH="$HOME/.local/bin:$PATH"

mise install # Installs the version from mise.toml

# Runs the version of Tuist indicated in the mise.toml file
mise exec -- tuist install --path ../ # `--path` needed as this is run from within the `ci_scripts` directory
mise exec -- tuist generate -p ../ --no-open # `-p` needed as this is run from within the `ci_scripts` directory
```
```bash [Homebrew]
#!/bin/sh
brew install --formula tuist@x.y.z

tuist generate
```
<!-- -->
:::

> [!NOTE]
> **Authentication**
>
> Use an <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> by setting the `TUIST_TOKEN` environment variable in your Xcode Cloud workflow settings.


### CircleCI {#circleci}

On [CircleCI](https://circleci.com) you can use <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC authentication</.localized_link> for secure, secretless authentication:

::: code-group
```yaml [OIDC (Mise)]
version: 2.1
jobs:
  build:
    macos:
      xcode: "15.0.1"
    steps:
      - checkout
      - run:
          name: Install Mise
          command: |
            curl https://mise.jdx.dev/install.sh | sh
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> $BASH_ENV
      - run:
          name: Install Tuist
          command: mise install
      - run:
          name: Build
          command: mise exec -- tuist setup cache
```
```yaml [Account token (Mise)]
version: 2.1
jobs:
  build:
    macos:
      xcode: "15.0.1"
    environment:
      TUIST_TOKEN: $TUIST_TOKEN
    steps:
      - checkout
      - run:
          name: Install Mise
          command: |
            curl https://mise.jdx.dev/install.sh | sh
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> $BASH_ENV
      - run:
          name: Install Tuist
          command: mise install
      - run:
          name: Build
          command: mise exec -- tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **Authentication**
>
> Before using OIDC authentication, you need to <.localized_link href="/guides/integrations/gitforge/github">connect your GitHub repository</.localized_link> to your Tuist project. CircleCI OIDC tokens include your connected GitHub repository, which Tuist uses to authorize access to your projects. From Tuist 4.218.0, the CLI exchanges the identity token on its first request, so no `tuist auth login` step is needed; on earlier versions, run `mise exec -- tuist auth login` before other Tuist commands. Alternatively, you can use an <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> with the `TUIST_TOKEN` environment variable.


### Bitrise {#bitrise}

On [Bitrise](https://bitrise.io) you can use <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC authentication</.localized_link> for secure, secretless authentication:

::: code-group
```yaml [OIDC (Mise)]
workflows:
  build:
    steps:
      - git-clone@8: {}
      - script@1:
          title: Install Mise
          inputs:
            - content: |
                curl https://mise.jdx.dev/install.sh | sh
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
      - script@1:
          title: Install Tuist
          inputs:
            - content: mise install
      - get-identity-token@0:
          inputs:
          - audience: tuist
      - script@1:
          title: Build
          inputs:
            - content: mise exec -- tuist setup cache
```
```yaml [Account token (Mise)]
workflows:
  build:
    steps:
      - git-clone@8: {}
      - script@1:
          title: Install Mise
          inputs:
            - content: |
                curl https://mise.jdx.dev/install.sh | sh
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
      - script@1:
          title: Install Tuist
          inputs:
            - content: mise install
      - script@1:
          title: Build
          inputs:
            - content: mise exec -- tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **Authentication**
>
> Before using OIDC authentication, you need to <.localized_link href="/guides/integrations/gitforge/github">connect your GitHub repository</.localized_link> to your Tuist project. Bitrise OIDC tokens include your connected GitHub repository, which Tuist uses to authorize access to your projects. From Tuist 4.218.0, the CLI exchanges the identity token on its first request, so no `tuist auth login` step is needed; on earlier versions, run `mise exec -- tuist auth login` before other Tuist commands. Alternatively, you can use an <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> with the `TUIST_TOKEN` environment variable.


### Codemagic {#codemagic}

In [Codemagic](https://codemagic.io), you can add an additional step to your workflow to install Tuist:

::: code-group
```yaml [Mise]
workflows:
  build:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
      vars:
        TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
    scripts:
      - name: Install Mise
        script: |
          curl https://mise.jdx.dev/install.sh | sh
          mise install # Installs the version from mise.toml
      - name: Build
        script: mise exec -- tuist setup cache
```
```yaml [Homebrew]
workflows:
  build:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
      vars:
        TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
    scripts:
      - name: Install Tuist
        script: |
          brew install --formula tuist@x.y.z
      - name: Build
        script: tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **Authentication**
>
> Create an <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> and add it as a secret environment variable named `TUIST_TOKEN`.

### Appcircle {#appcircle}

In [Appcircle](https://appcircle.io), you can use the built-in [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) and [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) workflow steps, or add a **Custom Script** step after the **Git Clone** step to install Tuist yourself:

::: code-group
```bash [Mise]
cd $AC_REPOSITORY_DIR
curl https://mise.jdx.dev/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
mise install
mise exec -- tuist setup cache
```
```bash [Homebrew]
cd $AC_REPOSITORY_DIR
brew install --formula tuist@x.y.z
tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **Workflow steps**
>
> The Tuist Install step installs Tuist with Homebrew and runs `tuist generate`. Set the **Tuist Version** input to pin the version, then add a Tuist Commands step to run commands such as `tuist test` or `tuist build`.

> [!NOTE]
> **Authentication**
>
> Create an <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>, add it as a variable named `TUIST_TOKEN` to an [environment variable group](https://docs.appcircle.io/build/build-environment-variables), and select that group in your build configuration. Mark the variable as secret with the lock icon.

## Run report {#run-report}

When Tuist uploads a run, the dashboard URLs for it are printed to the logs. To get them without scraping the logs — for example to post the test report link to Slack when a job fails, or to feed a run into your own tooling — pass `--run-report-path` (or set `TUIST_RUN_REPORT_PATH`) to `tuist test`, `tuist xcodebuild test`, or `tuist xcodebuild build`. Tuist writes a JSON report to that path once the run has been uploaded:

```json
{
  "runId": "0193f8c1-...",
  "status": "success",
  "runURL": "https://tuist.dev/acme/app/runs/0193f8c1-...",
  "testRunURL": "https://tuist.dev/acme/app/tests/test-runs/...",
  "buildRunURL": "https://tuist.dev/acme/app/builds/build-runs/...",
  "testRuns": [
    {
      "scheme": "App",
      "succeeded": true,
      "totalTests": 42,
      "skippedTests": 0,
      "ranTests": 42,
      "failedTestNames": [],
      "ranTestModules": 3,
      "skippedTestModules": 5
    }
  ],
  "buildRuns": [
    { "scheme": "App", "succeeded": true, "durationInSeconds": 12.3 }
  ]
}
```

| Field | Type | Description |
| - | - | - |
| `runId` | string | The run's unique identifier. |
| `status` | string | `"success"` or `"failure"`. |
| `runURL` | string | The dashboard URL for the run. Always present. |
| `testRunURL` | string? | The dashboard URL for the test run, present when the command ran tests. |
| `buildRunURL` | string? | The dashboard URL for the build run, present when the command built. |
| `testRuns` | array | Per-scheme test results: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules`, and `skippedTestModules`. The test counts are test cases, and `skippedTests` counts the ones the result bundle reports as skipped. `skippedTestModules` counts the test modules <.localized_link href="/guides/features/selective-testing">selective testing</.localized_link> skipped, and is omitted when selective testing didn't apply or the run is a test shard. |
| `buildRuns` | array | Per-scheme build results: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL` and `buildRunURL` are independent: a command that both builds and tests writes both, which the logs can't do — they only print one URL per run.

> [!NOTE]
> **When the report is written**
>
> The report is written only for runs that are uploaded to the server, which requires authentication and happens automatically on CI. The path is cleared at the start of every run, so a run that produces no report leaves nothing behind rather than a stale one from a previous run.

On GitLab CI, a common use is to expose a URL to later jobs through a [`dotenv` report](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv):

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
