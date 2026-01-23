---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# Xcode 项目{#xcode-project}

要在 Xcode 项目中使用注册库添加包，请使用默认的 Xcode 界面。您可在 Xcode 的“`”&gt;“Package
Dependencies”&gt;“` ”选项卡中，点击“` ”+“` ”按钮搜索注册库中的包。若包在注册库中可用，右上角将显示`tuist.dev` 注册库：

![添加包依赖项](/images/guides/features/build/registry/registry-add-package.png)

信息
<!-- -->
Xcode 目前不支持自动将源代码控制包替换为注册表对应项。您需要手动移除源代码控制包并添加注册表包以加快问题解决速度。
<!-- -->
:::
