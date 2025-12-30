---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times with Tuist Cache."
}
---
# 캐시 {#cache}

Xcode의 빌드 시스템은 [증분 빌드](https://en.wikipedia.org/wiki/Incremental_build_model)를
제공하여 단일 시스템에서 효율성을 향상시킵니다. 그러나 빌드 아티팩트는 다른 환경 간에 공유되지 않으므로 [지속적 통합(CI)
환경](https://en.wikipedia.org/wiki/Continuous_integration) 또는 로컬 개발 환경(Mac)에서 동일한
코드를 반복해서 다시 빌드해야 합니다.

Tuist는 캐싱 기능으로 이러한 문제를 해결하여 로컬 개발 환경과 CI 환경 모두에서 빌드 시간을 크게 단축합니다. 이러한 접근 방식은 피드백
루프를 가속화할 뿐만 아니라 컨텍스트 전환의 필요성을 최소화하여 궁극적으로 생산성을 향상시킵니다.

두 가지 유형의 캐싱을 제공합니다:
- <LocalizedLink href="/guides/features/cache/module-cache">모듈 캐시</LocalizedLink>
- <LocalizedLink href="/guides/features/cache/xcode-cache">Xcode 캐시</LocalizedLink>

## 모듈 캐시 {#module-cache}

튜이스트의 <LocalizedLink href="/guides/features/projects">프로젝트 생성</LocalizedLink>
기능을 사용하는 프로젝트의 경우, 개별 모듈을 바이너리로 캐싱하여 팀과 CI 환경 전체에서 공유하는 강력한 캐싱 시스템을 제공합니다.

새로운 Xcode 캐시를 사용할 수도 있지만, 이 기능은 현재 로컬 빌드에 최적화되어 있으며 생성된 프로젝트 캐싱에 비해 캐시 적중률이 낮을 수
있습니다. 그러나 어떤 캐싱 솔루션을 사용할지는 구체적인 요구 사항과 선호도에 따라 결정해야 합니다. 최상의 결과를 얻기 위해 두 캐싱 솔루션을
결합할 수도 있습니다.

<LocalizedLink href="/guides/features/cache/module-cache">모듈 캐시에 대해 자세히 알아보기 →</LocalizedLink>

## Xcode 캐시 {#xcode-cache}

::: 경고 XCODE 내 캐시 상태 경고
<!-- -->
Xcode 캐싱은 현재 로컬 증분 빌드에 최적화되어 있으며 빌드 작업의 전체 스펙트럼이 아직 경로 독립적이지 않습니다. 하지만 Tuist의 원격
캐시를 연결하면 이점을 경험할 수 있으며, 빌드 시스템의 기능이 계속 향상됨에 따라 빌드 시간은 시간이 지남에 따라 개선될 것으로 예상됩니다.
<!-- -->
:::

Apple은 Bazel 및 Buck과 같은 다른 빌드 시스템과 유사한 빌드 수준에서 새로운 캐싱 솔루션을 개발해 왔습니다. 새로운 캐싱 기능은
Xcode 26부터 사용할 수 있으며, 이제 Tuist는 Tuist의
<LocalizedLink href="/guides/features/projects">프로젝트 생성</LocalizedLink> 기능 사용
여부와 관계없이 이 기능과 원활하게 통합됩니다.

<LocalizedLink href="/guides/features/cache/xcode-cache">Xcode 캐시에 대해 자세히 알아보기 →</LocalizedLink>
