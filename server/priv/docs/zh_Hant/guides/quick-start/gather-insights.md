---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# 收集洞察力{#gather-insights}

Tuist 可以與伺服器整合以擴充其功能。其中一項功能就是收集專案和建置的相關資訊。您只需要在伺服器中擁有專案帳號即可。

首先，您需要執行驗證：

```bash
tuist auth login
```

## 建立專案{#create-a-project}

然後，您可以執行以下步驟來建立專案：

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

複製`my-handle/MyApp` ，代表專案的完整句柄。

## 連接專案{#connect-projects}

在伺服器上建立專案後，您必須將專案連接到本機專案。執行`tuist edit` ，並編輯`Tuist.swift` 檔案，以包含專案的完整句柄：

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

瞧！現在您已準備好收集專案與建置的相關資訊。執行`tuist test` 來執行測試，將結果回報到伺服器。

> [!NOTE]
> Tuist 會在本機暫存結果，並嘗試在不阻塞指令的情況下傳送。因此，這些結果可能不會在命令完成後立即傳送。在 CI 中，結果會立即傳送。


![顯示伺服器中執行清單的影像](/images/guides/quick-start/runs.png)。

擁有專案和建置的資料對於做出明智的決策至關重要。Tuist 將持續擴展其功能，您無需變更專案組態即可從中獲益。神奇吧？🪄
