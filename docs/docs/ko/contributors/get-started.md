---
{
  "title": "Get started",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Get started contributing to Tuist by following this guide."
}
---
# 시작하기 {#get-started}

iOS와 같은 Apple 플랫폼용 앱을 개발한 경험이 있다면 Tuist에 코드를 추가하는 것이 크게 다르지 않을 것입니다. 하지만 앱 개발과
비교했을 때 두 가지 차이점이 있습니다:

- **CLI와의 상호작용은 터미널을 통해 이루어집니다.** 사용자는 원하는 작업을 수행하는 Tuist를 실행한 다음 성공 또는 상태 코드와
  함께 반환합니다. 실행 중에 사용자에게 표준 출력 및 표준 오류에 대한 출력 정보를 전송하여 알림을 받을 수 있습니다. 제스처나 그래픽
  상호작용 없이 사용자의 의도만 전달합니다.

- **앱이 시스템 또는 사용자 이벤트를 수신할 때 iOS 앱에서 발생하는 것처럼 입력을 기다리며 프로세스를 유지하는 런루프(**)가 없습니다.
  CLI는 해당 프로세스에서 실행되며 작업이 완료되면 완료됩니다. 비동기 작업은
  [DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue)
  또는 [구조화된
  동시성](https://developer.apple.com/tutorials/app-dev-training/managing-structured-concurrency)과
  같은 시스템 API를 사용하여 수행할 수 있지만 비동기 작업이 실행되는 동안 프로세스가 실행되고 있는지 확인해야 합니다. 그렇지 않으면
  프로세스가 비동기 작업을 종료합니다.

Swift를 사용해 본 경험이 없다면 [Apple의 공식 서적](https://docs.swift.org/swift-book/)을 통해 언어와
재단의 API에서 가장 많이 사용되는 요소에 익숙해지는 것을 추천합니다.

## 최소 요구 사항 {#minimum-requirements}

Tuist에 기여하기 위한 최소 요건은 다음과 같습니다:

- macOS 14.0+
- Xcode 16.3+

## 로컬에서 프로젝트 설정 {#set-up-the-project-locally}

프로젝트 작업을 시작하려면 아래 단계를 따르세요:

- 다음을 실행하여 리포지토리를 복제합니다: `git clone git@github.com:tuist/tuist.git`
- [설치](https://mise.jdx.dev/getting-started.html) 개발 환경을 프로비저닝합니다.
- `mise install` 을 실행하여 Tuist에 필요한 시스템 종속성을 설치합니다.
- `tuist install` 을 실행하여 Tuist에 필요한 외부 종속성을 설치합니다.
- (선택 사항) `tuist auth login` 을 실행하여
  <LocalizedLink href="/guides/features/cache">Tuist 캐시에 액세스합니다.</LocalizedLink>
- `tuist generate` 를 실행하여 Tuist 자체에서 Tuist Xcode 프로젝트를 생성합니다.

**생성된 프로젝트가 자동으로 열립니다**. 생성하지 않고 다시 열어야 하는 경우 `open Tuist.xcworkspace` (또는
Finder 사용)를 실행합니다.

> [!참고] XED . ` xed 를 사용하여 프로젝트를 열려고 하면`, Tuist에서 생성한 프로젝트가 아닌 패키지가 열립니다. 튜이스트에서
> 생성한 프로젝트를 사용하여 도구를 도그푸딩하는 것이 좋습니다.

## 프로젝트 편집 {#편집-프로젝트}

종속성을 추가하거나 대상을 조정하는 등 프로젝트를 편집해야 하는 경우
<LocalizedLink href="/guides/features/projects/editing">`tuist edit`
명령</LocalizedLink>을 사용할 수 있습니다. 이 명령은 거의 사용되지 않지만 이 명령이 있다는 것을 아는 것이 좋습니다.

## 튜이스트 실행 {#run-tuist}

### Xcode에서 {#from-xcode}로 보내기

생성된 Xcode 프로젝트에서 `tuist` 을 실행하려면 `tuist` 스키마를 편집하고 명령에 전달할 인수를 설정합니다. 예를 들어
`tuist generate` 명령을 실행하려면 인수를 `generate --no-open` 으로 설정하여 생성 후 프로젝트가 열리지 않도록 할
수 있습니다.

![Tuist로 생성 명령을 실행하기 위한 스키마 구성 예시](/images/contributors/scheme-arguments.png)

또한 작업 디렉터리를 생성 중인 프로젝트의 루트로 설정해야 합니다. 모든 명령이 허용하는 `--path` 인수를 사용하거나 아래 그림과 같이
체계에서 작업 디렉터리를 구성하여 설정할 수 있습니다:


![Tuist를 실행할 작업 디렉터리 설정 방법
예시](/images/contributors/scheme-working-directory.png)

> [!경고] 프로젝트 설명 컴파일 `tuist` CLI는 빌드된 제품 디렉터리에 `ProjectDescription` 프레임워크가 있는지
> 여부에 따라 달라집니다. ` ProjectDescription` 프레임워크를 찾을 수 없어 `tuist` 실행에 실패하는 경우 먼저
> `Tuist-Workspace` 체계를 빌드하세요.

### 터미널 {#에서 터미널}에서

`run` 명령을 통해 Tuist 자체를 사용하여 `tuist` 을 실행할 수 있습니다:

```bash
tuist run tuist generate --path /path/to/project --no-open
```

또는 Swift 패키지 관리자를 통해 직접 실행할 수도 있습니다:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
