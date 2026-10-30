---
{
  "title": "선택적 테스팅",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Tuist 선택적 테스팅으로 최신 변경 사항의 영향을 받는 테스트만 실행하여, 지속적 통합에서 몇 초 만에 피드백을 받으세요."
}
---
# 선택적 테스팅 {#selective-testing}

프로젝트가 커질수록 모든 푸시마다 모든 테스트를 실행하는 것은 더 이상 현실적이지 않습니다. Tuist 선택적 테스팅은 마지막 성공적인 실행 이후 변경된 사항에 영향을 받는 테스트만 실행하여 테스트 시간을 획기적으로 단축합니다. 이 과정에서는 당사의 <.localized_link href="/guides/features/projects/hashing">해싱 알고리즘</.localized_link>을 사용합니다.

## 지원되는 빌드 시스템 {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

다른 빌드 시스템에 대한 지원도 계획되어 있습니다.
