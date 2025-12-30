---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# 編輯{#editing}

與傳統的 Xcode 專案或 Swift Packages 不同，前者的變更是透過 Xcode 的 UI 來完成，而 Tuist 管理的專案則是以 Swift
程式碼來定義，包含在**manifest 檔案** 中。如果您熟悉 Swift Packages 和`Package.swift` 檔案，則方法非常相似。

您可以使用任何文字編輯器編輯這些檔案，但我們建議您使用 Tuist 提供的工作流程，`tuist edit` 。該工作流程會建立一個包含所有清單檔案的
Xcode 專案，並允許您編輯和編譯它們。由於使用 Xcode，您可以獲得**代碼完成、語法高亮和錯誤檢查** 的所有好處。

## 編輯專案{#edit-the-project}

要編輯專案，您可以在 Tuist 專案目錄或子目錄中執行下列指令：

```bash
tuist edit
```

該指令會在全局目錄中建立一個 Xcode 專案，並在 Xcode 中開啟。該專案包含一個`Manifests`
目錄，您可以建立該目錄，以確保您所有的manifests都是有效的。

::: info GLOB-RESOLVED MANIFESTS
<!-- -->
`tuist edit` 使用專案根目錄（包含`Tuist.swift` 檔案的目錄）中的 glob`**/{Manifest}.swift`
解析要包含的清單。請確定專案根目錄中有一個有效的`Tuist.swift` 。
<!-- -->
:::

### 忽略清單檔案{#ignoring-manifest-files}

如果專案的子目錄中包含與清單檔案同名的 Swift 檔案 (例如`Project.swift`)，而這些檔案並非實際的 Tuist
清單，您可以在專案根目錄建立`.tuistignore` 檔案，將這些檔案排除在編輯專案之外。

`.tuistignore` 檔案使用 glob 模式指定應該忽略哪些檔案：

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

當您的測試夾具或範例程式碼碰巧使用與 Tuist 清單檔案相同的命名慣例時，此功能尤其有用。

## 編輯和產生工作流程{#edit-and-generate-workflow}

您可能已經注意到，編輯工作無法在產生的 Xcode 專案中完成。這是為了防止生成的專案依賴於 Tuist 而設計的，以確保您將來可以輕鬆地從 Tuist
轉移到其他專案。

迭代專案時，建議從終端會話執行`tuist edit` ，取得 Xcode 專案來編輯專案，並使用另一個終端會話執行`tuist generate` 。
