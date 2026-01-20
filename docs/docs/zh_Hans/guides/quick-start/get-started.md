---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# 开始{#get-started}

最简单的方法是在任意目录或 Xcode 项目或工作区目录中开始使用 Tuist：

代码组

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

该命令将引导您完成<LocalizedLink href="/guides/features/projects">创建生成项目</LocalizedLink>或集成现有
Xcode
项目或工作区的步骤。它可以帮助你将设置连接到远程服务器，让你访问<LocalizedLink href="/guides/features/selective-testing">选择性测试</LocalizedLink>、<LocalizedLink href="/guides/features/previews">预览</LocalizedLink>和<LocalizedLink href="/guides/features/registry">注册表</LocalizedLink>等功能。

::: info MIGRATE AN EXISTING PROJECT
<!-- -->
如果您想将现有项目迁移到生成的项目中，以改善开发人员的体验并利用我们的<LocalizedLink href="/guides/features/cache">缓存</LocalizedLink>，请查看我们的<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">迁移指南</LocalizedLink>。
<!-- -->
:::
