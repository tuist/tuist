---
{
  "title": "編輯",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "使用 Xcode 自動完成與建置驗證來編輯 Tuist 專案資訊清單。"
}
---
# 編輯 {#editing}

與透過 Xcode 介面進行變更的傳統 Xcode 專案或 Swift Package 不同，由 Tuist 管理的專案是在 **資訊清單檔案**中以 Swift 程式碼定義。如果你熟悉 Swift Package 和 `Package.swift` 檔案，這種做法非常類似。

你可以使用任何文字編輯器來編輯這些檔案，但我們建議使用 Tuist 提供的工作流程：`tuist edit`。此工作流程會建立一個包含所有資訊清單檔案的 Xcode 專案，讓你能夠編輯並編譯它們。得益於使用 Xcode，你可以享有 **程式碼自動完成、語法標示和錯誤檢查** 等所有優勢。

## 編輯專案 {#edit-the-project}

若要編輯你的專案，你可以在 Tuist 專案目錄或其子目錄中執行以下指令：

```bash
tuist edit
```

此指令會在全域目錄中建立一個 Xcode 專案，並在 Xcode 中開啟它。該專案包含一個 `Manifests` 目錄，你可以建置它以確保所有資訊清單皆有效。

> [!NOTE]
> **以 Glob 解析的資訊清單**
>
> `tuist edit` 會從專案根目錄（即包含 `Tuist.swift` 檔案的目錄）使用 glob `**/{Manifest}.swift` 來解析要納入的資訊清單。請確保專案根目錄中存在有效的 `Tuist.swift`。


### 忽略資訊清單檔案 {#ignoring-manifest-files}

如果你的專案在並非實際 Tuist 資訊清單的子目錄中包含與資訊清單檔案同名的 Swift 檔案（例如 `Project.swift`），你可以在專案根目錄建立 `.tuistignore` 檔案，將它們從編輯專案中排除。

`.tuistignore` 檔案使用 glob 模式來指定應忽略哪些檔案：

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

當你擁有測試固定資料或範例程式碼，且其恰巧採用與 Tuist 資訊清單檔案相同的命名慣例時，這特別實用。

## 編輯與產生工作流程 {#edit-and-generate-workflow}

你可能會注意到，無法從產生的 Xcode 專案進行編輯。這是刻意設計，以避免產生的專案對 Tuist 產生相依性，確保你未來能以極小成本遷離 Tuist。

在迭代開發專案時，我們建議在一個終端機工作階段中執行 `tuist edit` 以取得用於編輯專案的 Xcode 專案，並在另一個終端機工作階段中執行 `tuist generate`。
