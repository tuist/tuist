---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# 레지스트리 {#registry}

종속성의 수가 늘어날수록 종속성을 해결하는 데 걸리는 시간도 늘어납니다. 코코아팟](https://cocoapods.org/)이나
[npm](https://www.npmjs.com/)과 같은 다른 패키지 관리자는 중앙 집중식이지만, Swift 패키지 관리자는 그렇지
않습니다. 따라서 SwiftPM은 각 저장소의 딥 클론을 수행하여 종속성을 해결해야 하는데, 이는 중앙 집중식 접근 방식보다 시간이 오래 걸리고
메모리를 더 많이 차지할 수 있습니다. 이 문제를 해결하기 위해 Tuist는 [패키지
레지스트리](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)
구현을 제공하므로 _실제로 필요한 커밋만 다운로드할 수 있습니다_. 레지스트리의 패키지는 [Swift 패키지
색인](https://swiftpackageindex.com/)을 기반으로 합니다. - 에서 패키지를 찾을 수 있는 경우 해당 패키지는 튜이스트
레지스트리에서도 사용할 수 있습니다. 또한 패키지를 확인할 때 지연 시간을 최소화하기 위해 에지 스토리지를 사용하여 전 세계에 패키지를
배포합니다.

## 사용량 {#usage}

레지스트리를 설정하려면 프로젝트의 디렉터리에서 다음 명령을 실행합니다:

```bash
tuist registry setup
```

이 명령은 프로젝트의 레지스트리를 활성화하는 레지스트리 구성 파일을 생성합니다. 팀도 레지스트리를 활용할 수 있도록 이 파일을 커밋해야 합니다.

### 인증(선택 사항) {#authentication}

인증은 **선택 사항** 입니다. 인증하지 않으면 IP 주소당 **분당 요청 수 1,000건** 의 속도 제한으로 레지스트리를 사용할 수
있습니다. 더 높은 속도 제한인 **분당 20,000 요청** 을 실행하여 인증할 수 있습니다:

```bash
tuist registry login
```

::: info Mise란?
<!-- -->
인증하려면 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 계정과 프로젝트</LocalizedLink>가 필요합니다.
<!-- -->
:::

### 종속성 해결 {#resolving-dependencies}

소스 컨트롤 대신 레지스트리에서 종속성을 해결하려면 프로젝트 설정에 따라 계속 읽으세요:
- <LocalizedLink href="/guides/features/registry/xcode-project">Xcode 프로젝트</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">Xcode 패키지 통합으로 생성된 프로젝트</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">XcodeProj 기반 패키지 통합으로 생성된 프로젝트</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">Swift 패키지</LocalizedLink>

CI에서 레지스트리를 설정하려면 이 가이드를 따르세요:
<LocalizedLink href="/guides/features/registry/continuous-integration">연속 통합</LocalizedLink>.

### 패키지 레지스트리 식별자 {#package-registry-identifiers}

`Package.swift` 또는 `Project.swift` 파일에서 패키지 레지스트리 식별자를 사용하는 경우 패키지의 URL을 레지스트리
규칙에 맞게 변환해야 합니다. 레지스트리 식별자는 항상 `{조직}.{저장소}` 형식입니다. 예를 들어
`https://github.com/pointfreeco/swift-composable-architecture` 패키지에 대한 레지스트리를
사용하려면 패키지 레지스트리 식별자는 `pointfreeco.swift-composable-architecture` 입니다.

::: info Mise란?
<!-- -->
식별자는 점을 두 개 이상 포함할 수 없습니다. 리포지토리 이름에 점이 포함되어 있으면 밑줄로 대체됩니다. 예를 들어
`https://github.com/groue/GRDB.swift` 패키지는 레지스트리 식별자 `groue.GRDB_swift` 를 갖습니다.
<!-- -->
:::
