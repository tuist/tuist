---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# 動態配置{#dynamic-configuration}

在某些情況下，您可能需要在專案產生時動態設定專案。例如，您可能想要根據專案產生的環境來變更應用程式名稱、bundle 識別碼或部署目標。Tuist
可透過環境變數支援此功能，您可以從艙單檔案存取這些變數。

## 透過環境變數進行組態{#configuration-through-environment-variables}

Tuist 允許透過可以從艙單檔存取的環境變數來傳遞設定。例如

```bash
TUIST_APP_NAME=MyApp tuist generate
```

如果要傳輸多個環境變數，只需用空格分隔即可。例如

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## 從艙單中讀取環境變數{#reading-the-environment-variables-from-manifests}

變數可以使用
<LocalizedLink href="/references/project-description/enums/environment">`環境`</LocalizedLink>
類型來存取。任何遵循`TUIST_XXX` 定義在環境中或在執行指令時傳給 Tuist 的變數，都可以使用`Environment`
類型來存取。以下範例顯示我們如何存取`TUIST_APP_NAME` 變數：

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

存取變數會回傳一個`Environment.Value?` 類型的實體，它可以取下列任何值：

| 案例                | 說明          |
| ----------------- | ----------- |
| `.string(String)` | 當變數代表字串時使用。 |

您也可以使用下面定義的任一個輔助方法擷取字串或布林`環境` 變數，這些方法需要傳入預設值，以確保使用者每次都能得到一致的結果。這可避免定義上文定義的函式
appName()。

::: code-group

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
