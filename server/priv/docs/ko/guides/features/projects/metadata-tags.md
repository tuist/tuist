---
{
  "title": "메타데이터 태그",
  "titleTemplate": ":title · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "대상 메타데이터 태그를 사용하여 프로젝트의 특정 부분을 구성하고 집중하는 방법을 알아보세요"
}
---
# 메타데이터 태그 {#metadata-tags}

프로젝트의 규모와 복잡성이 커지면 전체 코드베이스를 한 번에 다루는 것은 비효율적일 수 있습니다. Tuist는 **메타데이터 태그**를 제공하여 타겟을 논리적 그룹으로 구성하고 개발 중 프로젝트의 특정 부분에 집중할 수 있도록 합니다.

## 메타데이터 태그란 무엇인가요? {#what-are-metadata-tags}

메타데이터 태그는 프로젝트의 타겟에 추가할 수 있는 문자열 라벨입니다. 이는 다음과 같은 작업을 가능하게 하는 마커 역할을 합니다:

- **관련된 타겟 그룹화** - 동일한 기능, 팀 또는 아키텍처 계층에 속하는 타겟에 태그 지정
- **워크스페이스 집중** - 특정 태그가 있는 타겟만 포함하는 프로젝트 생성
- **워크플로 최적화** - 관련 없는 코드베이스 부분을 로드하지 않고 특정 기능 작업
- **소스로 유지할 타겟 선택** - 캐싱 시 소스로 유지하려는 타겟 그룹 선택

태그는 타겟의 `metadata` 속성을 사용하여 정의되며 문자열 배열로 저장됩니다.

## 메타데이터 태그 정의 {#defining-metadata-tags}

프로젝트 매니페스트의 모든 타겟에 태그를 추가할 수 있습니다:

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

## 태그가 지정된 타겟에 집중하기 {#focusing-on-tagged-targets}

타겟에 태그를 지정한 후 `tuist generate` 명령어를 사용하여 특정 타겟만 포함하는 집중형 프로젝트를 생성할 수 있습니다:

### 태그로 집중

`tag:` 접두사를 사용하여 특정 태그와 일치하는 모든 타겟이 포함된 프로젝트를 생성합니다:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### 이름으로 집중

이름으로 특정 타겟에 집중할 수도 있습니다:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### 집중 방식

타겟에 집중할 때:

1. **포함된 타겟** - 쿼리와 일치하는 타겟이 생성된 프로젝트에 포함됨
2. **종속성** - 집중된 타겟의 모든 종속성이 자동으로 포함됨
3. **테스트 타겟** - 집중된 타겟의 테스트 타겟이 포함됨
4. **제외** - 다른 모든 타겟은 워크스페이스에서 제외됨

즉, 기능 작업에 필요한 것만 포함된 더 작고 관리하기 쉬운 워크스페이스를 얻게 됩니다.

## 태그 명명 규칙 {#tag-naming-conventions}

모든 문자열을 태그로 사용할 수 있지만, 일관된 명명 규칙을 따르면 태그를 체계적으로 관리하는 데 도움이 됩니다:

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

`feature:`, `team:` 또는 `layer:`과 같은 접두사를 사용하면 각 태그의 목적을 쉽게 이해하고 명명 충돌을 방지할 수 있습니다.

## 시스템 태그 {#system-tags}

Tuist는 시스템 관리 태그에 `tuist:` 접두사를 사용합니다. 이러한 태그는 Tuist에 의해 자동으로 적용되며 캐시 프로파일에서 특정 유형의 생성 콘텐츠를 대상으로 지정하는 데 사용할 수 있습니다.

### 사용 가능한 시스템 태그

| 태그 | 설명 |
| --- | --- |
| `tuist:synthesized` | 정적 라이브러리 및 정적 프레임워크에서 리소스 처리를 위해 Tuist가 생성한 합성 번들 타겟에 적용됩니다. 이러한 번들은 리소스 접근자 API를 제공하기 위해 역사적인 이유로 존재합니다. |

### 캐시 프로파일과 함께 시스템 태그 사용

캐시 프로파일에서 시스템 태그를 사용하여 합성 타겟을 포함하거나 제외할 수 있습니다:

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

> [!TIP]
> **합성 번들은 부모 태그를 상속합니다**
>
> 합성 번들 타겟은 `tuist:synthesized` 태그를 받는 것 외에도 부모 타겟의 모든 태그를 상속합니다. 즉, 정적 라이브러리에 `feature:auth` 태그를 지정하면 해당 합성 리소스 번들에 `feature:auth` 및 `tuist:synthesized` 태그가 모두 포함됩니다.


## 프로젝트 설명 헬퍼와 함께 태그 사용 {#using-tags-with-helpers}

<.localized_link href="/guides/features/projects/code-sharing">프로젝트 설명 헬퍼</.localized_link>를 활용하여 프로젝트 전반에 태그가 적용되는 방식을 표준화할 수 있습니다:

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

그런 다음 매니페스트에서 사용합니다:

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

### 향상된 개발 경험

프로젝트의 특정 부분에 집중하면 다음과 같은 이점을 얻을 수 있습니다:

- **Xcode 프로젝트 크기 축소** - 열기와 탐색이 더 빠른 작은 프로젝트로 작업
- **빌드 속도 향상** - 현재 작업에 필요한 것만 빌드
- **집중도 향상** - 관련 없는 코드로 인한 방해 요소 제거
- **인덱싱 최적화** - Xcode가 더 적은 코드를 인덱싱하여 자동 완성 속도가 빨라짐

### 더 나은 프로젝트 구성

태그는 코드베이스를 조직하는 유연한 방법을 제공합니다:

- **다양한 차원** - 기능, 팀, 레이어, 플랫폼 또는 기타 차원으로 타겟 태그 지정
- **구조 변경 없음** - 디렉터리 레이아웃을 변경하지 않고 조직 구조 추가
- **교차 관심사** - 단일 타겟이 여러 논리적 그룹에 속할 수 있음

### 캐싱과의 통합

메타데이터 태그는 <.localized_link href="/guides/features/cache">Tuist의 캐싱 기능</.localized_link>과 원활하게 연동됩니다:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## 모범 사례 {#best-practices}

1. **간단하게 시작** - 단일 태그 차원(예: 기능)으로 시작한 후 필요에 따라 확장
2. **일관성 유지** - 모든 매니페스트에서 동일한 명명 규칙 사용
3. **태그 문서화** - 프로젝트 문서에 사용 가능한 태그 목록과 그 의미를 기록
4. **헬퍼 활용** - 프로젝트 설명 헬퍼를 활용하여 태그 적용 표준화
5. **정기적 검토** - 프로젝트가 발전함에 따라 태그 전략을 검토하고 업데이트

## 관련 기능 {#related-features}

- <.localized_link href="/guides/features/projects/code-sharing">코드 공유</.localized_link> - 프로젝트 설명 헬퍼를 사용하여 태그 사용 표준화
- <.localized_link href="/guides/features/cache">캐시</.localized_link> - 태그와 캐싱을 결합하여 최적의 빌드 성능 달성
- <.localized_link href="/guides/features/selective-testing">선택적 테스팅</.localized_link> - 변경된 타겟에 대해서만 테스트 실행
