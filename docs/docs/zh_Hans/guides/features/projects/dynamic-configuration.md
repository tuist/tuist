---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# 动态配置{#dynamic-configuration}

在某些情况下，您可能需要在生成项目时进行动态配置。例如，您可能需要根据项目生成的环境来更改应用名称、包标识符或部署目标。Tuist
通过环境变量支持此功能，这些变量可从清单文件中访问。

## 通过环境变量进行配置{#configuration-through-environment-variables}

Tuist 允许通过环境变量传递配置，这些变量可在清单文件中访问。例如：

```bash
TUIST_APP_NAME=MyApp tuist generate
```

若需传递多个环境变量，请用空格分隔。例如：

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## 从清单中读取环境变量{#reading-the-environment-variables-from-manifests}

变量可通过
<LocalizedLink href="/references/project-description/enums/environment">`Environment`</LocalizedLink>
格式访问。任何遵循`TUIST_XXX` 规范的环境变量或命令执行时传递给 Tuist 的变量，均可通过`Environment`
格式访问。以下示例演示如何访问`TUIST_APP_NAME` 变量：

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

访问变量将返回`类型的实例Environment.Value?` ，其可能取以下任一值：

| 大小写               | 描述            |
| ----------------- | ------------- |
| `.string(String)` | 用于变量表示字符串的情况。 |

您也可通过下列辅助方法获取字符串或布尔值`环境` 变量。这些方法需传入默认值以确保每次返回一致结果，从而无需定义上文的appName()函数。

代码组

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
