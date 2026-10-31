---
{
  "title": "Bazel プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Bazel ワークスペースを Tuist に接続し、BUILD ファイルを変更することなく、CI 全体で共有のリモートキャッシュとビルド・テストのインサイトを利用できます。"
}
---
# Bazel プロジェクト {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

既存の Bazel ワークスペースを Tuist に接続するには、この手順に従ってください。Tuist は、Bazel がリモートキャッシュとして接続する [Remote Execution API](https://github.com/bazelbuild/remote-apis) キャッシュと、すべてのビルドとテストをダッシュボード上で可視化されたデータに変換する Build Event Service ストリームを提供します。

以下の各セクションでは、現在不足しているものを示し、そのギャップを埋める機能について順に説明します。

## 前提条件

- Bazel ワークスペース（ルートに `WORKSPACE` または `MODULE.bazel` がある）と、`PATH` に含まれる Bazel。
- <.localized_link href="/guides/install-tuist">Tuist コマンドラインインターフェース</.localized_link>。

## ワークスペースを接続する

> [!NOTE]
> `tuist init` 内の Bazel ワークフローには、それに同梱されたバージョンの Tuist CLI が必要です。以前のリリースでは、`tuist init` に「Integrate a Bazel workspace」がオプションとして表示されません。その場合は、ワークスペースのルートから `tuist auth login` を実行し、続いて `tuist bazel setup` を実行してください。これにより、以下の同じ手順が進められます。

Bazel ワークスペースのルートから `tuist init` を実行します。Tuist は `WORKSPACE` / `MODULE.bazel` を検出し、**Bazel ワークスペースを統合** オプションを提供します。ブラウザで認証を行い、プロジェクトを所有するアカウントを選択してください。

```bash
tuist init
```

コーディングエージェントやスクリプトから実行する場合は、まず `tuist auth login` を実行してください（ブラウザでのフローでは Enter キーを押すまで待ちます）。その後、非インタラクティブな形式を使用します。

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

init が完了すると、Tuist は次の処理を行います。

1. プロジェクトハンドルを含む `tuist.toml` をワークスペースのルートに書き込みます。
2. `.bazelrc` の隣に `.bazelrc.tuist` を書き込み、最も近い Tuist キャッシュリージョンに接続し、ワークスペースごとの認証ヘルパーを通じて認証を行います。
3. `.bazelrc` に `try-import %workspace%/.bazelrc.tuist` 行を追加します。

`try-import` 行をコミットしてください。これはどのマシンでも同一です。`.bazelrc.tuist` を `.gitignore` に追加してください。認証ヘルパーのパスはユーザーごと、キャッシュリージョンは場所ごとに異なるため、共有すべきではありません。

ワークスペースが接続されると、以下のすべてが自動的に有効になります。

## リモートキャッシュ

Bazel のローカルディスクキャッシュは `~/.cache/bazel` （または `--disk_cache` が指す場所）にあります。ある開発者のマシンでのキャッシュヒットは他の人には届かず、CI ジョブのコンテナは毎回空のキャッシュから開始されます。

Bazel の [Remote Execution API](https://github.com/bazelbuild/remote-apis) は、そのキャッシュを共有エンドポイントに拡張するためのプロトコルです。Tuist はこのプロトコルに対応しています。`.bazelrc.tuist` が配置されると、Bazel は出力がすでに共有キャッシュにあるアクションをスキップし、代わりにダウンロードします。1 台のマシンでの作業が、同じリビジョンをビルドする他のすべてのマシンに恩恵をもたらします。

同じリビジョンに対して 2 回のクリーンビルドを実行して確認してください（ローカルで 2 回、またはローカル 1 回 + CI 1 回）。

```bash
bazel clean
bazel build //...
```

2 回目の実行のサマリーにはキャッシュヒットが表示されるはずです。ダッシュボードで **Cache** を開き、時間経過に伴うヒット率を確認してください。

## ビルドとテストのインサイト

Bazel のビルドイベントストリームとテストごとの XML レポートは、呼び出しごとに出力されます。1 週間を通じてターゲットレベルの所要時間を比較したり、複数の CI 実行で不安定になったテストを発見したりするには、それらのイベントをどこかで収集・集計する必要があります。

Bazel がすでに出力している Build Event Service プロトコルは、まさにそのために設計されています。`tuist init` が書き込んだ `.bazelrc.tuist` は、BES ストリームを Tuist 向けに構成するため、次の `bazel build` および `bazel test` でビルドとテストのインサイトの流れが始まります。追加の設定は不要です。ダッシュボードで **Builds** と **Tests** を開いてデータを確認してください。

## チームを巻き込む

キャッシュヒットとインサイトは、プロジェクトに接続する人数が増えるほど効果が高まります。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">シングルサインオン</.localized_link>（Google、Okta、Microsoft）を設定することで、オンボーディングを個人ごとの `tuist auth login` ではなくワンクリックで完了できるようにしましょう。
