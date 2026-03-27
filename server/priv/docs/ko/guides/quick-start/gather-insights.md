---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# 인사이트 수집 {#gather-insights}

튜이스트는 서버와 통합하여 기능을 확장할 수 있습니다. 이러한 기능 중 하나는 프로젝트와 빌드에 대한 인사이트를 수집하는 것입니다. 서버에
프로젝트가 있는 계정만 있으면 됩니다.

먼저 실행을 통해 인증을 받아야 합니다:

```bash
tuist auth login
```

## 프로젝트 만들기 {#create-a-project}

그런 다음 실행하여 프로젝트를 만들 수 있습니다:

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

프로젝트의 전체 핸들을 나타내는 `my-handle/MyApp` 을 복사합니다.

## 프로젝트 연결 {#connect-projects}

서버에서 프로젝트를 생성한 후에는 로컬 프로젝트에 연결해야 합니다. ` tuist edit` 을 실행하고 `Tuist.swift` 파일을
수정하여 프로젝트의 전체 핸들을 포함합니다:

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

짜잔! 이제 프로젝트와 빌드에 대한 인사이트를 수집할 준비가 되었습니다. ` tuist test` 를 실행하여 결과를 서버에 보고하는 테스트를
실행합니다.

::: info Mise란?
<!-- -->
튜이스트는 로컬에서 결과를 대기열에 넣고 명령을 차단하지 않고 전송하려고 시도합니다. 따라서 명령이 완료된 후 즉시 전송되지 않을 수 있습니다.
CI에서는 결과가 즉시 전송됩니다.
<!-- -->
:::


![서버의 실행 목록을 보여주는 이미지](/images/guides/quick-start/runs.png)

프로젝트와 빌드에서 데이터를 확보하는 것은 정보에 입각한 결정을 내리는 데 매우 중요합니다. Tuist는 계속해서 기능을 확장할 예정이며,
프로젝트 구성을 변경하지 않고도 이 기능을 활용할 수 있습니다. 마법 같죠? 🪄
