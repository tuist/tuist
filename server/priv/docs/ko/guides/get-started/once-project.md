---
{
  "title": "Once 프로젝트",
  "titleTemplate": ":title · 시작하기 · 가이드 · Tuist",
  "description": "Once를 Tuist에 연결하여 공유 캐싱, 실시간 빌드 및 테스트 인사이트, 테스트 샤딩, 애플리케이션 미리보기를 활용하세요."
}
---
# Once 프로젝트 {#once-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/once-project
```

:::

[Once](https://buildonce.dev)는 캐시 가능한 스크립트와 빌드 그래프를 실행합니다. Tuist에 연결하여 여러 머신 간에 캐시된 작업을 공유하고, 실행을 실시간으로 추적하며, 팀이 시험해 볼 수 있도록 애플리케이션을 배포하세요. 기존 프로젝트 소스와 빌드 정의를 그대로 유지할 수 있으며, 통합 설정은 `once.toml`에 저장됩니다.

## 필수 조건

- [Once](https://buildonce.dev/docs/guide/getting-started)가 설치되어 있고 워크스페이스 또는 캐시 가능한 스크립트가 준비되어 있어야 합니다.
- Tuist 계정. Once 통합에는 Tuist CLI가 필요하지 않습니다.

## 프로젝트 연결하기 {#connect-the-project}

저장소 루트에서 다음 명령어를 실행하세요:

```bash
once connect --provider tuist --create
```

Once는 필요할 때 자동으로 로그인하고, 개인 계정 아래에 Tuist 프로젝트를 생성한 후 프로바이더 바인딩 정보를 `once.toml`에 기록합니다. 다른 계정을 선택하거나 기존 프로젝트를 사용하려면 [프로젝트 연결하기](https://buildonce.dev/docs/guide/infrastructure/connect)를 참조하세요.

기존 Tuist 프로젝트의 경우, 프로바이더와 캐시 바인딩을 직접 구성하세요:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
# url = "https://your-tuist-server.example.com"

[infrastructure.cache]
provider = "tuist"
```

`acme`와 `app`를 본인의 계정 및 프로젝트 핸들로 교체한 후 인증하세요:

```bash
once auth login --provider tuist
```

자격 증명이 아닌 대상 정보를 팀원들과 CI가 공유할 수 있도록 `once.toml`를 커밋하세요. 각 개발자는 자신의 머신에서 개별적으로 로그인합니다.

## 공유 캐시

로컬 캐시는 해당 캐시를 채운 머신에서만 유용합니다. Tuist가 구성되어 있으면 Once는 동일한 작업을 다시 실행하는 대신 다른 개발자나 CI에서 생성된 일치하는 결과를 복원할 수 있습니다.

캐시 가능한 스크립트나 그래프 타겟을 평소대로 실행하세요:

```bash
once build MyApplication
```

대시보드에서 **Once Cache**를 열어 원격 캐시 활동을 확인하세요. 설정 및 머신 간 재사용 확인 방법은 <.localized_link href="/guides/features/cache/once">Once 캐시</.localized_link>를 참조하세요.

## 빌드 인사이트

Once는 실행이 시작될 때 대시보드 링크를 출력합니다. 이를 열어 실행 진행 중 그래프, 액션 상태 및 캐시 결정을 추적하세요. **Builds**를 사용하여 로컬과 CI 성능을 비교하고 실패한 액션을 조사하세요. 전체 프로세스 출력을 위해 CI 로그를 보관하세요. 현재는 원시 액션 로그 수집을 지원하지 않습니다.

기록되는 내용과 코딩 에이전트 또는 Grafana에서 접근하는 방법은 <.localized_link href="/guides/features/build-insights/once">Once 빌드 인사이트</.localized_link>를 참조하세요.

## 테스트 인사이트 및 샤딩

Once 테스트 타겟을 실행하세요:

```bash
once test
```

**Tests**를 열어 보고된 스위트, 케이스, 소요 시간 및 실패를 검사하세요. 결과는 테스트 타겟의 보고 기능에 따라 달라지며, 테스트 프로세스를 실행하는 액션이 자동으로 케이스별 테스트 보고서를 생성하지는 않습니다.

슈트가 한 대의 머신을 넘어설 때는 호스팅된 샤드 계획을 생성하고 배치를 CI 워커에 분산하세요. <.localized_link href="/guides/features/test-insights/once">Once 테스트 인사이트</.localized_link> 및 <.localized_link href="/guides/features/test-sharding/once">Once 테스트 샤딩</.localized_link>을 참조하세요.

## 프리뷰 및 번들 크기

지원되는 Android, Apple 시뮬레이터 및 macOS 애플리케이션을 배포하려면 동일한 프로바이더에 아티팩트 바인딩을 추가하세요:

```toml
[infrastructure.artifacts]
name = "tuist"
```

```bash
once artifact publish MyApplication --track review
```

반환된 링크는 프로젝트의 프리뷰를 엽니다. 처리에는 잠시 시간이 걸릴 수 있습니다. 서명 요구 사항 및 빌드 후 선택적 게시 방법은 <.localized_link href="/guides/features/previews/once">Once 프리뷰</.localized_link>를 참조하세요.

번들 크기를 추적하려면 빌드된 `.app`, `.ipa`, `.xcarchive`, `.apk` 또는 `.aab`를 대상으로 Tuist CLI를 별도로 사용하세요. <.localized_link href="/guides/features/bundle-insights">Apple 또는 Android 번들 인사이트 가이드</.localized_link>를 따르세요. Once 아티팩트를 게시해도 번들 크기 보고서가 자동으로 업로드되지는 않습니다.

## 지속적 통합

`TUIST_TOKEN`에 프로젝트 작업이 승인된 계정 토큰을 사용하거나, 지원되는 CI 프로바이더의 OpenID Connect 신원을 통해 인증하세요:

```bash
once auth login --provider tuist --no-browser
once build MyApplication
once test
```

GitHub Actions에서는 작업에 `id-token: write` 및 `contents: read` 권한을 부여하세요. 예제는 <.localized_link href="/guides/integrations/continuous-integration#once">지속적 통합에서의 Once</.localized_link>를 참조하세요. 개인 개발자 로그인 정보는 CI 자격 증명이 아닙니다.

## 원격 실행

원격 실행이 활성화된 계정은 Tuist의 Linux 워커에서 eligible graph command actions도 실행할 수 있습니다. 이는 캐시된 결과 공유 또는 전체 CI 워크플로우 실행과는 별개입니다. 워커 요구 사항 및 설정 방법은 <.localized_link href="/guides/features/runners/once">Once 원격 실행</.localized_link>을 참조하세요.
