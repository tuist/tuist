---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# 開始{#get-started}

在任何目錄或 Xcode 專案或工作區的目錄中開始使用 Tuist 的最簡單方法：

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

該命令將引導您完成<LocalizedLink href="/guides/features/projects">創建生成專案</LocalizedLink>或整合現有
Xcode
專案或工作區的步驟。它會幫助您將設定連線至遠端伺服器，讓您可以使用<LocalizedLink href="/guides/features/selective-testing">選擇性測試</LocalizedLink>、<LocalizedLink href="/guides/features/previews">預覽</LocalizedLink>和<LocalizedLink href="/guides/features/registry">註冊表</LocalizedLink>等功能。

::: info MIGRATE AN EXISTING PROJECT
<!-- -->
如果您想要將現有專案遷移至已產生的專案，以改善開發人員的經驗，並利用我們的
<LocalizedLink href="/guides/features/cache">cache</LocalizedLink> 優勢，請參閱我們的
<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">migration 指南</LocalizedLink>。
<!-- -->
:::
