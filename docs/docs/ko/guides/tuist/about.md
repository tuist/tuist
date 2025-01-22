---
title: About Tuist
titleTemplate: :title · Guides · Tuist
description: Apple의 기본 도구를 확장하여 더 나은 앱을 효과적으로 개발하세요.
---

<script setup>
import VPFeature from "vitepress/dist/client/theme-default/components/VPFeature.vue";
</script>

# About Tuist {#about-tuist}

앱 개발의 세계에서, 특히 Apple과 같은 플랫폼의 경우 조직은 종종 **생산성 장애물**에 부딪히게 됩니다. 여기에는 느린 컴파일 시간, 신뢰할 수 없는 테스트, 리소스를 소모하는 복잡한 자동화 워크플로우 등이 포함됩니다. 이러한 문제를 해결하기 위해 기업은 보통 플랫폼 전담 팀을 운영합니다. 이 팀의 전문가는 코드베이스의 상태와 무결성을 유지하여 다른 개발자가 기능 개발에 집중할 수 있도록 합니다. 하지만 이러한 접근 방식은 핵심 팀원이 이탈하면 생산성에 심각한 영향을 미칠 수 있기 때문에 비용이 많이 들고 위험할 수 있습니다.

## What {#what}

**Tuist는 앱 개발을 가속화하고 향상시키기 위해 설계된 툴체인입니다.** Tuist는 공식 도구 및 시스템과 원활하게 통합되어  개발자들이 익숙한 환경에서 작업할 수 있도록 돕습니다. 이를 통해 도구와 시스템 통합의 복잡함을 줄여주고, 팀이 기능 개발과 전반적인 개발자 경험 개선에 더 많은 에너지를 쏟을 수 있도록 지원합니다. 본질적으로 Tuist는 가상의 플랫폼 팀의 역할을 합니다. 앱 아이디어의 구상 단계부터 사용자에게 출시되는 전 과정에서 발생하는 문제를 해결해줍니다.

Tuist is comprised of a [CLI](https://github.com/tuist/tuist), which is the main entry point for developers, and a <LocalizedLink href="/server/introduction/why-a-server">server</LocalizedLink> that the CLI integrates with to persist state and integrate with other publicly available services.

## Why {#why}

왜 Tuist를 선택해야 할까요? 다음과 같은 강력한 이유가 있습니다:

### Simplify 🌱 {#simplify}

As projects grow and span multiple platforms, modularization becomes crucial. Tuist는 이러한 복잡성을 간소화하여 프로젝트 구조를 최적화하고 더 잘 이해할 수 있는 도구를 제공합니다.

**Further reading:** <LocalizedLink href="/guides/develop/projects">Projects</LocalizedLink>

### Optimize workflows 🚀 {#optimize-workflows}

Leveraging project information, Tuist enhances efficiency through selective test execution and deterministic binary reuse across builds.

**Further reading:** <LocalizedLink href="/guides/develop/cache">Cache</LocalizedLink>, <LocalizedLink href="/guides/develop/selective-testing">Selective testing</LocalizedLink>, <LocalizedLink href="/guides/develop/registry">Registry</LocalizedLink>, and <LocalizedLink href="/guides/share/previews">Previews</LocalizedLink>

### Foster healthy project evolution 📈 {#foster-healthy-project-evolution}

We provide insights into your project's dynamics and expert guidance for informed decision-making. 이러한 접근 방식은 개발자의 이탈과 비즈니스 목표 누락으로 이어질 수 있는 건강하지 않은 프로젝트와 관련된 좌절감과 생산성 손실을 방지합니다.

**Further reading:** <LocalizedLink href="/server/introduction/why-a-server">Server</LocalizedLink>

### Break down silos 💜 {#break-down-silos}

Unlike platform-specific ecosystems (e.g., Xcode's contained environment), Tuist offers web-centric experiences and integrates seamlessly with popular tools like Slack, Prometheus, and GitHub, enhancing cross-tool collaboration.

**Further reading:** <LocalizedLink href="/guides/develop/projects">Projects</LocalizedLink>

---

Tuist와 프로젝트, 회사에 대해 더 자세히 알고 싶으시다면 당사의 비전, 가치, 팀에 대한 자세한 정보가 담긴 [핸드북](https://handbook.tuist.io/) 을 확인해보세요.
