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

翻訳を始めるにはアカウントが必要です。 GitHub アカウントでサインインできます。 サインイン後にアクセス権を得ると、翻訳を始められます。 翻訳対象のリソース一覧が表示されます。 リソースをクリックするとエディタが開き、左側にソース言語のリソース、右側に翻訳する箇所が表示されます。 右側のテキストを翻訳し、変更を保存してください。

翻訳が更新されると Crowdin が自動的に該当リポジトリにプルリクエストを送信し、メンテナーがレビューとマージを行います。

> [!IMPORTANT] 対象言語のリソースに直接変更を加えないでください
> Crowdin はファイルをセグメント化してソース言語とターゲット言語を関連付けています。 ソース言語を変更すると、この紐付けが壊れ、想定外の結果が生じる可能性があります。

## ガイドライン {#guidelines}

以下は私たちが翻訳の際に従っているガイドラインです。

### カスタムコンテナや GitHub Alerts について {#custom-containers-and-github-alerts}

[カスタムコンテナ](https://vitepress.dev/guide/markdown#custom-containers) や [GitHub Alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts) を翻訳する際は、タイトルと内容のみ翻訳し、アラートの種類自体は翻訳しないようにしてください。

:::details GitHub Alert の例

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

### 見出しタイトル {#heading-titles}

見出しを翻訳する場合、見出しのタイトル部分のみ翻訳し、ID は変更しないでください。 たとえば、次の見出しがあるとします：

```markdown
# Add dependencies {#add-dependencies}
```

これを翻訳する場合は、ID をそのままにして以下のように翻訳してください：

```markdown
# 의존성 추가하기 {#add-dependencies}
```
