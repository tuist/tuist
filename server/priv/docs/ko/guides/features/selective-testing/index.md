---
{
  "title": "선택적 테스팅",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Tuist 선택적 테스팅으로 최신 변경 사항에 영향을 받은 테스트만 실행하여, 지속적 통합에서 몇 초 안에 피드백을 받을 수 있습니다."
}
---
# 선택적 테스팅 {#selective-testing}

프로젝트가 커질수록 모든 푸시에서 모든 테스트를 실행하는 방식은 더 이상 실현 가능하지 않습니다. Tuist 선택적 테스팅은 마지막 성공적인 실행 이후 변경된 내용에 영향을 받는 테스트만 실행하여 테스트 시간을 크게 단축합니다. 이때 당사 <.localized_link href="/guides/features/projects/hashing">해싱 알고리즘</.localized_link>을 사용합니다. 샤딩이나 느린 테스트 수정 등 테스트 시간을 줄이는 다른 방법은 [느린 테스트](https://tuist.dev/solutions/slow-tests)를 참조하세요.

## 지원되는 빌드 시스템 {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

다른 빌드 시스템에 대한 지원도 계획되어 있습니다.
