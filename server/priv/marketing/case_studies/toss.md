---
title: "Toss: Building less to ship faster"
date: "2026-10-01"
url: "https://toss.im/"
founded_date: "2013"
company: "Toss"
excerpt: "Toss, Korea's financial super-app, is split into close to 1,000 modules. This is how the team used Tuist's binary cache to take builds that finish within a minute from about 20% to about 70% of local builds."
translations:
  ko:
    title: "토스팀의 개발 속도를 높이기 위한 여정"
    excerpt: "슈퍼앱 토스는 1,000개에 가까운 모듈로 잘게 나뉘어 있어요. 이런 환경에서 Tuist의 바이너리 캐시를 활용해, 1분 안에 끝나는 로컬 빌드 비율을 약 20%에서 약 70%까지 끌어올린 과정을 소개해요."
    body: |
      ## 풀어야 했던 문제

      ### 하나의 앱을 여러 팀이 함께 만들어요

      [토스](https://toss.im/)는 '사일로'라고 부르는 작은 팀 단위로 제품을 만들어요. 사일로마다 맡은 제품을 처음부터 끝까지 책임지고, 그 결과물은 모두 하나의 앱에 들어가요. 이런 환경에서 수많은 제품이 탄생했고, 그 과정에서 iOS 프로젝트의 모듈은 1,000개 가까이로 늘었어요.

      토스의 iOS 프로젝트는 이미 Tuist로 Xcode 프로젝트를 [생성](https://tuist.dev/en/docs/guides/features/projects)하고 있었고, 모듈도 잘게 나뉘어 있었어요. 대부분의 기능은 Interface, Implementation, Model, Testing 타깃으로 나뉘어 있어요. 모듈을 나눈 덕분에 어느 팀이 어떤 코드를 맡는지는 분명해졌지만, 빌드가 빨라지지는 않았어요.

      ### 빌드는 왜 느렸을까요

      토스팀의 목표는 분명했어요. 코드를 한 줄 고치면 1분 안에 결과를 확인할 수 있어야 한다는 것이었어요. 하지만 실제로는 로컬 빌드의 약 20%만 1분 안에 끝났어요.

      빌드를 분석해 보니 문제는 두 가지였어요. 하나는 컴파일이에요. 코드를 고칠 때마다 앱의 많은 부분을 다시 컴파일해야 했어요. 다른 하나는 컴파일이 시작되기 전에 쓰이는 시간이에요. 증분 빌드를 할 때마다 Xcode가 의존성 그래프를 계산하고, 모듈마다 Swift 빌드 계획을 세우고, 수백 개의 Xcode 프로젝트로 이루어진 워크스페이스의 build description을 만드는 데 많은 시간이 걸렸어요. 여러 모듈이 의존하는 기반 모듈을 한 줄만 고쳐도, 앱의 많은 부분에서 재컴파일과 Swift 빌드 계획이 다시 실행됐어요.

      토스팀은 먼저 바로 할 수 있는 일부터 했어요. 빌드 스크립트를 정리하고, 필요 없는 셋업 단계를 없애고, 빌드 configuration 수를 줄였어요. 하나하나 조금씩 효과가 있었지만, 문제를 근본적으로 해결하지는 못했어요. 컴파일 비용과 빌드 준비 비용 모두, 개발자가 실제로 고친 코드의 양이 아니라 Xcode가 빌드하고 확인해야 하는 모듈 수에 따라 늘어났기 때문이에요.

      이 과정을 마치면서 토스팀이 내린 결론이 이후 모든 작업의 출발점이 됐어요. 빌드 시간을 줄이는 가장 좋은 방법은 빌드를 하지 않는 것이에요.

      ## Tuist를 선택한 이유

      송금 기능을 개발하는 개발자는 증권 기능이나 디자인 시스템까지 직접 컴파일할 필요가 없어요. 이 모듈들은 있어야 하지만, 이미 빌드된 상태로 받아 오면 돼요. 그래서 토스팀은 개발자가 작업할 모듈을 지정하면, 나머지 모듈은 모두 미리 빌드한 바이너리로 바꾸기로 했어요.

      Tuist가 잘 맞았던 이유는 세 가지예요.

      **프로젝트 그래프를 이미 Tuist로 관리하고 있었어요.** 토스는 Tuist로 프로젝트를 생성하고 있어서, 어떤 모듈을 미리 빌드하고 어떤 모듈을 소스로 둘지 정하는 데 필요한 그래프가 이미 있었어요. Tuist의 [바이너리 캐시](https://tuist.dev/en/docs/guides/features/cache)와 focus 기능은 이 그래프를 그대로 사용하기 때문에, 빌드 시스템을 새로 바꾸지 않아도 됐어요.

      **빌드를 빠르게 하는 대신 빌드할 대상을 줄여요.** 모듈이 워크스페이스에 소스로 남아 있으면, Xcode는 그 모듈의 빌드 계획을 세워야 하고 다시 컴파일해야 하는 경우도 많아요. 개발자가 건드리지 않는 모듈을 미리 빌드한 XCFramework로 바꾸면, 그 모듈은 빌드 대상에서 아예 빠져요.

      **직접 호스팅할 수 있어요.** Tuist 서버와 캐시를 토스 인프라에서 직접 운영할 수 있어요.

      ## 진행 과정

      프로젝트는 약 3개월 동안 진행했어요. 먼저 개발자 머신에서 미리 빌드한 모듈을 쓸 수 있게 만들었고, 그다음 리모트 캐시로 토스팀 전체가 공유하도록 했어요.

      ### 캐시할 수 있는 그래프 만들기

      미리 빌드한 모듈이 효과를 내려면 의존성 그래프부터 바꿔야 했어요. 모든 모듈이 의존하는 모듈이 있으면, 그 모듈이 바뀔 때마다 미리 빌드해 둔 모듈까지 전부 다시 빌드해야 하기 때문이에요. 토스팀이 한 일은 다음과 같아요.

      - **불필요한 의존성을 없앴어요.** 코드 전체에서 쓰지 않는 import를 자동으로 찾아 지우도록 했고, 서드파티 의존성은 별도의 릴리스 저장소로 옮겼어요.
      - **모든 모듈을 캐시할 수 있게 만들었어요.** 전부 소스로 빌드할 때는 문제가 없던 코드 중 일부가, 모듈을 바이너리로 바꾸자 빌드되지 않았어요. 토스팀은 이런 모듈을 미리 빌드할 수 있는 구조로 고쳤어요.
      - **빌드 종류에 상관없이 같은 캐시를 쓰게 했어요.** 원래는 조건부 컴파일 플래그 때문에 사내 테스트용 빌드와 운영 빌드의 바이너리가 서로 달랐고, 개발자는 빌드 종류를 바꿀 때마다 캐시를 다시 만들어야 했어요. 토스팀은 공용 모듈에서 이 플래그를 없애고 캐시 전용 configuration을 하나 두어서, 같은 바이너리를 양쪽에서 쓸 수 있게 했어요.
      - **캐시할 수 있는 모듈 비율을 CI에서 확인해요.** 캐시할 수 있는 모듈 비율을 낮추는 변경이 있으면 Pull Request 단계에서 알려 주기 때문에, 메인 브랜치에 들어가기 전에 문제를 찾을 수 있어요.

      ### 개발자가 쓰기 편한 focus 방식

      토스팀은 Tuist의 focus 기능 위에 간단한 워크스페이스 설정 기능을 만들었어요. 개발자는 로컬 설정 파일에 작업할 스킴을 적어요. 그러면 셋업 스크립트가 소스로 남겨야 할 모듈을 계산해요. 여기에는 그 모듈에 의존하는 모듈도 포함돼요. Tuist는 나머지 모듈이 모두 미리 빌드한 XCFramework로 들어간 워크스페이스를 생성해요. 토스 개발자들은 이 설정을 얼마 전 토스팀이 공개한 iOS 디버깅 도구 [necto](https://github.com/toss/necto)로 손쉽게 편집할 수 있어요.

      그리고 focus하지 않은 모듈의 코드도 계속 찾아볼 수 있게 했고, focus하지 않은 모듈을 수정하는 것을 방지하는 장치도 마련했어요. AI 코딩 도구에도 캐시에 관한 같은 정보를 제공해서, AI 에이전트도 개발자와 같은 방식으로 작업하게 했어요.

      ### 직접 호스팅하는 리모트 캐시

      로컬 캐시만으로도 효과는 있었어요. 하지만 개발자는 새 변경 사항을 받을 때마다 자기 머신에서 캐시를 다시 만들어야 했고, 이 작업이 오래 걸렸어요. 그래서 다음 단계로, CI에서 캐시를 한 번 만들어 모두가 공유하도록 했어요.

      토스는 Tuist 서버를 자체 인프라에 배포했어요. CI가 개발자에게 필요한 캐시를 만들고, 개발자는 필요한 바이너리를 받아서 써요. 구축 과정에서 Tuist가 아직 지원하지 않는 기능이 필요할 때는, Tuist 팀이 대부분 며칠 안에 설정 옵션으로 추가해 줬어요. 캐시는 Tuist의 Kura 캐시 노드로 제공해서, 모든 팀이 빠르게 내려받을 수 있게 했어요.

      ## 모듈이 1,000개 가까이 되면 생기는 문제

      앱의 거의 모든 모듈을 XCFramework로 바꾸자 처음의 문제는 해결됐지만, 새로운 문제가 나타났어요. 1,000개 가까운 모듈이 바이너리가 되면, 보통 규모의 프로젝트에서는 드러나지 않던 비용이 병목이 돼요.

      - **Framework Search Path.** 미리 빌드한 프레임워크마다 Framework Search Path가 하나씩 추가돼요. 이 경로가 수백 개가 되면, import를 찾는 데 걸리는 시간만으로도 빌드 시간이 눈에 띄게 늘어나요.
      - **해시 안정성.** 캐시는 적중률이 높아야 쓸모가 있어요. 이 규모에서는 모듈 해시를 계산하는 방식이 조금만 어긋나도 불필요한 재빌드가 대량으로 발생해요.
      - **캐시 준비 비용.** 메인 브랜치가 계속 바뀌기 때문에, 전체 그래프를 바이너리로 빌드하고 배포하는 작업이 그 속도를 따라갈 만큼 빨라야 해요.

      토스와 Tuist 팀은 이 문제들을 함께 해결했고, 수정한 내용은 Tuist에 반영되어 모든 사용자가 쓸 수 있어요.

      ## 결과

      토스팀의 iOS 개발자가 토스 앱을 빌드하는 경험이 정말 많이 달라졌어요. 제품 개발자는 본인이 담당하는 모듈만 빌드하면 되는 환경이 마련됐고, 브랜치나 빌드 환경을 바꿔도 전체를 다시 빌드하는 일이 없어졌어요. 그리고 이런 환경에서는 Example 앱으로 개발할 때의 생산성도 한층 더 높아졌어요.

      - **1분 안에 끝나는 빌드**가 로컬 빌드의 약 20%에서 약 70%로 늘었어요.
      - **그래프의 대부분을 캐시에서 받아 와요.** 대부분의 모듈을 캐시할 수 있고, 캐시를 준비할 때도 대부분 리모트 캐시에서 받아 와요.

      빌드가 빨라진 것은 AI 에이전트에게도 아주 큰 영향을 줬어요. AI 에이전트도 코드를 고친 뒤 빌드로 결과를 확인하기 때문에, 빌드가 빨라진 만큼 AI와 함께하는 개발도 훨씬 빨라졌어요.

      ## 앞으로

      토스에게 빠른 빌드는 최종 목표가 아니었어요. 빠른 빌드는 iOS 개발자에게 최고의 개발 경험을 제공하기 위한 일 중 하나예요. 개발자가 제품 개발에 정말 필요한 고민에 집중할 수 있어야 하기 때문이에요. Tuist로 미리 빌드한 바이너리를 활용할 수 있게 된 것은 개발 경험에 아주 큰 변화였어요. 토스팀은 앞으로도 최고의 개발 환경을 만들기 위해 끊임없이 투자할 계획이에요.
---

## The challenge

### One app, many teams

At [Toss](https://toss.im/), product development is organized into small, autonomous teams called silos. Each silo owns its own product end to end, and each ships into the same app. Many products were born in this environment, and along the way the iOS codebase grew to close to 1,000 modules.

Toss's iOS project already used Tuist to [generate its Xcode projects](https://tuist.dev/en/docs/guides/features/projects) and was heavily modularized: most features are split into Interface, Implementation, Model, and Testing targets. The modular structure made ownership clear, but it did not make builds fast.

### Why builds were slow

The Toss team's goal was simple to state: after changing a line of code, a developer should see the result in under a minute. In practice, most developers were far from it. Only about 20% of local builds finished within that minute.

Profiling showed two problems. One was compilation: every change meant recompiling a large part of the app. The other was the time spent *before* the compiler did any real work. On every incremental build, Xcode spent a long time computing the dependency graph, planning Swift builds module by module, and creating the build description for a workspace made of hundreds of Xcode projects. A one-line change in a foundational module could trigger recompilation and Swift planning across a large part of the app.

The team tried the obvious levers first. They trimmed build scripts, removed redundant setup steps, and reduced the number of build configurations. Each helped a little. None changed the shape of the problem, because both costs grew with the number of modules Xcode had to build and consider, not with the amount of code a developer had actually changed.

The conclusion the team wrote down at the end of that phase became the thesis for everything that followed: the best way to reduce build time is to not build at all.

## Choosing Tuist

A developer working on the transfers feature does not need to compile the stock trading feature or the design system. They need those modules to exist, but they can arrive already built. The team's plan was to let each developer declare what they are working on, and to turn everything else into prebuilt binaries.

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

On top of Tuist's focused generation, the team built a small workspace configuration layer. A developer declares the scheme they are working on in a local config file. The setup script works out which modules must stay as source, including the modules that depend on them, and Tuist generates a workspace where everything else is a prebuilt XCFramework. Inside Toss, developers can easily edit this configuration with [necto](https://github.com/toss/necto), an iOS debugging tool the team recently open-sourced.

They also kept the rest of the app navigable, added safeguards against editing modules outside the focus, and gave AI coding assistants the same context about the cache, so agents follow the same workflow as humans.

### A self-hosted remote cache

A local cache works, but every developer still had to warm it on their own machine after pulling new changes, which was slow. The next step was to warm the cache once on CI and share it.

Toss deployed Tuist's server on its own infrastructure. CI warms the cache that developers need, and developers pull the binaries they need. Whenever the setup needed something Tuist didn't support yet, the Tuist team usually turned it into a configuration option within days. To keep downloads fast for every team, the cache is served through Tuist's Kura cache nodes.

## Scaling Tuist to Toss's graph

Moving almost the whole app to XCFrameworks solved the original problem and revealed a new one. When close to 1,000 modules are binaries, costs that are invisible in a typical project become the bottleneck.

- **Framework search paths.** Every prebuilt framework adds a framework search path, and with hundreds of them, simply resolving imports becomes a measurable part of each build.
- **Hash stability.** A cache is only as good as its hit rate. At this scale, small inconsistencies in how modules are hashed turn into large numbers of unnecessary rebuilds.
- **Warming cost.** Building and distributing the whole graph as binaries has to stay fast enough to keep up with a constantly moving main branch.

Toss and the Tuist team worked through these together, and the fixes now ship in Tuist for everyone.

## The results

For Toss's iOS developers, the experience of building the Toss app changed dramatically. Product developers now only need to build the modules they own, and switching branches or build environments no longer means rebuilding everything. In this setup, working in example apps became even more productive.

- **Builds within one minute** went from about 20% to about 70% of local builds.
- **Most of the graph is served from cache:** most modules can be cached, and most cache warms are served from the remote cache.

Faster builds also had a big impact on AI agents. Agents verify their changes by building too, so as builds got faster, development with AI got much faster as well.

## What's next

For Toss, faster builds were never the end goal. They are one part of giving iOS developers the best possible development experience, so that they can focus on the problems that really matter for their product. Being able to use prebuilt binaries through Tuist was a huge change to that experience, and the team will keep investing to build the best possible development environment.
