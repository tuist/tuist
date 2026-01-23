---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# Xcode 專案{#xcode-project}

要在 Xcode 專案中使用註冊表新增套件，請使用預設的 Xcode 使用者介面。您可透過點擊 Xcode 的「`」&gt;「Package
Dependencies」&gt;「` 」標籤頁中的「` 」+「`
」按鈕，在註冊表中搜尋套件。若該套件存在於註冊表中，您將在右上角看到「`」tuist.dev` 註冊表：

![新增套件依賴項](/images/guides/features/build/registry/registry-add-package.png)

::: info
<!-- -->
Xcode 目前不支援自動將原始碼控制套件替換為其登錄檔對應版本。您需手動移除原始碼控制套件並新增登錄檔套件，以加速問題解決進程。
<!-- -->
:::
