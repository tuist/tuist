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

> [提示] 申请一种新语言 如果您认为支持一种新语言会使 Tuist
> 受益，请在社区论坛创建一个新的[主题](https://community.tuist.io/c/general/4)，与社区讨论。

## 如何翻译 {#how-to-translate｝

我们在 [translate.tuist.dev](https://translate.tuist.dev) 上运行了
[Weblate](https://weblate.org/en-gb/) 实例。您可以前往
[项目](https://translate.tuist.dev/engage/tuist/)，创建一个账户，然后开始翻译。

翻译会通过 GitHub 的拉取请求同步回源代码库，维护者会审核并合并这些请求。

> [重要] 请勿修改目标语言中的资源 Weblate 将文件分段绑定源语言和目标语言。如果您修改了源语言，就会破坏绑定，调和可能会产生意想不到的结果。

## 指导方针 {#guidelines｝

以下是我们在翻译时遵循的准则。

### 自定义容器和 GitHub 警报 {#custom-containers-and-github-alerts}

翻译 [自定义容器](https://vitepress.dev/guide/markdown#custom-containers)或 [GitHub
警报](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)时，只翻译标题和内容**，而不翻译警报类型**
。

带有 GitHub 警报的详细示例
```markdown
    > [!WARNING] 루트 변수
    > 매니페스트의 루트에 있어야 하는 변수는...

    // Instead of
    > [!주의] 루트 변수
    > 매니페스트의 루트에 있어야 하는 변수는...
    ```
:::


::: details Example with custom container
```
    ::: warning 루트 변수\
    매니페스트의 루트에 있어야 하는 변수는...
    :::

    # Instead of
    ::: 주의 루트 변수\
    매니페스트의 루트에 있어야 하는 변수는...
    :::
```
:::

### Heading titles {#heading-titles}

When translating headings, only translate tht title but not the id. For example, when translating the following heading:

```
# 添加依赖项 {#add-dependencies}
```

It should be translated as (note the id is not translated):

```
# 의존성 추가하기 {#add-dependencies}
```

```
