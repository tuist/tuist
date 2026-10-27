---
{
  "title": "Bazel cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Share Bazel remote cache entries across your team and CI with Tuist."
}
---
# Bazel キャッシュ {#bazel-cache}

Tuist は、Bazel がリモートキャッシュとして接続する [Remote Execution API](https://github.com/bazelbuild/remote-apis) キャッシュを公開しています。アクションの出力がすでにキャッシュにある場合、Bazel はそのアクションをスキップし、Tuist のキャッシュから結果を取得するため、チーム全体および CI 環境でのコンパイル時間を短縮できます。

## セットアップ {#setup}

Bazel ワークスペースのルートから、次を実行します：

```bash
tuist bazel setup
```

これにより、`.bazelrc.tuist` ファイルが `.bazelrc` の隣に作成され、最も近い Tuist キャッシュリージョンに接続され、ワークスペースごとの認証情報ヘルパーを通じて認証されます。また、リポジトリの `.bazelrc` に `try-import` 行を追加します：

```text
try-import %workspace%/.bazelrc.tuist
```

インポートを自分で管理したい場合は、`--no-add-bazelrc-import` を渡してください。

`.bazelrc.tuist` を `.gitignore` に追加し、コミットする代わりに各マシンでセットアップを実行してください。生成されたファイルは、現在のユーザーの Tuist 設定ディレクトリ下の絶対的な認証情報ヘルパーのパスと、それを生成したマシンに最も近いキャッシュリージョンを指すため、これらの値はチームメンバーや継続的インテグレーションランナーには引き継がれません。`.bazelrc` 内の `try-import` 行をコミットしてください。これはすべてのマシンで同じです。

Bazel ワークスペースのマーカーが見つからない場合、ファイルがシンボリックリンクである場合、またはすでにリモートキャッシュや Build Event Service が構成されている場合、セットアップは既存の `.bazelrc` を変更しません。そのため、再度実行しても冪等性が保たれます。

統合を検証するために、通常の Bazel コマンドを実行します：

```bash
bazel build //...
```

その後、キャッシュアクティビティは Tuist ダッシュボードのプロジェクトの **Bazel Cache** ページに表示され、キャッシュ転送、ダウンロードとアップロード、読み書きレイテンシ、スループット、およびアクションキャッシュのヒット率を示します。プロジェクトの **Overview** には、ビルド時間とともに同じアクションキャッシュのヒット率の概要が表示されます。

特定のコマンドがキャッシュをどのように使用したかを確認するには、**Invocations** から開いてください。呼び出しページでは、アクションキャッシュのルックアップとコンテンツオブジェクトのリクエストが分離されているため、コールドなアクションキャッシュと遅いアーティファクトのダウンロードを区別できます。

## ビルドインサイト {#build-insights}

デフォルトでは、`tuist bazel setup` によって Bazel の Build Event Service も構成されるため、完了したコマンドが **Invocations** ダッシュボードに表示されます。ダッシュボードに表示される内容やカスタムメタデータの添付方法については、<.localized_link href="/guides/features/build-insights/bazel">Bazel ビルドインサイト</.localized_link> を参照してください。

リモートキャッシュのみを使用し、ビルドイベントストリームを送信したくない場合は、次を使用してオプトアウトしてください：

```bash
tuist bazel setup --no-build-insights
```

## 継続的インテグレーション {#continuous-integration}

<.localized_link href="/guides/server/authentication#continuous-integration">認証ガイド</.localized_link> のいずれかの方法を使用して CI を認証し、チェックアウトステップの一部として `tuist bazel setup` を一度実行して、`.bazelrc.tuist` がランナーに適したリージョンを反映するようにします。プロバイダー固有の例については、<.localized_link href="/guides/integrations/continuous-integration">継続的インテグレーションガイド</.localized_link> を参照してください。

## データ保持 {#data-retention}

Tuist はリモートキャッシュの観測データを 90 日間保持します。完全なポリシーについては、<.localized_link href="/guides/server/data-retention">データ保持</.localized_link> を参照してください。
