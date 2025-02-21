---
title: Issue reporting
titleTemplate: :title · Contributors · Tuist
description: 버그 리포트를 통해 Tuist에 어떻게 기여하는지 알아봅니다.
---

# Issue reporting {#issue-reporting}

Tuist를 사용하면 버그나 예상치 못한 동작을 경험할 수 있습니다.
이런 경우, 문제를 리포트 해주면 수정할 수 있습니다.

## GitHub 이슈는 티켓팅 플랫폼 {#github-issues-is-our-ticketing-platform}

문제는 Slack 이나 다른 플랫폼이 아닌 [GitHub issues](https://github.com/tuist/tuist/issues)에 리포트 해야 합니다. GitHub는 문제를 추적하고 관리하는데 유용하고, 코드베이스에 가까우며, 문제 진행 사항을 추적할 수 있게 합니다. 또한, GitHub는 문제에 대해 더 생각하고 더 많은 내용을 제공하도록 문제의 설명을 자세하게 적도록 유도합니다.

## 설명의 중요성 {#context-is-crucial}

충분한 설명이 없는 문제는 불완전한 것으로 간주되고 추가 내용을 제공해야 될 수도 있습니다. 추가 내용을 제공하지 않으면, 문제는 종료될 수 있습니다. 다음과 같이 생각해보시기 바랍니다: 더 많은 내용을 제공하면 문제를 더 쉽게 이해하고 해결할 수 있습니다. 그래서 문제가 해결되길 원하면, 가능한 자세한 내용을 제공해야 합니다. 다음 질문에 답변 해보시기 바랍니다:

- 무엇을 하려고 했나요?
- 그래프는 어떻게 생겼나요?
- Tuist의 어떤 버전을 사용하고 있나요?
- 이것이 당신을 방해하나요?

우리는 또한 최소한의 **재현 가능한 프로젝트**를 요구할 수도 있습니다.

## 재현 가능한 프로젝트 {#reproducible-project}

### 재현 가능한 프로젝트란 무엇입니까? {#what-is-a-reproducible-project}

재현 가능한 프로젝트는 문제를 보여주는 작은 Tuist 프로젝트 입니다 - 이런 문제는 Tuist의 버그일 수도 있습니다. 재현 가능한 프로젝트는 버그를 명확하게 보여주는 최소한의 기능을 포함해야 합니다.

### 왜 재현 가능한 테스트 케이스를 만들어야 합니까? {#why-should-you-create-a-reproducible-test-case}

재현 가능한 프로젝트로 문제의 원인을 분리할 수 있으며, 이는 문제를 해결하는 첫 번째 단계입니다. 버그 리포트에서 가장 중요한 것은 버그를 재현하는 경로를 정확하게 설명하는 것입니다.

재현 가능한 프로젝트는 버그를 유발하는 특정 환경을 공유하는 좋은 방법입니다. 재현 가능한 프로젝트는 문제 해결에 도움을 줄 수 있는 사람들에게 도움을 주는 가장 좋은 방법입니다.

### 재현 가능한 프로젝트를 생성하는 방법 {#steps-to-create-a-reproducible-project}

- 새로운 git 리포지터리를 생성합니다.
- 리포지터리 디렉토리에서 `tuist init`을 사용하여 프로젝트를 초기화 합니다.
- 발견된 오류를 재현하는데 필요한 코드를 추가합니다.
- 코드를 게시 (당신의 GitHub 계정이 이 작업을 수행하기 좋습니다) 한 다음에 이슈를 생성할 때 링크를 게시합니다.

### 재현 가능한 프로젝트의 이점 {#benefits-of-reproducible-projects}

- **더 작은 크기:** 오류만 남기고 모두 삭제했으므로, 버그를 찾기 위해 복잡한 과정을 수행하지 않아도 됩니다.
- **비밀 코드를 게시할 필요가 없음:** 많은 이유로 사이트에 게시할 수 없을 수 있습니다. 작은 부분으로 재현 가능한 테스트 케이스를 만들면 비밀 코드를 노출하지 않고 문제를 확인할 수 있습니다.
- **버그 증명:** 버그는 컴퓨터의 설정 조합으로 인해 발생할 수 있습니다. 재현 가능한 테스트 케이스는 기여자가 해당 빌드를 다운 받아 빌드하고 테스트할 수 있습니다. 이것은 문제의 원인을 확인하고 범위를 좁히는데 도움을 줍니다.
- **버그 해결에 대한 도움 받기:** 문제를 재현할 수 있으면, 문제를 해결할 가능성이 있습니다. 버그를 재현하지 않고는 문제를 해결하는 것은 거의 불가능 합니다.
