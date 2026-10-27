---
{
  "title": "About Tuist",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Extend your Apple native tooling to better apps at scale."
}
---
<script setup>
import VPFeature from "vitepress/dist/client/theme-default/components/VPFeature.vue";
</script>


# About Tuist {#about-tuist}

앱 개발, 특히 Apple과 같은 플랫폼에서 조직은 종종 **생산성을 저해하는 문제**에 직면합니다. 대표적인 예로는 느린 컴파일 속도, 신뢰할 수 없는 테스트, 그리고 많은 리소스를 소모하는 복잡한 자동화 워크플로우 등이 있습니다. 일반적으로 기업들은 이런 문제를 해결하기 위해 전담 플랫폼 팀을 운영합니다. 이 전문가들은 코드베이스의 품질과 안정성을 유지하여, 다른 개발자들이 기능 개발에 집중할 수 있도록 합니다. 하지만 이런 방식은 비용이 많이 들고 위험할 수 있습니다. 핵심 팀원이 떠나면 생산성이 심각하게 저하될 수 있기 때문입니다.

## What {#what}

Tuist는 앱 개발을 빠르고 효율적으로 할 수 있도록 설계된 툴체인입니다. 공식 도구 및 시스템과 자연스럽게 연동되어 개발자들이 익숙한 환경에서 작업할 수 있도록 지원합니다. 도구 및 시스템 통합의 부담을 덜어줌으로써, 팀은 기능 개발과 전반적인 개발자 경험 향상에 집중할 수 있습니다. 즉, Tuist는 가상의 플랫폼 팀 역할을 하며,  앱 아이디어가 떠오르는 순간부터 사용자에게 출시될 때까지 Tuist는 모든 과정에서 함께하며 발생하는 문제를 해결합니다.

Tuist는 개발자들을 위한 주된 인터페이스인 [CLI](https://github.com/tuist/tuist)와 상태 정보 유지 및 외부 서비스를 연동을 위한 <LocalizedLink href="/server/introduction/why-a-server">서버</LocalizedLink> 로 구성되어 있습니다.

## Why {#why}

왜 Tuist를 사용해야 할까요? 다음과 같은 매력적인 이유가 있습니다.

### Simplify 🌱 {#simplify}

프로젝트가 성장하고 여러 플랫폼에 걸쳐 확장될수록 모듈화는 매우 중요해집니다. Tuist는 복잡한 과정을 간단하게 만들어 프로젝트 구조를 최적화하고 더 이해하기 쉬운 도구를 제공합니다.

**Further reading:** <LocalizedLink href="/guides/features/projects">Projects</LocalizedLink>

### Optimize workflows 🚀 {#optimize-workflows}

프로젝트 정보를 활용하여 Tuist는 선택적 테스트 실행과 빌드 바이너리 재사용을 통해 효율성을 향상시킵니다.

**Further reading:** <LocalizedLink href="/guides/features/cache">Cache</LocalizedLink>, <LocalizedLink href="/guides/features/selective-testing">Selective testing</LocalizedLink>, <LocalizedLink href="/guides/features/registry">Registry</LocalizedLink>, and <LocalizedLink href="/guides/features/previews">Previews</LocalizedLink>

### Foster healthy project evolution 📈 {#foster-healthy-project-evolution}

우리는 당신의 프로젝트 동향을 분석하고, 현명한 의사 결정을 위한 전문적인 가이드를 제공합니다. 이 접근 방식은 문제가 있는 프로젝트에서 발생하는 좌절감과 생산성 저하를 방지하여 개발자 이탈과 비즈니스 목표 미달성을 방지합니다.

**Further reading:** <LocalizedLink href="/server/introduction/why-a-server">Server</LocalizedLink>

### Break down silos 💜 {#break-down-silos}

플랫폼별 생태계(예: Xcode의 폐쇄적인 환경 등)과 달리, Tuist는 웹 중심 경험을 제공하며 Slack, Prometheus, Github과 같은 인기 있는 도구와 원활하게 통합되어 도구 간 협업을 강화합니다.

**Further reading:** <LocalizedLink href="/guides/features/projects">Projects</LocalizedLink>

---

Tuist, 프로젝트, 그리고 회사에 대해 더 알고 싶다면 [핸드북](https://handbook.tuist.io/) 을 확인해보세요. 우리의 비전, 가치, 그리고 Tuist를 만들어가는 팀에 대한 자세한 내용을 담고 있습니다.
