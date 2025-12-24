---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# 암시적 가져오기 {#implicit-imports}

원시 Xcode 프로젝트 그래프를 유지 관리할 때의 복잡성을 완화하기 위해 Apple은 종속성을 암시적으로 정의할 수 있는 방식으로 빌드
시스템을 설계했습니다. 즉, 앱과 같은 제품은 종속성을 명시적으로 선언하지 않더라도 프레임워크에 종속될 수 있습니다. 작은 규모에서는 괜찮지만
프로젝트 그래프가 복잡해지면 암시성이 불안정한 증분 빌드 또는 미리보기나 코드 완성 같은 에디터 기반 기능으로 나타날 수 있습니다.

문제는 암시적 종속성이 발생하는 것을 막을 수 없다는 것입니다. 모든 개발자는 Swift 코드에 `import` 문을 추가하면 암시적 종속성이
생성됩니다. 이때 Tuist가 등장합니다. Tuist는 프로젝트의 코드를 정적으로 분석하여 암시적 종속성을 검사하는 명령을 제공합니다. 다음
명령은 프로젝트의 암시적 종속성을 출력합니다:

```bash
tuist inspect implicit-imports
```

명령이 암시적 가져오기를 감지하면 0이 아닌 종료 코드를 사용하여 종료합니다.

::: tip VALIDATE IN CI
<!-- -->
새 코드가 업스트림에 푸시될 때마다 이 명령을
<LocalizedLink href="/guides/features/automate/continuous-integration">연속 통합</LocalizedLink> 명령의 일부로 실행하는 것을 강력히 권장합니다.
<!-- -->
:::

::: warning NOT ALL IMPLICIT CASES ARE DETECTED
<!-- -->
정적 코드 분석에 의존하여 암시적 종속성을 감지하기 때문에 모든 경우를 포착하지 못할 수도 있습니다. 예를 들어, 코드의 컴파일러 지시문을 통한
조건부 가져오기는 Tuist가 이해하지 못합니다.
<!-- -->
:::
