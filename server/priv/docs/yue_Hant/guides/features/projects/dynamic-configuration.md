---
{
  "title": "動態設定",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何使用環境變數來動態設定你的專案。"
}
---
# 動態配置 {#dynamic-configuration}

有些情況下，你可能需要在生成時動態配置項目。例如，你可能想根據項目生成的環境來更改應用名稱、捆綁標識符或部署目標。Tuist 通過環境變量支持此功能，這些變量可以從清單文件中訪問。

## 通過環境變量進行配置 {#configuration-through-environment-variables}

Tuist 允許通過環境變量傳遞配置，這些變量可以從清單文件中訪問。例如：

```bash
TUIST_APP_NAME=MyApp tuist generate
```

如果你想傳遞多個環境變量，只需用空格分隔它們。例如：

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## 從清單中讀取環境變量 {#reading-the-environment-variables-from-manifests}

可以使用 [`Environment`](https://projectdescription.tuist.dev/documentation/projectdescription/environment) 類型來訪問變量。任何遵循 `TUIST_XXX` 約定並在環境中定義或在運行命令時傳遞給 Tuist 的變量，都可以使用 `Environment` 類型訪問。訪問器使用去掉 `TUIST_` 前綴後的駝峰式變量名，因此 `TUIST_APP_NAME` 會讀作 `Environment.appName`，而 `TUIST_ENABLE_ANALYTICS` 會讀作 `Environment.enableAnalytics`。要檢查清單是否在 CI 上評估，請使用 `Environment.isCI` 布爾值。以下示例讀取 `TUIST_APP_NAME`：

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

訪問變量會返回一個 `Environment.Value?` 類型的實例，它可以是以下任何值：

| 情況 | 描述 |
| --- | --- |
| `.string(String)` | 當變量代表字符串時使用。 |

你也可以使用下面定義的任何一種輔助方法來檢索字符串或布爾型 `Environment` 變量，這些方法需要傳遞一個默認值，以確保用戶每次都能獲得一致的結果。這避免了定義上面提到的 appName() 函數的需要。

::: code-group

```swift [String]
Environment.appName.getString(default: "MyApp")
```

```swift [Boolean]
Environment.enableAnalytics.getBoolean(default: false)
```
<!-- -->
:::

## 將額外的環境變量轉發到清單 {#forwarding-additional-environment-variables-to-manifests}

默認情況下，只有以 `TUIST_` 為前綴的變量，以及 `CI` 和 `DEVELOPER_DIR`，會被轉發到評估 `Project.swift`、`Workspace.swift`、`Package.swift` 和項目描述助手的子進程。這保持了生成的確定性，並防止無關的 shell 或 CI 變量使清單緩存失效。

當清單需要讀取不受你控制的變量時（例如，已經讀取 `OPENSWIFTUI_LIBRARY_TYPE` 的第三方 `Package.swift`），請在 `Tuist.swift` 中通過生成選項上的 `manifestEnvironment` 聲明它們。每個條目要么是字面名稱，要么是以 `*` 結尾的名稱用於前綴匹配：

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

列出的變量會參與清單緩存哈希值的計算，因此它們值的變化會按預期使緩存失效。未列出的變量在清單評估過程中保持隱藏。
