---
{
  "title": "Bazelキャッシュ",
  "titleTemplate": ":title · キャッシュ · 機能 · ガイド · Tuist",
  "description": "TuistでチームやCI全体でBazelのリモートキャッシュエントリを共有します。"
}
---
# Bazelキャッシュ {#bazel-cache}

Tuistは、Bazelがリモートキャッシュとして接続する[Remote Execution API](https://github.com/bazelbuild/remote-apis)キャッシュを公開しています。アクションの出力がすでにキャッシュにある場合、Bazelはそのアクションをスキップし、Tuistのキャッシュから結果を取得するため、チーム全体およびCI環境でのコンパイル時間を短縮できます。GitHub Actionsの設定については、[Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)をご覧ください。リモートキャッシュの仕組みや、セルフホスト型キャッシュとマネージド型キャッシュの違いについては、[Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)をご覧ください。

## セットアップ {#setup}

Bazelワークスペースのルートで、次を実行してください：

```bash
tuist bazel setup
```

これにより、`.bazelrc`の隣に`.bazelrc.tuist`ファイルが作成され、最も近いTuistキャッシュリージョンに接続され、ワークスペースごとの認証情報ヘルパーによって認証されます。また、リポジトリの`.bazelrc`に`try-import`行を追加します：

```text
try-import %workspace%/.bazelrc.tuist
```

インポートを自分で管理したい場合は、`--no-add-bazelrc-import`を指定してください。

`.bazelrc.tuist`を`.gitignore`に追加し、コミットする代わりに各マシンでセットアップを実行してください。生成されたファイルは、現在のユーザーのTuist設定ディレクトリ下の絶対パスにある認証情報ヘルパーと、それを生成したマシンに最も近いキャッシュリージョンを指すため、これらの値はチームメンバーや継続的インテグレーションランナーには引き継がれません。`.bazelrc`内の`try-import`行はすべてのマシンで同じであるため、これをコミットしてください。

Bazelワークスペースのマーカーが見つからない場合、ファイルがシンボリックリンクである場合、またはすでにリモートキャッシュやBuild Event Serviceが設定されている場合、セットアップは既存の`.bazelrc`を変更しません。そのため、再度実行しても冪等性が保たれます。

統合を確認するために、通常のBazelコマンドを実行してください：

```bash
bazel build //...
```

その後、キャッシュアクティビティはTuistダッシュボードのプロジェクトの**Bazel Cache**ページに表示され、キャッシュ転送、ダウンロードとアップロード、読み書きのレイテンシ、スループット、およびアクションキャッシュのヒット率が示されます。プロジェクトの**Overview**には、ビルド時間とともに同じアクションキャッシュのヒット率の概要が表示されます。

特定のコマンドがキャッシュをどのように使用したかを確認するには、**Invocations**から開いてください。呼び出しページでは、アクションキャッシュのルックアップとコンテンツオブジェクトのリクエストが区別されているため、コールドなアクションキャッシュと遅いアーティファクトのダウンロードを識別できます。

## リモート実行 {#remote-execution}

Tuistは、BazelアクションをLinuxエグゼキューター上で実行することもできるため、キャッシュミスはローカルマシンやCIランナーではなくリモートで実行されます。リモート実行はアカウントごとにリクエストに応じて有効化されます：有効にするには[お問い合わせください](mailto:contact@tuist.dev)。有効化後、セットアップ時に`--remote-execution`を指定してください：

```bash
tuist bazel setup --remote-execution
```

セットアップにより、`.bazelrc.tuist`内でBazelがTuistのエグゼキューターを指すように設定され、リモートキャッシュの隣に配置されます。実行ごとに現在のエグゼキューターとイメージを検索するため、生成された値をコピーするのではなく、セットアップを再実行してください。アクションはマシンにインストールされたツールではなく、エグゼキューターのLinuxツールチェーンで実行されるため、ワークスペースでアクションが必要とするツールチェーンを宣言してください。

セットアップはまた、`--jobs`をアカウントが同時に実行できるリモートアクション数の2倍に設定するため、次のアクションが待機状態になります。これがなければ、Bazelはマシンのコア数と同じ数のアクションを並列に実行し、2コアのCIランナーでは2つのリモートアクションのみが実行中になります。

異なる値を使用するには、コマンドラインで`--jobs`を指定するか、`try-import`行の後の`.bazelrc`で設定してください。Bazelは最後に読み取った値を使用するため、その行の前にある`--jobs`は生成された値に置き換えられます。

## ビルドインサイト {#build-insights}

デフォルトでは、`tuist bazel setup`はBazelのBuild Event Serviceも設定するため、完了したコマンドが**Invocations**ダッシュボードに表示されます。ダッシュボードに表示される内容やカスタムメタデータの添付方法については、<.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link>をご覧ください。

リモートキャッシュのみを使用し、ビルドイベントストリームを送信したくない場合は、以下でオプトアウトしてください：

```bash
tuist bazel setup --no-build-insights
```

## 継続的インテグレーション {#continuous-integration}

<.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link>に記載されている方法のいずれかを使用してCIを認証し、チェックアウトステップの一部として`tuist bazel setup`を1回実行して、`.bazelrc.tuist`がランナーに適したリージョンを反映するようにしてください。プロバイダー固有の例については、<.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link>をご覧ください。

## データ保持 {#data-retention}

Tuistはリモートキャッシュの観測データを90日間保持します。完全なポリシーについては、<.localized_link href="/guides/server/data-retention">data retention</.localized_link>をご覧ください。
