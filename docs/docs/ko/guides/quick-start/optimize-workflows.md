---
title: Optimize workflows
titleTemplate: :title · Quick-start · Guides · Tuist
description: Tuist로 워크플로우를 최적화하는 방법을 배워봅시다.
---

# Optimize workflows {#optimize-workflows}

Tuist는 프로젝트에 대한 설명과 그에 따른 다양한 정보를 바탕으로, 워크플로우를 더 효율적으로 최적화할 수 있습니다. 몇 가지 예시를 살펴봅시다.

## Smart test runs {#smart-test-runs}

`tuist test`를 다시 실행해 보겠습니다. 다음과 같은 메시지가 표시됩니다.

```bash
There are no tests to run, finishing early
```

마지막으로 테스트를 실행한 이후 프로젝트에서 변경한 사항이 없으므로 테스트를 다시 실행할 필요가 없습니다. 무엇보다도 가장 좋은 점은 이 기능이 다양한 기기나 CI 환경에서 작동한다는 것입니다.

## Cache {#cache}

If you clean build the project, which you usually do on CI or after cleaning the global cache in the hope of fixing cryptic compilation issues, you have to compile the whole project from scratch. When the project becomes large, this can take a long time.

Tuist solves that by re-using binaries from previous builds. Run the following command:

```bash
tuist cache
```

The command will build and share all the cacheable targets in your project in a local and remote cache. After it completes, try generating the project:

```bash
tuist generate
```

You'll notice your project groups includes a new group `Cache` containing the binaries from the cache.

<img src="/images/guides/quick-start/cache.png" alt="An screenshot of a project group structure where you can see XCFrameworks in a cache group" style="max-width: 300px;"/>

If you push your changes upstream to a remote repository, other developers can clone the project, and run the following commands:

```bash
tuist install
tuist auth
tuist generate
```

And they'll suddenly get a project with the dependencies as binaries.

## Optimizations on CI {#optimizations-on-ci}

If want to access those optimizations on CI,
you'll have to generate a project-scoped token to authenticate requests in the CI environment.

```bash
tuist project tokens create my-handle/MyApp
```

Then expose the token as an environment variable `TUIST_CONFIG_TOKEN` in your CI environment. The presence of the token will automatically enable the optimizations and insights.

> [!IMPORTANT] CI ENVIRONMENT DETECTION
> Tuist only uses the token when it detects it's running on a CI environment. If your CI environment is not detected, you can force the token usage by setting the environment variable `CI` to `1`.
