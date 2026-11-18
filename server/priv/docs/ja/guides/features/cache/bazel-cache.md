---
{
  "title": "Bazelキャッシュ",
  "titleTemplate": ":title · キャッシュ · 機能 · ガイド · Tuist",
  "description": "Tuistを使用して、チームとCI間でBazelのリモートキャッシュエントリを共有します。"
}
---
# Bazelキャッシュ {#bazel-cache}

Tuistは、Bazelがリモートキャッシュとして接続する[Remote Execution API](https://github.com/bazelbuild/remote-apis)キャッシュを公開しています。アクションの出力がすでにキャッシュにある場合、Bazelはそのアクションをスキップし、Tuistのキャッシュから結果を取得するため、チーム全体およびCI環境でのコンパイル時間を短縮できます。GitHub Actionsの設定については、[Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)をご覧ください。リモートキャッシュの仕組みや、セルフホスト型キャッシュとマネージド型キャッシュの違いについては、[Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)をご覧ください。

## セットアップ {#setup}

Bazelワークスペースのルートで次を実行します。

```bash
tuist bazel setup
```

これにより、`.bazelrc.tuist`ファイルが`.bazelrc`の隣に作成され、最も近いTuistキャッシュリージョンに接続され、ワークスペースごとの認証ヘルパーを通じて認証されます。また、リポジトリの`.bazelrc`に`try-import`行を追加します。

```text
try-import %workspace%/.bazelrc.tuist
```

インポートを自分で管理したい場合は、`--no-add-bazelrc-import`を指定してください。

`.bazelrc.tuist`を`.gitignore`に追加し、コミットする代わりに各マシンでセットアップを実行してください。生成されたファイルは、現在のユーザーのTuist設定ディレクトリ内の絶対パスにある認証ヘルパーと、それを生成したマシンに最も近いキャッシュリージョンを指すため、これらの値はチームメンバーやCIランナーには引き継がれません。`.bazelrc`内の`try-import`行はすべてのマシンで同じであるため、これをコミットしてください。

Bazelワークスペースのマーカーが見つからない場合、ファイルがシンボリックリンクである場合、またはすでにリモートキャッシュやBuild Event Serviceが設定されている場合、セットアップは既存の`.bazelrc`を変更しません。そのため、再度実行しても冪等性が保たれます。

統合を検証するために、通常のBazelコマンドを実行します。

```bash
bazel build //...
```

その後、キャッシュアクティビティはTuistダッシュボードのプロジェクトの**Bazel Cache**ページに表示され、キャッシュ転送、ダウンロードとアップロード、読み書きレイテンシ、スループット、およびアクションキャッシュヒット率が示されます。プロジェクトの**Overview**には、ビルド時間とともに同じアクションキャッシュヒット率の概要が表示されます。

特定のコマンドがキャッシュをどのように使用したかを確認するには、**Invocations**から開いてください。呼び出しページでは、アクションキャッシュのルックアップとコンテンツオブジェクトのリクエストが分離されているため、コールドなアクションキャッシュと遅いアーティファクトのダウンロードを区別できます。

## リモート実行 {#remote-execution}

Tuistは、BazelアクションをLinuxエグゼキューター上で実行することもできるため、キャッシュミスはローカルマシンやCIランナーではなくリモートで実行されます。リモート実行は有効化されたアカウントで利用可能です。あなたのアカウントで有効にするには、[メールでお問い合わせ](mailto:contact@tuist.dev)いただくか、[ミーティングを予約](https://cal.tuist.dev/team/tuist/tuist)してください。その後、セットアップ時に`--remote-execution`を渡します。

```bash
tuist bazel setup --remote-execution
```

セットアップにより、`.bazelrc.tuist`内でBazelがTuistのエグゼキューターを指すように設定され、リモートキャッシュの隣に配置されます。実行ごとに現在のエグゼキューターとイメージを検索するため、生成された値をコピーするのではなく、セットアップを再実行してください。アクションはマシンにインストールされたツールではなく、エグゼキューターのLinuxツールチェーンで実行されるため、ワークスペースでアクションに必要なツールチェーンを宣言してください。

セットアップでは、`--jobs`をアカウントが同時に実行可能なリモートアクション数の2倍に設定するため、それぞれの実行で次のアクションが待機状態になります。これがないと、Bazelはマシンのコア数と同じ数のアクションを並列に実行し、2コアのCIランナーでは2つのリモートアクションのみが実行中となります。

別の値を使用するには、コマンドラインで`--jobs`を渡すか、`try-import`行の後に`.bazelrc`で設定してください。Bazelは最後に読み込んだ値を使用するため、その行より前の`--jobs`は生成された値に置き換えられます。

## ビルドインサイト {#build-insights}

デフォルトでは、`tuist bazel setup`によってBazelのBuild Event Serviceも構成され、完了したコマンドが**Invocations**ダッシュボードに表示されます。ダッシュボードに表示される内容やカスタムメタデータの添付方法については、<.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link>をご覧ください。

リモートキャッシュのみを使用し、ビルドイベントストリームを送信したくない場合は、次を使用してオプトアウトしてください。

```bash
tuist bazel setup --no-build-insights
```

## 継続的インテグレーション {#continuous-integration}

<.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link>に記載されている方法のいずれかを使用してCIを認証し、チェックアウトステップの一部として`tuist bazel setup`を一度実行して、`.bazelrc.tuist`がランナーに適したリージョンを反映するようにしてください。プロバイダー固有の例については、<.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link>をご覧ください。

## データ保持 {#data-retention}

Tuistはリモートキャッシュの観測データを90日間保持します。完全なポリシーについては、<.localized_link href="/guides/server/data-retention">data retention</.localized_link>をご覧ください。
