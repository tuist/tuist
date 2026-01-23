---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# 蒐集見解{#gather-insights}

Tuist 可與伺服器整合以擴展其功能。其中一項功能是收集專案與建置的分析數據。您只需在伺服器上擁有包含專案的帳戶即可。

首先，您需要執行以下指令進行驗證：

```bash
tuist auth login
```

## 建立專案{#create-a-project}

接著可執行以下指令建立專案：

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

複製`my-handle/MyApp` ，此為專案完整識別碼。

## 連結專案{#connect-projects}

在伺服器上建立專案後，您必須將其與本地專案連結。執行`tuist edit` ，並編輯`Tuist.swift` 檔案，加入專案完整路徑：

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

好了！現在您已準備好收集專案與建置的相關洞察。執行 ``tuist test` ` 即可運行測試，並將結果回報至伺服器。

::: info
<!-- -->
Tuist 會將結果排入本地佇列，並嘗試在不阻塞指令的情況下傳送。因此結果可能不會在指令結束後立即傳送。在 CI 中，結果會立即傳送。
<!-- -->
:::


![顯示伺服器中運行清單的圖片](/images/guides/quick-start/runs.png)

掌握專案與建置的數據對決策至關重要。Tuist 將持續擴展功能，您無需變更專案設定即可享受這些優勢。很神奇吧？🪄
