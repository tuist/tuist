---
title: 翻訳する
titleTemplate: :title · コントリビューター · Tuist
description: このドキュメントでは、Tuist の開発を導く原則について説明します。
---

# 翻訳 {#translate}

言語は理解を妨げる大きな壁になることがあります。 私たちは Tuist をできるだけ多くの人に使っていただきたいと考えています。 もし Tuist がサポートしていない言語を話す場合、Tuist のさまざまな部分を翻訳していただくことでご協力ください。

翻訳をメンテナンスするためには継続的な取り組みが必要となるため、私たちはメンテナンスに協力してくださるコントリビューターがいる言語を随時追加していきます。 現在サポートされている言語は、以下のとおりです：

- 英語
- 韓国語
- 日本語
- ロシア語

> [!TIP] 新しい言語のリクエスト
> Tuist に新しい言語サポートを追加することが有益であると考える場合は、コミュニティフォーラムの[トピック](https://community.tuist.io/c/general/4)を作成して、コミュニティと議論してみてください。

## 翻訳方法 {#how-to-translate}

私たちは翻訳の管理に [Crowdin](https://crowdin.com/) を使用しています。 まず、貢献したいプロジェクトに移動します：

- [Documentation](https://crowdin.com/project/tuist-documentation)
- [Website](https://crowdin.com/project/tuist-documentation)

You'll need an account to start translating. You can sign in with GitHub. Once you have access, you can start translating. You'll see the list of resources that are available for translation. When you click on a resource, the editor will open, and you'll see a split view with the resource in the source language on the left and the translation on the right. Translate the text on the right and save your changes.

As translations are updated, Crowdin will push them automatically to the right repository opening a pull request, which the maintainers will review and merge.

> [!IMPORTANT] DON'T MODIFY THE RESOURCES IN THE TARGET LANGUAGE
> Crowdin segments the files to bind source and target languages. If you modify the source language, you'll break the binding, and the reconciliation might yield unexpected results.

## Guidelines

The following are the guidelines we follow when translating.

### Custom containers and GitHub alerts

When translating [custom containers](https://vitepress.dev/guide/markdown#custom-containers) or [GitHub Alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts), only translate the title and the content **but not the type of alert**.

:::details Example with GitHub Alert

````markdown
    > [!WARNING] 루트 변수
    > 매니페스트의 루트에 있어야 하는 변수는...

    // Instead of
    > [!주의] 루트 변수
    > 매니페스트의 루트에 있어야 하는 변수는...
    ```
:::


::: details Example with custom container
```markdown
    ::: warning 루트 변수\
    매니페스트의 루트에 있어야 하는 변수는...
    :::

    # Instead of
    ::: 주의 루트 변수\
    매니페스트의 루트에 있어야 하는 변수는...
    :::
````

:::

### Heading titles

When translating headings, only translate tht title but not the id. For example, when translating the following heading:

```markdown
# Add dependencies {#add-dependencies}
```

It should be translated as (note the id is not translated):

```markdown
# 의존성 추가하기 {#add-dependencies}
```
