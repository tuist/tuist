---
title: Get started
titleTemplate: :title · Contributors · Tuist
description: 다음 가이드를 통해 Tuist 기여를 시작합니다.
---

# Get started {#get-started}

iOS 처럼 Apple 플랫폼의 앱을 빌드해 본 경험이 있다면, Tuist 에 코드를 추가하는 것은 다르지 않습니다. 앱 개발과 비교해서 두 가지 차이점이 있습니다:

- **CLI와의 상호작용은 터미널을 통해 일어납니다.** 사용자가 원하는 작업을 Tuist로 실행하면 성공 또는 상태 코드를 반환합니다. 실행하는 동안 사용자는 동작 내용과 오류에 대한 정보를 확인할 수 있습니다. 제스처 또는 그래픽 상호작용은 없고, 사용자의 의도만 존재합니다.

- **입력을 기다리면서 프로세스를 활성 상태로 유지하는 런루프가 존재하지 않습니다.** 이것은 시스템 또는 사용자 이벤트를 수신할 때 iOS 앱과 유사합니다. CLI는 동일 프로세스로 실행되고 작업이 완료되면 종료됩니다. 비동기 작업은 [DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue) 또는 [structured concurrency](https://developer.apple.com/tutorials/app-dev-training/managing-structured-concurrency) 와 같은 시스템 API를 사용하여 수행할 수 있지만, 비동기 작업이 수행되는 동안 프로세스가 실행 중인지 확인해야 합니다. 그렇지 않으면, 프로세스는 비동기 작업을 종료합니다.

Swift에 대한 경험이 없다면, 언어와 Foundation API에서 자주 사용하는 요소에 대해 익숙해 지도록 [Apple’s official book](https://docs.swift.org/swift-book/)을 추천합니다.

## 최소 요구 사항 {#minimum-requirements}

Tuist에 기여하기 위해 최소 요구 사항은 다음과 같습니다:

- macOS 14.0+
- Xcode 16.3+

## 로컬에 프로젝트 설정하기 {#set-up-the-project-locally}

프로젝트에 작업을 시작하려면 다음과 같습니다:

- `git clone git@github.com:tuist/tuist.git` 수행하여 리포지터리를 복사합니다.
- 개발 환경을 위해 Mise 를 [설치](https://mise.jdx.dev/getting-started.html) 합니다.
- `mise install` 을 실행하여 Tuist에 필요한 시스템 종속성을 설치합니다.
- `tuist install` 을 실행하여 Tuist에 필요한 외부 종속성을 설치합니다.
- (선택 사항) `tuist auth login`을 실행하여 <LocalizedLink href="/guides/develop/build/cache">Tuist Cache</LocalizedLink>에 접근합니다.
- `tuist generate` 를 실행하여 Tuist를 사용하는 Tuist Xcode  프로젝트를 생성합니다.

**생성된 프로젝트는 자동으로 열립니다**. 프로젝트 생성 없이 프로젝트를 열려면, `open Tuist.xcworkspace` 를 실행하거나 Finder 를 사용합니다.

> [!NOTE] XED.
> `xed .`를 사용하여 프로젝트를 열면, Tuist로 생성한 프로젝트가 열리지 않고, 패키지가 열립니다. Tuist로 생성한 프로젝트를 사용하는 것을 권장합니다.

## 프로젝트 수정하기 {#edit-the-project}

의존성을 추가하거나 타겟을 조정하는 것과 같이 프로젝트 수정이 필요한 경우, <LocalizedLink href="/guides/develop/projects/editing">`tuist edit` 명령어</LocalizedLink>를 사용할 수 있습니다. 거의 사용되지 않지만, 이런 명령어가 존재한다는 것을 알아두면 좋습니다.

## Tuist 실행하기 {#run-tuist}

### Xcode {#from-xcode}

생성된 Xcode 프로젝트에서 `tuist`를 실행하려면, `tuist` 스킴을 수정하고 명령어에 전달할 인수를 설정합니다. 예를 들어, `tuist generate` 명령어를 실행하려면, 프로젝트 생성 후에 프로젝트가 열리지 않도록 `generate --no-open` 인수를 설정할 수 있습니다.

![Tuist로 generate 명령어를 실행하기 위한 스킴 구성의 예](/images/contributors/scheme-arguments.png)

또한 생성되는 프로젝트의 루트를 작업 디렉토리로 설정해야 합니다. 모든 명령어를 적용하는 `--path` 인수를 사용할 수도 있고, 아래와 같이 스킴에 작업 디렉토리를 구성할 수도 있습니다:

![Tuist를 실행 하기위해 작업 디렉토리를 설정하는 예](/images/contributors/scheme-working-directory.png)

> [!WARNING] PROJECTDESCRIPTION COMPILATION\
> `tuist` CLI는 빌드된 디렉토리에 `ProjectDescription` 프레임워크의 존재에 따라 달라집니다. `ProjectDescription` 프레임워크를 찾을 수 없어 `tuist` 실행이 실패하면 먼저 `Tuist-Workspace` 스킴을 빌드합니다.

### Terminal {#from-the-terminal}

Tuist의 `run` 명령어를 통해 `tuist`를 수행할 수 있습니다:

```bash
tuist run tuist generate --path /path/to/project --no-open
```

또한 Swift Package Manager를 통해 직접 실행할 수도 있습니다:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
