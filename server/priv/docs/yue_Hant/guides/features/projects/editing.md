---
{
  "title": "編輯",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "使用 Xcode 自動完成和構建驗證來編輯 Tuist 專案清單。"
}
---
# 編輯 {#editing}

與傳統 Xcode 專案或 Swift Packages 不同（後者透過 Xcode UI 進行變更），由 Tuist 管理的專案是定義在包含於 **manifest 檔案** 中的 Swift 程式碼。如果你熟悉 Swift Packages 和 `Package.swift` 檔案，做法非常相似。

你可以使用任何文字編輯器來編輯這些檔案，但我們建議使用 Tuist 提供的工作流程：`tuist edit`。此工作流程會建立一個包含所有 manifest 檔案的 Xcode 專案，讓你能夠編輯並編譯它們。借助 Xcode，你可以獲得 **程式碼自動完成、語法標示和錯誤檢查** 等所有優勢。

## 編輯專案 {#edit-the-project}

要編輯你的專案，你可以在 Tuist 專案目錄或其子目錄中執行以下指令：

```bash
tuist edit
```

該指令會在全域目錄中建立一個 Xcode 專案並在 Xcode 中開啟它。專案包含一個 `Manifests` 目錄，你可以建置它以確保所有 manifest 都有效。

> [!NOTE]
> **Glob 解析的 Manifest**
>
> `tuist edit` 會使用從專案根目錄（即包含 `Tuist.swift` 檔案的目錄）開始的 glob `**/{Manifest}.swift` 來解析要包含的 manifest。請確保專案根目錄中存在有效的 `Tuist.swift`。


### 忽略 manifest 檔案 {#ignoring-manifest-files}

如果你的專案在非實際 Tuist manifest 的子目錄中包含與 manifest 檔案同名的 Swift 檔案（例如 `Project.swift`），你可以在專案根目錄建立 `.tuistignore` 檔案，將它們從編輯專案中排除。

`.tuistignore` 檔案使用 glob 模式來指定應忽略哪些檔案：

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

這在你擁有測試 fixture 或範例程式碼，而它們恰好使用與 Tuist manifest 檔案相同的命名慣例時特別有用。

## 編輯與產生工作流程 {#edit-and-generate-workflow}

你可能已經注意到，無法從產生的 Xcode 專案進行編輯。這是刻意設計，以防止產生的專案對 Tuist 產生依賴，確保你將來可以輕鬆遷離 Tuist。

在迭代開發專案時，我們建議在一個終端機工作階段中執行 `tuist edit` 以取得用於編輯專案的 Xcode 專案，並在另一個終端機工作階段中執行 `tuist generate`。
