---
{
  "title": "Bazel キャッシュ",
  "titleTemplate": ":title · キャッシュ · 機能 · ガイド · Tuist",
  "description": "Tuist で Bazel のリモートキャッシュエントリをチームや CI と共有しましょう。"
}
---
# Bazel キャッシュ {#bazel-cache}

Tuist は、Bazel がリモート キャッシュとして接続する [Remote Execution API](https://github.com/bazelbuild/remote-apis) キャッシュを公開しています。アクションの出力がすでにキャッシュに存在する場合、Bazel はそのアクションをスキップし、Tuist のキャッシュから結果を取得するため、チームや CI 環境全体でコンパイル時間を短縮できます。

## セットアップ {#setup}

Bazel ワークスペースのルートから次を実行します。

```bash
tuist bazel setup
```

これにより、`.bazelrc.tuist` ファイルが `.bazelrc` の隣に作成され、最も近い Tuist キャッシュリージョンに接続され、ワークスペースごとの認証情報ヘルパーを通じて認証されます。また、リポジトリの `.bazelrc` に `try-import` 行が追加されます。

```text
try-import %workspace%/.bazelrc.tuist
```

インポートを自分で管理したい場合は、`--no-add-bazelrc-import` を指定してください。

`.bazelrc.tuist` を `.gitignore` に追加し、コミットする代わりに各マシンでセットアップを実行してください。生成されたファイルは、現在のユーザーの Tuist 設定ディレクトリ配下の絶対的な認証情報ヘルパーのパスと、それを生成したマシンに最も近いキャッシュリージョンを指すため、これらの値はチームメンバーや継続的インテグレーションランナーには引き継がれません。すべてのマシンで同じである `.bazelrc` 内の `try-import` 行をコミットしてください。

セットアップは、Bazel ワークスペースのマーカーが見つからない場合、ファイルがシンボリックリンクである場合、またはすでにリモート キャッシュや Build Event Service が構成されている場合は、既存の `.bazelrc` を変更しません。そのため、再度実行しても冪等性が保たれます。

統合を検証するために、通常の Bazel コマンドを実行します。

```bash
bazel build //...
```

その後、キャッシュ アクティビティは Tuist ダッシュボードのプロジェクトの **Bazel Cache** ページに表示され、キャッシュ転送、ダウンロードとアップロード、読み取りおよび書き込みのレイテンシ、スループット、アクション キャッシュのヒット率を示します。プロジェクトの **Overview** には、ビルド時間とともに同じアクション キャッシュのヒット率の概要が表示されます。

特定のコマンドがキャッシュをどのように使用したかを確認するには、**Invocations** から開いてください。呼び出しページでは、アクション キャッシュのルックアップとコンテンツ オブジェクトのリクエストが区別されているため、コールドなアクション キャッシュと遅いアーティファクトのダウンロードを区別できます。

## ビルドの洞察 {#build-insights}

デフォルトでは、`tuist bazel setup` によって Bazel の Build Event Service も構成されるため、完了したコマンドが **Invocations** ダッシュボードに表示されます。ダッシュボードに表示される内容やカスタム メタデータを添付する方法については、<.localized_link href="/guides/features/build-insights/bazel">Bazel ビルドの洞察</.localized_link> を参照してください。

リモート キャッシュのみを使用し、ビルド イベント ストリームを送信したくない場合は、次のようにオプトアウトしてください。

```bash
tuist bazel setup --no-build-insights
```

## 継続的インテグレーション {#continuous-integration}

<.localized_link href="/guides/server/authentication#continuous-integration">認証ガイド</.localized_link> のいずれかの方法を使用して CI を認証し、チェックアウト ステップの一部として `tuist bazel setup` を一度実行して、`.bazelrc.tuist` がランナーに適したリージョンを反映するようにします。プロバイダー固有の例については、<.localized_link href="/guides/integrations/continuous-integration">継続的インテグレーション ガイド</.localized_link> を参照してください。

## データ保持 {#data-retention}

Tuist はリモート キャッシュの観測データを 90 日間保持します。完全なポリシーについては、<.localized_link href="/guides/server/data-retention">データ保持</.localized_link> を参照してください。
