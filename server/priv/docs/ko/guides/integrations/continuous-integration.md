---
{
  "title": "지속적 통합(CI)",
  "titleTemplate": ":title · 자동화 · 가이드 · Tuist",
  "description": "CI 워크플로에서 Tuist를 사용하는 방법을 알아보세요."
}
---
# 지속적 통합(CI) {#continuous-integration-ci}

[지속적 통합](https://en.wikipedia.org/wiki/Continuous_integration) 워크플로에서 Tuist 명령어를 실행하려면 CI 환경에 Tuist를 설치해야 합니다. 

인증은 선택 사항이지만, <.localized_link href="/guides/features/cache">캐시</.localized_link>와 같은 서버 측 기능을 사용하려면 필수입니다. 

다음 섹션에서는 다양한 CI 플랫폼에서 이를 수행하는 방법을 예시로 보여줍니다. Once는 자체 네이티브 Tuist 프로바이더를 통해 연결되므로 Tuist CLI가 필요하지 않습니다. 해당 워크플로는 [Once](#once)를 참조하세요.

## Once {#once}

<.localized_link href="/guides/get-started/once-project">Once 시작하기</.localized_link>에서 프로바이더 및 캐시 바인딩을 커밋하세요. [Once 설치 안내](https://buildonce.dev/docs/guide/getting-started)에 따라 작업에서 Once를 설치한 후, 캐시 가능한 작업을 실행하기 전에 인증하세요.

GitHub Actions, CircleCI, Bitrise는 Once의 헤드리스 OpenID Connect 로그인을 지원합니다. <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 인증</.localized_link>에 설명된 대로 리포지토리를 Tuist 프로젝트에 연결하세요. GitHub Actions에서는 identity-token 권한을 부여합니다:

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

타겟이 요구하는 툴체인을 갖춘 OS를 선택하세요. `MyTarget`을 타겟으로 교체하고, 기존 툴 설치 워크플로를 통해 Once 버전을 고정하세요. resulting 세션은 작업 중 캐시 접근, 보고 및 아티팩트 게시에 재사용됩니다.

다른 프로바이더에서는 필요한 작업에 대해 승인된 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>으로 `TUIST_TOKEN`을 설정하세요. CI 비밀 저장소에 보관하고, `once.toml`이나 워크플로 소스에는 절대 포함하지 마세요. 해당 토큰을 사용할 때는 상호작용형 로그인 단계가 필요하지 않습니다.

다중 워커 스위트의 경우 <.localized_link href="/guides/features/test-sharding/once">Once 테스트 샤딩</.localized_link>을 따르세요. 애플리케이션을 게시하려면 명시적인 <.localized_link href="/guides/features/previews/once">Once 미리보기 게시</.localized_link> 단계를 추가하세요. 일반 빌드는 미리보기를 암시적으로 게시하지 않습니다.

## 예시 {#examples}

### GitHub Actions {#github-actions}

[GitHub Actions](https://docs.github.com/en/actions)에서는 안전하고 비밀 정보 없이 인증할 수 있도록 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 인증</.localized_link>을 사용할 수 있습니다:

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
> **OIDC 설정**
>
> OIDC 인증을 사용하기 전에 <.localized_link href="/guides/integrations/gitforge/github">GitHub 리포지토리 연결</.localized_link>을 통해 Tuist 프로젝트에 연결해야 합니다. OIDC가 작동하려면 `permissions: id-token: write`이 필요합니다. Tuist 4.218.0부터 CLI는 첫 요청 시 ID 토큰을 교환하므로 워크플로에 `tuist auth login` 단계가 필요하지 않습니다. 이전 버전에서는 다른 Tuist 명령어 전에 `tuist auth login`를 실행하세요. 또는 `TUIST_TOKEN` 비밀과 함께 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>을 사용할 수 있습니다.


> [!TIP]
> 환경 간 Tuist 버전을 고정하기 위해 Tuist 프로젝트에서 `mise use --pin` 사용을 권장합니다. 이 명령어는 `mise.toml` 파일에 Tuist 버전을 고정합니다.


### Xcode Cloud {#xcode-cloud}

Xcode 프로젝트를 신뢰 소스로 사용하는 [Xcode Cloud](https://developer.apple.com/xcode-cloud/)에서는 Tuist를 설치하고 필요한 명령어(예: `tuist generate`)를 실행하기 위해 [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) 스크립트를 추가해야 합니다:

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
> **인증**
>
> Xcode Cloud 워크플로 설정에서 `TUIST_TOKEN` 환경 변수를 설정하여 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>을 사용하세요.


### CircleCI {#circleci}

[CircleCI](https://circleci.com)에서는 안전하고 비밀 정보 없이 인증할 수 있도록 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 인증</.localized_link>을 사용할 수 있습니다:

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
> **인증**
>
> OIDC 인증을 사용하기 전에 <.localized_link href="/guides/integrations/gitforge/github">GitHub 리포지토리 연결</.localized_link>을 통해 Tuist 프로젝트에 연결해야 합니다. CircleCI OIDC 토큰에는 연결된 GitHub 리포지토리가 포함되며, Tuist는 이를 사용하여 프로젝트에 대한 접근을 승인합니다. Tuist 4.218.0부터 CLI는 첫 요청 시 ID 토큰을 교환하므로 `tuist auth login` 단계가 필요하지 않습니다. 이전 버전에서는 다른 Tuist 명령어 전에 `mise exec -- tuist auth login`를 실행하세요. 또는 `TUIST_TOKEN` 환경 변수와 함께 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>을 사용할 수 있습니다.


### Bitrise {#bitrise}

[Bitrise](https://bitrise.io)에서는 안전하고 비밀 정보 없이 인증할 수 있도록 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 인증</.localized_link>을 사용할 수 있습니다:

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
> **인증**
>
> OIDC 인증을 사용하기 전에 <.localized_link href="/guides/integrations/gitforge/github">GitHub 리포지토리 연결</.localized_link>을 통해 Tuist 프로젝트에 연결해야 합니다. Bitrise OIDC 토큰에는 연결된 GitHub 리포지토리가 포함되며, Tuist는 이를 사용하여 프로젝트에 대한 접근을 승인합니다. Tuist 4.218.0부터 CLI는 첫 요청 시 ID 토큰을 교환하므로 `tuist auth login` 단계가 필요하지 않습니다. 이전 버전에서는 다른 Tuist 명령어 전에 `mise exec -- tuist auth login`를 실행하세요. 또는 `TUIST_TOKEN` 환경 변수와 함께 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>을 사용할 수 있습니다.


### Codemagic {#codemagic}

[Codemagic](https://codemagic.io)에서는 Tuist를 설치하기 위해 워크플로에 추가 단계를 포함할 수 있습니다:

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
> **인증**
>
> <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>을 생성하고 `TUIST_TOKEN`이라는 이름의 비밀 환경 변수로 추가하세요.

### Appcircle {#appcircle}

[Appcircle](https://appcircle.io)에서는 내장된 [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) 및 [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) 워크플로 단계를 사용하거나, **Git Clone** 단계 후에 **Custom Script** 단계를 추가하여 직접 Tuist를 설치할 수 있습니다:

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
> Tuist Install 단계는 Homebrew로 Tuist를 설치하고 `tuist generate`를 실행합니다. 버전을 고정하려면 **Tuist Version** 입력 값을 설정한 후, `tuist test` 또는 `tuist build`와 같은 명령어를 실행하기 위해 Tuist Commands 단계를 추가하세요.

> [!NOTE]
> **인증**
>
> <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>을 생성하고, 이를 [환경 변수 그룹](https://docs.appcircle.io/build/build-environment-variables)에 `TUIST_TOKEN`라는 이름의 변수로 추가한 후, 빌드 구성에서 해당 그룹을 선택하세요. 잠금 아이콘을 사용하여 변수를 비밀로 표시하세요.

## xcodebuild 출력 형식 지정 {#xcodebuild-output-formatting}

`tuist build`, `tuist test`, `tuist xcodebuild build`, 그리고 `tuist xcodebuild test`는 [xcbeautify](https://github.com/cpisciotta/xcbeautify)의 포맷터를 사용하여 `xcodebuild`의 출력을 형식화하므로, 이러한 명령어를 직접 xcbeautify로 파이프할 필요가 없습니다. GitHub Actions에서는 `GITHUB_ACTIONS` 환경 변수를 통해 감지되며, Tuist는 xcbeautify의 GitHub Actions 렌더러를 사용하여 컴파일러 경고, 오류 및 테스트 실패를 실행 요약 및 풀 리퀘스트의 주석으로 표시합니다. 다른 모든 곳에서는 터미널 렌더러를 사용하며, 출력이 파이프되거나 `NO_COLOR`가 설정되지 않은 경우 색상이 적용됩니다.

명확한 오류 없이 빌드가 실패하는 경우와 같이 `xcodebuild`의 형식화되지 않은 출력을 확인하려면 `--verbose`를 전달하세요.

작업이 Tuist를 거치지 않고 직접 `xcodebuild`를 호출하는 경우, 직접 xcbeautify로 파이프하고 `pipefail`를 설정하여 빌드가 실패해도 단계가 실패하도록 하세요:

```bash
set -o pipefail
xcodebuild test -scheme App | xcbeautify --renderer github-actions
```

## 실행 보고서 {#run-report}

Tuist가 실행을 업로드하면 대시보드 URL이 로그에 출력됩니다. 로그를 스크래핑하지 않고 이 URL을 얻으려면(예: 작업 실패 시 테스트 보고서 링크를 Slack에 게시하거나 자체 도구에 실행 데이터를 제공하기 위해) `tuist test`, `tuist xcodebuild test` 또는 `tuist xcodebuild build`에 `--run-report-path`를 전달하거나(또는 `TUIST_RUN_REPORT_PATH`를 설정하세요). Tuist는 실행이 업로드되면 해당 경로에 JSON 보고서를 작성합니다:

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
| `status` | 문자열 | `"success"` 또는 `"failure"`. |
| `runURL` | 문자열 | 실행에 대한 대시보드 URL입니다. 항상 존재합니다. |
| `testRunURL` | 문자열? | 명령어가 테스트를 실행했을 때 존재하는 테스트 실행에 대한 대시보드 URL입니다. |
| `buildRunURL` | 문자열? | 명령어가 빌드를 수행했을 때 존재하는 빌드 실행에 대한 대시보드 URL입니다. |
| `testRuns` | 배열 | 스킴별 테스트 결과: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules`, 그리고 `skippedTestModules`. 테스트 카운트는 테스트 케이스 수이며, `skippedTests`는 결과 번들에서 건너뜀(skipped)으로 보고된 항목의 수를 나타냅니다. `skippedTestModules`는 <.localized_link href="/guides/features/selective-testing">선택적 테스팅</.localized_link>이 건너뛴 테스트 모듈의 수를 나타내며, 선택적 테스팅이 적용되지 않았거나 실행이 테스트 샤드인 경우 생략됩니다. |
| `buildRuns` | 배열 | 스킴별 빌드 결과: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL`와 `buildRunURL`는 독립적입니다: 빌드와 테스트를 모두 수행하는 명령어는 둘 다 기록하지만, 로그는 실행당 하나의 URL만 출력할 수 있습니다.

> [!NOTE]
> **보고서 작성 시기**
>
> 보고서는 서버에 업로드된 실행에 대해서만 작성되며, 이는 인증이 필요하고 CI에서 자동으로 발생합니다. 경로는 모든 실행 시작 시 지워지므로, 보고서를 생성하지 않는 실행은 이전 실행의 오래된 보고서 대신 아무것도 남기지 않습니다.

GitLab CI에서는 [`dotenv` 보고서](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv)를 통해 이후 작업에 URL을 노출하는 것이 일반적인 용도입니다:

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
