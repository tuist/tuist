---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# Xcode 專案{#xcode-project}

要在 Xcode 專案中使用註冊表新增套件，請使用預設的 Xcode UI。您可以按一下 Xcode 中`Package Dependencies`
標籤中的`+` 按鈕，在註冊表中搜尋套件。如果套件在註冊表中可用，您會在右上方看到`tuist.dev` 註冊表：

新增套件相依性](/images/guides/features/build/registry/registry-add-package.png)。

::: info
<!-- -->
Xcode 目前不支援將原始碼控制套件自動取代為其相對應的註冊表套件。您需要手動移除原始碼控制套件並新增註冊表套件，以加快解析速度。
<!-- -->
:::
