---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# 동적 구성 {#dynamic-configuration}

프로젝트 생성 시점에 설정을 동적으로 변경해야 하는 경우가 있습니다. 예를 들어, 프로젝트가 생성되는 환경에 따라 앱 이름, 번들 식별자 또는
배포 대상을 변경하고 싶을 수 있습니다. Tuist는 매니페스트 파일에서 접근 가능한 환경 변수를 통해 이를 지원합니다.

## 환경 변수를 통한 설정 {#configuration-through-environment-variables}

Tuist에서는 매니페스트 파일에서 접근할 수 있는 환경 변수를 통해 설정을 전달할 수 있습니다. 예:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

여러 환경 변수를 전달하려면 공백으로 구분하면 됩니다. 예:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## 매니페스트에서 환경 변수 읽기 {#reading-the-environment-variables-from-manifests}

변수는
<LocalizedLink href="/references/project-description/enums/environment">`Environment`</LocalizedLink>
Type으로 접근할 수 있습니다. 환경에서 정의되거나 명령 실행 시 Tuist에 전달된 `TUIST_XXX` 형식의 변수는
`Environment` Type으로 접근 가능합니다. 다음 예시는 `TUIST_APP_NAME` 변수에 접근하는 방법을 보여줍니다:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

변수에 접근하면 `Environment.Value?` Type의 객체가 반환되며, 다음 값 중 하나를 가질 수 있습니다:

| 값                 | 설명                    |
| ----------------- | --------------------- |
| `.string(String)` | 변수가 문자열을 나타낼 때 사용됩니다. |

아래 정의된 헬퍼 메서드 중 하나를 사용하여 문자열 또는 Bool `Environment` 변수를 가져올 수도 있습니다. `환경` 변수. 이
메서드들은 사용자가 매번 일관된 결과를 얻을 수 있도록 기본 값을 전달해야 합니다. 이렇게 하면 위에서 정의한 appName() 함수를 정의할
필요가 없습니다.

::: code-group

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
