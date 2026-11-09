---
{
  "title": "Xcode ビルドインサイト",
  "titleTemplate": ":title · ビルドインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで Xcode のビルド分析を追跡し、ローカルおよび CI のビルドパフォーマンスを監視します。"
}
---
# Xcode ビルドインサイト {#xcode-build-insights}

大規模なプロジェクトでは、同じコードを何度も再ビルドする必要はありません。Tuist Build Insights を使えば、ビルドの分析データを追跡でき、ローカルや CI のビルド時間がボトルネックになる前に傾向を把握できます。

ビルドインサイトは `tuist inspect build` コマンドによって動作し、通常はスキームのポストアクションに追加します。

ローカルのビルド時間の追跡を開始するには、スキームのポストアクションに `tuist inspect build` コマンドを追加します。

![ビルドを検査するためのポストアクション](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> 「Provide build settings from」フィールドを実行可能ファイルまたはメインのビルドターゲットに設定し、ビルド構成を取得します。

> [!NOTE]
> ビルドが失敗した場合、ポストスキームアクションは実行されません。
>
> その場合は、スキームの `.xcscheme` ファイルにある `<BuildAction>` 要素で `runPostActionsOnFailure` を `YES` に設定することで実行できます。
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

[Mise](https://mise.jdx.dev/) の場合、ポストアクション環境で `tuist` を有効化します。

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise のパス解決**
>
> 環境の `PATH` はスキームのポストアクションに継承されないため、Mise の絶対パスを使用してください。これは Mise のインストール方法によって異なります。ビルド設定はターゲットから継承されるため、`mise` を `$SRCROOT` から実行できます。

[Homebrew](https://brew.sh/) の場合、Homebrew のパスをポストアクション環境に追加します。

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

ログインすると、ローカルビルドが追跡され、Tuist ダッシュボードから確認できます。

> [!TIP]
> ダッシュボードにすばやくアクセスするには、CLI から `tuist project show --web` を実行します。

![ビルドインサイト付きダッシュボード](/images/guides/features/build-insights/builds-dashboard.png)

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
