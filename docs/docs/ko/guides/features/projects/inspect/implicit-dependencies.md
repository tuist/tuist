---
title: Implicit imports
titleTemplate: :title · Inspect · Projects · Develop · Guides · Tuist
description: Learn how to use Tuist to find implicit dependencies.
---

# 암시적 임포트 {#implicit-imports}

Apple은 순수 Xcode 프로젝트의 그래프 관리 복잡성을 줄이기 위해, 의존성을 암시적으로 정의할 수 있는 방식으로 빌드 시스템을 설계했습니다. 이는 앱과 같은 프로덕트가 의존성을 명시적으로 선언하지 않아도 프레임워크에 의존성을 가질 수 있다는 뜻입니다. 소규모 프로젝트에서는 문제없을 수 있지만, 프로젝트 그래프의 복잡성이 증가함에 따라 이러한 암시적인 방식 때문에 증분 빌드가 불안정해지거나 프리뷰, 코드 자동완성 같은 에디터 기능이 제대로 작동하지 않을 수 있습니다.

문제는 이러한 암시적 의존성의 발생을 막을 방법이 없다는 것입니다. 어떤 개발자든 `import`문을 Swift 코드에 추가할 수 있으며, 이를 통해 암시적 의존성이 생성되기 때문입니다. 이때 Tuist가 등장합니다. Tuist는 프로젝트 내 코드를 정적 분석하여 암시적 의존성을 검사할 수 있는 명령어를 제공합니다. 다음 명령어는 프로젝트의 암시적 종속성을 출력합니다:

```bash
tuist inspect implicit-imports
```

해당 명령어가 암시적 임포트를 발견할 경우, 0이 아닌 종료 코드와 함께 종료됩니다.

> [!TIP] CI에서의 검증
> 새로운 코드가 upstream으로 push될 때마다 이 명령어를 <LocalizedLink href="/guides/features/automate/continuous-integration">CI(continuous intergration)</LocalizedLink> 명령의 일부로 실행할 것을 강력히 권장합니다.

> [!IMPORTANT] 모든 암시적 경우가 감지되는 것은 아닙니다.
> Tuist는 암시적 의존성을 감지하기 위해 정적 코드 분석에 의존하므로, 모든 경우를 찾아내지 못할 수 있습니다. 예를 들어, Tuist는 코드에서 컴파일러 지시문(compiler directives)을 통한 조건부 임포트(conditional imports)를 이해할 수 없습니다.
