---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# 动态配置{#dynamic-configuration}

在某些情况下，您可能需要在生成时动态配置项目。例如，您可能希望根据项目生成的环境来更改应用名称、包标识符或部署目标。Tuist
通过环境变量支持此功能，这些变量可在清单文件中访问。

## 通过环境变量进行配置{#configuration-through-environment-variables}

Tuist 允许通过环境变量传递配置，这些配置可在清单文件中访问。例如：

```bash
TUIST_APP_NAME=MyApp tuist generate
```

若需传递多个环境变量，只需用空格分隔即可。例如：

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## 从清单中读取环境变量{#reading-the-environment-variables-from-manifests}

可以通过
<LocalizedLink href="/references/project-description/enums/environment">`Environment`</LocalizedLink>
这种形式访问变量。任何遵循`TUIST_XXX` 规范定义的环境变量，或在运行命令时传递给 Tuist 的变量，均可通过`Environment`
这种形式访问。以下示例展示了如何访问`TUIST_APP_NAME` 变量：

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

访问变量将返回类型为 ``Environment.Value?` 的实例，其值可能为以下任意一种：`

| 大小写               | 描述           |
| ----------------- | ------------ |
| `.string(String)` | 当变量表示字符串时使用。 |

您还可以通过以下定义的任一辅助方法检索字符串或布尔值`环境变量`
，这些方法需要传入默认值以确保用户每次都能获得一致的结果。这样就无需定义上文提到的appName()函数。

代码组

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
