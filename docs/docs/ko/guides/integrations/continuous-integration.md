---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# 지속적 통합(CI) {#continuous-integration-ci}

지속적 통합](https://en.wikipedia.org/wiki/Continuous_integration) 환경에서 Tuist를 사용할 수
있습니다. 다음 섹션에서는 다양한 CI 플랫폼에서 이 작업을 수행하는 방법에 대한 예를 제공합니다.

## 예제 {#예제}

CI 워크플로에서 튜이스트 명령을 실행하려면 CI 환경에 튜이스트를 설치해야 합니다.

### Xcode 클라우드 {#xcode-cloud}

Xcode 프로젝트를 소스로 사용하는 [Xcode Cloud](https://developer.apple.com/xcode-cloud/)에서
[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)
스크립트를 추가하여 Tuist를 설치하고 필요한 명령(예: `tuist generate`)을 실행해야 합니다:

:::코드 그룹

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
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
:::
### 코드매직 {#코드매직}

코드매직](https://codemagic.io)에서 워크플로에 추가 단계를 추가하여 Tuist를 설치할 수 있습니다:

::: 코드 그룹
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
        script: mise exec -- tuist build
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

### GitHub 액션 {#github-actions}

깃허브 액션](https://docs.github.com/en/actions)에서 Tuist를 설치하는 단계를 추가할 수 있으며, Mise
설치를 관리하는 경우에는 Mise와 Tuist의 설치를 추상화한
[mise-action](https://github.com/jdx/mise-action)을 사용할 수 있습니다:

::: 코드 그룹
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

::: 팁 Tuist 프로젝트에서 `mise use --pin` 을 사용하여 여러 환경에 걸쳐 Tuist 버전을 고정하는 것이 좋습니다. 이
명령은 Tuist의 버전이 포함된 `.tool-versions` 파일을 생성합니다:

## 인증 {#인증}

1}cache</LocalizedLink>와 같은 서버 측 기능을 사용하는 경우 CI 워크플로에서 서버로 가는 요청을 인증할 방법이 필요합니다.
이를 위해 다음 명령을 실행하여 프로젝트 범위 토큰을 생성할 수 있습니다:

```bash
tuist project tokens create my-handle/MyApp
```

이 명령은 전체 핸들 `my-account/my-project` 로 프로젝트에 대한 토큰을 생성합니다. 이 값을 CI 환경의 환경 변수
`TUIST_CONFIG_TOKEN` 에 설정하여 노출되지 않도록 비밀로 구성합니다.

> [중요] CI 환경 감지 Tuist는 CI 환경에서 실행 중임을 감지한 경우에만 토큰을 사용합니다. CI 환경이 감지되지 않는 경우 환경
> 변수 `CI` 을 `1` 으로 설정하여 토큰 사용을 강제할 수 있습니다.
