---
{
  "title": "Bazel キャッシュ",
  "titleTemplate": ":title · キャッシュ · 機能 · ガイド · Tuist",
  "description": "Tuist を使って、チームや CI 間で Bazel のリモートキャッシュエントリを共有します。"
}
---
# Bazelキャッシュ {#bazel-cache}

Tuistは、Bazelがリモートキャッシュとして接続する[Remote Execution API](https://github.com/bazelbuild/remote-apis)キャッシュを公開しています。アクションの出力がすでにキャッシュにある場合、Bazelはそのアクションをスキップし、Tuistのキャッシュから結果を取得します。これにより、チーム全体およびCI環境でのコンパイル時間を短縮できます。

## セットアップ {#setup}

Bazelワークスペースのルートから、以下を実行してください：

```bash
tuist bazel setup
```

これにより、`.bazelrc.tuist`ファイルが`.bazelrc`の隣に作成され、最も近いTuistキャッシュリージョンに接続され、ワークスペースごとの認証ヘルパーを通じて認証されます。また、リポジトリの`.bazelrc`に`try-import`行を追加します：

```text
try-import %workspace%/.bazelrc.tuist
```

インポートを自分で管理したい場合は、`--no-add-bazelrc-import`を指定してください。

`.bazelrc.tuist`を`.gitignore`に追加し、コミットする代わりに各マシンでセットアップを実行してください。生成されたファイルは、現在のユーザーのTuist設定ディレクトリ下の絶対的な認証ヘルパーパスと、それを生成したマシンに最も近いキャッシュリージョンを指しているため、これらの値はチームメンバーや継続的インテグレーションランナーには引き継がれません。`.bazelrc`内の`try-import`行をコミットしてください。これはすべてのマシンで同じです。

Bazelワークスペースのマーカーが見つからない場合、ファイルがシンボリックリンクである場合、またはすでにリモートキャッシュやBuild Event Serviceが設定されている場合、セットアップは既存の`.bazelrc`を変更しません。そのため、再度実行しても冪等性が保たれます。

統合を検証するために、通常のBazelコマンドを実行してください：

```bash
bazel build //...
```

キャッシュアクティビティは、Tuistダッシュボードのプロジェクトの**Bazel Cache**ページに表示されます。ここには、キャッシュ転送、ダウンロードとアップロード、読み書きレイテンシ、スループット、およびアクションキャッシュヒット率が表示されます。プロジェクトの**Overview**には、ビルド時間とともに同じアクションキャッシュヒット率の概要が表示されます。

特定のコマンドがキャッシュをどのように使用したかを確認するには、**Invocations**から開いてください。呼び出しページでは、アクションキャッシュのルックアップとコンテンツオブジェクトのリクエストが分離されており、コールドなアクションキャッシュと遅いアーティファクトダウンロードを区別できます。

## ビルドインサイト {#build-insights}

デフォルトでは、`tuist bazel setup`はBazelのBuild Event Serviceも設定するため、完了したコマンドが**Invocations**ダッシュボードに表示されます。ダッシュボードに表示される内容やカスタムメタデータの添付方法については、<.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link>を参照してください。

リモートキャッシュのみを使用し、ビルドイベントストリームを送信したくない場合は、以下でオプトアウトしてください：

```bash
tuist bazel setup --no-build-insights
```

## 継続的インテグレーション {#continuous-integration}

<.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link>に記載されているいずれかの方法でCIを認証し、チェックアウトステップの一部として`tuist bazel setup`を一度実行して、`.bazelrc.tuist`がランナーに適したリージョンを反映するようにしてください。プロバイダー固有の例については、<.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link>を参照してください。

## データ保持 {#data-retention}

Tuistはリモートキャッシュの観測データを90日間保持します。完全なポリシーについては、<.localized_link href="/guides/server/data-retention">data retention</.localized_link>を参照してください。
