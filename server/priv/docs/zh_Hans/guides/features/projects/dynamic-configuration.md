---
{
  "title": "动态配置",
  "titleTemplate": ":title · 项目 · 功能 · 指南 · Tuist",
  "description": "了解如何使用环境变量动态配置你的项目。"
}
---
# 动态配置 {#dynamic-configuration}

在某些场景下，你可能需要在生成时动态配置项目。例如，根据项目生成的环境更改应用名称、Bundle 标识符或部署目标。Tuist 通过环境变量支持这一功能，这些变量可以从清单文件中访问。

## 通过环境变量进行配置 {#configuration-through-environment-variables}

Tuist 允许通过环境变量传递配置，这些变量可以从清单文件中访问。例如：

```bash
TUIST_APP_NAME=MyApp tuist generate
```

如果要传递多个环境变量，只需用空格分隔它们。例如：

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## 从清单中读取环境变量 {#reading-the-environment-variables-from-manifests}

可以使用 [`Environment`](https://projectdescription.tuist.dev/documentation/projectdescription/environment) 类型访问变量。任何遵循 `TUIST_XXX` 约定并在环境中定义或在运行命令时传递给 Tuist 的变量，都可以通过 `Environment` 类型访问。以下示例展示了如何访问 `TUIST_APP_NAME` 变量：

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

访问变量会返回一个类型为 `Environment.Value?` 的实例，它可以是以下值之一：

| 情况 | 描述 |
| --- | --- |
| `.string(String)` | 当变量表示字符串时使用。 |

你还可以使用下面定义的辅助方法检索字符串或布尔类型的 `Environment` 变量，这些方法需要传入默认值，以确保用户每次都能获得一致的结果。这样就无需定义上面提到的 appName() 函数。

::: code-group

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::

## 将额外的环境变量转发到清单 {#forwarding-additional-environment-variables-to-manifests}

默认情况下，只有以 `TUIST_` 为前缀的变量，以及 `CI` 和 `DEVELOPER_DIR`，会被转发到评估 `Project.swift`、`Workspace.swift`、`Package.swift` 和项目描述助手的子进程。这保持了生成的确定性，并防止无关的 shell 或 CI 变量使清单缓存失效。

当清单需要读取不受你控制的变量时（例如，第三方 `Package.swift` 已经读取了 `OPENSWIFTUI_LIBRARY_TYPE`），请在 `Tuist.swift` 中通过生成选项上的 `manifestEnvironment` 声明它们。每个条目要么是字面名称，要么是以 `*` 结尾的名称用于前缀匹配：

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            manifestEnvironment: [
                "OPENSWIFTUI_*",
                "MY_VAR",
            ]
        )
    )
)
```

列出的变量会参与清单缓存哈希的计算，因此它们的值变化会按预期使缓存失效。未列出的变量在清单评估过程中保持隐藏。
