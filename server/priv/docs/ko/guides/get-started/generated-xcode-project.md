---
{
  "title": "생성된 Xcode 프로젝트",
  "titleTemplate": ":title · 시작하기 · 가이드 · Tuist",
  "description": "모듈식 Xcode 프로젝트를 선언형 Swift로 압축하고 그래프를 기반으로 모듈 캐싱, 선택적 테스팅, 패키지 레지스트리, 빌드 및 테스트 인사이트를 활용하세요."
}
---
# 생성된 Xcode 프로젝트 {#generated-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/generated-xcode-project
```

:::

Tuist가 Swift 매니페스트로부터 Xcode 프로젝트를 설명하고 생성하도록 하려면 이 경로를 따르세요. 생성된 프로젝트는 모듈식 Xcode 프로젝트의 복잡성을 그래프의 간결하고 선언적인 설명으로 압축합니다. 또한 모듈 캐시와 선택적 테스팅을 위한 필수 조건입니다.

아래 각 섹션은 현재 부족한 부분부터 시작하여 그 격차를 채우는 기능을 안내합니다.

## 사전 요구 사항

- Xcode가 설치된 macOS.
- <.localized_link href="/guides/install-tuist">Tuist 명령줄 인터페이스</.localized_link>.

## 프로젝트 생성

작동 방식을 가장 빠르게 확인하는 방법은 새 프로젝트를 만드는 것입니다. 빈 디렉토리에서 `tuist init`를 실행하고 **생성된 프로젝트 만들기**를 선택한 후, 플랫폼을 선택하고 이름을 확인합니다. затем 인증하고 프로젝트를 소유할 계정을 선택하세요.

```bash
mkdir MyApp && cd MyApp
tuist init
```

코딩 에이전트나 스크립트로 이를 수행하는 경우, 먼저 `tuist auth login`를 실행하세요(브라우저 흐름에서 Enter 키를 누르기를 기다립니다). 그런 다음 비대화형 형식을 사용하세요:

```bash
tuist init --build-system generated-xcode --name MyApp --platform ios --account <account>
```

init이 완료되면 `tuist generate`를 실행하세요. Tuist는 매니페스트 옆에 `.xcworkspace`를 작성하고 Xcode에서 엽니다. 타겟을 빌드하고 실행하세요. 시뮬레이터에서 예제 앱이 실행되는 것을 볼 수 있습니다.

이것이 "연결 + 생성" 상태입니다. 아래 내용은 모두 선택 사항이며 독립적입니다.

기존 앱을 이동하는 경우, 먼저 [Xcode 프로젝트 마이그레이션 가이드](https://tuist.dev/en/docs/guides/features/projects/adoption/migrate/xcode-project)를 사용하여 연결한 후, 돌아와서 문제에 맞는 섹션을 계속 진행하세요.

## 프로젝트 생성

`.xcodeproj`는 앱의 구조를 XML로 번들링합니다: 파일 참조, 빌드 단계, 타겟 종속성, 스킴 및 빌드 설정이 모두 동일한 트리에 존재하며, 그래프를 그래프로 추론하기 위한 기본 요소가 없습니다. 프로젝트가 커질수록 그 구조를 이해하기 어려워지며, Xcode는 변경 사항이 없을 때 해싱하여 작업을 건너뛰기 위한 안정적인 핸들을 도구에 제공하지 않습니다.

생성된 프로젝트는 그래프를 선언적 Swift로 압축합니다. `Project.swift`는 타겟, 종속성 및 리소스를 직접 설명하며, Tuist는 뒤에 있는 그래프의 안정적인 모델을 유지합니다. 이 모델이 아래 섹션을 가능하게 합니다: 모듈 캐싱은 이를 해싱하여 바이너리를 재사용하고, 선택적 테스팅은 입력이 변경되지 않은 테스트를 건너뛰기 위해 이를 해싱합니다.

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            sources: ["MyApp/Sources/**"],
            dependencies: []
        )
    ]
)
```

각 `tuist generate`는 매니페스트로부터 결정론적 워크스페이스를 생성합니다. `.xcodeproj` 및 `.xcworkspace`를 `.gitignore`에 추가하세요.

## 모듈 캐시

모듈식 Xcode 프로젝트를 처음부터 컴파일하는 것은 머신별 비용이 듭니다. 각 팀원과 각 CI 러너는 동일한 오브젝트 파일의 자체 복사본을 생성합니다. Xcode 컴파일레이션 캐시는 내부 루프를 단축시키지만 모든 타겟의 머신별 빌드를 제거하지 않으며, 전체 프레임워크를 미리 빌드된 바이너리로 대체할 수 없습니다.

모듈 캐시는 이를 수행합니다. 그래프의 모든 캐시 가능한 종속성(프레임워크, 라이브러리, 번들)을 한 번 빌드하고, 타겟 입력의 해시에 대해 결과 바이너리를 저장하며, 이후 생성 시 타겟을 해당 바이너리로 교체합니다. 변경되지 않은 모듈은 컴파일되지 않습니다:

```bash
tuist cache
```

첫 번째 실행은 모든 것을 컴파일하고 바이너리를 계정에 업로드합니다. 다음 `tuist generate`에서 변경되지 않은 종속성은 캐시된 바이너리로 대체되며, Xcode는 소스에서 컴파일하는 대신 `.xcframework`에 링크합니다.

## 선택적 테스팅

`xcodebuild test`는 변경 사항이 어떤 테스트에 영향을 미치는지 알지 못하므로, CI는 모든 푸시에서 전체 스위트 실행합니다. 스위트가 커짐에 따라 실제로 실행해야 하는 것과 실행되는 것 사이의 격차는 수 분에서 수십 분으로 늘어납니다.

선택적 테스팅은 마지막 성공적인 테스트 실행 이후 변경된 사항에 영향을 받는 테스트만 실행하며, 프로젝트 그래프와 모듈 캐시가 의존하는 동일한 해싱 알고리즘을 사용합니다:

```bash
tuist test
```

첫 번째 `tuist test`는 모든 것을 실행하고 타겟별 해시를 지속합니다. 이후 실행에서는 입력이 변경되지 않은 타겟을 건너뜁니다. `tuist test`를 CI에서 `xcodebuild test` 대신 사용하도록 이동하면 피드백이 수 분 대신 수 초 내에 도착합니다.

## 패키지 레지스트리

Swift Package Manager는 패키지가 레지스트리가 아닌 URL로 주소 지정되기 때문에 각 패키지의 git 기록을 깊이 복제하여 종속성을 해결합니다. 수십 개의 전달적 패키지가 있는 프로젝트에서는 깨끗한 체크아웃에서 해결에 수 분이 걸리며 모든 CI 작업에서 반복됩니다.

Tuist 패키지 레지스트리는 Swift Package Index가 추적하는 동일한 패키지를 제공하지만, 실제 레지스트리로 작동하므로 SwiftPM은 실제로 필요한 커밋만 가져옵니다. `Tuist.swift`에서 `registryEnabled: true`를 설정하여 한 번 활성화하세요:

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

다시 생성하세요. 패키지 해결 시간이 수 분에서 수 초로 줄어듭니다.

## 빌드 인사이트

Xcode는 로그와 빌드 보고서에 타겟별 빌드 지속 시간을 기록합니다. 둘 다 실행 간 또는 머신 간으로 집계되지 않으므로, 빌드 시간 회귀는 일반적으로 전체적으로 느려진 CI로만 나타납니다.

빌드 인사이트는 생성된 스킴에 대한 모든 빌드의 지속 시간과 단계 타이밍을 자동으로 기록합니다. 추가로 구성할 항목이 없습니다. 다음 `tuist generate` + 빌드 사이클 후에 대시보드의 **빌드** 탭을 엽니다.

## 테스트 인사이트

Xcode는 테스트별 결과를 한 번에 하나씩 보고합니다. 실제로 필요한 교차 실행 신호(불안정성 비율, 주별 지속 시간, 어떤 시뮬레이터 변형이 실패하는지)를 집계하지 않습니다.

테스트 인사이트는 생성된 스킴에 대한 모든 테스트의 결과와 지속 시간을 자동으로 기록하고 실행 간 결과를 상관관계로 분석합니다. 불안정한 테스트, 느린 테스트 및 실패는 대시보드의 **테스트** 탭에 표시됩니다. 불안정성이 누적되면 대시보드에서 격리하여 병합을 차단하지 않도록 하세요.

## 팀 함께 참여시키기

모듈 캐시와 선택적 테스팅은 모두가 동일한 공유 표면에 도달할 때 가장 큰 효과를 발휘합니다. 대시보드의 계정 설정에서 팀원을 조직에 초대하고, <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>(Google, Okta, Microsoft)을 설정하여 온보딩이 개인별 `tuist auth login`가 아닌 클릭 한 번으로 이루어지도록 하세요.
