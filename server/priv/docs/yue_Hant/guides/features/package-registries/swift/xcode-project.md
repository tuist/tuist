---
{
  "title": "Xcode 專案",
  "titleTemplate": ":title · Swift · Package Registries · 功能 · 指南 · Tuist",
  "description": "了解如何在 Xcode 專案中使用 Tuist Registry。"
}
---
# Xcode 專案 {#xcode-project}

如要在 Xcode 專案中使用註冊表加入套件，請使用預設的 Xcode UI。你可以點擊 Xcode 中 `Package Dependencies` 分頁內的 `+` 按鈕，在註冊表中搜尋套件。如果該套件已收錄於註冊表，你會在右上角看到 `tuist.dev` 註冊表：

![加入套件依賴](/images/guides/features/build/registry/registry-add-package.png)

## 解析原始碼控制套件 {#resolving-source-control-packages}

以原始碼控制 URL 宣告的套件（例如你所加入套件的傳遞依賴）預設會從原始碼控制解析。`tuist registry setup` 會寫入以下使用者預設值，將 Xcode 設定為改從註冊表解析：

```bash
defaults write com.apple.dt.Xcode IDEPackageDependencySCMToRegistryTransformation useRegistryIdentityAndSources
```

當註冊表存在對應項目時，Xcode 便會從註冊表解析原始碼控制套件；否則會退回至原始碼控制。

> [!NOTE]
> 這是每台機器的 Xcode 偏好設定，而非專案設定，因此提交註冊表設定檔並不會與團隊其他成員共享。每位開發者都需要在自己的機器上執行一次 `tuist registry setup`。此偏好設定隨後會套用至該機器上的所有 Xcode 專案。
