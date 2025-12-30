---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# 메타데이터 태그 {#metadata-tags}

프로젝트의 규모가 커지고 복잡해지면 전체 코드베이스를 한 번에 작업하는 것이 비효율적일 수 있습니다. 튜이스트는 개발 중에 대상을 논리적인
그룹으로 구성하고 프로젝트의 특정 부분에 집중할 수 있는 방법으로 **메타데이터 태그(** )를 제공합니다.

## 메타데이터 태그란 무엇인가요? {#what-are-metadata-tags}

메타데이터 태그는 프로젝트의 대상에 첨부할 수 있는 문자열 레이블입니다. 메타데이터 태그는 마커 역할을 합니다:

- **관련 대상 그룹화** - 동일한 기능, 팀 또는 아키텍처 계층에 속한 대상에 태그를 지정합니다.
- **작업 공간 집중하기** - 특정 태그가 있는 대상만 포함하는 프로젝트 생성
- **워크플로 최적화** - 코드베이스의 관련 없는 부분을 로드하지 않고 특정 기능에 대해 작업하세요.
- **소스로 유지할 대상 선택** - 캐싱할 때 소스로 유지할 대상 그룹을 선택합니다.

태그는 대상의 `메타데이터` 속성을 사용하여 정의되며 문자열 배열로 저장됩니다.

## 메타데이터 태그 정의 {#defining-metadata-tags}

프로젝트 매니페스트의 모든 대상에 태그를 추가할 수 있습니다:

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

## 태그된 타겟에 집중 {#focusing-on-tagged-targets}

대상에 태그를 지정한 후에는 `tuist generate` 명령을 사용하여 특정 대상만 포함된 집중 프로젝트를 만들 수 있습니다:

### 태그별 집중

`태그:` 접두사를 사용하여 특정 태그와 일치하는 모든 대상이 포함된 프로젝트를 생성합니다:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### 이름으로 초점 맞추기

이름별로 특정 대상에 집중할 수도 있습니다:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### 포커스 작동 방식

목표에 집중할 때

1. **포함된 타겟** - 쿼리와 일치하는 타겟이 생성된 프로젝트에 포함됩니다.
2. **종속성** - 초점이 맞춰진 대상의 모든 종속성이 자동으로 포함됩니다.
3. **테스트 대상** - 집중 대상에 대한 테스트 대상이 포함되어 있습니다.
4. **제외** - 다른 모든 대상은 워크스페이스에서 제외됩니다.

즉, 기능 작업에 필요한 항목만 포함된 더 작고 관리하기 쉬운 작업 공간을 확보할 수 있습니다.

## 태그 명명 규칙 {#tag-naming-conventions}

어떤 문자열이든 태그로 사용할 수 있지만, 일관된 명명 규칙을 따르면 태그를 체계적으로 정리하는 데 도움이 됩니다:

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

`feature:`, `team:`, `layer:` 와 같은 접두사를 사용하면 각 태그의 목적을 더 쉽게 이해하고 이름 충돌을 피할 수
있습니다.

## 프로젝트 설명 도우미와 함께 태그 사용 {#using-tags-with-helpers}

<LocalizedLink href="/guides/features/projects/code-sharing">프로젝트 설명 도우미</LocalizedLink>를 활용하여 프로젝트 전체에 태그가 적용되는 방식을 표준화할 수 있습니다:

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

그런 다음 적하 목록에 사용하세요:

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

### 향상된 개발 환경

프로젝트의 특정 부분에 집중하면 됩니다:

- **Xcode 프로젝트 크기 줄이기** - 더 빠르게 열고 탐색할 수 있는 작은 프로젝트로 작업하세요.
- **빌드 속도 향상** - 현재 작업에 필요한 것만 빌드하세요.
- **집중력 향상** - 관련 없는 코드로 인한 방해 방지
- **인덱싱 최적화** - Xcode가 더 적은 코드를 인덱싱하여 자동 완성 속도를 높입니다.

### 더 나은 프로젝트 구성

태그는 코드베이스를 유연하게 구성할 수 있는 방법을 제공합니다:

- **여러 차원** - 기능, 팀, 계층, 플랫폼 또는 기타 차원별로 대상에 태그 지정하기
- **구조 변경 없음** - 디렉토리 레이아웃을 변경하지 않고 조직 구조 추가
- **크로스 커팅 문제** - 단일 대상이 여러 논리 그룹에 속할 수 있습니다.

### 캐싱과 통합

메타데이터 태그는 <LocalizedLink href="/guides/features/cache">Tuist의 캐싱 기능</LocalizedLink>과 원활하게 작동합니다:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## 모범 사례 {#best-practices}

1. **간단하게 시작** - 단일 태그 지정 차원(예: 기능)으로 시작하여 필요에 따라 확장합니다.
2. **일관성 유지** - 모든 적하목록에 동일한 명명 규칙을 사용합니다.
3. **태그 문서화** - 사용 가능한 태그 목록과 그 의미를 프로젝트 문서에 보관하세요.
4. **헬퍼 사용** - 프로젝트 설명 헬퍼를 활용하여 태그 적용을 표준화하세요.
5. **주기적으로 검토** - 프로젝트가 발전함에 따라 태그 지정 전략을 검토하고 업데이트하세요.

## 관련 기능 {#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">코드 공유</LocalizedLink> - 프로젝트 설명 도우미를 사용하여 태그 사용 표준화하기
- <LocalizedLink href="/guides/features/cache">캐시</LocalizedLink> - 최적의 빌드 성능을
  위해 태그와 캐싱을 결합하세요.
- <LocalizedLink href="/guides/features/selective-testing">선택적 테스트</LocalizedLink> - 변경된 대상에 대해서만 테스트 실행
