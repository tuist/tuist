---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Develop · Guides · Tuist",
  "description": "프로젝트를 동적 구성하기 위해 환경 변수를 사용하는 방법을 배워봅니다."
}
---
# Dynamic configuration {#dynamic-configuration}

프로젝트 생성 시점에 프로젝트를 동적으로 구성 해야하는 경우가 있습니다. 예를 들어, 프로젝트가 생성되는 환경에 따라 앱 이름, 번들 식별자, 또는 배포 타겟을 변경해야 되는 경우가 있습니다. Tuist는 매니페스트 파일에서 접근될 수 있는 환경 변수를 통해 동적 구성을 지원합니다.

## 환경 변수를 통한 구성 {#configuration-through-environment-variables}

Tuist는 매니페스트 파일에서 접근될 수 있는 환경 변수를 통해 구성을 전달합니다. 예를 들어:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

여러 환경 변수를 전달하려면 공백으로 구분해서 전달하면 됩니다. 예를 들어:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## 매니페스트에서 환경 변수 읽기 {#reading-the-environment-variables-from-manifests}

변수는 <LocalizedLink href="/references/project-description/enums/environment">`Environment`</LocalizedLink> 타입을 사용하여 접근할 수 있습니다. `TUIST_XXX` 형식으로 환경에 정의되거나 명령어 수행 시 Tuist에 전달되면 `Environment` 타입을 사용하여 접근할 수 있습니다. 다음의 예제는 `TUIST_APP_NAME` 변수에 어떻게 접근하는지 보여줍니다:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

변수에 접근하면 다음의 값 중에 하나인 `Environment.Value?` 타입의 인스턴스를 반환합니다:

| Case              | Description                           |
| ----------------- | ------------------------------------- |
| `.string(String)` | 변수가 문자열을 나타낼 때 사용됩니다. |

아래 정의된 메서드 중 하나를 사용하여 문자열 또는 불리언 `Environment` 변수를 가져올 수 있으며, 이 메서드는 매번 일관된 결과를 얻을 수 있도록 기본값을 전달해야 합니다. 이것은 위에 정의된 appName() 함수를 정의할 필요성을 없애줍니다.

::: code-group

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```

:::
