---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# 动态配置{#dynamic-configuration}

在某些情况下，您可能需要在生成时动态配置项目。例如，您可能想根据生成项目的环境更改应用程序名称、捆绑标识符或部署目标。Tuist
支持通过环境变量来实现这一点，这些变量可以从清单文件中访问。

## 通过环境变量进行配置{#configuration-through-environment-variables}

Tuist 允许通过可从清单文件访问的环境变量传递配置。例如

```bash
TUIST_APP_NAME=MyApp tuist generate
```

如果要传递多个环境变量，只需用空格隔开即可。例如

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## 从清单中读取环境变量{#reading-the-environment-variables-from-manifests}

可以使用
<LocalizedLink href="/references/project-description/enums/environment">`Environment`</LocalizedLink>
类型访问变量。环境中定义的或运行命令时传递给 Tuist 的变量`TUIST_XXX` 都可以使用`Environment`
类型访问。下面的示例展示了如何访问`TUIST_APP_NAME` 变量：

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

访问变量时会返回一个`Environment.Value?` 类型的实例，它可以接受以下任何值：

| 案例                | 描述             |
| ----------------- | -------------- |
| `.string(String)` | 当变量表示一个字符串时使用。 |

您还可以使用下面定义的辅助方法检索字符串或布尔`环境` 变量，这些方法需要传递一个默认值，以确保用户每次都能获得一致的结果。这样就无需定义上文定义的函数
appName()。

代码组

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
