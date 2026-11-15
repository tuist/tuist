---
{
  "title": "Bazel キャッシュ",
  "titleTemplate": ":title · キャッシュ · 機能 · ガイド · Tuist",
  "description": "Tuist を使用して、チームや CI で Bazel のリモートキャッシュエントリを共有します。"
}
---
# Bazel キャッシュ {#bazel-cache}

Tuist は、Bazel がリモートキャッシュとして接続する [Remote Execution API](https://github.com/bazelbuild/remote-apis) キャッシュを公開しています。アクションの出力がすでにキャッシュにある場合、Bazel はそのアクションをスキップし、Tuist のキャッシュから結果を取得するため、チーム全体および CI 環境でのコンパイル時間を短縮できます。キャッシングとリモート実行を備えた GitHub Actions の設定については、[Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions) を参照してください。

## セットアップ {#setup}

Bazel ワークスペースのルートから次を実行します。

```bash
tuist bazel setup
```

これにより、`.bazelrc.tuist` ファイルが `.bazelrc` の隣に作成され、最も近い Tuist キャッシュリージョンに接続され、ワークスペースごとの認証ヘルパーを通じて認証されます。また、リポジトリの `.bazelrc` に `try-import` 行を追加します。

```text
try-import %workspace%/.bazelrc.tuist
```

インポートを自分で管理したい場合は、`--no-add-bazelrc-import` を指定してください。

`.bazelrc.tuist` を `.gitignore` に追加し、コミットする代わりに各マシンでセットアップを実行してください。生成されたファイルは、現在のユーザーの Tuist 設定ディレクトリ内の絶対パスにある認証ヘルパーと、それを生成したマシンに最も近いキャッシュリージョンを指すため、これらの値は同僚や継続的インテグレーションランナーには引き継がれません。すべてのマシンで同じである `.bazelrc` 内の `try-import` 行をコミットしてください。

セットアップは、Bazel ワークスペースマーカーが見つからない場合、ファイルがシンボリックリンクの場合、またはすでにリモートキャッシュや Build Event Service が構成されている場合は、既存の `.bazelrc` を変更しません。そのため、再度実行しても冪等性が保たれます。

統合を検証するために、通常の Bazel コマンドを実行します。

```bash
bazel build //...
```

その後、キャッシュアクティビティは Tuist ダッシュボードのプロジェクトの **Bazel Cache** ページに表示され、キャッシュ転送、ダウンロードとアップロード、読み書きのレイテンシ、スループット、およびアクションキャッシュのヒット率が示されます。プロジェクトの **Overview** には、ビルド時間とともに同じアクションキャッシュのヒット率の概要が表示されます。

特定のコマンドがキャッシュをどのように使用したかを確認するには、**Invocations** から開いてください。呼び出しページでは、アクションキャッシュのルックアップとコンテンツオブジェクトのリクエストが区別されているため、コールドなアクションキャッシュと遅いアーティファクトのダウンロードを区別できます。

## リモート実行 {#remote-execution}

Tuist は Linux エグゼキューター上で Bazel アクションを実行することもできるため、キャッシュミスはローカルマシンや CI ランナーではなくリモートで実行されます。セットアップ時に `--remote-execution` を指定してください。

```bash
tuist bazel setup --remote-execution
```

セットアップにより、`.bazelrc.tuist` 内で Bazel が Tuist のエグゼキューターを指すように設定され、リモートキャッシュの隣に配置されます。実行ごとに現在のエグゼキューターとイメージを検索するため、生成された値をコピーするのではなく、セットアップを再実行してください。アクションはマシンにインストールされたツールではなく、エグゼキューターの Linux ツールチェーンで実行されるため、ワークスペースでアクションに必要なツールチェーンを宣言してください。

セットアップでは、`--jobs` もアカウントで同時に実行可能なリモートアクション数の 2 倍に設定されるため、次のアクションが待機状態になります。これがなければ、Bazel はマシンのコア数と同じ数のアクションを並列に実行し、2 コアの CI ランナーでは同時に 2 つのリモートアクションしか実行されません。

異なる値を使用するには、コマンドラインで `--jobs` を指定するか、`try-import` 行の後に `.bazelrc` で設定してください。Bazel は最後に読み込んだ値を使用するため、その行より前の `--jobs` は生成された値で置き換えられます。

## ビルドインサイト {#build-insights}

デフォルトでは、`tuist bazel setup` によって Bazel の Build Event Service も構成され、完了したコマンドが **Invocations** ダッシュボードに表示されます。ダッシュボードに表示される内容やカスタムメタデータの添付方法については、<.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> を参照してください。

リモートキャッシュのみを使用し、ビルドイベントストリームを送信したくない場合は、次を使用してオプトアウトしてください。

```bash
tuist bazel setup --no-build-insights
```

## 継続的インテグレーション {#continuous-integration}

<.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> のいずれかの方法で CI を認証し、チェックアウトステップの一部として `tuist bazel setup` を一度実行して、`.bazelrc.tuist` がランナーに適したリージョンを反映するようにします。プロバイダー固有の例については、<.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> を参照してください。

## データ保持 {#data-retention}

Tuist はリモートキャッシュの観測データを 90 日間保持します。完全なポリシーについては、<.localized_link href="/guides/server/data-retention">data retention</.localized_link> を参照してください。
