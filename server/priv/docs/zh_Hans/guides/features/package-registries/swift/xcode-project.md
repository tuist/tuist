---
{
  "title": "Xcode 项目",
  "titleTemplate": ":title · Swift · 包注册表 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Xcode 项目中使用 Tuist Registry。"
}
---
# Xcode 项目 {#xcode-project}

要在 Xcode 项目中使用注册表添加包，请使用默认的 Xcode 界面。你可以点击 Xcode 中 `Package Dependencies` 标签页里的 `+` 按钮，在注册表中搜索包。如果该包在注册表中可用，你将在右上角看到 `tuist.dev` 注册表：

![添加包依赖项](/images/guides/features/build/registry/registry-add-package.png)

## 解析源代码管理包 {#resolving-source-control-packages}

使用源代码管理 URL 声明的包（例如你所添加包的传递依赖项）默认会从源代码管理中解析。`tuist registry setup` 会通过写入以下用户默认设置，将 Xcode 配置为改为从注册表中解析它们：

```bash
defaults write com.apple.dt.Xcode IDEPackageDependencySCMToRegistryTransformation useRegistryIdentityAndSources
```

随后，只要存在等效的注册表包，Xcode 就会从注册表中解析源代码管理包；否则回退到源代码管理。

> [!NOTE]
> 这是每台机器上的 Xcode 偏好设置，而非项目设置，因此提交注册表配置文件不会将其共享给团队其他成员。每位开发者都需要在自己的机器上运行一次 `tuist registry setup`。该偏好设置随后会应用于该机器上的所有 Xcode 项目。
