---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# 翻訳する {#translate}

言語が理解の障壁になることがあります。私たちは、Tuistができるだけ多くの人にとって利用しやすいものであるようにしたいと考えています。もしあなたがTuistがサポートしていない言語を話すなら、Tuistの様々な面を翻訳することで私たちを助けることができます。

翻訳を維持することは継続的な努力であるため、私たちは、私たちがそれらを維持するのを助けるために喜んで貢献者を見るように言語を追加します。現在、以下の言語がサポートされています：

- 英語
- 韓国語
- 日本語
- ロシア語
- 中国語
- スペイン語
- ポルトガル語

> [!TIP] REQUEST A NEW LANGUAGE
> もしTuistが新しい言語をサポートすることが有益だとお考えでしたら、新しい[コミュニティフォーラムのトピック](https://community.tuist.io/c/general/4)を作成してコミュニティと議論してください。

## どのように翻訳するか{#how-to-translate}。

Weblate](https://weblate.org/en-gb/)のインスタンスが[translate.tuist.dev](https://translate.tuist.dev)で動いています。プロジェクト](https://translate.tuist.dev/engage/tuist/)にアクセスしてアカウントを作成し、翻訳を始めることができます。

翻訳はGitHubのプルリクエストを使ってソースリポジトリに同期され、メンテナがレビューしてマージする。

> [重要] ターゲット言語のリソースを変更しないでください
> Weblateは、ソース言語とターゲット言語をバインドするためにファイルをセグメント化します。ソース言語を変更すると、バインディングが壊れてしまい、リコンシリエーションが予期しない結果をもたらす可能性があります。

## ガイドライン

以下は、私たちが翻訳を行う際のガイドラインです。

### カスタムコンテナとGitHubアラート{#custom-containers-and-github-alerts}。

カスタムコンテナ](https://vitepress.dev/guide/markdown#custom-containers)または[GitHubアラート](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)を翻訳する場合は、タイトルとコンテンツ**のみを翻訳し、アラートの種類**
は翻訳しません。

::: 詳細 GitHubアラートの例
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
# 依存関係の追加 {#add-dependencies}
```

It should be translated as (note the id is not translated):

```
# 추가하기{#add-dependencies}。
```

```
