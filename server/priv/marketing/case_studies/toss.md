---
title: "Toss: Building less to ship faster"
date: "2026-10-01"
url: "https://toss.im/"
founded_date: "2013"
company: "Toss"
excerpt: "Toss, Korea's financial super-app, rebuilt its iOS local development loop with Tuist's binary cache. Builds that finish within a minute went from about 20% to about 70% of local builds across a graph of close to 1,000 modules."
translations:
  ko:
    title: "Toss, 더 적게 빌드해서 더 빠르게 출시한 방법"
    excerpt: "한국 최대의 금융 슈퍼앱 Toss는 Tuist의 바이너리 캐시로 iOS 로컬 개발 루프를 재설계했습니다. 1,000개에 가까운 모듈로 이루어진 코드베이스에서 1분 안에 끝나는 로컬 빌드 비율이 약 20%에서 약 70%로 올랐습니다."
    body: |
      ## 해결 과제

      ### 하나의 앱, 여러 팀

      [Toss](https://toss.im/)에서는 제품 개발이 '사일로'라고 부르는 작고 독립적인 팀 단위로 조직되어 있습니다. 각 사일로는 자신의 제품을 처음부터 끝까지 책임지고, 모두가 같은 앱에 코드를 올립니다. 수년에 걸쳐 iOS 코드베이스는 1,000개에 가까운 모듈로 커졌고, 메인 브랜치에는 하루 종일 변경 사항이 들어옵니다.

      팀은 이미 Tuist로 Xcode 프로젝트를 [생성](https://tuist.dev/en/docs/guides/features/projects)하고 있었고, 모듈화도 적극적으로 진행해 왔습니다. 대부분의 기능이 Interface, Implementation, Model, Testing 타깃으로 나뉘어 있습니다. 모듈 구조 덕에 책임 범위는 명확해졌지만, 그것만으로 빌드가 빨라지지는 않았습니다.

      ### 빌드 시간은 어디서 소모됐는가

      팀의 목표는 간단했습니다. 코드 한 줄을 바꾼 뒤 개발자가 1분 안에 결과를 볼 수 있어야 한다는 것이었습니다. 하지만 현실은 거리가 멀었습니다. 로컬 빌드 중 약 20%만이 1분 안에 끝났습니다.

      프로파일링 결과, 컴파일은 문제의 한 부분에 지나지 않았습니다. 변경이 있을 때마다 앱의 상당 부분을 다시 컴파일하는 비용이 큰 데다, 모든 증분 빌드에서 상당 시간이 컴파일러가 실제로 일을 시작하기 *전에* 소모되고 있었습니다. Xcode가 의존성 그래프를 계산하고, 모듈 단위로 Swift 빌드를 계획하고, 수백 개의 Xcode 프로젝트로 이루어진 워크스페이스의 빌드 설명(build description)을 만드는 과정이 그것입니다. 기반이 되는 모듈 한 줄만 바꿔도, 앱의 상당 부분에서 재컴파일과 Swift 계획 단계가 연쇄적으로 일어났습니다.

      팀은 쉬운 방법부터 시도했습니다. 빌드 스크립트를 정리하고, 불필요한 셋업 단계를 걷어 내고, 빌드 설정 수를 줄였습니다. 각각 조금씩은 도움이 됐지만, 문제의 모양 자체는 바꾸지 못했습니다. 두 종류의 비용 모두 개발자가 실제로 바꾼 코드의 양이 아니라, Xcode가 빌드하고 고려해야 하는 모듈의 수에 비례해 자라고 있었기 때문입니다.

      그 단계를 마치며 팀이 적어 둔 결론은, 이후 모든 작업의 전제가 되었습니다. 빌드 시간을 줄이는 가장 좋은 방법은 아예 빌드하지 않는 것이다.

      ## Tuist를 선택한 이유

      송금 기능을 개발하는 사람이 주식 거래, 보험, 디자인 시스템을 컴파일할 필요는 없습니다. 그 모듈들이 존재해야 하긴 하지만, 이미 빌드된 상태로 도착해도 됩니다. 팀의 계획은 각 개발자가 자신이 작업 중인 영역을 선언하면, 그 외 모든 것을 사전 빌드된 바이너리로 바꾸는 것이었습니다.

      Tuist는 세 가지 이유에서 자연스러운 선택이었습니다.

      **이미 프로젝트 그래프의 신뢰 가능한 출처(source of truth)였습니다.** Toss는 Tuist로 프로젝트를 생성하고 있었기 때문에, 무엇을 사전 빌드하고 무엇을 소스로 유지할지 판단하는 데 필요한 그래프가 이미 존재했습니다. Tuist의 [바이너리 캐시](https://tuist.dev/en/docs/guides/features/cache)와 포커스 생성(focused generation)은 바로 그 그래프 위에서 동작하므로, 혜택을 보기 위해 새로운 빌드 시스템으로 옮겨 갈 필요가 없었습니다.

      **속도를 끌어올리는 것이 아니라, 일을 아예 없앱니다.** 모듈이 워크스페이스에 소스로 남아 있는 한 Xcode는 그 모듈을 계획하고 자주 다시 컴파일해야 합니다. 개발자가 손대지 않는 모듈을 사전 빌드된 XCFramework로 바꾸면, 그 모듈은 빌드 과정에서 완전히 사라집니다.

      **자체 호스팅이 가능합니다.** Tuist 서버와 캐시를 Toss 자체 인프라에서 운영할 수 있었습니다.

      ## 접근 방식

      이 프로젝트는 약 3개월이 걸렸습니다. 먼저 개발자 로컬 환경에서 사전 빌드된 모듈이 동작하도록 만들고, 그다음 리모트 캐시로 팀 전체에 공유했습니다.

      ### 그래프를 캐시 가능하게 만들기

      사전 빌드가 효과를 내려면 그래프 자체가 먼저 바뀌어야 했습니다. 모든 것 아래에 깔려 있는 모듈 하나가 바뀌면, 사전 빌드 여부와 관계없이 모든 것이 무효화되기 때문입니다. 팀은 다음을 진행했습니다.

      - **불필요한 의존성을 걷어 냈습니다.** 코드베이스 전반에서 사용되지 않는 import를 자동으로 탐지하고 제거하는 체계를 만들었고, 서드파티 의존성은 별도의 릴리스 레포지토리로 분리했습니다.
      - **모든 모듈을 캐시 가능하게 만들었습니다.** 모든 모듈을 소스에서 빌드하던 시절에는 문제없던 일부 패턴이, 모듈이 바이너리로 바뀌자 깨지기 시작했습니다. 팀은 사전 빌드가 가능해질 때까지 해당 모듈들을 다시 설계했습니다.
      - **빌드 변형(variant)을 통합했습니다.** 내부용 빌드와 프로덕션 빌드는 조건부 컴파일 플래그 때문에 서로 다른 바이너리를 만들어 냈고, 그 결과 변형을 바꿀 때마다 캐시를 다시 데워야 했습니다. 팀은 공유 모듈에서 이런 플래그를 제거하고 공통 캐시 설정을 도입해, 하나의 바이너리 세트가 양쪽에 모두 쓰이도록 했습니다.
      - **CI에서 캐시 가능성을 지켰습니다.** 어떤 변경이 캐시 가능한 모듈의 비율을 떨어뜨리면 알림을 띄우는 Pull Request 체크를 추가해, 회귀가 메인 브랜치에 들어오기 전에 잡히도록 했습니다.

      ### 개발자가 실제로 쓸 수 있는 포커스 워크플로우

      Tuist의 포커스 생성 위에, 팀은 작은 워크스페이스 설정 레이어를 만들었습니다. 개발자는 자신이 작업 중인 스킴을 로컬 설정 파일에 선언합니다. 셋업 스크립트는 소스로 남아 있어야 하는 모듈과 그에 의존하는 모듈을 계산하고, Tuist는 나머지 전부가 사전 빌드된 XCFramework인 워크스페이스를 생성합니다.

      앱의 다른 부분도 여전히 탐색할 수 있게 유지했고, 개발자가 자신의 포커스 밖 모듈을 수정하면 명확한 로그를 띄우도록 했으며, AI 코딩 어시스턴트에게도 동일한 캐시 컨텍스트를 전달해 에이전트가 사람과 같은 워크플로우를 따르도록 했습니다.

      ### 자체 호스팅 리모트 캐시

      로컬 캐시는 동작하지만, 새 변경을 받아 올 때마다 모든 개발자가 자신의 머신에서 캐시를 다시 데워야 했고 그 과정이 느렸습니다. 다음 단계는 CI에서 한 번 데운 캐시를 팀 전체가 공유하는 것이었습니다.

      Toss는 Tuist 서버를 자체 인프라에 배포했습니다. CI가 메인 브랜치와 릴리스 브랜치의 캐시를 데우고, 개발자는 필요한 바이너리를 받아 옵니다. 설정이 Tuist에서 아직 지원되지 않는 경우에도, Tuist 팀이 보통 며칠 안에 그것을 설정 옵션으로 추가해 주었습니다. 모든 팀의 다운로드가 빠르게 유지되도록 캐시는 Tuist의 Kura 캐시 노드를 통해 제공됩니다.

      ## Toss 그래프 규모에 맞춘 Tuist 확장

      앱의 거의 전체를 XCFramework로 옮기자 원래의 문제는 해결됐지만, 새로운 문제가 드러났습니다. 1,000개에 가까운 모듈이 전부 바이너리가 되면, 일반적인 프로젝트에서는 보이지 않던 비용이 병목이 되기 시작합니다.

      - **검색 경로(search path).** 사전 빌드된 모든 프레임워크는 검색 경로를 하나씩 더합니다. 그 수가 수백 개에 이르면 import를 해석하는 과정 자체가 매 빌드에서 측정 가능한 비중을 차지하게 됩니다.
      - **해시 안정성.** 캐시는 적중률만큼만 유용합니다. 이 규모에서는 모듈을 해싱하는 방식의 사소한 불일치가 수많은 불필요한 재빌드로 이어집니다.
      - **캐시 데움 비용.** 전체 그래프를 바이너리로 빌드하고 배포하는 작업이, 끊임없이 움직이는 메인 브랜치를 따라갈 수 있을 만큼 빨라야 합니다.

      Toss와 Tuist 팀은 이 문제들을 함께 풀어 나갔고, 그 과정에서 나온 수정들은 이제 모두가 쓰는 Tuist에 들어가 있습니다.

      ## 결과

      Toss를 빌드하는 일상적인 경험이 바뀌었습니다. 어떤 기능을 작업하는 개발자는 자신의 모듈만, 그리고 그 주변 몇 가지만 컴파일하면 됩니다. 브랜치나 빌드 변형을 바꾸는 일이 더 이상 전체를 다시 빌드하는 것을 의미하지 않습니다.

      - **1분 이내에 끝나는 빌드**가 전체 로컬 빌드의 약 20%에서 약 70%로 올랐습니다.
      - **그래프의 대부분이 캐시에서 제공됩니다.** 대부분의 모듈이 캐시 가능하며, 캐시 데움의 대부분을 리모트 캐시가 담당합니다.

      빌드 시간뿐 아니라, 이 프로젝트는 팀이 아키텍처를 바라보는 방식을 바꿔 놓았습니다. 캐시 가능성은 이제 CI가 모든 Pull Request에서 확인하는 지표가 되었고, 그래프의 큰 부분을 무효화시키는 모듈들은 구체적인 리팩터링 대상이 되었습니다.

      ## 앞으로의 계획

      Toss에게 빠른 빌드는 그 자체가 목표였던 적이 없습니다. iOS 개발자들이 도구를 기다리는 대신 자신의 제품에 집중할 수 있도록, 가능한 한 최고의 개발 경험을 제공하기 위한 한 조각일 뿐입니다. Tuist로 앱을 사전 빌드한 것은 그 방향으로 내디딘 큰 걸음이었고, 팀은 Toss에서의 일상적인 개발을 더 빠르고 매끄럽게 만들기 위한 투자를 계속해 나갈 것입니다.
---

## The challenge

### One app, many teams

At [Toss](https://toss.im/), product development is organized into small, autonomous teams called silos. Each silo owns its own product end to end, and each ships into the same app. Over the years, the iOS codebase grew to close to 1,000 modules, with changes landing on the main branch all day.

The team already used Tuist to [generate its Xcode projects](https://tuist.dev/en/docs/guides/features/projects) and had modularized aggressively: most features are split into Interface, Implementation, Model, and Testing targets. The modular structure made ownership clear. It did not make builds fast.

### Where the time went

The team's goal was simple to state: after changing a line of code, a developer should see the result in under a minute. In practice, most developers were far from it. Only about 20% of local builds finished within that minute.

Profiling showed that compilation was only part of the problem. Compiling a large part of the app on every change was expensive on its own, and on top of that, a large share of every incremental build was spent *before* the compiler did any real work: Xcode computing the dependency graph, planning Swift builds module by module, and creating the build description for a workspace made of hundreds of Xcode projects. A one-line change in a foundational module could trigger recompilation and Swift planning across a large part of the app.

The team tried the obvious levers first. They trimmed build scripts, removed redundant setup steps, and reduced the number of build configurations. Each helped a little. None changed the shape of the problem, because both costs grew with the number of modules Xcode had to build and consider, not with the amount of code a developer had actually changed.

The conclusion the team wrote down at the end of that phase became the thesis for everything that followed: the best way to reduce build time is to not build at all.

## Choosing Tuist

A developer working on the transfers feature does not need to compile the stock trading feature, the insurance feature, or the design system. They need those modules to exist, but they can arrive already built. The team's plan was to let each developer declare what they are working on, and to turn everything else into prebuilt binaries.

Tuist was the natural fit for three reasons.

**It was already the source of truth for the project graph.** Because Toss generated its projects with Tuist, the graph needed to decide what to prebuild and what to keep as source already existed. Tuist's [binary cache](https://tuist.dev/en/docs/guides/features/cache) and focused generation build directly on that graph, so the team did not need to migrate to a new build system to get the benefit.

**It removes the work instead of speeding it up.** As long as a module stays in the workspace as source, Xcode still has to plan it and often recompile it. Turning the modules a developer isn't touching into prebuilt XCFrameworks takes them out of the build entirely.

**It can be self-hosted.** Tuist's server and cache can run on Toss's own infrastructure.

## The approach

The project took about three months: first making prebuilt modules work on developers' machines, then sharing them across the team through a remote cache.

### Making the graph cacheable

Before prebuilding could pay off, the graph itself had to change. If a module sits underneath everything, a change to it invalidates everything, prebuilt or not. The team:

- **Removed unnecessary dependencies.** They automated the detection and removal of unused imports across the codebase, and moved third-party dependencies into a separate release repository.
- **Made every module cacheable.** Some patterns that worked when everything was built from source broke once modules were replaced with binaries, so the team reshaped those modules until they could be prebuilt.
- **Unified build variants.** Internal and production builds originally produced different binaries because of conditional compilation flags, which forced developers to rebuild the cache when switching between them. The team removed those flags from shared modules and introduced a single shared cache configuration, so one set of binaries serves both.
- **Guarded cacheability in CI.** A pull request check now alerts when a change reduces the share of modules that can be cached, so regressions are caught before they reach the main branch.

### A focus workflow developers can live with

On top of Tuist's focused generation, the team built a small workspace configuration layer. A developer declares the scheme they are working on in a local config file. The setup script works out which modules must stay as source, including the modules that depend on them, and Tuist generates a workspace where everything else is a prebuilt XCFramework.

They kept the rest of the app navigable, added clear logs when someone edits a module outside their focus, and gave AI coding assistants the same context about the cache, so agents follow the same workflow as humans.

### A self-hosted remote cache

A local cache works, but every developer still had to warm it on their own machine after pulling new changes, which was slow. The next step was to warm the cache once on CI and share it.

Toss deployed Tuist's server on its own infrastructure. CI warms the cache for the main branch and release branches, and developers pull the binaries they need. Whenever the setup needed something Tuist didn't support yet, the Tuist team usually turned it into a configuration option within days. To keep downloads fast for every team, the cache is served through Tuist's Kura cache nodes.

## Scaling Tuist to Toss's graph

Moving almost the whole app to XCFrameworks solved the original problem and revealed a new one. When close to 1,000 modules are binaries, costs that are invisible in a typical project become the bottleneck.

- **Search paths.** Every prebuilt framework adds a search path, and with hundreds of them, simply resolving imports becomes a measurable part of each build.
- **Hash stability.** A cache is only as good as its hit rate. At this scale, small inconsistencies in how modules are hashed turn into large numbers of unnecessary rebuilds.
- **Warming cost.** Building and distributing the whole graph as binaries has to stay fast enough to keep up with a constantly moving main branch.

Toss and the Tuist team worked through these together, and the fixes now ship in Tuist for everyone.

## The results

The everyday experience of building Toss changed. A developer working on a feature compiles their own modules and not much else, and switching branches or build variants no longer means rebuilding the world.

- **Builds within one minute** went from about 20% to about 70% of local builds.
- **Most of the graph is served from cache:** most modules can be cached, and most cache warms are served from the remote cache.

Beyond build times, the project changed how the team thinks about architecture. Cacheability is now something CI checks on every pull request, and the modules that invalidate the most of the graph have become a concrete target for refactoring.

## What's next

For Toss, faster builds were never the end goal. They are one part of giving iOS developers the best possible development experience, where they can stay focused on their product instead of waiting on tooling. Prebuilding the app with Tuist was a big step in that direction, and the team will keep investing in making everyday development at Toss faster and smoother.
