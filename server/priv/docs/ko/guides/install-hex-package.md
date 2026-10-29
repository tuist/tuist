---
{
  "title": "Install the Hex package",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Learn how to install and configure Tuist's Hex package in your Elixir project."
}
---
# Hex 패키지 설치 {#install-the-hex-package}

Tuist는 Elixir 프로젝트와 통합되어 <.localized_link href="/guides/features/build-insights/elixir">빌드 인사이트</.localized_link> 및 <.localized_link href="/guides/features/test-insights/elixir">테스트 인사이트</.localized_link>와 같은 기능을 사용할 수 있게 해주는 [Hex](https://hex.pm/packages/tuist_ex) 패키지인 `tuist_ex`를 제공합니다. 이 가이드에서는 이를 설치하고 구성하는 방법을 안내합니다.

이 패키지는 Elixir 1.18 이상이 필요합니다. Tuist 명령줄 인터페이스(CLI)는 필요하지 않습니다.

## 1. 프로젝트 생성 {#create-the-project}

Tuist 대시보드에서 프로젝트를 생성하고 빌드 시스템으로 **Mix (Elixir)** 을 선택하세요. 핸들인 `account/project`가 Mix 프로젝트를 이에 연결합니다.

## 2. 패키지 추가 {#add-the-package}

`tuist_ex`를 `mix.exs`의 의존성에 추가하세요:

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

그런 다음 가져오세요:

```bash
mix deps.get
```

`runtime: false`는 실행 중인 애플리케이션에서 Tuist를 제외시킵니다. 캐싱, 빌드 인사이트 및 테스트 인사이트를 함께 구성하려면 <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Elixir 시작하기</.localized_link>를 계속 진행하세요. 아래 섹션에서는 인증 및 구성 세부 정보를 다룹니다.

## 3. 팀 및 지속적 통합(CI) 인증 {#authenticate}

각 팀원은 자신의 머신에서 Tuist 기능에 액세스하기 위해 다음을 실행합니다:

```bash
mix tuist.login
```

브라우저가 열리고 승인을 기다립니다. 브라우저 없이 로그인하려면 자격 증명을 전달하세요:

```bash
mix tuist.login --email person@example.com --password secret
```

자체 호스팅 또는 로컬 Tuist 서버를 사용하는 경우, `mix.exs`에서 기본 URL을 설정하거나 `--url`로 전달하세요:

```bash
mix tuist.login --url http://localhost:8080
```

호스트명 표기를 일관되게 유지하세요. 예를 들어, `localhost`에 저장된 로그인은 `127.0.0.1`에 저장된 로그인과 별개입니다.

GitHub Actions, CircleCI 및 Bitrise에서는 지속적 통합(CI)에 로그인 단계가 필요하지 않습니다. 작업이 처음으로 보고서를 보낼 때, 제공자의 OpenID Connect 토큰을 Tuist 토큰으로 교환합니다. GitHub 저장소를 Tuist 프로젝트에 <.localized_link href="/guides/integrations/gitforge/github">연결</.localized_link>하고, GitHub Actions에서 작업에 `id-token: write` 권한을 부여하세요:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix test
```

Fly.io Machines와 같은 다른 OpenID Connect 신원 공급자를 사용하는 경우, 계정의 **설정 → 인증** 페이지 내 **워크로드 신원** 섹션에서 워크로드 신원 신뢰 정책을 구성하세요. 이는 해당 계정이 소유한 모든 현재 및 향후 프로젝트에 대한 CI 액세스를 허용합니다. `TUIST_OIDC_ACCOUNT`를 프로젝트가 속한 Tuist 계정으로 설정하고, 정책의 대상(audience)이 포함된 새로 발급된 신원 토큰을 `TUIST_OIDC_TOKEN`를 통해 제공하세요. 계정 토큰이나 유효한 저장된 로그인이 없을 때 통합 기능이 이를 자동으로 교환합니다. `mix tuist.login`도 CI 외부에서 이를 허용합니다. 자동 교환은 동일한 서버, 계정 및 제공된 신원 토큰에 대해서만 만료되지 않은 세션을 재사용합니다. 해당 신원을 변경하면 새로운 교환이 트리거되며, 빈 신원이 제공되면 이전 세션을 재사용하는 대신 실패합니다. Tuist 세션은 리프레시 토큰 없이 1시간 동안 지속되므로, 장기간 실행되는 워크로드의 경우 세션이 만료되기 전에 새 신원 토큰을 발급하고 `mix tuist.login`를 다시 실행하세요. <.localized_link href="/guides/server/authentication#workload-identity-trust-policies">워크로드 신원 설정</.localized_link> 및 <.localized_link href="/guides/server/authentication#flyio-machines">Fly.io 예제</.localized_link>를 참조하세요.

포크에서의 풀 리퀘스트는 OpenID Connect 토큰을 받지 못하므로, 실행 결과가 보고되지 않으며 평소와 같이 통과 또는 실패합니다. 다른 제공자의 경우, `TUIST_TOKEN` 환경 변수를 계정 토큰으로 설정하세요. 토큰을 생성하려면 <.localized_link href="/guides/integrations/continuous-integration#authentication">지속적 통합 인증 가이드</.localized_link>를 따르세요.

## 4. `mix test` 및 `mix compile` 계속 사용 {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">공유 설정</.localized_link>이 컴파일 및 테스트 별칭을 설치해 줍니다. `mix test test/my_app_test.exs:12 --trace`는 동일한 출력 및 종료 코드로 실행을 보고하며, 컴파일 통합은 `mix test` 또는 `mix phx.server`에 의해 트리거된 빌드를 포함합니다. 할 일이 없는 컴파일은 보고되지 않습니다.

작업은 자체 이름으로 호출할 때도 작동합니다. Mix는 `dev` 환경에서 그렇게 입력된 작업을 시작하므로, 테스트 환경을 위해 두 번째 프로세스에서 다시 시작해야 합니다. 이를 건너뛰려면 작업을 선호하는 환경에 추가하세요:

```elixir
def cli do
  [preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]]
end
```

## 구성 참조 {#configuration-reference}

`mix.exs`의 프로젝트 옵션에서 `tuist` 아래에 다음 옵션을 사용할 수 있습니다:

| 옵션 | 유형 | 기본값 | 설명 |
| --- | --- | --- | --- |
| `project` | `String` | 없음 (필수) | `account/project` 형식의 프로젝트 식별자입니다. |
| `url` | `String` | `"https://tuist.dev"` | Tuist 서버의 기본 URL입니다. |
| `cache` | `boolean` 또는 키워드 목록 | 비활성화됨 | 설정은 의존성 캐싱을 활성화합니다. 제외 사항 및 추가 입력에 대해서는 <.localized_link href="/guides/features/cache/elixir">Elixir 캐시</.localized_link>를 참조하세요. |
| `test_retries` | `integer` | `0` | 실패한 테스트를 재시도하는 횟수입니다. <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">테스트 재시도</.localized_link>를 참조하세요. |
| `tags` | `String` 목록 | `[]` | 모든 빌드에 첨부할 태그입니다. <.localized_link href="/guides/features/build-insights/elixir#custom-metadata">사용자 정의 메타데이터</.localized_link>를 참조하세요. |
| `values` | 맵 | `%{}` | 모든 빌드에 첨부할 키-값 데이터입니다. |

환경 변수는 `mix.exs`보다 우선합니다:

| 변수 | 설명 |
| --- | --- |
| `TUIST_PROJECT` | `account/project` 형식의 프로젝트 식별자입니다. |
| `TUIST_URL` | Tuist 서버의 기본 URL입니다. |
| `TUIST_TOKEN` | 저장된 로그인 대신 인증에 사용할 토큰입니다. |
| `TUIST_OIDC_TOKEN` | Tuist 토큰으로 교환되는 새로 발급된 OpenID Connect ID 토큰입니다. GitHub Actions 및 Bitrise의 경우 대상(audience)은 `tuist`이어야 하며, 다른 제공자의 경우 프로젝트의 신뢰 정책과 일치해야 합니다. `mix tuist.login`에서 사용되거나 계정 토큰이나 유효한 저장된 로그인이 없을 때 대체 수단으로 사용됩니다. |
| `TUIST_OIDC_ACCOUNT` | 프로젝트를 소유한 Tuist 계정 핸들입니다. 프로젝트 신뢰 정책을 통해 토큰을 교환할 때 필요합니다. 기존 신뢰 정책 중에서 선택하며 자체적으로 액세스 권한을 부여하지는 않습니다. |
| `TUIST_TEST_RETRIES` | 실패한 테스트를 재시도하는 횟수입니다. |
| `TUIST_TAGS` | 빌드에 첨부할 쉼표로 구분된 태그입니다. |
| `TUIST_VALUES` | 빌드에 첨부할 쉼표로 구분된 `key=value` 쌍입니다. |
| `TUIST_DEBUG` | 보고서를 보낼 수 없는 이유를 출력하려면 `1`로 설정하세요. |

보고서는 `mix test` 또는 `mix compile`의 종료 코드를 절대 변경하지 않습니다. 보고서를 보낼 수 없는 경우, `TUIST_DEBUG=1`가 설정되지 않으면 작업은 아무 것도 출력하지 않습니다.

## 다음 단계 {#next-steps}

패키지가 설치되고 구성되면 다음을 사용할 수 있습니다:

- 컴파일된 의존성을 로컬 및 CI 빌드 전체에서 재사용하기 위한 <.localized_link href="/guides/features/cache/elixir">의존성 캐싱</.localized_link>.
- 컴파일 시간, 경고 및 빌드 지연 요인을 추적하기 위한 <.localized_link href="/guides/features/build-insights/elixir">빌드 인사이트</.localized_link>.
- 각 테스트까지 테스트 성능을 추적하기 위한 <.localized_link href="/guides/features/test-insights/elixir">테스트 인사이트</.localized_link>.
- 간헐적으로 실패하는 테스트를 감지하고 추적하기 위한 <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">불안정한 테스트</.localized_link>.
- 지속적 통합 러너 간에 테스트를 분할하기 위한 <.localized_link href="/guides/features/test-sharding/elixir">테스트 샤딩</.localized_link>.
