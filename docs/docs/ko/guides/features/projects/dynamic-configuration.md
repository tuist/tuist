---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# 동적 구성 {#dynamic-configuration}

생성 시 프로젝트를 동적으로 구성해야 하는 특정 시나리오가 있을 수 있습니다. 예를 들어 프로젝트가 생성되는 환경에 따라 앱의 이름, 번들
식별자 또는 배포 대상을 변경하고 싶을 수 있습니다. Tuist는 매니페스트 파일에서 액세스할 수 있는 환경 변수를 통해 이를 지원합니다.

## 환경 변수를 통한 구성 {#configuration-through-environment-variables}

Tuist에서는 매니페스트 파일에서 액세스할 수 있는 환경 변수를 통해 구성을 전달할 수 있습니다. 예를 들어

```bash
TUIST_APP_NAME=MyApp tuist generate
```

여러 환경 변수를 전달하려면 공백으로 구분하면 됩니다. 예를 들어

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## 매니페스트에서 환경 변수 읽기 {#reading-the-environment-variables-from-manifests}

변수는
<LocalizedLink href="/references/project-description/enums/environment">`환경`</LocalizedLink>
유형을 사용하여 액세스할 수 있습니다. 환경에 정의되어 있거나 명령 실행 시 Tuist에 전달된 `TUIST_XXX` 규칙을 따르는 모든 변수는
`환경` 유형을 사용하여 액세스할 수 있습니다. 다음 예는 `TUIST_APP_NAME` 변수에 액세스하는 방법을 보여줍니다:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

변수에 액세스하면 다음 값 중 하나를 취할 수 있는 `Environment.Value?` 유형의 인스턴스가 반환됩니다:

| 케이스            | 설명                    |
| -------------- | --------------------- |
| `.string(문자열)` | 변수가 문자열을 나타낼 때 사용합니다. |

아래에 정의된 도우미 메서드 중 하나를 사용하여 문자열 또는 부울 `환경` 변수를 검색할 수도 있으며, 이러한 메서드에는 사용자가 매번 일관된
결과를 얻을 수 있도록 기본값을 전달해야 합니다. 이렇게 하면 위에 정의된 appName() 함수를 정의할 필요가 없습니다.

::: code-group

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
