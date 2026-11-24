---
{
  "title": "動態設定",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何使用環境變數來動態設定你的專案。"
}
---
# 動態配置 {#dynamic-configuration}

有啲情況下，你可能需要喺生成項目時動態配置。例如，你可能想根據項目生成嘅環境更改應用程式名稱、Bundle Identifier 或部署目標。Tuist 透過環境變數支援呢個功能，你可以從 manifest 檔案存取佢哋。

## 透過環境變數進行配置 {#configuration-through-environment-variables}

Tuist 允許透過環境變數傳遞配置，你可以從 manifest 檔案存取佢哋。例如：

```bash
TUIST_APP_NAME=MyApp tuist generate
```

如果你想傳遞多個環境變數，只需用空格分隔佢哋。例如：

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## 從 Manifest 讀取環境變數 {#reading-the-environment-variables-from-manifests}

你可以使用 [`Environment`](https://projectdescription.tuist.dev/documentation/projectdescription/environment) 類型存取變數。任何符合 `TUIST_XXX` 慣例並喺環境中定義或執行命令時傳遞畀 Tuist 嘅變數，都可以透過 `Environment` 類型存取。存取器會使用駝峰式命名嘅變數名稱，並省略 `TUIST_` 前綴，所以 `TUIST_APP_NAME` 會讀作 `Environment.appName`，而 `TUIST_ENABLE_ANALYTICS` 則讀作 `Environment.enableAnalytics`。要檢查 manifest 是否喺 CI 上評估，請使用 `Environment.isCI` 布林值。以下範例讀取 `TUIST_APP_NAME`：

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

存取變數會返回一個 `Environment.Value?` 類型嘅實例，佢可以係以下任何值：

| 情況 | 描述 |
| --- | --- |
| `.string(String)` | 當變數代表字串時使用。 |

你亦可以使用下面定義嘅輔助方法擷取字串或布林值 `Environment` 變數，呢啲方法要求傳遞預設值，以確保用戶每次都能獲得一致嘅結果。咁樣就無須定義上面提到嘅 appName() 函數。

::: code-group

```swift [String]
Environment.appName.getString(default: "MyApp")
```

```swift [Boolean]
Environment.enableAnalytics.getBoolean(default: false)
```
<!-- -->
:::

## 將額外環境變數轉發到 Manifest {#forwarding-additional-environment-variables-to-manifests}

預設情況下，只有以 `TUIST_` 為前綴嘅變數，加上 `CI` 同 `DEVELOPER_DIR`，會被轉發到評估 `Project.swift`、`Workspace.swift`、`Package.swift` 同項目描述助手嘅子進程。呢樣做可以保持生成過程具確定性，並防止無關嘅 Shell 或 CI 變數使 manifest 快取失效。

當 manifest 需要讀取你無法控制嘅變數時（例如，第三方 `Package.swift` 已經讀取 `OPENSWIFTUI_LIBRARY_TYPE`），請喺 `Tuist.swift` 中透過生成選項嘅 `manifestEnvironment` 聲明佢哋。每個條目可以係文字名稱，或者以 `*` 結尾嘅名稱以進行前綴匹配：

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

列出嘅變數會參與 manifest 快取哈希值計算，所以佢哋嘅值變更會如預期般使快取失效。未列出嘅變數會喺 manifest 評估期間保持隱藏。
