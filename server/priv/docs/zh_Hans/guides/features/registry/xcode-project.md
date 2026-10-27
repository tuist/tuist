---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# Xcode 项目{#xcode-project}

要在 Xcode 项目中使用注册表添加软件包，请使用默认的 Xcode UI。您可以点击 Xcode 中`Package Dependencies`
标签页中的`+` 按钮，在注册表中搜索软件包。如果软件包在注册表中可用，您将在右上角看到`tuist.dev` 注册表：

添加软件包依赖关系](/images/guides/features/build/registry/registry-add-package.png)。

信息
<!-- -->
Xcode 目前不支持将源代码控制包自动替换为其注册表对应包。您需要手动删除源代码控制包并添加注册表包，以加快解决速度。
<!-- -->
:::
