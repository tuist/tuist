---
{
  "title": "Bazel プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Bazel ワークスペースを Tuist に接続し、BUILD ファイルを変更することなく、CI 全体で共有のリモートキャッシュとビルド・テストのインサイトを活用します。"
}
---
# Bazelプロジェクト {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

既存のBazelワークスペースをTuistに接続するには、この手順に従ってください。Tuistは、Bazelがリモートキャッシュとして接続する[Remote Execution API](https://github.com/bazelbuild/remote-apis)キャッシュと、すべてのビルドとテストをダッシュボード上の可視化されたデータに変換するBuild Event Serviceストリームを提供します。TuistがBazelに追加する機能の概要については、[Bazel with Tuist](https://tuist.dev/build-systems/bazel)をご覧ください。他のBazelプロバイダーから移行する場合、[BuildBuddy](https://tuist.dev/compare/buildbuddy)および[EngFlow](https://tuist.dev/compare/engflow)の比較ページで変更点を確認できます。

以下の各セクションでは、まず現状で不足している点を示し、そのギャップを埋める機能について説明します。

## 前提条件

- Bazelワークスペース（ルートに`WORKSPACE`または`MODULE.bazel`があること）と、`PATH`上に配置されたBazel。
- <.localized_link href="/guides/install-tuist">Tuistコマンドラインインターフェース</.localized_link>。

## ワークスペースを接続する

Bazelワークスペースのルートから`tuist init`を実行します。Tuistは`WORKSPACE` / `MODULE.bazel`を検出し、**Bazelワークスペースを統合**オプションを提供します。ブラウザで認証を行い、プロジェクトを所有すべきアカウントを選択してください。

```bash
tuist init
```

コーディングエージェントやスクリプトから実行する場合は、まず`tuist auth login`を実行し（ブラウザフローではEnterキーを押すまで待機します）、その後、非インタラクティブな形式を使用します。

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

initが完了すると、Tuistは以下を行います。

1. プロジェクトハンドルを含む`tuist.toml`をワークスペースのルートに書き出します。
2. `.bazelrc`の隣に`.bazelrc.tuist`を書き出し、最も近いTuistキャッシュリージョンに接続し、ワークスペースごとのクレデンシャルヘルパーを通じて認証します。
3. `.bazelrc`に`try-import %workspace%/.bazelrc.tuist`行を追加します。

`try-import`行をコミットしてください。これはすべてのマシンで同一です。`.bazelrc.tuist`を`.gitignore`に追加してください。クレデンシャルヘルパーのパスはユーザーごと、キャッシュリージョンは場所ごとに異なるため、共有しないでください。

ワークスペースが接続されると、以下のすべてが自動的に有効になります。

## リモートキャッシュ

Bazel独自のローカルディスクキャッシュは`~/.cache/bazel`（または`--disk_cache`が指す場所）にあります。ある開発者のマシンでのキャッシュヒットは他の人には届かず、CIジョブのコンテナは毎回空のキャッシュから開始されます。

Bazelの[Remote Execution API](https://github.com/bazelbuild/remote-apis)は、同じキャッシュを共有エンドポイントに拡張するためのプロトコルです。Tuistはこのプロトコルに対応しています。`.bazelrc.tuist`が配置されると、Bazelは出力がすでに共有キャッシュにあるアクションをスキップし、代わりにダウンロードします。あるマシンでの作業成果は、同じリビジョンをビルドする他のすべてのマシンに恩恵をもたらします。

同じリビジョンに対して2回のクリーンビルドを行い、検証します（ローカルで2回、またはローカル1回＋CI 1回）。

```bash
bazel clean
bazel build //...
```

2回目の実行のサマリーにはキャッシュヒットが表示されるはずです。ダッシュボードの**Cache**を開き、時間経過に伴うヒット率を確認してください。

## ビルドとテストのインサイト

BazelのビルドイベントストリームとテストごとのXMLレポートは、呼び出しごとに出力されます。1週間を通じたターゲットレベルの所要時間を比較したり、複数のCI実行を経てフラッキーになったテストを発見したりするには、これらのイベントをどこかで収集・集計する必要があります。

Bazelがすでに出力しているBuild Event Serviceプロトコルは、まさにそのために設計されています。`tuist init`が書き出した`.bazelrc.tuist`により、BESストリームがTuist向けに構成されるため、次の`bazel build`および`bazel test`以降、ビルドとテストのインサイトの流れが始まります。追加の設定は不要です。ダッシュボードの**Builds**と**Tests**を開いてデータを確認してください。

## チームを巻き込む

キャッシュヒットとインサイトの効果は、プロジェクトに接続する人数が増えるほど増幅されます。ダッシュボードのアカウント設定からチームメンバーを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを個人ごとの`tuist auth login`ではなくワンクリックで完了できるようにしましょう。
