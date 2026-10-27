---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# 收集见解{#gather-insights}

Tuist 可以与服务器集成，以扩展其功能。其中一项功能就是收集有关项目和构建的信息。您只需在服务器上拥有一个项目账户。

首先，您需要通过运行进行身份验证：

```bash
tuist auth login
```

## 创建项目{#create-a-project}

然后运行

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

复制`my-handle/MyApp` ，它代表项目的完整句柄。

## 连接项目{#connect-projects}

在服务器上创建项目后，必须将其连接到本地项目。运行`tuist edit` 并编辑`Tuist.swift` 文件，以包含项目的完整句柄：

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

瞧！您现在可以收集有关项目和构建的信息了。运行`tuist test` 运行测试，向服务器报告结果。

信息
<!-- -->
Tuist 会在本地查询结果，并尝试在不阻塞命令的情况下发送结果。因此，这些结果可能不会在命令结束后立即发送。在 CI 中，结果会立即发送。
<!-- -->
:::


显示服务器运行列表的图像](/images/guides/quick-start/runs.png)。

从您的项目和构建中获取数据对于做出明智的决策至关重要。Tuist 将继续扩展其功能，您无需更改项目配置即可从中受益。神奇吧？🪄
