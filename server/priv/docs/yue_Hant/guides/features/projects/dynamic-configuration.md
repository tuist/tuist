---
{
  "title": "動態設定",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何使用環境變數來動態設定你的專案。"
}
---
# 動態設定 {#dynamic-configuration}

有時你需要在生成項目時動態設定。例如，你可能想根據項目生成的環境來更改應用程式名稱、bundle identifier 或部署目標。Tuist 透過環境變數支援此功能，你可以從 manifest 檔案存取這些變數。

## 透過環境變數進行設定 {#configuration-through-environment-variables}

Tuist 允許透過環境變數傳遞設定，這些變數可以從 manifest 檔案中存取。例如：

```bash
TUIST_APP_NAME=MyApp tuist generate
```

如果你想傳遞多個環境變數，只需用空格分隔它們。例如：

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## 從 manifests 讀取環境變數 {#reading-the-environment-variables-from-manifests}

可以使用 [`Environment`](https://projectdescription.tuist.dev/documentation/projectdescription/environment) 類型來存取變數。任何遵循 `TUIST_XXX` 慣例並在環境中定義或在執行命令時傳遞給 Tuist 的變數，都可以使用 `Environment` 類型存取。以下範例顯示我們如何存取 `TUIST_APP_NAME` 變數：

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

存取變數會回傳一個 `Environment.Value?` 類型的實例，它可以是以下任何值：

| 情況 | 描述 |
| --- | --- |
| `.string(String)` | 當變數代表字串時使用。 |

你也可以使用下面定義的輔助方法來檢索字串或布林值 `Environment` 變數，這些方法需要傳遞一個預設值，以確保用戶每次都能獲得一致的結果。這避免了需要定義上面提到的 appName() 函數。

::: code-group

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::

## 將額外的環境變數轉發到 manifests {#forwarding-additional-environment-variables-to-manifests}

預設情況下，只有以 `TUIST_` 為前綴的變數，加上 `CI` 和 `DEVELOPER_DIR`，會被轉發到評估 `Project.swift`、`Workspace.swift`、`Package.swift` 和項目描述輔助程式的子進程。這保持了生成的確定性，並防止無關的 shell 或 CI 變數使 manifest 快取失效。

當 manifest 需要讀取不受你控制的變數時（例如，已經讀取 `OPENSWIFTUI_LIBRARY_TYPE` 的第三方 `Package.swift`），請在 `Tuist.swift` 中透過生成選項上的 `manifestEnvironment` 聲明它們。每個條目要么是一個文字名稱，要么是一個以 `*` 結尾的名稱用於前綴匹配：

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

列出的變數會參與 manifest 快取的雜湊計算，因此它們值的變化會按預期使快取失效。未列出的變數在 manifest 評估過程中仍然隱藏。
