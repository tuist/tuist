---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "CI 워크플로우에서 Tuist를 사용하는 방법에 대해 알아보세요."
}
---
# Continuous Integration (CI) {#continuous-integration-ci}

Tuist를 [CI(Continuous Integration)](https://en.wikipedia.org/wiki/Continuous_integration) 환경에서 사용할 수 있습니다. 다음 섹션에서는 다양한 CI 플랫폼에서 이를 수행하는 방법에 대한 예시를 제공합니다.

## Examples {#examples}

CI 워크플로우에서 Tuist 명령어를 실행하려면, CI 환경에 Tuist를 설치해야 합니다.

### Xcode Cloud {#xcode-cloud}

[Xcode Cloud](https://developer.apple.com/xcode-cloud/)에서는 Xcode 프로젝트를 진실 공급원(source of truth)으로 사용하기 때문에, [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) 스크립트를 추가하여 Tuist를 설치하고 필요한 명령어를 실행해야 합니다. 예를 들어 `tuist generate` 명령어를 실행합니다:

:::code-group

```bash [Mise]
#!/bin/sh
curl https://mise.jdx.dev/install.sh | sh
mise install # Installs the version from .mise.toml

# Runs the version of Tuist indicated in the .mise.toml file {#runs-the-version-of-tuist-indicated-in-the-misetoml-file}
mise exec -- tuist generate
```

```bash [Homebrew]
#!/bin/sh
brew install --formula tuist@x.y.z

tuist generate
```

:::

### Codemagic {#codemagic}

[Codemagic](https://codemagic.io)에서 워크플로우에 Tuist를 설치하는 추가 단계를 다음과 같이 추가할 수 있습니다:

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

### GitHub Actions {#github-actions}

On [GitHub Actions](https://docs.github.com/en/actions) you can add an additional step to install Tuist, and in the case of managing the installation of Mise, you can use the [mise-action](https://github.com/jdx/mise-action), which abstracts the installation of Mise and Tuist:

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

:::tip
Tuist 프로젝트에서 환경 간 Tuist 버전을 고정하려면 `mise use -pin` 명령어를 사용하는 것을 권장합니다. 이 명령어는 Tuist의 버전을 포함하는 `.tool-version` 파일을 생성합니다.
:::

## 인증 {#authentication}

<LocalizedLink href="/guides/features/build/cache">cache</LocalizedLink>와 같은 server-side 기능을 사용할 때, CI 워크플로우에서 서버로 가는 요청을 인증할 방법이 필요합니다. 이를 위해, 다음 명령어를 실행하여 프로젝트 범위의 토큰을 생성할 수 있습니다.

```bash
tuist project tokens create my-handle/MyApp
```

이 명령어는 `my-account/my-project`라는 전체 핸들을 가진 프로젝트에 대한 토큰을 생성합니다. 해당 값을 CI 환경의 `TUIST_CONFIG_TOKEN` 환경 변수로 설정하고, secret으로 설정하여 노출되지 않도록 합니다.

> [!IMPORTANT] CI 환경 감지
> Tuist는 CI 환경에서 실행 중임을 감지할 때만 토큰을 사용합니다. CI 환경이 감지되지 않는 경우, 환경 변수 `CI`를 `1`로 설정하여 토큰 사용을 강제할 수 있습니다.
