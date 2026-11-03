---
{
  "title": "Xcode 專案",
  "titleTemplate": ":title · Swift · Package Registries · 功能 · 指南 · Tuist",
  "description": "了解如何在 Xcode 專案中使用 Tuist Registry。"
}
---
# Xcode 專案 {#xcode-project}

要在 Xcode 專案中使用註冊表新增套件，請使用預設的 Xcode UI。你可以點擊 Xcode 中 `Package Dependencies` 分頁裡的 `+` 按鈕，在註冊表中搜尋套件。如果該套件在註冊表中可用，你會在右上角看到 `tuist.dev` 註冊表：

![新增套件依賴項](/images/guides/features/build/registry/registry-add-package.png)

## 解析原始碼控制套件 {#resolving-source-control-packages}

以原始碼控制 URL 宣告的套件（例如你所新增套件的傳遞性依賴項）預設會從原始碼控制解析。`tuist registry setup` 會透過寫入以下使用者預設值，將 Xcode 設定為改為從註冊表解析它們：

```bash
defaults write com.apple.dt.Xcode IDEPackageDependencySCMToRegistryTransformation useRegistryIdentityAndSources
```

每當存在註冊表對應項目時，Xcode 就會從註冊表解析原始碼控制套件；若不存在，則退回使用原始碼控制。

> [!NOTE]
> 這是每台機器的 Xcode 偏好設定，而非專案設定，因此提交註冊表設定檔並不會與團隊其他成員共享。每位開發者都需要在自己的機器上執行一次 `tuist registry setup`。該偏好設定隨後會套用至該機器上的所有 Xcode 專案。
