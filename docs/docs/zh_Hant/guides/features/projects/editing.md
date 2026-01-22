---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# 編輯{#editing}

與傳統 Xcode 專案或 Swift 套件不同，後者透過 Xcode 介面進行修改，Tuist 管理之專案乃透過 Swift
程式碼定義，該程式碼存放於**中的 manifest 檔案** 。若您熟悉 Swift 套件及其`Package.swift` 檔案，此方法與之極為相似。

您可使用任何文字編輯器修改這些檔案，但建議採用 Tuist 提供的作業流程：執行 ``` 並輸入 `tuist edit``。此流程將建立包含所有清單檔案的
Xcode 專案，便於編輯與編譯。透過 Xcode 環境，您可充分運用**的代碼補全、語法高亮及錯誤檢查功能** 。

## 編輯專案{#edit-the-project}

若要編輯專案，您可在 Tuist 專案目錄或子目錄中執行以下指令：

```bash
tuist edit
```

此指令會在全域目錄中建立 Xcode 專案並於 Xcode 中開啟。該專案包含一個`Manifests` 目錄，您可透過建置此目錄來確保所有清單檔案皆為有效。

::: info GLOB-RESOLVED MANIFESTS
<!-- -->
`tuist edit` 會透過全域模式解析需包含的清單檔案，例如：`**/{Manifest}.swift` 從專案根目錄（即包含`Tuist.swift`
檔案的目錄）進行解析。請確保專案根目錄存在有效的`Tuist.swift` 檔案。
<!-- -->
:::

### 忽略清單檔案{#ignoring-manifest-files}

若專案中存在與清單檔案同名的 Swift 檔案（例如：`Project.swift` ），且這些檔案位於非 Tuist
清單的子目錄中，可於專案根目錄建立`.tuistignore 檔案（參見` ），將其排除於編輯專案範圍外。

`.tuistignore 檔案使用全域模式指定應忽略的檔案：`

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

此規則在測試固定裝置或範例程式碼恰巧採用與 Tuist 清單檔案相同命名規範時尤為實用。

## 編輯與生成工作流程{#edit-and-generate-workflow}

您可能已注意到，無法從生成的 Xcode 專案進行編輯。此設計旨在避免生成的專案依賴 Tuist，確保未來能輕鬆遷移至其他工具。

在迭代專案時，建議於終端機視窗執行 ``` tuist edit `` ` 以取得 Xcode 專案進行編輯，並另開終端機視窗執行 ``` tuist
generate ``` 。
