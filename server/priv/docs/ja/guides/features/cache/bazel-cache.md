---
{
  "title": "Bazel キャッシュ",
  "titleTemplate": ":title · キャッシュ · 機能 · ガイド · Tuist",
  "description": "Tuist で Bazel のリモートキャッシュエントリをチームや CI と共有します。"
}
---
# Bazel キャッシュ {#bazel-cache}

Tuist は、Bazel がリモート キャッシュとして接続する [Remote Execution API](https://github.com/bazelbuild/remote-apis) キャッシュを公開しています。アクションの出力がすでにキャッシュに存在する場合、Bazel はそのアクションをスキップし、Tuist のキャッシュから結果を取得します。これにより、チーム全体および CI 環境でのコンパイル時間を短縮できます。

## セットアップ {#setup}

Bazel ワークスペースのルートで次を実行してください:

```bash
tuist bazel setup
```

これにより、`.bazelrc` の隣に `.bazelrc.tuist` ファイルが作成され、最も近い Tuist キャッシュリージョンに接続され、ワークスペースごとの認証情報ヘルパーを通じて認証されます。また、リポジトリの `.bazelrc` に `try-import` 行を追加します:

```text
try-import %workspace%/.bazelrc.tuist
```

インポートを自分で管理したい場合は、`--no-add-bazelrc-import` を指定してください。

`.bazelrc.tuist` を `.gitignore` に追加し、コミットする代わりに各マシンでセットアップを実行してください。生成されたファイルは、現在のユーザーの Tuist 設定ディレクトリ下の絶対パスにある認証情報ヘルパーと、それを生成したマシンに最も近いキャッシュリージョンを指すため、これらの値はチームメイトや継続的インテグレーションランナーには引き継がれません。すべてのマシンで同じである `.bazelrc` 内の `try-import` 行をコミットしてください。

Bazel ワークスペースのマーカーが見つからない場合、ファイルがシンボリックリンクの場合、またはすでにリモート キャッシュや Build Event Service が構成されている場合、セットアップは既存の `.bazelrc` を変更しません。このため、再度実行しても冪等性が保たれます。

統合を検証するために、通常の Bazel コマンドを実行してください:

```bash
bazel build //...
```

その後、キャッシュのアクティビティは Tuist ダッシュボードのプロジェクトの **Bazel Cache** ページに表示され、キャッシュ転送、ダウンロードとアップロード、読み書きのレイテンシ、スループット、およびアクション キャッシュのヒット率を示します。プロジェクトの **Overview** には、ビルド時間とともに同じアクション キャッシュのヒット率の概要が表示されます。

特定のコマンドがキャッシュをどのように使用したかを確認するには、**Invocations** から開いてください。呼び出しページでは、アクション キャッシュのルックアップとコンテンツ オブジェクトのリクエストが区別されているため、コールドなアクション キャッシュと遅いアーティファクトのダウンロードを区別できます。

## リモート実行 {#remote-execution}

Tuist は、Bazel アクションを Linux エグゼキューター上で実行することもできるため、キャッシュミスはローカル マシンや CI ランナーではなくリモートで処理されます。セットアップ時に `--remote-execution` を指定してください:

```bash
tuist bazel setup --remote-execution
```

セットアップにより、`.bazelrc.tuist` 内で Bazel が Tuist のエグゼキューターを指すように設定され、リモート キャッシュの隣に配置されます。実行ごとに現在のエグゼキューターとイメージを検索するため、生成された値をコピーするのではなく、セットアップを再実行してください。アクションはマシンにインストールされたツールではなく、エグゼキューターの Linux ツールチェーンで実行されるため、ワークスペースでアクションに必要なツールチェーンを宣言してください。

セットアップでは、`--jobs` もアカウントで同時に実行可能なリモート アクション数の 2 倍に設定されるため、次のアクションが待機状態になります。これがなければ、Bazel はマシンのコア数と同じ数のアクションを並列に実行し、2 コアの CI ランナーでは同時に 2 つのリモート アクションしか実行できません。

異なる値を使用するには、コマンドラインで `--jobs` を指定するか、`try-import` 行の後に `.bazelrc` で設定してください。Bazel は最後に読み取った値を使用するため、その行より前の `--jobs` は生成された値で置き換えられます。

## ビルドの洞察 {#build-insights}

デフォルトでは、`tuist bazel setup` によって Bazel の Build Event Service も構成されるため、完了したコマンドが **Invocations** ダッシュボードに表示されます。ダッシュボードに表示される内容やカスタム メタデータを添付する方法については、<.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> を参照してください。

リモート キャッシュのみが必要で、ビルド イベント ストリームを送信したくない場合は、次を使用してオプトアウトしてください:

```bash
tuist bazel setup --no-build-insights
```

## 継続的インテグレーション {#continuous-integration}

<.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> のいずれかの方法を使用して CI を認証し、チェックアウト ステップの一部として `tuist bazel setup` を一度実行して、`.bazelrc.tuist` がランナーに適したリージョンを反映するようにしてください。プロバイダー固有の例については、<.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> を参照してください。

## データ保持 {#data-retention}

Tuist はリモート キャッシュの観測データを 90 日間保持します。完全なポリシーについては、<.localized_link href="/guides/server/data-retention">data retention</.localized_link> を参照してください。
