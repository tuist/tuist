---
title: Test flakiness
titleTemplate: :title · Test · Develop · Guides · Tuist
description: Tuist로 불안정한 테스트를 방지하고, 감지하고, 수정합니다.
---

# Test flakiness {#test-flakiness}

> [!IMPORTANT] 원격 프로젝트 필요\
> 이 기능은 <0>원격 프로젝트</0>를 필요로 합니다.

여러 테스트 케이스 그룹에서는 불안정한 테스트가 흔하게 발생합니다. 이러한 테스트는 테스트 대상의 코드가 변경되지 않았어도 테스트가 성공하기도 실패하기도 합니다. 불안정한 테스트는 여러 테스트 케이스 그룹의 신뢰를 떨어뜨리고 실제 리그레션 (기능이 잘 동작하다가 실패하는 현상) 이 발생했을 때 원인을 파악하기 어렵게 만들기 때문에 문제입니다. 더욱이 개발자는 테스트가 통과될 때까지 여러번 테스트를 수행해야 하므로 개발 과정이 지연될 수 있습니다.

다행히, Tuist는 불안정한 테스트를 감지할 수 있는 솔루션을 제공합니다.

## 불안정성 감지 {#detecting-flakiness}

<0>`tuist test`</0>로 테스트를 수행하면, Tuist는 테스트 상태를 식별하는 해시와 각 테스트 케이스의 결과를 저장합니다. 테스트가 포함된 모듈이나 해당 모듈의 의존성 중 하나라도 변경되면 이 해시는 변경됩니다. 해시와 결과 덕분에 Tuist는 테스트가 불안정한지 판단할 수 있습니다. 동일한 해시에 서로 다른 테스트 결과가 나온다면 이 테스트 케이스는 불안정하다고 판단할 수 있습니다.

프로젝트 대시보드에서 불안정한 테스트 목록과 테스트 실행 결과를 다운로드하여 불안정성에 대한 원인을 분석할 수 있습니다. 예를 들어, 아래 이미지는 `test_create_list_and_revoke_project_token` 테스트 케이스가 불안정한 테스트로 표기된 것을 확인할 수 있습니다:

<img src="/images/guides/develop/test/flaky-test-case.png" alt="An image that shows the Tuist dashboard where one can see a test case named test_create_list_and_revoke_project_token and all their test runs where one of them shows as failing."/>
