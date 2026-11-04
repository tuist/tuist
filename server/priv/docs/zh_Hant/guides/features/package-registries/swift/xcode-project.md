---
{
  "title": "Xcode 專案",
  "titleTemplate": ":title · Swift · 套件註冊表 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Xcode 專案中使用 Tuist Registry。"
}
---
# Xcode 專案 {#xcode-project}

若要在 Xcode 專案中使用登錄檔新增套件，請使用預設的 Xcode 使用者介面。你可以點擊 Xcode 中 `Package Dependencies` 分頁裡的 `+` 按鈕，在登錄檔中搜尋套件。如果該套件存在於登錄檔中，你會在右上角看到 `tuist.dev` 登錄檔：

![新增套件相依性](/images/guides/features/build/registry/registry-add-package.png)

## 解析原始碼控制套件 {#resolving-source-control-packages}

以原始碼控制 URL 宣告的套件（例如你所新增套件的傳遞相依性）預設會從原始碼控制解析。`tuist registry setup` 會透過寫入以下使用者預設值，將 Xcode 設定為改為從登錄檔解析：

```bash
defaults write com.apple.dt.Xcode IDEPackageDependencySCMToRegistryTransformation useRegistryIdentityAndSources
```

當登錄檔中存在對應項目時，Xcode 會從登錄檔解析原始碼控制套件；若不存在，則退回使用原始碼控制。

> [!NOTE]
> 這是每台機器的 Xcode 偏好設定，而非專案設定，因此提交登錄檔設定檔案並不會與團隊其他成員共用。每位開發者都需要在自己的機器上執行一次 `tuist registry setup`。此後，該偏好設定將套用至該機器上的所有 Xcode 專案。
