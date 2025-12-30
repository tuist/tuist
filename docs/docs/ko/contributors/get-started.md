---
{
  "title": "Get started",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Get started contributing to Tuist by following this guide."
}
---
# 시작하기 {#get-started}

iOS 같은 Apple 플랫폼에서 앱을 경험한 경험이 있다면 Tuist에 코드를 추가하는 것도 크게 다르지 않지만, 앱을 개발하는 것과 비교 할
때 두 개의 큰 차이 점이 있습니다:

- **CLI와 상호작용은 터미널에서 이루어 집니다.** 사용자는 원하는 Task를 실행하고 성공이나 상태 코드를 반환하는 Tuist를 실행
  합니다. 실행하는 동안, 콘솔에 출력 되는 정보를 통해 알림을 받을 수 있습니다. 어떠한 제스쳐 기능이나 GUI도 없습니다, 오직 사용자의
  의지만 있습니다.

- **입력을 기다리는 어떤 프로세스도 없습니다**, iOS 앱에서 시스템이나 사용자 이벤트를 받을 때 처럼. CLI는 자체 프로세스를 실행하고
  작업이 끝나면 종료합니다. 비동기 작업은
  [DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue)나
  [structured
  concurrency](https://developer.apple.com/tutorials/app-dev-training/managing-structured-concurrency)
  같은 시스템 API를 통해 완료될 수 있지만, 비동기 작업이 수행되는 동안 프로세스가 동작하는지 확인해야 합니다. 아니면, 프로세스는 비동기
  작업을 끝낼 것 입니다.

Swift에 아무 경험이 없다면, 언어에 친숙해지기 위해 [Apple’s official
book](https://docs.swift.org/swift-book/)과 가장 많이 사용되는 Foundation API의 요소들을
추천합니다.

## 최소 요구사항 {#minimum-requirements}

Tuist에 기여하기 위한 최소 요구사항:

- macOS 14.0 이상 버전
- Xcode 16.3 이상 버전

## 프로젝트를 Local에 설치하세요 {#set-up-the-project-locally}

프로젝트에서 작업을 시작하기 위해 아래 단계를 따라할 수 있습니다:

- `git clone git@github.com:tuist/tuist.git`로 소스를 받으세요
- [Install](https://mise.jdx.dev/getting-started.html) 개발 환경을 맞추기 위한 Mise.
- Tuist에 필요한 의존성을 설치하기 위해 `mise install` 를 실행하세요
- Tuist에 필요한 외부 의존성을 설치하기 위해 `tuist install` 를 실행하세요
- (선택사항) <LocalizedLink href="/guides/features/cache">Tuist Cache에 접근하기 위해 `tuist auth login`를 실행하세요</LocalizedLink>
- Tuist Xcode 프로젝트를 Tuist 스스로 행성 하기 위해 `tuist generate` 를 실행하세요

**생성된 프로젝트는 자동으로 열립니다**. 생성하지 않고 다시 열고 싶으면 `open Tuist.xcworkspace` 를 실행하거나
Finder를 사용하세요.

::: XED 관련 .
<!-- -->
`xed .`를 사용한 프로젝트를 열려고 하면, Tuist로 생성된 프로젝트가 아니라 패키지를 열 겁니다. Tuist를 직접 사용해보려면
Tuist로 만든 프로젝트를 권장 합니다.
<!-- -->
:::

## 프로젝트 편집 {#edit-the-project}

의존성을 추가하거나 Target을 조정하는 등, 프로젝트를 수정해야 한다면,
<LocalizedLink href="/guides/features/projects/editing">`tuist edit` 명령을 사용할 수 있습니다</LocalizedLink>. 드물게 사용되지만 알아두면 좋습니다.

## Tuist 실행 {#run-tuist}

### Xcode에서 {#from-xcode}

생성된 Xcode 프로젝트에서 `tuist` 를 실행하려면, `tuist` scheme을 수정하고, 명령에 넘길 인수들을 설정하세요. 예를
들어`tuist generate` 명령을 실행할 때 프로젝트가 열리는 것을 방지 하기 위해, `generate --no-open` 인수를 넘길
수 있습니다.

![Tuist의 generate 명령을 실행하기 위한 Scheme 설정
예](/images/contributors/scheme-arguments.png)

또한 생성된 최상위 프로젝트에 작업 폴더를 설정 해야 할 것 입니다. 아니면 아래 처럼 `--path` 인수를 넘기 거나 Scheme에서 작업
폴더를 설정할 수 있습니다:


![Tuist를 실행하기 위한 작업 폴더 설정 예 ](/images/contributors/scheme-working-directory.png)

::: 경고 PROJECTDESCRIPTION 컴파일
<!-- -->
`tuist` CLI는 만들어진 products 폴더에 있는 `ProjectDescription` framework에 의존 합니다.
`ProjectDescription` framework가 없다고 `tuist`가 실행되지 않는다면, `Tuist-Workspace`
scheme을 먼저 빌드하세요.
<!-- -->
:::

### 터미널에서 {#from-the-terminal}

Tuist의 run 명령을 사용해서 `tuist` 를 자체적으로 실행할 수도 있습니다:

```bash
tuist run tuist generate --path /path/to/project --no-open
```

대신, Swift Package Manager를 직접적으로 실행할 수도 있습니다:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
