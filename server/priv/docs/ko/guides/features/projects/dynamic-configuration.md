---
{
  "title": "동적 구성",
  "titleTemplate": ":title · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "환경 변수를 사용하여 프로젝트를 동적으로 구성하는 방법을 알아보세요."
}
---
# 동적 구성 {#dynamic-configuration}

프로젝트 생성 시점에 동적으로 구성해야 하는 경우가 있습니다. 예를 들어, 프로젝트가 생성되는 환경에 따라 앱 이름, 번들 식별자 또는 배포 대상을 변경할 수 있습니다. Tuist는 매니페스트 파일에서 접근할 수 있는 환경 변수를 통해 이를 지원합니다.

## 환경 변수를 통한 구성 {#configuration-through-environment-variables}

Tuist는 매니페스트 파일에서 접근할 수 있는 환경 변수를 통해 구성 값을 전달할 수 있게 해줍니다. 예를 들면 다음과 같습니다:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

여러 환경 변수를 전달하려면 공백으로 구분하면 됩니다. 예를 들면 다음과 같습니다:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## 매니페스트에서 환경 변수 읽기 {#reading-the-environment-variables-from-manifests}

변수는 [`Environment`](https://projectdescription.tuist.dev/documentation/projectdescription/environment) 타입을 사용해 접근할 수 있습니다. 환경에서 정의되거나 명령 실행 시 Tuist에 전달된 `TUIST_XXX` 규칙을 따르는 모든 변수는 `Environment` 타입을 사용해 접근할 수 있습니다. 다음 예시는 `TUIST_APP_NAME` 변수에 접근하는 방법을 보여줍니다:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

변수에 접근하면 `Environment.Value?` 타입의 인스턴스를 반환하며, 이는 다음 값 중 하나를 가질 수 있습니다:

| 케이스 | 설명 |
| --- | --- |
| `.string(String)` | 변수가 문자열을 나타낼 때 사용됩니다. |

아래에 정의된 헬퍼 메서드 중 하나를 사용하여 문자열 또는 불리언 `Environment` 변수를 가져올 수도 있습니다. 이러한 메서드는 사용자가 매번 일관된 결과를 얻을 수 있도록 기본값을 전달해야 합니다. 이렇게 하면 위에서 정의한 appName() 함수를 별도로 정의할 필요가 없습니다.

::: code-group

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::

## 매니페스트로 추가 환경 변수 전달하기 {#forwarding-additional-environment-variables-to-manifests}

기본적으로 `TUIST_` 접두사가 붙은 변수와 `CI`, `DEVELOPER_DIR`만 `Project.swift`, `Workspace.swift`, `Package.swift` 및 프로젝트 설명 헬퍼를 평가하는 하위 프로세스로 전달됩니다. 이로 인해 생성 과정이 결정적으로 유지되며, 관련 없는 셸 또는 CI 변수가 매니페스트 캐시를 무효화하는 것을 방지합니다.

매니페스트가 제어 범위에 있지 않은 변수를 읽어야 할 때(예: 이미 `OPENSWIFTUI_LIBRARY_TYPE`를 읽는 서드파티 `Package.swift`)에는 생성 옵션의 `manifestEnvironment`를 통해 `Tuist.swift`에 해당 변수를 선언하세요. 각 항목은 리터럴 이름이거나, 접두사 매칭을 위해 `*`로 끝나는 이름입니다:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            manifestEnvironment: [
                "OPENSWIFTUI_*",
                "MY_VAR",
            ]
        )
    )
)
```

목록에 포함된 변수는 매니페스트 캐시 해시에 포함되므로, 값이 변경되면 예상대로 캐시가 무효화됩니다. 목록에 포함되지 않은 변수는 매니페스트 평가에서 숨겨진 상태로 유지됩니다.
