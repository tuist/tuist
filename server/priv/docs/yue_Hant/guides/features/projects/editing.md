---
{
  "title": "編輯",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "使用 Xcode 自動完成與建置驗證來編輯 Tuist 專案清單。"
}
---
# 編輯 {#editing}

與透過 Xcode UI 進行變更的傳統 Xcode 專案或 Swift Packages 不同，由 Tuist 管理的專案是定義在包含於 **manifest 檔案** 中的 Swift 程式碼。如果你熟悉 Swift Packages 和 `Package.swift` 檔案，做法非常相似。

你可以使用任何文字編輯器來編輯這些檔案，但我們建議使用 Tuist 提供的工作流程，即 `tuist edit`。此工作流程會建立一個包含所有 manifest 檔案的 Xcode 專案，並讓你能夠編輯和編譯它們。得益於使用 Xcode，你可以獲得 **程式碼補全、語法高亮顯示和錯誤檢查** 的所有好處。

## 編輯專案 {#edit-the-project}

要編輯你的專案，你可以在 Tuist 專案目錄或子目錄中執行以下命令：

```bash
tuist edit
```

該命令會在全域目錄中建立一個 Xcode 專案並在 Xcode 中開啟它。該專案包含一個 `Manifests` 目錄，你可以建構它以確保所有 manifest 都有效。

> [!NOTE]
> **Glob 解析的 Manifest**
>
> `tuist edit` 會使用從專案根目錄（包含 `Tuist.swift` 檔案的目錄）開始的 glob `**/{Manifest}.swift` 來解析要包含的 manifest。請確保專案根目錄下有一個有效的 `Tuist.swift`。


### 忽略 manifest 檔案 {#ignoring-manifest-files}

如果你的專案在非實際 Tuist manifest 的子目錄中包含與 manifest 檔案同名的 Swift 檔案（例如 `Project.swift`），你可以在專案根目錄建立一個 `.tuistignore` 檔案，將它們從編輯專案中排除。

`.tuistignore` 檔案使用 glob 模式來指定應忽略哪些檔案：

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

當你擁有恰好使用與 Tuist manifest 檔案相同命名慣例的測試固定資料或範例程式碼時，這特別有用。

## 編輯和產生工作流程 {#edit-and-generate-workflow}

你可能已經注意到，無法從產生的 Xcode 專案進行編輯。這是為了防止產生的專案依賴 Tuist 而特意設計的，確保你將來可以輕鬆地從 Tuist 遷移。

在迭代專案時，我們建議在終端機工作階段中執行 `tuist edit` 以取得用於編輯專案的 Xcode 專案，並使用另一個終端機工作階段來執行 `tuist generate`。
