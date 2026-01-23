---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# 암시적 Import {#implicit-imports}

Xcode 프로젝트 그래프를 원시 Xcode 프로젝트로 유지 관리하는 복잡성을 완화하기 위해, Apple은 빌드 시스템을 의존성을 암시적으로
정의할 수 있도록 설계했습니다. 이는 예를 들어 앱과 같은 Product가 의존성을 명시적으로 선언하지 않아도 프레임워크에 의존할 수 있음을
의미합니다. 소규모에서는 문제가 없지만, 프로젝트 그래프의 복잡성이 증가함에 따라 이러한 암시성은 신뢰할 수 없는 증분 빌드나 미리 보기 또는
코드 완성 같은 편집기 기반 기능으로 나타날 수 있습니다.

문제는 암시적 의존성을 발생하지 않도록 막을 수 없다는 점입니다. 개발자는 Swift 코드에 `import` 문장을 추가할 수 있으며, 이로
인해 암시적 종속성이 생성됩니다. 바로 여기서 Tuist가 필요합니다. Tuist는 프로젝트 내 코드를 정적 분석하여 암시적 종속성을 검사하는
명령어를 제공합니다. 다음 명령어는 프로젝트의 암시적 의존성을 출력합니다:

```bash
tuist inspect dependencies --only implicit
```

명령어가 암시적 임포트를 감지하면 0이 아닌 종료 코드로 종료됩니다.

::: tip CI에서 검사하기
<!-- -->
새로운 코드가 올라올 때마다 이 명령을
<LocalizedLink href="/guides/features/automate/continuous-integration">CI</LocalizedLink>
명령의 일부로 실행하는 것을 강력히 권장합니다.
<!-- -->
:::

::: warning 모든 암시적 import가 감지되지는 않음
<!-- -->
Tuist는 암시적 의존성을 탐지하기 위해 정적 코드 분석에 의존하므로 모든 경우를 포착하지 못할 수 있습니다. 예를 들어, Tuist는 코드
내 컴파일러 지시문을 통한 조건부 import를 이해하지 못합니다.
<!-- -->
:::
