---
title: Optimize workflows
titleTemplate: :title · Quick-start · Guides · Tuist
description: Tuist로 워크플로우를 최적화 하는 방법을 배워봅시다.
---

# Optimize workflows {#optimize-workflows}

Tuist는 프로젝트에 대한 설명과 그에 따른 다양한 정보를 바탕으로, 워크플로우를 더 효율적으로 최적화 할 수 있습니다. 몇 가지 예시를 살펴봅시다.

## Smart test runs {#smart-test-runs}

`tuist test`를 다시 실행해 보겠습니다. 다음과 같은 메시지가 표시됩니다.

```bash
There are no tests to run, finishing early
```

마지막으로 테스트를 실행한 이후 프로젝트에서 변경한 사항이 없으므로 테스트를 다시 실행할 필요가 없습니다. 무엇보다도 가장 좋은 점은 이 기능이 다양한 기기나 CI 환경에서 작동한다는 것입니다.

## Cache {#cache}

CI에서 수행하거나 난해난 컴파일 문제를 해결하기 위해 프로젝트를 클린 빌드해야 한다면 프로젝트를 처음부터 컴파일 해야 합니다. 프로젝트 규모가 커진다면 이 작업은 오랜 시간이 걸립니다.

Tuist는 이전 빌드에서 바이너리 재사용으로 이 문제를 해결합니다. 다음의 명령어를 수행하시기 바랍니다:

```bash
tuist cache
```

이 명령어는 프로젝트에서 캐시할 수 있는 모든 타겟을 로컬과 원격 캐시에 빌드하고 공유합니다. 완료되면, 프로젝트를 생성할 수 있습니다:

```bash
tuist generate
```

캐시에서 바이너리가 포함된 새로운 `Cache` 그룹이 프로젝트에 포함되어 있는 것을 알 수 있습니다.

<img src="/images/guides/quick-start/cache.png" alt="An screenshot of a project group structure where you can see XCFrameworks in a cache group" style="max-width: 300px;"/>

변경 사항을 원격 리포지토리에 푸시하면 다른 개발자는 이 프로젝트를 복제하고 다음의 명령어를 수행할 수 있습니다:

```bash
tuist install
tuist auth
tuist generate
```

그러면 바이너리로 의존성을 가지는 프로젝트가 생성됩니다.

## CI에서 최적화 {#optimizations-on-ci}

CI에서 이러한 최적화를 사용하려면, CI 환경에서 인증을 요청하기 위해 프로젝트 범위의 토큰을 생성해야 합니다.

```bash
tuist project tokens create my-handle/MyApp
```

그런 다음에 CI 환경에서 `TUIST_CONFIG_TOKEN`라는 환경 변수로 토큰을 노출합니다. 이 토큰이 있으면 자동으로 최적화가 활성화 됩니다.

> [!IMPORTANT] CI 환경 감지\
> Tuist는 CI 환경에서 실행 중임을 감지할 때만 토큰을 사용합니다. CI 환경이 감지되지 않는 경우, 환경 변수 `CI`를 `1`로 설정하여 토큰 사용을 강제할 수 있습니다.
