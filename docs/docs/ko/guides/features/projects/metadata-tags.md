---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# 메타데이터 태그 {#metadata-tags}

프로젝트의 규모와 복잡성이 커짐에 따라 전체 코드를 한 번에 다루는 것은 비효율적일 수 있습니다. Tuist는 Target을 논리적인 그룹으로
구성하고 개발 과정에서 프로젝트의 특정 부분에 집중할 수 있는 방법으로 **metadata tags**를 제공합니다.

## 메타데이터 태그란 무엇인가요? {#what-are-metadata-tags}

메타데이터 태그는 프로젝트의 Target에 부착할 수 있는 문자열 레이블입니다. 이 태그는 다음과 같은 기능을 수행하는 마커 역할을 합니다:

- **관련 Target 그룹화** - 동일한 기능, 팀 또는 아키텍처 계층에 속하는 Target에 태그 지정
- **워크스페이스에 집중하기** - 특정 태그가 지정된 대상만 포함하는 프로젝트 생성하기
- **워크플로우 최적화** - 코드의 관련 없는 부분을 불러오지 않고 특정 기능 작업 수행
- **소스로 유지할 Target을 선택** - 캐싱 할 때 소스로 유지할 Target 그룹 선택

태그는 대상의 `메타데이터` 속성을 사용하여 정의되며 문자열 배열로 저장됩니다.

## 메타데이터 태그 정의 {#defining-metadata-tags}

프로젝트 매니페스트의 모든 Target에 태그를 추가할 수 있습니다:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "Authentication",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.authentication",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:auth", "team:identity"])
        ),
        .target(
            name: "Payment",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.payment",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:payment", "team:commerce"])
        ),
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "com.example.app",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "Authentication"),
                .target(name: "Payment")
            ]
        )
    ]
)
```

## 태그된 Target에 집중하기 {#focusing-on-tagged-targets}

Target에 태그를 지정하면 `tuist generate` 명령어를 사용하여 특정 Target만 포함된 프로젝트를 생성할 수 있습니다:

### 태그별 집중

`tag:` 접두사를 사용하여 특정 태그와 일치하는 모든 Target을 가진 프로젝트를 생성하세요:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### 이름으로 모으기

특정 Target의 이름을 지정하여 모을 수도 있습니다:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### 모으기 작동 방식

Target으로 모을 때:

1. **포함된 Target** - 검색어와 일치하는 Target이 생성된 프로젝트에 포함됩니다
2. **의존성** - 모으는 Target의 모든 의존성이 자동으로 포함됩니다
3. **테스트 Target** - 모으는 Target에 대한 테스트 Target이 포함됨
4. **제외** - 워크스페이스에서 다른 모든 Target은 제외됩니다

이는 기능 작업에 필요한 요소만 포함된 더 작고 관리하기 쉬운 작업 공간을 의미합니다.

## 태그 명명 규칙 {#tag-naming-conventions}

태그로 어떤 문자열이든 사용할 수 있지만, 일관된 명명 규칙을 따르면 태그를 체계적으로 관리하는 데 도움이 됩니다:

```swift
// Organize by feature
metadata: .metadata(tags: ["feature:authentication", "feature:payment"])

// Organize by team ownership
metadata: .metadata(tags: ["team:identity", "team:commerce"])

// Organize by architectural layer
metadata: .metadata(tags: ["layer:ui", "layer:business", "layer:data"])

// Organize by platform
metadata: .metadata(tags: ["platform:ios", "platform:macos"])

// Combine multiple dimensions
metadata: .metadata(tags: ["feature:auth", "team:identity", "layer:ui"])
```

`와 같은 접두사를 사용하면: feature:`, `team:`, 또는 `layer:` 각 태그의 목적을 쉽게 이해하고 이름 충돌을 피할 수
있습니다.

## 시스템 태그 {#system-tags}

Tuist는 시스템 관리 태그에 `tuist:` 접두사를 사용합니다. 이러한 태그는 Tuist에 의해 자동으로 적용되며, 생성된 콘텐츠의 특정
유형을 대상으로 하는 캐시 프로필에서 사용할 수 있습니다.

### 사용 가능한 시스템 태그

| 태그                  | 설명                                                                                                       |
| ------------------- | -------------------------------------------------------------------------------------------------------- |
| `tuist:synthesized` | Tuist가 정적 라이브러리 및 정적 프레임워크의 리소스 처리를 위해 생성하는 합성 번들 타깃에 적용됩니다. 이러한 번들은 리소스 액세서 API를 제공하기 위한 역사적 이유로 존재합니다. |

### 캐시 프로필과 함께 시스템 태그 사용하기

캐시 프로필에서 시스템 태그를 사용하여 합성된 대상을 포함하거나 제외할 수 있습니다:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            profiles: .profiles(
                [
                    "development": .profile(
                        .onlyExternal,
                        and: ["tag:tuist:synthesized"]  // Also cache synthesized bundles
                    )
                ],
                default: .onlyExternal
            )
        )
    )
)
```

::: tip SYNTHESIZED BUNDLES INHERIT PARENT TAGS
<!-- -->
합성된 번들 타깃은 부모 타깃의 모든 태그를 상속하며, 여기에 `tuist:synthesized` 태그가 추가됩니다. 즉, 정적 라이브러리에
`feature:auth` 태그를 지정하면, 해당 라이브러리의 합성된 리소스 번들에는 `feature:auth` 태그와
`tuist:synthesized` 태그가 모두 포함됩니다.
<!-- -->
:::

## 프로젝트 설명 도우미와 함께 태그 사용하기 {#using-tags-with-helpers}

<LocalizedLink href="/guides/features/projects/code-sharing">프로젝트 설명
헬퍼</LocalizedLink>를 활용하여 프로젝트 전반에 걸쳐 태그 적용 방식을 표준화할 수 있습니다:

```swift
// Tuist/ProjectDescriptionHelpers/Project+Templates.swift
import ProjectDescription

extension Target {
    public static func feature(
        name: String,
        team: String,
        dependencies: [TargetDependency] = []
    ) -> Target {
        .target(
            name: name,
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.\(name.lowercased())",
            sources: ["Sources/**"],
            dependencies: dependencies,
            metadata: .metadata(tags: [
                "feature:\(name.lowercased())",
                "team:\(team.lowercased())"
            ])
        )
    }
}
```

그런 다음 매니페스트에서 사용하세요:

```swift
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "Features",
    targets: [
        .feature(name: "Authentication", team: "Identity"),
        .feature(name: "Payment", team: "Commerce"),
    ]
)
```

## 메타데이터 태그 사용의 이점 {#benefits}

### 개발 환경 개선

프로젝트의 특정 부분에 집중함으로써 다음과 같은 효과를 얻을 수 있습니다:

- **Xcode 프로젝트 크기 줄이기** - 더 빠르게 열고 탐색할 수 있는 작은 프로젝트로 작업하세요
- **빌드 속도 향상** - 현재 작업에 필요한 부분만 빌드하세요
- **집중력 향상** - 관련 없는 코드로 인한 주의 분산 방지
- **인덱싱 최적화** - Xcode가 인덱싱하는 코드 양이 줄어들어 자동 완성 속도가 빨라집니다

### 더 나은 프로젝트 구성

태그는 코드베이스를 유연하게 구성하는 방법을 제공합니다:

- **다중 차원** - 기능, 팀, 계층, 플랫폼 또는 기타 차원으로 태그 대상 지정
- **구조 변경 금지** - 디렉토리 레이아웃 변경 없이 조직 구조 추가
- **횡단 관심사** - 단일 대상이 여러 논리적 그룹에 속할 수 있음

### 캐싱과의 통합

메타데이터 태그는 <LocalizedLink href="/guides/features/cache">Tuist의 캐싱
기능</LocalizedLink>과 완벽하게 연동됩니다:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## 모범 사례 {#best-practices}

1. **간단하게 시작하세요** - 단일 태깅 차원(예: 기능)으로 시작하여 필요에 따라 확장하세요
2. **일관성을 유지하세요** - 모든 매니페스트에서 동일한 명명 규칙을 사용하세요
3. **태그 문서화** - 프로젝트 문서에 사용 가능한 태그 목록과 그 의미를 기록하세요
4. **헬퍼 사용** - 태그 적용을 표준화하기 위해 프로젝트 설명 헬퍼 활용
5. **주기적으로 검토하세요** - 프로젝트가 발전함에 따라 태깅 전략을 검토하고 업데이트하세요

## 관련 기능 {#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">코드
  공유</LocalizedLink> - 태그 사용을 표준화하기 위해 프로젝트 설명 도우미를 사용하십시오
- <LocalizedLink href="/guides/features/cache">Cache</LocalizedLink> - 최적의 빌드
  성능을 위해 태그를 캐싱과 결합하십시오
- <LocalizedLink href="/guides/features/selective-testing">선택적
  테스트</LocalizedLink> - 변경된 대상에 대해서만 테스트 실행
