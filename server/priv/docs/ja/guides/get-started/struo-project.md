---
{
  "title": "Struo プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Struo を Tuist に接続して、共有キャッシュ、ビルドとテストのリアルタイムインサイト、テストシャーディング、アプリケーションプレビューを利用しましょう。"
}
---
# Struo プロジェクト {#struo-project}

<a id="once-project"></a>

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/struo-project
```

:::

[Struo](https://struo.run) はキャッシュ可能なスクリプトとビルドグラフを実行します。Tuist と連携させることで、マシン間でキャッシュされた作業を共有し、実行状況をリアルタイムで追跡し、チームが試せるアプリケーションを公開できます。既存のプロジェクトソースとビルド定義はそのまま維持でき、統合設定は `struo.toml` に記述します。

## 前提条件

- [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) 以降がインストールされており、ワークスペースまたはキャッシュ可能なスクリプトがあること。[インストールガイド](https://struo.run/docs/guide/getting-started)に従うか、mise でバージョンを固定してください。

  ```bash
  mise use -g github:tuist/struo@1.0.0
  ```

- Tuist アカウント。Struo の統合には Tuist CLI は不要です。

## Once からアップグレードする {#upgrading-from-once}

Struo は Once の新しい名称です。`once.toml` ファイルを `struo.toml` に改名し、mise のピンを `github:tuist/once` から `github:tuist/struo` に更新し、`once` コマンドを `struo` に置き換えてください。スクリプトヘッダーを `# once` から `# struo` に、shebang を `#!/usr/bin/env -S struo exec -- bash` に更新します。`ONCE_*` 環境変数を `STRUO_*`（例：`STRUO_CACHE_PROVIDER`）に改名してください。Tuist の認証情報は引き続き `TUIST_TOKEN` を使用します。

ignore ファイル内の `.once/` エントリを `.struo/` に変更してください。出力は現在 `.struo/out/` に格納され、共有ローカルコンテンツキャッシュは `$XDG_CACHE_HOME/struo/cas`（デフォルトでは `~/.cache/struo/cas`）を使用します。キャッシュキーとローカルストレージは新しい名前を使用するため、古いキャッシュエントリを移動するのではなく、アップグレード後はローカルキャッシュが空の状態になることを想定してください。`struo auth login --provider tuist` で再度サインインしてください。

名称変更により Tuist の互換性エンドポイントは変更されません。ライブレポートは引き続き `once.events.v1` を使用し、既存の `/api/.../once` ルートもサポートされています。[上位プロジェクトの改名ガイド](https://struo.run/changelog/2026-11-18-once-is-now-struo)を参照してください。

## プロジェクトを接続する {#connect-the-project}

リポジトリのルートから次を実行してください。

```bash
struo connect --provider tuist --create
```

必要に応じて Struo がサインインを行い、個人アカウントの下に Tuist プロジェクトを作成し、プロバイダーのバインディングを `struo.toml` に書き込みます。別のアカウントや既存のプロジェクトを選択するには、[プロジェクトを接続する](https://struo.run/docs/guide/infrastructure/connect)を参照してください。

既存の Tuist プロジェクトの場合、プロバイダーとキャッシュのバインディングを自分で設定してください。

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
# url = "https://your-tuist-server.example.com"

[infrastructure.cache]
provider = "tuist"
```

`acme` と `app` をあなたのアカウントとプロジェクトのハンドルに置き換え、その後認証してください。

```bash
struo auth login --provider tuist
```

`struo.toml` をコミットし、認証情報ではなく目的地をチームメンバーや CI と共有してください。各開発者は各自のマシンでサインインします。

## 共有キャッシュ

ローカルキャッシュは、それを生成したマシンにのみ役立ちます。Tuist を構成することで、Struo は同じ作業を再び実行する代わりに、他の開発者や CI によって生成された一致する結果を復元できます。

キャッシュ可能なスクリプトまたはグラフターゲットを通常通り実行してください。

```bash
struo build MyApplication
```

ダッシュボードで **Struo Cache** を開き、リモートキャッシュのアクティビティを確認してください。セットアップとマシン間での再利用確認については、<.localized_link href="/guides/features/cache/struo">Struo キャッシュ</.localized_link>を参照してください。

## ビルドインサイト

Struo は実行開始時にダッシュボードへのリンクを表示します。これを開いて、実行の進行中にグラフ、アクションステータス、およびキャッシュの決定を追跡してください。**Builds** を使用して、ローカルと CI のパフォーマンスを比較し、失敗したアクションを調査してください。完全なプロセス出力を得るには CI ログを保持してください。生のアクションログの取り込みは現在利用できません。

記録される内容と、コーディングエージェントや Grafana からアクセスする方法については、<.localized_link href="/guides/features/build-insights/struo">Struo ビルドインサイト</.localized_link>を参照してください。

## テストインサイトとシャーディング

Struo のテストターゲットを実行してください。

```bash
struo test
```

**Tests** を開き、報告されたスイート、ケース、所要時間、および失敗を確認してください。結果はテストターゲットのレポート機能に依存します。テストプロセスを実行するアクションが自動的にケースごとのテストレポートになるわけではありません。

スイートが1台のマシンでは処理しきれなくなった場合は、ホスト型シャーディングプランを作成し、そのバッチを CI ワーカーに分散してください。<.localized_link href="/guides/features/test-insights/struo">Struo テストインサイト</.localized_link>および <.localized_link href="/guides/features/test-sharding/struo">Struo テストシャーディング</.localized_link>を参照してください。

## プレビューとバンドルサイズ

サポートされている Android、Apple シミュレーター、および macOS アプリケーションを公開するために、同じプロバイダーにアーティファクトバインディングを追加してください。

```toml
[infrastructure.artifacts]
name = "tuist"
```

```bash
struo artifact publish MyApplication --track review
```

返されたリンクはプロジェクトのプレビューを開きます。処理には少し時間がかかる場合があります。署名の要件とビルド後のオプション公開については、<.localized_link href="/guides/features/previews/struo">Struo プレビュー</.localized_link>を参照してください。

バンドルサイズを追跡するには、ビルド済みの `.app`、`.ipa`、`.xcarchive`、`.apk`、または `.aab` に対して Tuist CLI を別途使用してください。<.localized_link href="/guides/features/bundle-insights">Apple または Android バンドルインサイトガイド</.localized_link>に従ってください。Struo アーティファクトを公開しても、バンドルサイズレポートは自動的にアップロードされません。

## 継続的インテグレーション

プロジェクトの操作が許可されたアカウントトークンを `TUIST_TOKEN` で使用するか、サポートされている CI プロバイダーの OpenID Connect ID を介して認証してください。

```bash
struo auth login --provider tuist --no-browser
struo build MyApplication
struo test
```

GitHub Actions では、ジョブに `id-token: write` と `contents: read` を付与してください。例については、<.localized_link href="/guides/integrations/continuous-integration#struo">継続的インテグレーションでの Struo</.localized_link>を参照してください。個人開発者のログインは CI 認証情報ではありません。

## リモート実行

リモート実行が有効なアカウントは、Tuist の Linux ワーカー上で対象となるグラフコマンドアクションを実行することもできます。これはキャッシュ結果の共有や、CI ワークフロー全体の実行とは別物です。ワーカーの要件とセットアップについては、<.localized_link href="/guides/features/runners/struo">Struo リモート実行</.localized_link>を参照してください。
