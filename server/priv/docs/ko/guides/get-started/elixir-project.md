---
{
  "title": "Elixir project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Set up Tuist once for Elixir dependency caching, build and test insights, flaky test detection, and optional test sharding."
}
---
# Elixir 프로젝트 {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

Tuist를 한 번 설정한 후 `mix compile`와 `mix test`를 계속 사용하세요. `tuist_ex` Hex 패키지는 지원되는 종속성을 캐시하고 빌드 및 테스트 실행 결과를 대시보드에 보고합니다.

## 필수 조건

- Elixir 1.18 이상에서 Mix로 빌드된 Elixir 프로젝트.
- Tuist 계정.

## Tuist 설정하기 {#set-up-tuist}

Tuist 대시보드에서 프로젝트를 생성하고 빌드 시스템으로 **Mix (Elixir)** 을 선택하세요. `mix.exs`의 종속성에 패키지를 추가하세요:

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

패키지를 가져오고, 프로젝트를 구성한 후 로그인하세요:

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

설정은 `mix.exs`을 프로젝트 핸들로 업데이트하고, 종속성 캐싱을 활성화하며, 컴파일 및 테스트 별칭을 설치합니다. Phoenix의 데이터베이스 설정과 같은 다른 설정과 표준 테스트 준비 과정은 그대로 유지됩니다. 사용자 정의 별칭을 안전하게 통합할 수 없는 경우 파일을 변경하지 않고 중단됩니다.

팀과 CI가 동일한 설정을 사용하도록 업데이트된 `mix.exs`을 커밋하세요. 복사해야 할 스크립트나 평가 코드가 없습니다. 로그인은 브라우저를 엽니다. 헤드리스 로그인 및 CI 자격 증명은 <.localized_link href="/guides/install-hex-package#authenticate">인증</.localized_link>을 참조하세요.

이제 일반적인 명령어를 실행하세요:

```bash
mix compile
mix test
```

빌드는 **Builds** 아래에, 테스트 실행은 **Tests** 아래에, 종속성 캐시 활동은 **Mix cache** 아래에 표시됩니다. 이는 세 가지 모두에 대한 공유 설정입니다. 불안정한 테스트 감지는 보고된 실행을 사용합니다. 재시도 및 CI 샤딩은 선택 사항입니다.

## 종속성 캐싱

Tuist는 종속성 목록 없이 지원되는 Hex 및 Git 종속성을 자동으로 선택합니다. 캐시 미스 시 정상적으로 컴파일하고 결과를 저장하며, 캐시 히트 시 이를 복원합니다. 네이티브/사용자 정의 컴파일 및 로컬 종속성은 Mix로 남습니다.

컴파일은 재현 가능해야 합니다. 추가 컴파일 타임 입력을 선언하고 모델링되지 않은 입력이나 필수 부작용이 있는 종속성을 제외하세요. 지원되는 입력, 캐시 검증 및 맞춤 설정에 대해서는 <.localized_link href="/guides/features/cache/elixir">Elixir 캐시</.localized_link>를 참조하세요.

## 빌드 인사이트

빌드 시간, 파일 간의 종속성 그래프, 그리고 시간이 지남에 따라 둘이 어떻게 변화하는지를 통해 빌드 그래프를 최적화하고 컴파일이 수행되는 환경에서 사용 가능한 모든 코어를 최대한 활용할 수 있습니다.

`compile` 별칭이 적용되면 Tuist는 모든 빌드를 보고합니다. 소요 시간, 경고 및 오류, 각 파일의 컴파일 시간, 그리고 의존하는 파일들이 포함됩니다. 다음 `mix compile` 이후 대시보드의 **Builds**를 열어 확인하세요.

## 테스트 인사이트

Tuist는 모든 `mix test` 실행에서 각 테스트의 결과와 지속 시간을 기록하므로, 테스트 스위트가 시간이 지남에 따라 어떻게 변화하는지 확인하고, 느려진 테스트를 찾아내고, CI에서 실행이 실패한 이유를 이해할 수 있습니다. 대시보드의 **Tests** 아래에서 모듈, `describe` 블록 및 개별 테스트 수준까지 확인할 수 있습니다.

## 불안정한 테스트

불안정한 테스트는 동일한 코드에서 통과하기도 하고 실패하기도 합니다. Tuist는 CI에서 동일한 커밋에서 실패했다가 통과한 테스트를 불안정하다고 표시합니다. 또한 패키지가 실패한 테스트를 재시도하도록 하여 단일 실행에서 이를 감지할 수 있습니다:

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

재시도에서 통과한 테스트는 불안정한 것으로 보고되며 실행은 성공합니다. **Flaky Tests** 페이지에서 이들을 확인할 수 있습니다.

## 테스트 샤딩

테스트 샤딩은 테스트 스위트를 CI 러너들에 분산합니다. Tuist는 이전 실행에서 각 테스트 파일이 걸린 시간을 사용하여 샤드의 균형을 맞추며, 프로젝트를 한 번 컴파일하고 해당 빌드를 모든 러너와 공유합니다. 하나의 명령어로 샤드를 계획합니다:

```bash
mix tuist.test.build --shard-max 4
```

각 러너는 `TUIST_SHARD_INDEX`이 설정된 상태에서 자신의 부분을 실행하며, 결과는 대시보드에 단일 테스트 실행으로 도착합니다:

```bash
TUIST_SHARD_INDEX=0 mix test
```

## 팀 함께 참여시키기

인사이트는 프로젝트에 연결된 인원 수에 따라 누적됩니다. 대시보드의 계정 설정에서 팀원을 조직에 초대하고 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>(Google, Okta, Microsoft)을 설정하여 온보딩이 개인별 `mix tuist.login` 대신 클릭 한 번으로 이루어지도록 하세요.

CI에서는 개인 로그인을 사용하지 마세요. GitHub Actions, CircleCI 및 Bitrise는 OpenID Connect를 통해 인증할 수 있으며, 다른 제공업체에서는 범위가 지정된 `TUIST_TOKEN`을 설정하세요. <.localized_link href="/guides/install-hex-package#authenticate">CI 인증 단계</.localized_link>를 따르세요.
