---
{
  "title": "지속적 통합(CI)",
  "titleTemplate": ":title · 자동화 · 가이드 · Tuist",
  "description": "CI 워크플로우에서 Tuist를 사용하는 방법을 알아보세요."
}
---
# 지속적 통합(CI) {#continuous-integration-ci}

[지속적 통합](https://en.wikipedia.org/wiki/Continuous_integration) 워크플로에서 Tuist 명령을 실행하려면 CI 환경에 Tuist를 설치해야 합니다. 

인증은 선택 사항이지만, <.localized_link href="/guides/features/cache">캐시</.localized_link>와 같은 서버 측 기능을 사용하려면 필수입니다. 

다음 섹션에서는 다양한 CI 플랫폼에서 이를 수행하는 방법을 예시로 제공합니다.

## 예시 {#examples}

### GitHub Actions {#github-actions}

[GitHub Actions](https://docs.github.com/en/actions)에서는 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 인증</.localized_link>을 사용하여 안전하고 비밀 키 없이 인증할 수 있습니다:

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
      - run: tuist auth login
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
      - run: tuist auth login
      - run: tuist setup cache
```
```yaml [Project token (Mise)]
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
```yaml [Project token (Homebrew)]
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
> **Oidc 설정**
>
> OIDC 인증을 사용하기 전에 <.localized_link href="/guides/integrations/gitforge/github">GitHub 리포지토리를 연결</.localized_link>하여 Tuist 프로젝트에 연동해야 합니다. OIDC가 작동하려면 `permissions: id-token: write`이 필요합니다. 대신 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>과 `TUIST_TOKEN` 시크릿을 사용할 수도 있습니다.


> [!TIP]
> Tuist 프로젝트에서 `mise use --pin`을 사용하여 환경 간 Tuist 버전을 고정하는 것을 권장합니다. 이 명령은 Tuist 버전이 포함된 `.tool-versions` 파일을 생성합니다.


### Xcode Cloud {#xcode-cloud}

Xcode 프로젝트를 신뢰 소스로 사용하는 [Xcode Cloud](https://developer.apple.com/xcode-cloud/)에서는 Tuist를 설치하고 필요한 명령(예: `tuist generate`)을 실행하기 위해 [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) 스크립트를 추가해야 합니다:

::: code-group

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
export PATH="$HOME/.local/bin:$PATH"

mise install # Installs the version from .mise.toml

# Runs the version of Tuist indicated in the .mise.toml file {#runs-the-version-of-tuist-indicated-in-the-misetoml-file}
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
> **인증**
>
> Xcode Cloud 워크플로 설정에서 `TUIST_TOKEN` 환경 변수를 설정하여 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>을 사용하세요.


### CircleCI {#circleci}

[CircleCI](https://circleci.com)에서는 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 인증</.localized_link>을 사용하여 안전하고 비밀 키 없이 인증할 수 있습니다:

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
          name: Authenticate
          command: mise exec -- tuist auth login
      - run:
          name: Build
          command: mise exec -- tuist setup cache
```
```yaml [Project token (Mise)]
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
> **인증**
>
> OIDC 인증을 사용하기 전에 <.localized_link href="/guides/integrations/gitforge/github">GitHub 리포지토리를 연결</.localized_link>하여 Tuist 프로젝트에 연동해야 합니다. CircleCI OIDC 토큰에는 연결된 GitHub 리포지토리 정보가 포함되어 있으며, Tuist는 이를 사용하여 프로젝트 접근을 승인합니다. 대신 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>과 `TUIST_TOKEN` 환경 변수를 사용할 수도 있습니다.


### Bitrise {#bitrise}

[Bitrise](https://bitrise.io)에서는 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 인증</.localized_link>을 사용하여 안전하고 비밀 키 없이 인증할 수 있습니다:

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
          title: Authenticate
          inputs:
            - content: mise exec -- tuist auth login
      - script@1:
          title: Build
          inputs:
            - content: mise exec -- tuist setup cache
```
```yaml [Project token (Mise)]
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
> **인증**
>
> OIDC 인증을 사용하기 전에 <.localized_link href="/guides/integrations/gitforge/github">GitHub 리포지토리를 연결</.localized_link>하여 Tuist 프로젝트에 연동해야 합니다. Bitrise OIDC 토큰에는 연결된 GitHub 리포지토리 정보가 포함되어 있으며, Tuist는 이를 사용하여 프로젝트 접근을 승인합니다. 대신 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>과 `TUIST_TOKEN` 환경 변수를 사용할 수도 있습니다.


### Codemagic {#codemagic}

[Codemagic](https://codemagic.io)에서는 워크플로에 단계를 추가하여 Tuist를 설치할 수 있습니다:

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
          mise install # Installs the version from .mise.toml
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
> **인증**
>
> <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>을 생성하고 `TUIST_TOKEN`이라는 이름의 시크릿 환경 변수로 추가하세요.

### Appcircle {#appcircle}

[Appcircle](https://appcircle.io)에서는 기본 제공되는 [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) 및 [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) 워크플로 단계를 사용하거나, **Git Clone** 단계 후에 **Custom Script** 단계를 추가하여 직접 Tuist를 설치할 수 있습니다:

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
> **워크플로 단계**
>
> Tuist Install 단계는 Homebrew로 Tuist를 설치하고 `tuist generate`을 실행합니다. 버전을 고정하려면 **Tuist Version** 입력을 설정한 후, Tuist Commands 단계를 추가하여 `tuist test` 또는 `tuist build`와 같은 명령을 실행하세요.

> [!NOTE]
> **인증**
>
> <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>을 생성하고 `TUIST_TOKEN`이라는 이름의 변수로 [환경 변수 그룹](https://docs.appcircle.io/build/build-environment-variables)에 추가한 후, 빌드 구성에서 해당 그룹을 선택하세요. 잠금 아이콘을 사용하여 변수를 시크릿으로 표시하세요.

## 실행 보고서 {#run-report}

Tuist가 실행을 업로드하면 대시보드 URL이 로그에 출력됩니다. 로그를 파싱하지 않고 이러한 URL을 얻으려면(예: 작업 실패 시 테스트 보고서 링크를 Slack에 게시하거나 자체 도구에 실행 데이터를 전달하기 위해) `--run-report-path`(또는 `TUIST_RUN_REPORT_PATH` 설정)을 `tuist test`, `tuist xcodebuild test`, 또는 `tuist xcodebuild build`에 전달하세요. Tuist는 실행이 업로드되면 해당 경로에 JSON 보고서를 작성합니다:

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

| 필드 | 유형 | 설명 |
| - | - | - |
| `runId` | 문자열 | 실행의 고유 식별자입니다. |
| `status` | 문자열 | `"success"` 또는 `"failure"`입니다. |
| `runURL` | 문자열 | 실행에 대한 대시보드 URL입니다. 항상 존재합니다. |
| `testRunURL` | 문자열? | 테스트 실행에 대한 대시보드 URL로, 명령이 테스트를 실행할 때 나타납니다. |
| `buildRunURL` | 문자열? | 빌드 실행에 대한 대시보드 URL로, 명령이 빌드를 수행할 때 나타납니다. |
| `testRuns` | 배열 | 스키마별 테스트 결과: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules`, 그리고 `skippedTestModules`. 테스트 카운트는 테스트 케이스 수이며, `skippedTests`는 결과 번들에서 건너뛴 것으로 보고된 항목의 수를 나타냅니다. `skippedTestModules`는 <.localized_link href="/guides/features/selective-testing">선택적 테스팅</.localized_link>이 건너뛴 테스트 모듈 수를 나타내며, 선택적 테스팅이 적용되지 않았거나 실행이 테스트 샤드인 경우 생략됩니다. |
| `buildRuns` | 배열 | 스키마별 빌드 결과: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL`와 `buildRunURL`는 독립적입니다: 빌드와 테스트를 모두 수행하는 명령은 둘 다 기록하지만, 로그는 실행당 하나의 URL만 출력하므로 이를 수행할 수 없습니다.

> [!NOTE]
> **보고서 작성 시점**
>
> 보고서는 서버에 업로드된 실행에만 작성되며, 이는 인증이 필요하고 CI에서 자동으로 발생합니다. 경로는 모든 실행 시작 시 지워지므로, 보고서가 생성되지 않은 실행은 이전 실행의 오래된 데이터를 남기지 않고 아무것도 남기지 않습니다.

GitLab CI에서는 [`dotenv` 보고서](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv)를 통해 이후 작업에 URL을 노출하는 것이 일반적인 사용 사례입니다:

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
