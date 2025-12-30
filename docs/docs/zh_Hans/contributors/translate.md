---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# 翻译 {#translate｝

语言可能成为理解的障碍。我们希望尽可能多的人都能使用 Tuist。如果您使用的语言不支持 Tuist，您可以帮助我们翻译 Tuist 的各种表面。

由于维护翻译是一项持续性的工作，因此我们会在看到有贡献者愿意帮助我们维护翻译时添加语言。目前支持以下语言：

- 英语
- 韩语
- 日语
- 俄罗斯
- 中文
- 西班牙语
- 葡萄牙语

::: 提示 申请一种新语言
<!-- -->
如果您认为 Tuist
将从支持一种新语言中受益，请在社区论坛中创建一个新的[主题](https://community.tuist.io/c/general/4)与社区进行讨论。
<!-- -->
:::

## 如何翻译 {#how-to-translate｝

我们在 [translate.tuist.dev](https://translate.tuist.dev) 上运行了
[Weblate](https://weblate.org/en-gb/) 实例。您可以前往
[项目](https://translate.tuist.dev/engage/tuist/)，创建一个账户，然后开始翻译。

翻译会通过 GitHub 的拉取请求同步回源代码库，维护者会审核并合并这些请求。

警告 不要修改目标语言中的资源
<!-- -->
Weblate 对文件进行分段，以绑定源语言和目标语言。如果修改了源语言，就会破坏绑定，调和可能会产生意想不到的结果。
<!-- -->
:::

## 指导方针 {#guidelines｝

以下是我们在翻译时遵循的准则。

### 自定义容器和 GitHub 警报 {#custom-containers-and-github-alerts}

翻译 [custom containers](https://vitepress.dev/guide/markdown#custom-containers)
时，只翻译标题和内容**，而不翻译警报类型** 。

```markdown
<!-- -->
::: warning 루트 변수
<!-- -->
매니페스트의 루트에 있어야 하는 변수는...
<!-- -->
:::
```

### 标题 {#heading-titles}

翻译标题时，只翻译标题而不翻译 id。例如，在翻译以下标题时：

```markdown
# Add dependencies {#add-dependencies}
```

应翻译为（注意 ID 没有翻译）：

```markdown
# 의존성 추가하기 {#add-dependencies}
```
