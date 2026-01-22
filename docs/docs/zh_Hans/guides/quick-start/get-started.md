---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# 开始操作{#get-started}

在任意目录或Xcode项目/工作区目录中启动Tuist的最简方式：

代码组

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

该命令将引导您完成以下步骤：<LocalizedLink href="/guides/features/projects">创建生成项目</LocalizedLink>或集成现有Xcode项目/工作区。它可帮助您将环境连接至远程服务器，从而访问<LocalizedLink href="/guides/features/selective-testing">选择性测试</LocalizedLink>、<LocalizedLink href="/guides/features/previews">预览</LocalizedLink>及<LocalizedLink href="/guides/features/registry">注册表</LocalizedLink>等功能。

::: info MIGRATE AN EXISTING PROJECT
<!-- -->
若需将现有项目迁移至生成式项目以提升开发体验并利用我们的<LocalizedLink href="/guides/features/cache">缓存</LocalizedLink>功能，请查阅我们的<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">迁移指南</LocalizedLink>。
<!-- -->
:::
