---
{
  "title": "Xcode ビルドインサイト",
  "titleTemplate": ":title · ビルドインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで Xcode のビルド分析を追跡し、ローカルおよび CI ビルドのパフォーマンスを監視します。"
}
---
# Xcode ビルドインサイト {#xcode-build-insights}

大規模プロジェクトでの作業において、同じコードを何度も再ビルドする必要はありません。Tuist Build Insights を使えば、ビルドの分析データを追跡でき、ローカルおよび CI のビルド時間がボトルネックになる前に傾向を把握できます。

ビルドインサイトは `tuist inspect build` コマンドによって提供され、通常はスキームのポストアクションに追加します。

ローカルのビルド時間の追跡を開始するには、スキームのポストアクションに `tuist inspect build` コマンドを追加して活用できます：

![ビルドを調査するためのポストアクション](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> 「Provide build settings from」フィールドを実行可能ファイルまたはメインのビルドターゲットに設定し、ビルド構成をキャプチャしてください。

> [!NOTE]
> ビルドが失敗した場合、ポストスキームアクションは実行されません。
>
> その場合は、スキームの `.xcscheme` ファイル内の `<BuildAction>` 要素で `runPostActionsOnFailure` を `YES` に設定することで実行できます：
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

[Mise](https://mise.jdx.dev/) の場合、ポストアクション環境で `tuist` を有効化してください：

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise のパス解決**
>
> 環境の `PATH` はスキームのポストアクションに継承されないため、Mise の絶対パスを使用してください。これは Mise のインストール方法によって異なります。ビルド設定はターゲットから継承されるべきであり、`mise` が `$SRCROOT` から実行できるようにします。

[Homebrew](https://brew.sh/) の場合、Homebrew のパスをポストアクション環境に追加してください：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

ログインすると、ローカルビルドが追跡され、Tuist ダッシュボードから利用できるようになります：

> [!TIP]
> ダッシュボードにすばやくアクセスするには、CLI から `tuist project show --web` を実行してください。

![ビルドインサイト付きダッシュボード](/images/guides/features/build-insights/builds-dashboard.png)

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
