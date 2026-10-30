---
{
  "title": "Swift",
  "titleTemplate": ":title · 패키지 레지스트리 · 기능 · 가이드 · Tuist",
  "description": "Tuist의 글로벌 캐시 네트워크를 기반으로 하는 Tuist Swift 패키지 레지스트리를 사용하여 Swift Package Manager 의존성 해결 속도를 몇 분에서 몇 초로 단축하세요."
}
---
# Swift Package Registry {#swift-package-registry}

의존성 개수가 늘어날수록 의존성을 해결하는 데 걸리는 시간도 증가합니다. [CocoaPods](https://cocoapods.org/)나 [npm](https://www.npmjs.com/)과 같은 다른 패키지 관리자는 중앙 집중식이지만, Swift Package Manager는 그렇지 않습니다. 따라서 SwiftPM은 각 리포지토리를 전체 복제(deep clone)하여 의존성을 해결해야 하며, 이 과정은 시간이 많이 소요되고 중앙 집중식 접근 방식보다 더 많은 메모리를 차지합니다. 이를 해결하기 위해 Tuist는 [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md) 구현을 제공하므로 _실제로 필요한_ 커밋만 다운로드할 수 있습니다. 레지스트리의 패키지는 [Swift Package Index](https://swiftpackageindex.com/)를 기반으로 합니다. 해당 인덱스에서 패키지를 찾을 수 있다면 Tuist Registry에서도 사용할 수 있습니다. 또한 패키지는 전 세계 엣지 스토리지를 통해 배포되어 의존성 해결 시 최소 지연 시간을 보장합니다.

## 사용 방법 {#usage}

레지스트리를 설정하는 두 가지 방법이 있습니다:

### 옵션 1: 생성 중 자동 설정(권장) {#automatic-setup}

Tuist를 사용하여 프로젝트를 생성하는 경우, `Tuist.swift` 구성에서 `registryEnabled` 옵션을 설정하여 레지스트리를 활성화할 수 있습니다:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

이 옵션을 사용하면 `tuist generate`가 워크스페이스에 레지스트리 구성 파일을 자동으로 생성합니다. 따라서 `tuist registry setup`를 별도로 실행할 필요가 없습니다.

> [!TIP]
> `registryEnabled`는 Tuist의 XcodeProj 기반 통합 대신 Xcode의 기본 Swift Package Manager 통합을 통해 의존성을 통합하는 프로젝트에도 레지스트리를 구성합니다. 다만 소스 제어 URL로 선언된 패키지를 레지스트리에서 해결하도록 Xcode를 구성하지는 않습니다. 이를 위해서는 각 머신에서 `tuist registry setup`를 한 번 실행해야 하며, 자세한 내용은 <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">소스 제어 패키지 해결</.localized_link>을 참조하세요.


### 옵션 2: 수동 설정 {#manual-setup}

레지스트리를 수동으로 설정하려면 프로젝트 디렉터리에서 다음 명령어를 실행하세요:

```bash
tuist registry setup
```

이 명령어는 프로젝트용 레지스트리를 활성화하는 레지스트리 구성 파일을 생성합니다. 팀원들도 레지스트리의 혜택을 받을 수 있도록 이 파일을 커밋하세요.

### 인증(선택 사항) {#authentication}

인증은 **선택 사항**입니다. 인증 없이도 IP 주소당 **분당 1,000회 요청**의 속도 제한으로 레지스트리를 사용할 수 있습니다. **분당 20,000회 요청**의 더 높은 속도 제한을 얻으려면 다음 명령어를 실행하여 인증하세요:

```bash
tuist registry login
```

> [!NOTE]
> 인증에는 <.localized_link href="/guides/server/accounts-and-projects">Tuist 계정 및 프로젝트</.localized_link>가 필요합니다.


### 의존성 해결 {#resolving-dependencies}

소스 제어가 아닌 레지스트리에서 의존성을 해결하려면 프로젝트 설정에 따라 다음 내용을 계속 읽으세요:
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

CI에서 레지스트리를 설정하려면 다음 가이드를 따르세요: <.localized_link href="/guides/features/package-registries/swift/continuous-integration">지속적 통합</.localized_link>.

### 패키지 레지스트리 식별자 {#package-registry-identifiers}

`Package.swift` 또는 `Project.swift` 파일에서 패키지 레지스트리 식별자를 사용할 때는 패키지 URL을 레지스트리 규칙에 맞게 변환해야 합니다. 레지스트리 식별자는 항상 `{organization}.{repository}` 형식입니다. 예를 들어 `https://github.com/pointfreeco/swift-composable-architecture` 패키지의 레지스트리를 사용하려면 패키지 레지스트리 식별자는 `pointfreeco.swift-composable-architecture`가 됩니다.

> [!NOTE]
> 식별자에는 점이 하나 이상 포함될 수 없습니다. 리포지토리 이름에 점이 있으면 밑줄로 대체됩니다. 예를 들어 `https://github.com/groue/GRDB.swift` 패키지의 레지스트리 식별자는 `groue.GRDB_swift`가 됩니다.
