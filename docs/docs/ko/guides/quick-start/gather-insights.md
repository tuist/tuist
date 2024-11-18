---
title: Gather insights
titleTemplate: :title · Quick-start · Guides · Tuist
description: 프로젝트에서 인사이트를 수집하는 방법에 대해 배웁니다.
---

# Gather insights {#gather-insights}

Tuist는 기능을 확장하기 위해 서버와 통합할 수 있습니다. 프로젝트와 빌드에 대해 인사이트를 수집하는 것이 그 기능 중에 하나입니다. 서버의 프로젝트에 필요한 계정만 있으면 됩니다.

먼저, 다음을 수행하여 인증을 해야 합니다:

```bash
tuist auth
```

## Create a project {#create-a-project}

그런 다음에 다음을 수행하여 프로젝트를 생성할 수 있습니다:

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

프로젝트의 전체 식별자를 나타내는 `my-handle/MyApp`을 복사합니다.

## 프로젝트 연결 {#connect-projects}

서버에 프로젝트를 생성한 후에 로컬 프로젝트와 연결해야 합니다. `tuist edit`를 수행하고 프로젝트의 전체 처리를 포함하기 위해 `Tuist.swift` 파일을 수정합니다:

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

Voilà! 이제 프로젝트와 빌드에 대한 인사이트를 수집하기 위한 준비가 되었습니다. `tuist test`를 수행하여 테스트를 수행하고 서버에 결과를 전송합니다.

> [!NOTE]\
> Tuist는 결과를 로컬의 대기열에 추가하여 차단없이 전송을 시도합니다. 그러므로 명령어가 종료된 후에 바로 전송되지 않을 수 있습니다. CI에서 결과는 바로 전송됩니다.

![An image that shows a list of runs in the server](/images/guides/quick-start/runs.png)

프로젝트와 빌드에서 얻은 데이터는 정보에 입각한 결정을 내리는데 중요합니다.
Tuist는 계속해서 기능을 확장하고 프로젝트 구성 변경 없이 이러한 기능을 사용할 수 있습니다. 마법 같지 않나요? 🪄
