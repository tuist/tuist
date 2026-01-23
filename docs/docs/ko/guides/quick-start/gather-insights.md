---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# 인사이트 수집 {#gather-insights}

Tuist는 서버와 연동하여 기능을 확장할 수 있습니다. 그 기능 중 하나는 프로젝트 및 빌드에 대한 인사이트를 수집하는 것입니다. 서버에
프로젝트가 있는 계정만 있으면 됩니다.

먼저 다음 명령어를 실행하여 인증해야 합니다:

```bash
tuist auth login
```

## 프로젝트 생성 {#create-a-project}

다음 명령어를 실행하여 프로젝트를 생성할 수 있습니다:

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

`my-handle/MyApp` 를 복사하세요. 이는 프로젝트의 전체 핸들을 나타냅니다.

## 프로젝트 연결 {#connect-projects}

서버에 프로젝트를 생성한 후 로컬 프로젝트에 연결해야 합니다. `tuist edit` 를 실행하고 `Tuist.swift` 파일을 편집하여
프로젝트의 전체 핸들을 포함시키세요:

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

자, 이제 프로젝트와 빌드에 대한 인사이트를 수집할 준비가 되었습니다. `tuist test` 를 실행하여 테스트를 실행하고 결과를 서버에
보고하세요.

::: info Mise란?
<!-- -->
Tuist는 결과를 로컬에 대기열에 넣고 명령어를 차단하지 않고 전송하려고 시도합니다. 따라서 명령어 완료 직후에 전송되지 않을 수 있습니다.
CI에서는 결과가 즉시 전송됩니다.
<!-- -->
:::


![서버 내 실행 목록을 보여주는 이미지](/images/guides/quick-start/runs.png)

프로젝트 및 빌드 데이터를 확보하는 것은 정보에 기반한 의사결정에 필수적입니다. Tuist는 지속적으로 기능을 확장할 것이며, 여러분은 프로젝트
설정을 변경하지 않고도 그 혜택을 누릴 수 있습니다. 마법 같죠? 🪄
