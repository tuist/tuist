---
{
  "title": "캐시 볼륨",
  "titleTemplate": ":title · 러너 · 기능 · 가이드 · Tuist",
  "description": "GitHub Actions, Buildkite 및 GitLab CI를 사용하는 Tuist Linux 또는 macOS 러너 작업 간에 Xcode, 모듈 및 Gradle 캐시와 기타 디렉터리를 유지하세요."
}
---
# 캐시 볼륨 {#cache-volumes}

Tuist 러너는 작업 간에 캐시를 유지하므로 새 러너가 워밍업된 상태로 시작합니다. 각 작업은 최신 저장된 콘텐츠의 개인용 쓰기 가능 복사본을 받습니다.

- **관리형 캐시**는 Xcode 컴파일레이션 캐시, Tuist 모듈 캐시 및 Gradle 캐시를 각각 한 단계로 유지합니다. Tuist는 각 캐시의 위치를 알고 있으며 자체 스토리지 내에 보관합니다.
- **사용자 지정 볼륨**은 패키지 관리자의 다운로드 캐시 등 선택한 키 아래의 다른 디렉터리를 모두 유지합니다.

체크아웃 후와 캐시를 사용하는 명령어 전에 단계를 추가하세요. Tuist 러너가 아닌 러너에서는 아무 작업도 수행하지 않으며, 캐시 문제로 인해 작업이 실패하지 않습니다. 단계에서 경고를 로그로 남기고 작업은 빈 캐시로 계속됩니다.

> [!NOTE]
> macOS 27의 러너는 아직 캐시 볼륨이나 캐시된 체크아웃을 연결하지 않습니다. 해당 캐시 단계는 경고를 로그로 남기고 작업은 빈 캐시로 계속되며, `actions/checkout`는 평소대로 리포지토리를 클론합니다.

## 관리형 캐시 {#managed-caches}

단계는 캐시가 저장되는 위치만 결정합니다. 기존 캐시 설정을 유지하세요: `tuist setup cache` 또는 컴파일레이션 캐싱을 켜는 빌드 설정(<.localized_link href="/guides/features/cache/xcode-cache">Xcode 캐시 가이드</.localized_link> 참조), 모듈 캐시에 대한 인증, 그리고 Gradle의 원격 빌드 캐시를 위한 <.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle 플러그인</.localized_link>. GitLab CI에서는 `extends`가 `before_script`를 대체하므로 스니펫을 `!reference`와 결합하세요.

### Xcode 캐시 {#xcode-cache}

macOS 러너에서 Xcode 컴파일레이션 캐시 스토어를 유지합니다.

::: code-group

```yaml [GitHub Actions]
jobs:
  build:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/xcode-cache@v1
      - run: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [Buildkite]
steps:
  - label: Build
    agents:
      queue: tuist-macos
    plugins:
      - tuist/xcode-cache#v1: ~
    command: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/xcode-cache-gitlab/v1/xcode-cache.yml

build:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-xcode-cache, before_script]
  script:
    - xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```
<!-- -->
:::

### 모듈 캐시 {#module-cache}

macOS 러너에서 Tuist의 로컬 캐시를 유지합니다: <.localized_link href="/guides/features/cache/module-cache">모듈 캐시</.localized_link> 바이너리, 컴파일된 매니페스트, 플러그인 및 선택적 테스팅 결과.

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-macos
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/module-cache@v1
      - uses: jdx/mise-action@v4
      - run: tuist auth login
      - run: tuist install
      - run: tuist generate --no-open
      - run: tuist test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-macos
    plugins:
      - tuist/module-cache#v1: ~
    command: |
      mise install
      tuist auth login
      tuist install
      tuist generate --no-open
      tuist test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/module-cache-gitlab/v1/module-cache.yml

test:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-module-cache, before_script]
  script:
    - mise install
    - tuist auth login
    - tuist install
    - tuist generate --no-open
    - tuist test
```
<!-- -->
:::

### Gradle 캐시 {#gradle-cache}

Linux 및 macOS 러너에서 Gradle 사용자 홈의 `caches` 및 `wrapper` 디렉터리를 유지합니다: 의존성, 변환된 jar 파일, 컴파일된 빌드 스크립트 및 Gradle 배포판. 사용하는 경우 단계 전에 `GRADLE_USER_HOME`를 설정하고, `actions/setup-java`의 `cache: gradle`와 같이 해당 디렉터리의 다른 캐싱을 비활성화하세요.

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
      - uses: tuist/gradle-cache@v1
      - run: ./gradlew test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/gradle-cache#v1: ~
    command: ./gradlew test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/gradle-cache-gitlab/v1/gradle-cache.yml

test:
  tags: [tuist-linux]
  before_script:
    - !reference [.tuist-gradle-cache, before_script]
  script:
    - ./gradlew test
```
<!-- -->
:::

## 사용자 지정 볼륨 {#custom-volumes}

안정적인 `key`와 `path`를 선택한 후, 의존성을 설치하기 전에 볼륨을 연결하세요. 경로는 비어 있거나 존재하지 않아야 합니다. 동일한 디렉터리에 기록하는 아카이브 캐시나 아티팩트 복원을 제거하세요. 하나의 볼륨에 여러 디렉터리를 유지하려면 [하나의 볼륨에 여러 디렉터리](#several-directories-in-one-volume)를 참조하세요.

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: npm
          path: ~/.npm
      - run: npm ci
      - run: npm test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: npm
              path: ~/.npm
    command: |
      npm ci
      npm test
```

```yaml [GitLab CI]
test:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key npm --path ~/.npm
  script:
    - npm ci
    - npm test
```
<!-- -->
:::

### 하나의 볼륨에 여러 디렉터리 {#several-directories-in-one-volume}

볼륨은 여러 디렉터리를 포함할 수 있습니다. GitHub Actions에서는 줄마다 하나의 경로를 나열하세요. Buildkite에서는 `path`를 목록으로 설정하세요. GitLab CI에서는 디렉터리마다 `--path`를 한 번씩 전달하세요. 빈 줄과 주변 공백은 무시됩니다.

::: code-group

```yaml [GitHub Actions]
jobs:
  lint:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: python-tools
          path: |
            ~/.cache/pip
            ~/.cache/pre-commit
      - run: pip install pre-commit
      - run: pre-commit run --all-files
```

```yaml [Buildkite]
steps:
  - label: Lint
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: python-tools
              path:
                - ~/.cache/pip
                - ~/.cache/pre-commit
    command: |
      pip install pre-commit
      pre-commit run --all-files
```

```yaml [GitLab CI]
lint:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key python-tools --path ~/.cache/pip --path ~/.cache/pre-commit
  script:
    - pip install pre-commit
    - pre-commit run --all-files
```
<!-- -->
:::

- **공유 용량.** 모든 경로는 볼륨의 용량을 공유하며 함께 복원되고 저장됩니다.
- **작고 관련된 디렉터리를 그룹화하세요.** 크거나 자주 변경되는 디렉터리는 자체 볼륨을 사용하세요.
- **중첩 금지.** 하나의 볼륨 내 경로들은 서로 포함해서는 안 됩니다.
- **목록 변경 시 콜드 스타트.** 각 경로는 볼륨 내부의 고유 디렉터리에 저장되며, 경로 작성 방식으로 식별됩니다. 단일 경로와 여러 경로 간 전환, 또는 경로 추가, 제거, 재작성은 해당 레이아웃을 변경합니다. 변경 후 첫 번째 작업은 영향을 받은 경로에 대해 콜드 스타트로 시작됩니다. 더 이상 목록에 없는 경로의 콘텐츠는 삭제할 때까지 볼륨에 남아 있습니다.

### 키 작동 방식 {#how-keys-work}

키는 시간이 지남에 따라 변경되는 볼륨의 이름이며, `actions/cache` 키와 같은 고정 스냅샷의 이름이 아닙니다.

- **키당 하나의 볼륨.** 각 키는 리포지토리(Buildkite에서는 파이프라인, GitLab CI에서는 프로젝트), 플랫폼, CPU 아키텍처 및 사용자를 범위로 합니다. 이를 연결하는 모든 작업은 최신 저장된 콘텐츠에서 시작하며, 자격 있는 작업은 변경 사항을 동일한 볼륨에 다시 저장합니다.
- **키를 안정적으로 유지하세요.** 버전이나 락파일 해시를 키에 넣지 마세요. `actions/cache`를 사용하면 `deps-${{ hashFiles('Package.resolved') }}`와 같은 키가 변경될 때마다 새 항목을 생성하고 `restore-keys`는 이전 항목으로 대체됩니다. 여기서는 새 키가 새롭고 빈 볼륨을 의미합니다. 모든 변경 후 첫 번째 작업은 콜드 스타트로 시작하며, 이전 볼륨은 만료될 때까지 유지됩니다. 키를 유지하고 도구가 콘텐츠를 업데이트하도록 하세요. 패키지 관리자는 여전히 유효한 항목을 재사용합니다.
- **부분 일치 없음.** 복원 키가 없습니다. 아직 저장되지 않은 키는 빈 상태로 시작합니다.
- **`tuist-`로 시작하는 키는** Tuist 자체 캐시를 위해 예약되어 있으며 볼륨이 연결되기 전에 거부됩니다.
- **의도적으로 초기화.** 작업을 빈 상태로 시작하려면 키를 변경하거나 볼륨을 삭제하세요.
- **`tuist-` 키는 Tuist에 맡기세요.** 관리형 캐시는 `tuist-`로 시작하는 키를 사용하므로 사용자 지정 볼륨에는 다른 이름을 선택하세요.

Linux에서는 경로가 일반 디렉터리로 마운트되므로 도구는 `deps`, `_build`, `node_modules`와 같은 일반적인 위치를 사용할 수 있습니다. 일반적인 `.gitignore` 규칙을 유지하세요. macOS에서는 경로가 심볼릭 링크입니다. `~/.npm`와 같은 다운로드 캐시를 사용하세요. `node_modules` 및 캐시 디렉터리를 교체하는 도구는 지원되지 않습니다. `.gitignore`에서 후행 슬래시가 없는 워크스페이스 링크를 무시하세요.

## 변경 사항 저장 {#saving-changes}

관리형 캐시와 사용자 지정 볼륨은 모든 브랜치에서 자체 리포지토리의 성공한 작업 변경 사항을 저장합니다.

| 제공자 | 변경 사항을 저장하는 작업 |
| --- | --- |
| GitHub Actions | 리포지토리 자체의 푸시, 스케줄, 수동 실행 및 풀 리퀘스트 작업 |
| Buildkite | 파이프라인 리포지토리의 웹훅 및 스케줄 빌드(풀 리퀘스트 포함) |
| GitLab CI | 프로젝트의 푸시, 스케줄 및 웹 파이프라인, 그리고 연결에 <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API 액세스 토큰</.localized_link>이 있을 경우 자체 머지 리퀘스트의 파이프라인 |

다른 작업도 캐시를 사용할 수 있지만 변경 사항은 삭제됩니다. 여기에는 포크 풀 리퀘스트, `pull_request_target` 작업, API 또는 대시보드에서 시작된 Buildkite 빌드, 포크에서 발생하거나 API 액세스 토큰이 없는 GitLab 머지 리퀘스트, 태그가 포함됩니다. 볼륨을 변경하지 않는 작업은 저장된 버전을 그대로 유지합니다. 러너 프로필에서 저장할 브랜치를 제한할 수 있습니다. 자세한 내용은 [저장할 브랜치 선택](#choose-which-branches-save)을 참조하세요.

동시 실행 작업은 독립적으로 작동하며 서로 다른 작업의 변경 사항은 병합되지 않습니다. 자격 증명이나 대체 불가능한 데이터는 절대 캐시하지 마세요.

### 저장할 브랜치 선택 {#choose-which-branches-save}

관리형 캐시와 사용자 지정 볼륨을 저장할 브랜치를 변경할 수 있습니다. **러너 → 프로필**을 열고 작업이 사용하는 프로필을 편집한 후 **캐시 저장 출처**를 확장하세요. 작업은 요청한 프로필을 사용합니다: GitHub Actions에서는 `runs-on:`, Buildkite에서는 큐, GitLab CI에서는 `tags:`입니다. 이 설정은 해당 프로필을 사용하는 작업의 모든 볼륨(나중에 생성된 볼륨 포함)에 적용됩니다.

![기본 브랜치가 활성화되고 develop과 release/*가 추가 브랜치로 추가된 상태에서 '캐시 저장 출처' 섹션이 확장된 러너 프로필 양식](/images/guides/features/runners/save-cache-from.png)

기본적으로 리포지토리의 모든 성공한 작업은 변경 사항을 저장합니다. 특정 브랜치에서만 저장하려면 **특정 브랜치로 제한**을 켜세요:

- **기본 브랜치**를 사용하면 각 리포지토리의 기본 브랜치에서 실행되는 작업이 저장할 수 있습니다. 추가 브랜치에서만 저장하려면 이 옵션을 끄세요.
- **추가 브랜치** 아래에 저장할 브랜치 이름을 최대 20개까지 추가하세요. `*`를 와일드카드로 사용하세요: `release/*`는 `release/1.0`와 일치합니다.

[변경 사항 저장](#saving-changes)에 나열된 작업은 브랜치가 일치할 때 변경 사항을 저장합니다. GitHub Actions 푸시 및 수동 실행에서는 이름이 일치하는 태그도 일치합니다.

다른 브랜치의 작업도 캐시를 사용할 수 있지만 변경 사항은 삭제됩니다. 포크 풀 리퀘스트처럼 저장하지 않는 작업은 일치하는 브랜치에서도 저장하지 않습니다. 이러한 설정을 제한하거나 프로필을 삭제하면 더 이상 허용되지 않는 대기 중인 변경 사항이 삭제되며, 삭제된 프로필은 모든 브랜치에서 저장하는 상태로 되돌아갑니다.

## 용량 및 보존 기간 {#capacity-and-retention}

Xcode 캐시는 **30GB**로 시작합니다. 모듈 캐시, Gradle 캐시 및 각 사용자 지정 볼륨은 **20GB**로 시작합니다. 캐시 또는 볼륨에 다른 용량을 부여하려면 `1gb`부터 `100gb`까지의 정수 GB 크기를 설정하세요:

::: code-group

```yaml [GitHub Actions]
- uses: tuist/xcode-cache@v1
  with:
    size: 50gb
- uses: tuist/module-cache@v1
  with:
    size: 40gb
```

```yaml [Buildkite]
plugins:
  - tuist/xcode-cache#v1:
      size: 50gb
  - tuist/module-cache#v1:
      size: 40gb
```

```yaml [GitLab CI]
build:
  variables:
    TUIST_XCODE_CACHE_SIZE: 50gb
    TUIST_MODULE_CACHE_SIZE: 40gb
```
<!-- -->
:::

Gradle 캐시와 사용자 지정 볼륨은 동일한 `size` 입력을 사용합니다(GitLab CI에서는 `TUIST_GRADLE_CACHE_SIZE` 및 `TUIST_VOLUME_SIZE`, `tuist-cache-volume`의 경우 `--size`). 더 큰 크기는 다음 작업부터 콘텐츠를 유지하면서 볼륨을 확장합니다. 더 작은 크기는 볼륨이 다음으로 삭제되거나 만료된 후에 적용됩니다. 작업이 하나의 캐시에 대해 서로 다른 크기를 요청하면 가장 큰 크기가 적용되므로 각 크기를 한 곳에서 선언하세요.

모든 항목은 **작업 마운트 없이 7일**이 지나면 만료되며, 만료 후 다음 작업은 빈 볼륨으로 시작합니다. Tuist는 Xcode 및 모듈 캐시를 용량에 맞게 정리하며, Gradle 캐시 단계는 모든 빌드 후 7일간 사용되지 않은 항목을 Gradle이 제거하도록 합니다.

사용자 지정 볼륨은 오래된 의존성을 정리하지 않습니다. 도구의 정리 설정을 사용하여 크기를 작게 유지하세요. 가득 찬 볼륨에 쓰기를 시도하면 작업이 실패할 수 있습니다. 저장된 콘텐츠가 볼륨 용량의 **80%** 에 도달하고 작업이 공간 부족에 직면하면 다음 작업은 빈 볼륨으로 시작하며 해당 변경 사항은 새 저장 상태를 시작합니다.

## 볼륨 검사 및 삭제 {#inspecting-and-clearing-volumes}

**러너 → 볼륨**을 열어 사용된 공간, 캐시 히트율 및 작업 기록을 검사하세요. Xcode, 모듈 및 Gradle 캐시도 여기에 표시됩니다.

계정 관리자는 **볼륨 삭제**를 선택하여 볼륨과 저장된 콘텐츠를 제거할 수 있습니다. 실행 중인 작업은 개인 복사본을 유지하지만 다시 저장할 수 없으며, 동일한 키를 사용하는 다음 작업은 빈 볼륨으로 시작합니다. 삭제된 볼륨은 목록에 더 이상 표시되지 않습니다.

터미널 또는 워크플로에서 볼륨을 삭제하려면 ID를 조회하여 `tuist runner volume delete`에 전달하세요:

```bash
tuist runner volume list --account my-org --name gradle-build-cache --json
tuist runner volume delete <volume-id> --account my-org --yes
```

동일한 작업은 [API](https://tuist.dev/api/docs#tag/runners)를 통해 `DELETE /api/accounts/{account_handle}/runners/volumes/{volume_id}`로, [MCP 서버](/guides/features/agentic-coding/mcp)를 통해 `delete_runner_volume`로 사용할 수 있습니다. 모두 계정 관리 권한 또는 `account:runners:write` 범위가 포함된 토큰이 필요합니다.
