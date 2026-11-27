---
{
  "title": "動態設定",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何使用環境變數來動態設定你的專案。"
}
---
# 動態設定 {#dynamic-configuration}

在某些情況下，你可能需要在專案產生期間進行動態設定。例如，你可能想根據專案產生的環境來變更應用程式名稱、Bundle Identifier 或部署目標。Tuist 透過環境變數支援此功能，這些變數可從 manifest 檔案中存取。

## 透過環境變數進行設定 {#configuration-through-environment-variables}

Tuist 允許透過環境變數傳遞設定，這些變數可從 manifest 檔案中存取。例如：

```bash
TUIST_APP_NAME=MyApp tuist generate
```

若要傳遞多個環境變數，只需用空格分隔即可。例如：

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## 從 manifest 讀取環境變數 {#reading-the-environment-variables-from-manifests}

可以使用 [`Environment`](https://projectdescription.tuist.dev/documentation/projectdescription/environment) 類型來存取變數。任何遵循 `TUIST_XXX` 慣例並在環境中定義或在執行命令時傳遞給 Tuist 的變數，都可以使用 `Environment` 類型存取。存取器會使用去掉 `TUIST_` 前綴後的駝峰式變數名稱，因此 `TUIST_APP_NAME` 會以 `Environment.appName` 讀取，而 `TUIST_ENABLE_ANALYTICS` 則以 `Environment.enableAnalytics` 讀取。若要檢查 manifest 是否在 CI 上評估，請使用 `Environment.isCI` 布林值。以下範例讀取 `TUIST_APP_NAME`：

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

存取變數會回傳一個 `Environment.Value?` 類型的實體，其值可以是下列任一項：

| 案例 | 說明 |
| --- | --- |
| `.string(String)` | 當變數代表字串時使用。 |

你也可以使用下方定義的輔助方法來取得字串或布林值的 `Environment` 變數；這些方法需要傳入預設值，以確保使用者每次都能獲得一致的結果。這樣就不需要定義上述的 appName() 函式。

::: code-group

```swift [String]
Environment.appName.getString(default: "MyApp")
```

```swift [Boolean]
Environment.enableAnalytics.getBoolean(default: false)
```
<!-- -->
:::

## 將額外的環境變數轉發至 manifest {#forwarding-additional-environment-variables-to-manifests}

預設情況下，只有以 `TUIST_` 為前綴的變數，以及 `CI` 和 `DEVELOPER_DIR`，會被轉發至評估 `Project.swift`、`Workspace.swift`、`Package.swift` 及專案描述輔助工具的子程序。這能讓產生過程保持確定性，並防止不相關的 Shell 或 CI 變數使 manifest 快取失效。

當 manifest 需要讀取不在你控制範圍內的變數時（例如，第三方 `Package.swift` 已經讀取 `OPENSWIFTUI_LIBRARY_TYPE`），請在 `Tuist.swift` 中透過產生選項上的 `manifestEnvironment` 宣告它們。每個項目可以是明確的名稱，或是以 `*` 結尾的名稱以進行前綴比對：

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

列出的變數會參與 manifest 快取的雜湊計算，因此其值的變更會如預期般使快取失效。未列出的變數在 manifest 評估過程中仍然不可見。
