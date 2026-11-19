---
{
  "title": "Bazel プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "BUILD ファイルを変更することなく、Bazel ワークスペースを Tuist に接続し、CI 全体で共有のリモートキャッシュとビルド・テストのインサイトを活用します。"
}
---
# Bazel プロジェクト {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

既存の Bazel ワークスペースを Tuist に接続するには、この手順に従ってください。Tuist は、Bazel がリモートキャッシュとして接続する [Remote Execution API](https://github.com/bazelbuild/remote-apis) キャッシュと、すべてのビルドとテストをダッシュボード上で可視化されたデータに変換する Build Event Service ストリームを提供します。Tuist が Bazel に追加する機能の概要については、[Bazel with Tuist](https://tuist.dev/build-systems/bazel) を参照してください。他の Bazel プロバイダーから移行する場合は、[BuildBuddy](https://tuist.dev/compare/buildbuddy) および [EngFlow](https://tuist.dev/compare/engflow) の比較ページで変更点を確認できます。

以下の各セクションでは、まず現在不足している部分を説明し、その後、そのギャップを埋める機能の手順を案内します。

## 前提条件

- Bazel ワークスペース（ルートに `WORKSPACE` または `MODULE.bazel` があること）と、`PATH` にある Bazel。
- <.localized_link href="/guides/install-tuist">Tuist コマンドラインインターフェース</.localized_link>。

## ワークスペースを接続する

Bazel ワークスペースのルートから `tuist init` を実行します。Tuist は `WORKSPACE` / `MODULE.bazel` を検出し、**Bazel ワークスペースを統合** オプションを提供します。ブラウザで認証を行い、プロジェクトを所有すべきアカウントを選択してください。

```bash
tuist init
```

コーディングエージェントやスクリプトから実行する場合は、まず `tuist auth login` を実行し（ブラウザフローでは Enter キーを押すまで待機します）、その後、非インタラクティブな形式を使用します。

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

init が完了すると、Tuist は次のことを行います。

1. プロジェクトハンドルを含む `tuist.toml` をワークスペースのルートに書き込みます。
2. `.bazelrc` の隣に `.bazelrc.tuist` を書き込み、最も近い Tuist キャッシュリージョンに接続し、ワークスペースごとの認証情報ヘルパーを通じて認証を行います。
3. `.bazelrc` に `try-import %workspace%/.bazelrc.tuist` 行を追加します。

`try-import` 行をコミットします。これはすべてのマシンで同一です。`.bazelrc.tuist` を `.gitignore` に追加してください。認証情報ヘルパーのパスはユーザーごと、キャッシュリージョンは場所ごとに異なるため、共有しないでください。

ワークスペースが接続されると、以下のすべてが自動的に有効になります。

## リモートキャッシュ

Bazel のローカルディスクキャッシュは `~/.cache/bazel` （または `--disk_cache` が指す場所）にあります。ある開発者のマシンでのキャッシュヒットは他の人には届かず、CI ジョブのコンテナは毎回空のキャッシュから開始されます。

Bazel の [Remote Execution API](https://github.com/bazelbuild/remote-apis) は、同じキャッシュを共有エンドポイントに拡張するためのプロトコルです。Tuist はこれに対応しています。`.bazelrc.tuist` が配置されると、Bazel は出力がすでに共有キャッシュにあるアクションをスキップし、代わりにダウンロードします。1 台のマシンでの作業が、同じリビジョンをビルドする他のすべてのマシンに役立ちます。

同じリビジョンに対して 2 回のクリーンビルドを実行して確認します（ローカルで、または 1 回ローカル + 1 回 CI）：

```bash
bazel clean
bazel build //...
```

2 回目の実行のサマリーにはキャッシュヒットが表示されるはずです。ダッシュボードで **Cache** を開き、時間経過に伴うヒット率を確認してください。

## ビルドとテストのインサイト

Bazel のビルドイベントストリームとテストごとの XML レポートは、呼び出しごとに出力されます。1 週間を通してターゲットレベルの所要時間を比較したり、複数の CI 実行で不安定になったテストを発見したりするには、これらのイベントをどこかで収集・集計する必要があります。

Bazel がすでに出力している Build Event Service プロトコルは、まさにそのために設計されています。`tuist init` が書き込んだ `.bazelrc.tuist` は、BES ストリームを Tuist に向けて構成するため、次の `bazel build` と `bazel test` でビルドおよびテストのインサイトの流れが始まります。追加の設定は不要です。ダッシュボードで **Builds** と **Tests** を開いてデータを確認してください。

## チームを巻き込む

キャッシュヒットとインサイトは、プロジェクトに接続されている人数が増えるほど効果が大きくなります。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> （Google、Okta、Microsoft）を設定して、オンボーディングを個人ごとの `tuist auth login` ではなくワンクリックで完了できるようにしましょう。
