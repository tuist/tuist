---
title: Install Tuist
titleTemplate: :title · Quick-start · Guides · Tuist
description: Tuist를 설치하는 방법을 알아보세요.
---

# Install Tuist {#install-tuist}

Tuist CLI는 실행 가능한 동적 프레임워크와 일련의 리소스(예: 템플릿)로 구성되어 있습니다. [소스에서](https://github.com/tuist/tuist) 수동으로 Tuist를 빌드할 수도 있지만, **올바른 설치를 위해 다음 설치 방법 중 하나를 사용하는 것이 좋습니다.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

:::info
Mise는 여러 환경에서 툴의 버전을 일관되게 유지가 필요한 팀이나 조직에 추천되는 [Homebrew](https://brew.sh)의 대안입니다.
:::

다음의 명령어를 통해 Tuist를 설치할 수 있습니다:

```bash
mise install tuist # .tool-versions/.mise.toml에 지정된 현재 버전을 설치합니다.
mise install tuist@x.y.z # 특정 버전 설치
mise install tuist@3 # 주요 버전 설치
```

단일 버전의 도구를 시스템 전반에 걸쳐 설치 및 활성화하는 Homebrew와 같은 도구와 달리 **Mise는 버전을 시스템 전체에 또는 프로젝트별로 활성화해야 한다는 점**에 유의하세요. 이 작업은 `mise use`를 실행하여 수행합니다.

```bash
mise use tuist@x.y.z # 현재 프로젝트에서 tuist-x.y.z 사용
mise use tuist@latest # 현재 디렉터리에서 최신 tuist를 사용합니다.
mise use -g tuist@x.y.z # 시스템의 기본값으로 tuist-x.y.z 사용
mise use -g tuist@system # 시스템의 tuist를 전역 기본값으로 사용합니다.
```

### <0>Homebrew</0> {#recommended-homebrew}

Tuist는 [Homebrew](https://brew.sh) 및 [우리의 포뮬러](https://github.com/tuist/homebrew-tuist)를 사용하여 설치할 수 있습니다:

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

:::tip VERIFYING THE AUTHENTICITY OF THE BINARIES

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```

:::
