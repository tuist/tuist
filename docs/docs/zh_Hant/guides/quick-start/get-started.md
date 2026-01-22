---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# 開始使用{#get-started}

在任何目錄或您的 Xcode 專案／工作區目錄中開始使用 Tuist 的最簡便方式：

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

此指令將引導您逐步完成以下步驟：<LocalizedLink href="/guides/features/projects">建立生成專案</LocalizedLink>或整合現有
Xcode 專案／工作區。它協助您將設定連接到遠端伺服器，使您能使用諸如
<LocalizedLink href="/guides/features/selective-testing">選擇性測試</LocalizedLink>、<LocalizedLink href="/guides/features/previews">預覽功能</LocalizedLink>及
<LocalizedLink href="/guides/features/registry">註冊表</LocalizedLink>等服務。

::: info MIGRATE AN EXISTING PROJECT
<!-- -->
若欲將現有專案遷移至生成式專案以提升開發者體驗並運用我們的<LocalizedLink href="/guides/features/cache">快取</LocalizedLink>功能，請參閱我們的<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">遷移指南</LocalizedLink>。
<!-- -->
:::
