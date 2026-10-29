---
{
  "title": "サーバー",
  "titleTemplate": ":title · コード · コントリビューター · Tuist",
  "description": "Tuist Server に貢献する。"
}
---
# サーバー {#server}

ソース: [github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## 用途 {#what-it-is-for}

このサーバーは、認証、アカウントとプロジェクト、キャッシュストレージ、インサイト、プレビュー、レジストリ、および統合（GitHub、Slack、SSO）など、Tuist のサーバーサイド機能を提供します。Postgres と ClickHouse を備えた Phoenix/Elixir アプリケーションです。

## 貢献方法 {#how-to-contribute}

サーバーへの貢献には、CLA（`server/CLA.md`）への署名が必要です。

### ローカル環境のセットアップ {#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

ブラウザで `http://localhost:8080` を開いてください。開発環境では、ログインページに **テストユーザーとしてログイン** ボタンがあり、事前に用意されたアカウント（`tuistrocks@tuist.dev` / `tuistrocks`）でサインインできます。

> [!NOTE]
> 社内開発者は fnox を介して 1Password から開発用シークレットを読み込みます。`mise run dev` はサーバーを `fnox exec` で実行します（`server/fnox.toml` を参照）。外部のコントリビューターは 1Password へのアクセス権限が不要です。サーバーはそれなしでもローカルで動作します。OAuth、Stripe、その他のサードパーティ統合は無効になりますが、コア機能は動作します。

### ローカル Helm テスト {#local-helm-testing}

[kind](https://kind.sigs.k8s.io/) と付属の mise タスクを使用して、マシン上でフルスタックを起動できます。これにより、Docker イメージをローカルでビルドし、kind クラスターを作成し、チャートをインストールし、すべてのサービスを自動的にポートフォワードします。

```bash
# Deploy everything (builds images from source)
mise run helm:up --license "YOUR_LICENSE_KEY"

# Include the observability stack (Grafana, Prometheus, Loki, Tempo)
mise run helm:up --license "YOUR_LICENSE_KEY" --observability

# Check status
mise run helm:status

# Tear down
mise run helm:down
```

**前提条件:** `docker`、`kind`、`helm`、および `kubectl`。

### テストとフォーマット {#tests-and-formatting}

- テスト: `mix test`
- フォーマット: `mise run format`
