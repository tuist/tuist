---
{
  "title": "Once プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Once を Tuist に接続して、共有キャッシュ、ビルドとテストのリアルタイムなインサイト、テストのシャーディング、アプリケーションプレビューを利用しましょう。"
}
---
# Once プロジェクト {#once-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/once-project
```

:::

[Once](https://buildonce.dev) はキャッシュ可能なスクリプトとビルドグラフを実行します。Tuist に接続することで、マシン間でキャッシュされた作業を共有し、実行状況をリアルタイムで追跡し、チームが試せるようアプリケーションを公開できます。既存のプロジェクトソースとビルド定義はそのまま維持し、統合設定は `once.toml` に記述します。

## 前提条件

- [Once](https://buildonce.dev/docs/guide/getting-started) がインストールされており、ワークスペースまたはキャッシュ可能なスクリプトがあること。
- Tuist アカウント。Once の統合には Tuist CLI は不要です。

## プロジェクトの接続 {#connect-the-project}

リポジトリのルートで次を実行します：

```bash
once connect --provider tuist --create
```

必要に応じて Once がサインインし、個人アカウントの下に Tuist プロジェクトを作成して、プロバイダーのバインディングを `once.toml` に書き込みます。別のアカウントや既存のプロジェクトを選択するには、[プロジェクトの接続](https://buildonce.dev/docs/guide/infrastructure/connect) を参照してください。

既存の Tuist プロジェクトの場合は、プロバイダーとキャッシュのバインディングを自分で設定します：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
# url = "https://your-tuist-server.example.com"

[infrastructure.cache]
provider = "tuist"
```

`acme` と `app` を自分のアカウントとプロジェクトのハンドルに置き換えて、認証を行います：

```bash
once auth login --provider tuist
```

クレデンシャルではなく宛先情報をチームメイトや CI と共有するため、`once.toml` をコミットしてください。各開発者は各自のマシンでサインインします。

## 共有キャッシュ

ローカルキャッシュはそれを生成したマシンにしか役立ちません。Tuist を構成しておくと、Once は同じ作業を再度実行するのではなく、他の開発者や CI が生成した一致する結果を復元できます。

キャッシュ可能なスクリプトまたはグラフターゲットを通常どおり実行します：

```bash
once build MyApplication
```

ダッシュボードで **Once Cache** を開き、リモートキャッシュのアクティビティを確認します。セットアップとマシン間での再利用確認については、<.localized_link href="/guides/features/cache/once">Once キャッシュ</.localized_link> を参照してください。

## ビルドインサイト

実行開始時に Once がダッシュボードへのリンクを表示します。これを開いて、実行の進行に合わせてグラフ、アクションの状態、キャッシュの判断を追跡します。**Builds** を使用して、ローカルと CI のパフォーマンスを比較し、失敗したアクションを調査します。完全なプロセス出力を得るには CI ログを保持してください。生のアクションログの取り込みは現在利用できません。

記録される内容と、コーディングエージェントや Grafana からそれらにアクセスする方法については、<.localized_link href="/guides/features/build-insights/once">Once ビルドインサイト</.localized_link> を参照してください。

## テストインサイトとシャーディング

Once のテストターゲットを実行します：

```bash
once test
```

**Tests** を開き、報告されたスイート、ケース、所要時間、失敗を確認します。結果はテストターゲットのレポート機能に依存します。テストプロセスを実行するアクションであっても、自動的にケースごとのテストレポートが生成されるわけではありません。

スイートが 1 台のマシンでは処理しきれなくなった場合は、ホスト型シャーディングプランを作成し、そのバッチを CI ワーカーに分散します。<.localized_link href="/guides/features/test-insights/once">Once テストインサイト</.localized_link> および <.localized_link href="/guides/features/test-sharding/once">Once テストシャーディング</.localized_link> を参照してください。

## プレビューとバンドルサイズ

サポートされている Android、Apple シミュレーター、および macOS アプリケーションを公開するため、同じプロバイダーにアーティファクトバインディングを追加します：

```toml
[infrastructure.artifacts]
name = "tuist"
```

```bash
once artifact publish MyApplication --track review
```

返されたリンクを開くとプロジェクトのプレビューが表示されます。処理には少し時間がかかる場合があります。署名の要件とビルド後のオプション公開については、<.localized_link href="/guides/features/previews/once">Once プレビュー</.localized_link> を参照してください。

バンドルサイズを追跡するには、ビルド済みの `.app`、`.ipa`、`.xcarchive`、`.apk`、または `.aab` に対して Tuist CLI を個別に使用します。<.localized_link href="/guides/features/bundle-insights">Apple または Android のバンドルインサイトガイド</.localized_link> に従ってください。Once アーティファクトを公開しても、バンドルサイズレポートは自動的にアップロードされません。

## 継続的インテグレーション

プロジェクトの操作が許可されたアカウントトークンを `TUIST_TOKEN` で使用するか、サポートされている CI プロバイダーの OpenID Connect ID を介して認証します：

```bash
once auth login --provider tuist --no-browser
once build MyApplication
once test
```

GitHub Actions では、ジョブに `id-token: write` と `contents: read` を付与します。例については、<.localized_link href="/guides/integrations/continuous-integration#once">継続的インテグレーションでの Once</.localized_link> を参照してください。個人開発者のログイン情報は CI のクレデンシャルではありません。

## リモート実行

リモート実行が有効なアカウントでは、Tuist の Linux ワーカー上で対象となるグラフコマンドアクションを実行できます。これはキャッシュ結果の共有や CI ワークフロー全体の実行とは別物です。ワーカーの要件とセットアップについては、<.localized_link href="/guides/features/runners/once">Once リモート実行</.localized_link> を参照してください。
