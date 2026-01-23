---
{
  "title": "Server",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist Server."
}
---
# サーバー{#server}

Source:
[github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## 目的{#what-it-is-for}

サーバーはTuistのサーバーサイド機能（認証、アカウントとプロジェクト、キャッシュストレージ、インサイト、プレビュー、レジストリ、統合機能（GitHub、Slack、SSO））を支えています。Phoenix/Elixirアプリケーションで、PostgresとClickHouseを使用しています。

警告 TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDBは非推奨となり、今後削除されます。現時点でローカル環境のセットアップや移行に必要であれば、[TimescaleDBインストールドキュメント](https://docs.timescale.com/self-hosted/latest/install/installation-macos/)を参照してください。
<!-- -->
:::

## 貢献方法{#how-to-contribute}

サーバーへの貢献にはCLA（`server/CLA.md` ）への署名が必要です。

### ローカルに設定する{#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Minimal secrets
export TUIST_SECRET_KEY_BASE="$(mix phx.gen.secret)"

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

> [!NOTE] ファーストパーティ開発者は暗号化されたシークレットを`priv/secrets/dev.key`
> から読み込みます。外部貢献者はこのキーを所有していませんが、問題ありません。サーバーは`TUIST_SECRET_KEY_BASE`
> でローカル実行を継続しますが、OAuth、Stripe、その他の統合機能は無効のままです。

### テストと書式設定{#tests-and-formatting}

- テスト:`mix test`
- フォーマット:`mise run format`
