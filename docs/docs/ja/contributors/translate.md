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

::: tip 新しい言語をリクエストする
<!-- -->
Tuistが新しい言語をサポートすることが有益だと思われる場合は、新しい[コミュニティフォーラムのトピック](https://community.tuist.io/c/general/4)を作成してコミュニティと議論してください。
<!-- -->
:::

## 翻訳方法 {#how-to-translate}

[Weblate](https://weblate.org/en-gb/)のインスタンスが[translate.tuist.dev](https://translate.tuist.dev)で動いています。[プロジェクト](https://translate.tuist.dev/engage/tuist/)にアクセスしてアカウントを作成し、翻訳を始めることができます。

翻訳はGitHubのプルリクエストを使ってソースリポジトリに同期され、メンテナがレビューしてマージする。

::: warning 対象言語のリソースを変更しないでください
<!-- -->
Weblateは、ソース言語とターゲット言語をバインドするためにファイルをセグメント化します。ソース言語を変更すると、バインディングが壊れ、リコンシリエーションが予期せぬ結果をもたらすかもしれません。
<!-- -->
:::

## ガイドライン {#guidelines}

以下は、私たちが翻訳を行う際のガイドラインです。

### カスタムコンテナとGitHubアラート {#custom-containers-and-github-alerts}

[カスタムコンテナ](https://vitepress.dev/guide/markdown#custom-containers)を翻訳する場合、タイトルとコンテンツのみを翻訳しますが、**アラートのタイプは翻訳しません**。

```markdown
<!-- -->
::: warning 루트 변수
<!-- -->
매니페스트의 루트에 있어야 하는 변수는...
<!-- -->
:::
```

### 見出しタイトル {#heading-titles}

見出しを翻訳するときは、タイトルだけを翻訳し、idは翻訳しないでください。例えば、以下の見出しを翻訳する場合：

```markdown
# Add dependencies {#add-dependencies}
```

以下のように訳すべきである（idは訳されていないことに注意）：

```markdown
# 의존성 추가하기 {#add-dependencies}
```
