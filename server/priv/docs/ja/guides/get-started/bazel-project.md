---
{
  "title": "Bazel project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect a Bazel workspace to Tuist for a shared remote cache and build and test insights across CI, without changing any BUILD file."
}
---
# Bazelプロジェクト {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

既存のBazelワークスペースをTuistに接続するには、この手順に従ってください。Tuistは、Bazelがリモートキャッシュとして接続する[Remote Execution API](https://github.com/bazelbuild/remote-apis)キャッシュと、すべてのビルドとテストをダッシュボード上の可視データに変換するBuild Event Serviceストリームを提供します。

以下の各セクションでは、現在不足しているものを最初に示し、そのギャップを埋める機能について順を追って説明します。

## 前提条件

- Bazelワークスペース（ルートに`WORKSPACE`または`MODULE.bazel`がある）と、`PATH`上にあるBazel。
- <.localized_link href="/guides/install-tuist">Tuistコマンドラインインターフェース</.localized_link>。

## ワークスペースを接続する

> [!NOTE]
> `tuist init`内のBazelワークフローには、それに同梱されているバージョンのTuist CLIが必要です。以前のリリースでは、`tuist init`に「Integrate a Bazel workspace」がオプションとして表示されません。代わりに、ワークスペースのルートから`tuist auth login`を実行し、続いて`tuist bazel setup`を実行してください。これにより、以下と同じ手順が進みます。

Bazelワークスペースのルートから`tuist init`を実行します。Tuistは`WORKSPACE` / `MODULE.bazel`を検出し、**Bazelワークスペースを統合**オプションを提供します。ブラウザで認証を行い、プロジェクトを所有すべきアカウントを選択してください。

```bash
tuist init
```

コーディングエージェントやスクリプトからこれを実行する場合は、まず`tuist auth login`を実行します（ブラウザフローではEnterキーを押すまで待機します）。その後、非対話形式を使用します：

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

initが完了すると、Tuistは以下の処理を行います：

1. プロジェクトハンドルを含む`tuist.toml`をワークスペースのルートに書き込みます。
2. `.bazelrc`の隣に`.bazelrc.tuist`を書き込み、最も近いTuistキャッシュリージョンに接続し、ワークスペースごとのクレデンシャルヘルパーを通じて認証します。
3. `.bazelrc`に`try-import %workspace%/.bazelrc.tuist`行を追加します。

`try-import`行をコミットします。これはすべてのマシンで同一です。`.gitignore`に`.bazelrc.tuist`を追加します。クレデンシャルヘルパーのパスはユーザーごと、キャッシュリージョンは場所ごとに異なるため、共有しないでください。

ワークスペースが接続されると、以下のすべてが自動的に有効になります。

## リモートキャッシュ

Bazel独自のローカルディスクキャッシュは`~/.cache/bazel`の下にあります（または`--disk_cache`が指す場所）。ある開発者のマシンでのキャッシュヒットは他の人には届かず、CIジョブコンテナは毎回空のキャッシュから開始されます。

Bazelの[Remote Execution API](https://github.com/bazelbuild/remote-apis)は、その同じキャッシュを共有エンドポイントに拡張するためのプロトコルです。Tuistはこのプロトコルをサポートしています。`.bazelrc.tuist`が配置されると、Bazelは出力がすでに共有キャッシュにあるアクションをスキップし、代わりにそれらをダウンロードします。あるマシンでの作業は、同じリビジョンをビルドする他のすべてのマシンの恩恵となります。

同じリビジョンに対して2回のクリーンビルドで確認します（ローカルで、または1回ローカル＋1回CI）：

```bash
bazel clean
bazel build //...
```

2回目の実行のサマリーにはキャッシュヒットが表示されるはずです。ダッシュボードで**Cache**を開き、時間経過に伴うヒット率を確認してください。

## ビルドとテストのインサイト

BazelのビルドイベントストリームとテストごとのXMLレポートは、呼び出しごとに出力されます。1週間を通してターゲットレベルの所要時間を比較したり、複数のCI実行で不安定になったテストを発見したりするには、これらのイベントをどこかで収集・集計する必要があります。

Bazelがすでに出力しているBuild Event Serviceプロトコルは、まさにそのために設計されています。`tuist init`が書き込んだ`.bazelrc.tuist`は、BESストリームをTuistに対して構成するため、次の`bazel build`および`bazel test`でビルドとテストのインサイトの流れが始まります。追加の設定は不要です。ダッシュボードで**Builds**と**Tests**を開いてデータを確認してください。

## チームを巻き込む

キャッシュヒットとインサイトは、プロジェクトに接続されている人の数とともに増幅されます。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">シングルサインオン</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを個人ごとの`tuist auth login`ではなくクリックだけで完了できるようにします。
