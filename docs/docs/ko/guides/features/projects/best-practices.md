---
{
  "title": "Best practices",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the best practices for working with Tuist and Xcode projects."
}
---
# 모범 사례 {#best-practices}

수년 동안 다양한 팀 및 프로젝트와 함께 작업하면서 저희는 Tuist 및 Xcode 프로젝트 작업 시 따를 것을 권장하는 일련의 모범 사례를
확인했습니다. 이러한 모범 사례는 필수 사항은 아니지만 유지 관리 및 확장이 용이한 방식으로 프로젝트를 구성하는 데 도움이 될 수 있습니다.

## Xcode {#xcode}

### 낙담 패턴 {#discouraged-patterns}

#### 원격 환경을 모델링하기 위한 구성 {#configurations-to-model-remote-environments}

많은 조직에서 빌드 구성을 사용하여 다양한 원격 환경을 모델링하지만(예: `디버그-프로덕션` 또는 `릴리스-캐너리`), 이 접근 방식에는 몇
가지 단점이 있습니다:

- **불일치:** 그래프 전체에 구성 불일치가 있는 경우 빌드 시스템에서 일부 대상에 대해 잘못된 구성을 사용할 수 있습니다.
- **복잡성:** 프로젝트는 추론하고 유지 관리하기 어려운 로컬 구성과 원격 환경의 긴 목록으로 끝날 수 있습니다.

빌드 구성은 다양한 빌드 설정을 구현하도록 설계되었으며, 프로젝트에 `디버그` 및 `릴리스` 이상의 기능이 필요한 경우는 거의 없습니다. 서로
다른 환경을 모델링해야 할 필요성은 다른 방식으로 달성할 수 있습니다:

- **디버그 빌드에서:** 앱 개발 시 액세스할 수 있어야 하는 모든 구성(예: 엔드포인트)을 앱에 포함시키고 런타임에 전환할 수 있습니다.
  전환은 스키마 실행 환경 변수를 사용하거나 앱 내의 UI를 사용하여 수행할 수 있습니다.
- **릴리스 빌드에서:** 릴리즈의 경우 릴리즈 빌드가 바인딩된 구성만 포함할 수 있으며 컴파일러 지시어를 사용하여 구성을 전환하는 런타임
  로직은 포함할 수 없습니다.

::: 정보 비표준 구성 Tuist는 비표준 구성을 지원하며 바닐라 Xcode 프로젝트에 비해 관리하기 쉽지만, 종속성 그래프 전체에서 구성이
일관되지 않으면 경고를 받게 됩니다. 이를 통해 빌드 안정성을 보장하고 구성 관련 문제를 방지할 수 있습니다.:::

## Generated projects

### 빌드 가능한 폴더

Tuist 4.62.0은 병합 충돌을 줄이기 위해 Xcode 16에 도입된 기능인 **빌드 가능한 폴더** (Xcode의 동기화된 그룹)에 대한
지원을 추가했습니다.

Tuist의 와일드카드 패턴(예: `Sources/**/*.swift`)은 이미 생성된 프로젝트에서 병합 충돌을 제거하지만, 빌드 가능한 폴더는
추가적인 이점을 제공합니다:

- **자동 동기화**: 프로젝트 구조가 파일 시스템과 동기화된 상태로 유지되므로 파일을 추가하거나 제거할 때 다시 생성할 필요가 없습니다.
- **AI 친화적인 워크플로**: 코딩 어시스턴트와 에이전트가 프로젝트 재생성 없이 코드베이스를 수정할 수 있습니다.
- **더 간단한 구성**: 명시적인 파일 목록 관리 대신 폴더 경로를 정의하세요.

보다 간소화된 개발 환경을 위해 기존의 `Target.sources` 및 `Target.resources` 속성 대신 빌드 가능한 폴더를
채택하는 것이 좋습니다.

:::코드 그룹

```swift [With buildable folders]
let target = Target(
  name: "App",
  buildableFolders: ["App/Sources", "App/Resources"]
)
```

```swift [Without buildable folders]
let target = Target(
  name: "App",
  sources: ["App/Sources/**"],
  resources: ["App/Resources/**"]
)
```
:::
