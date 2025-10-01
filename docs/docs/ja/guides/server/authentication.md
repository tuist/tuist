---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 認証 {#authentication}

サーバと対話するために、CLIは[ベアラ認証](https://swagger.io/docs/specification/authentication/bearer-authentication/)を使用して要求を認証する必要がある。CLIはユーザーまたはプロジェクトとしての認証をサポートする。

## ユーザーとして{#as-a-user}。

お使いのマシンでCLIをローカルに使用する場合は、ユーザーとして認証することをお勧めします。ユーザーとして認証するには、以下のコマンドを実行する必要があります：

```bash
tuist auth login
```

このコマンドは、Webベースの認証フローを実行する。認証が完了すると、CLIは、`~/.config/tuist/credentials`
の下に、長期間のリフレッシュ・トークンと短期間のアクセストークンを保存します。このディレクトリの各ファイルは、認証したドメインを表し、デフォルトでは`tuist.dev.json`
となります。そのディレクトリに保存されている情報は機密なので、**安全を確保してください** 。

CLI は、サーバへのリクエスト時に自動的に認証情報を検索します。アクセストークンの有効期限が切れている場合、CLI
はリフレッシュトークンを使用して新しいアクセストークンを取得します。

## プロジェクトとして{#as-a-project}。

継続的インテグレーションのような非インタラクティブ環境では、インタラクティブフローによる認証はできません。そのような環境では、プロジェクトスコープのトークンを使ってプロジェクトとして認証することをお勧めします：

```bash
tuist project tokens create
```

CLIは、トークンが環境変数`TUIST_CONFIG_TOKEN` として定義され、`CI=1`
環境変数が設定されていることを期待する。CLIはリクエストを認証するためにトークンを使用する。

> [重要] 限定された範囲
> プロジェクト・スコープ・トークンの権限は、CI環境からプロジェクトが安全に実行できると考えられるアクションに限定されています。今後、トークンが持つ権限を文書化する予定です。
