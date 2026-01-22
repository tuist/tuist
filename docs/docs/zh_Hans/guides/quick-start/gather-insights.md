---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# 收集见解{#gather-insights}

Tuist可通过集成服务器扩展功能。其中一项功能是收集项目与构建的洞察信息。您只需在服务器中拥有包含项目的账户即可。

首先，您需要通过运行以下命令进行身份验证：

```bash
tuist auth login
```

## 创建项目{#create-a-project}

随后可通过运行以下命令创建项目：

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

复制`my-handle/MyApp` ，该链接代表项目的完整句柄。

## 连接项目{#connect-projects}

在服务器上创建项目后，需将其与本地项目关联。运行`tuist edit` ，并编辑`Tuist.swift` 文件，添加项目的完整句柄：

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

好了！现在您已准备好收集项目和构建的洞察信息。运行`tuist test` 即可执行测试并将结果上报至服务器。

信息
<!-- -->
Tuist将结果本地入队，并尝试在不阻塞命令的情况下发送。因此命令执行完毕后结果可能不会立即发送。在CI中，结果会立即发送。
<!-- -->
:::


![服务器运行列表示意图](/images/guides/quick-start/runs.png)

项目与构建数据对决策至关重要。Tuist将持续扩展功能，您无需修改项目配置即可享受这些新特性。神奇吧？🪄
