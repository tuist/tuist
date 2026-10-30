---
title: Elixir 캐시
titleTemplate: ":title · 캐시 · 가이드 · Tuist"
description: Elixir 프로젝트의 의존성 캐싱을 활성화하고 Mix를 계속 사용하세요.
---

# Elixir 캐시

Tuist는 로컬과 CI 빌드 전반에서 컴파일된 의존성을 재사용합니다. 한 번만 활성화한 후 `mix compile`와 `mix test`를 계속 사용하세요.

## 설정

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Elixir 시작하기</.localized_link> 가이드를 따라 한 번 설정하세요. 공유 설정을 통해 빌드 및 테스트 인사이트와 함께 의존성 캐싱이 활성화되며, 추가적인 캐시 설정은 필요하지 않습니다.

`cache: true`는 지원되는 Hex 및 Git 의존성을 자동으로 선택하므로 직접 나열할 필요가 없습니다. 네이티브/커스텀 컴파일과 로컬 의존성은 Mix를 통해 정상적으로 계속 처리됩니다. 애플리케이션의 소스 파일은 캐시되지 않습니다.

## 평소대로 빌드

```sh
mix compile
mix test
```

의존성 컴파일이 필요하면 Tuist는 로컬 캐시를 먼저 확인한 후 공유 원격 캐시를 확인합니다. 캐시 미스 시 정상적으로 컴파일하고 결과를 저장해 향후 빌드에 재사용합니다. Mix가 최신으로 간주하는 선택된 지원 의존성의 경우, 컴파일 결과물이 존재하고 유효하면 로컬 히트로 집계되며 캐시 조회가 필요하지 않습니다. 인증이나 캐시를 사용할 수 없는 경우에도 Mix는 정상적으로 컴파일합니다.

## 캐시 히트 확인

프로젝트 대시보드에서 **Mix 캐시**를 열어 히트율, 전송량 및 최근 빌드를 확인하세요. 빌드의 **Mix 캐시** 탭을 선택하여 어떤 작업이 히트 또는 미스되었는지 확인할 수 있습니다. **CAS 출력**은 실제 원격 다운로드 및 업로드를 표시하며, 로컬 히트는 원격 전송 기록을 생성하지 않습니다. 이미 최신인 결과물을 재사용하면 히트율에는 기여하지만 전송 바이트, 복원 지연 시간 또는 절약된 예상 시간은 발생하지 않습니다.

복원을 시험하려면 지원되는 의존성의 컴파일 결과물을 정리하고 다시 빌드하세요:

```sh
mix deps.clean nimble_options --build
mix compile
```

`nimble_options`를 프로젝트에서 사용 중이며 이미 캐시가 채워진 의존성으로 바꾸세요. 동일한 Mix 환경과 컴파일러 설정을 유지하세요.

## 필요할 때만 맞춤 설정

대부분의 프로젝트는 `cache: true`를 그대로 유지할 수 있습니다. 예외 사항에는 키워드 목록을 사용하세요:

```elixir
tuist: [
  project: "your-account/your-project",
  cache: [exclude: [:a_dependency_with_compile_time_side_effects]]
]
```

- **추가 컴파일 타임 입력:** 외부 파일은 `inputs: ["schemas"]`로, 환경 변수는 `env: ["COMPILER_OPTION"]`로 선언하세요.
- **로컬 전용:** `remote: false`로 설정하세요.
- **원격 업로드 없음:** `upload: false`로 설정하세요. 서버 권한은 여전히 접근을 제어합니다.
- **캐싱 비활성화:** `cache: false`로 설정하세요.

> [!IMPORTANT]
> 컴파일 과정에서 임의의 Elixir 코드가 실행될 수 있습니다. 추가 입력을 선언하고, 시간 또는 네트워크에 종속된 코드나 사이드 이펙트가 매 빌드마다 반드시 실행되어야 하는 의존성은 제외하세요. 캐시된 아티팩트에는 비밀 정보가 포함될 수 있으며, 캐시 작성자는 신뢰할 수 있는 코드 생산자로 간주됩니다. 신뢰할 수 없는 작업에는 캐시 쓰기 자격 증명을 부여하지 마세요.

의존성 선택, 다양한 체크아웃 경로 간 재사용, 문제 해결 및 구현 세부 사항은 <.localized_link href="/guides/features/cache/elixir-advanced">고급 Elixir 캐시 구성</.localized_link>을 참조하세요.
