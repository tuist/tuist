---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 認証{#authentication}

サーバーと通信するには、CLIは[ベアラー認証](https://swagger.io/docs/specification/authentication/bearer-authentication/)を使用してリクエストを認証する必要があります。CLIは、ユーザーとして、アカウントとして、またはOIDCトークンを使用して認証することをサポートしています。

## ユーザーとして{#as-a-user}

ローカルマシンでCLIを使用する場合は、ユーザーとして認証することをお勧めします。ユーザーとして認証するには、次のコマンドを実行する必要があります：

```bash
tuist auth login
```

このコマンドを実行すると、Webベースの認証フローが開始されます。認証が完了すると、CLIは`~/.config/tuist/credentials`
配下に、長期有効なリフレッシュトークンと短期有効なアクセストークンを保存します。このディレクトリ内の各ファイルは、認証を行ったドメインを表しており、デフォルトでは`tuist.dev.json`
となります。このディレクトリに保存される情報は機密性が高いため、**必ず安全に保管してください** 。

CLIはサーバーへのリクエスト時に、自動的に認証情報を参照します。アクセストークンの有効期限が切れている場合、CLIはリフレッシュトークンを使用して新しいアクセストークンを取得します。

## OIDCトークン{#oidc-tokens}

OpenID Connect (OIDC) をサポートする CI 環境では、Tuist
は長期保存型のシークレットを管理する必要なく、自動的に認証を行うことができます。サポートされている CI 環境で実行する場合、CLI は自動的に OIDC
トークンプロバイダーを検出し、CI から提供されたトークンを Tuist アクセストークンと交換します。

### 対応しているCIプロバイダー{#supported-ci-providers}

- GitHub Actions
- CircleCI
- Bitrise

### OIDC認証の設定{#setting-up-oidc-authentication}

1. **リポジトリをTuistに接続する**:
   <LocalizedLink href="/guides/integrations/gitforge/github">GitHub統合ガイド</LocalizedLink>に従って、GitHubリポジトリをTuistプロジェクトに接続してください。

2. **`tuist auth login`** を実行してください：CIワークフローでは、認証を必要とするコマンドを実行する前に、`tuist auth
   login` を実行してください。CLIはCI環境を自動的に検出し、OIDCを使用して認証を行います。

プロバイダ固有の設定例については、<LocalizedLink href="/guides/integrations/continuous-integration">継続的インテグレーションガイド</LocalizedLink>を参照してください。

### OIDC トークンのスコープ{#oidc-token-scopes}

OIDCトークンには、リポジトリに接続されているすべてのプロジェクトへのアクセスを提供する「`」ci` スコープグループが付与されます。「`」ci`
スコープに含まれる内容の詳細については、[スコープグループ](#scope-groups)を参照してください。

::: tip SECURITY BENEFITS
<!-- -->
OIDC認証は、長期有効トークンよりも安全です。その理由は以下の通りです：
- ローテーションや管理に関する秘密はありません
- トークンは短命であり、個々のワークフローの実行範囲内に限定されます
- 認証はリポジトリのIDに関連付けられています
<!-- -->
:::

## アカウントトークン{#account-tokens}

OIDCをサポートしていないCI環境の場合、または権限を細かく制御する必要がある場合は、アカウントトークンを使用できます。アカウントトークンを使用すると、トークンがアクセスできるスコープやプロジェクトを正確に指定できます。

### アカウントトークンの作成{#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

このコマンドでは、以下のオプションが使用可能です:

| オプション        | 説明                                                                                            |
| ------------ | --------------------------------------------------------------------------------------------- |
| `--スコープ`     | 必須。トークンに付与するスコープのカンマ区切りリスト。                                                                   |
| `--name`     | 必須。トークンの一意の識別子（1～32文字、英数字、ハイフン、アンダースコアのみ）。                                                    |
| `--有効期限`     | オプション。トークンの有効期限を設定します。`30d` （日）、`6m` （月）、または`1y` （年）のような形式を使用してください。指定がない場合、トークンには有効期限がありません。 |
| `--projects` | トークンを特定のプロジェクトハンドルに限定してください。指定がない場合、トークンはすべてのプロジェクトにアクセスできます。                                 |

### 利用可能なスコープ{#available-scopes}

| 適用範囲                     | 説明                    |
| ------------------------ | --------------------- |
| `account:members:read`   | アカウントメンバーを読み込む        |
| `account:members:write`  | アカウントメンバーの管理          |
| `account:registry:read`  | Swiftパッケージレジストリから読み込む |
| `account:registry:write` | Swiftパッケージレジストリに公開する  |
| `project:previews:read`  | プレビューをダウンロード          |
| `project:previews:write` | アップロードプレビュー           |
| `project:admin:read`     | プロジェクト設定を読む           |
| `project:admin:write`    | プロジェクト設定の管理           |
| `project:cache:read`     | キャッシュされたバイナリをダウンロード   |
| `project:cache:write`    | キャッシュされたバイナリをアップロード   |
| `project:bundles:read`   | バンドルを表示               |
| `project:bundles:write`  | バンドルのアップロード           |
| `project:tests:read`     | テスト結果を読む              |
| `project:tests:write`    | テスト結果をアップロード          |
| `project:builds:read`    | ビルド分析を読む              |
| `project:builds:write`   | ビルド分析のアップロード          |
| `project:runs:read`      | Readコマンドの実行           |
| `project:runs:write`     | コマンドの実行の作成と更新         |

### スコープグループ{#scope-groups}

スコープグループを使用すると、単一の識別子で複数の関連するスコープを簡単に指定できます。スコープグループを使用すると、その中に含まれる個々のスコープがすべて自動的に展開されます。

| スコープグループ | 対象範囲                                                                                                                                     |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `ci`     | `project:cache:write`,`project:previews:write`,`project:bundles:write`,`project:tests:write`,`project:builds:write`,`project:runs:write` |

### 継続的インテグレーション{#continuous-integration}

OIDCをサポートしていないCI環境では、`ci` スコープグループを使用してアカウントトークンを作成し、CIワークフローの認証を行うことができます:

```bash
tuist account tokens create my-account --scopes ci --name ci
```

これにより、一般的なCI操作（キャッシュ、プレビュー、バンドル、テスト、ビルド、実行）に必要なすべてのスコープを含むトークンが生成されます。生成されたトークンをCI環境のシークレットとして保存し、`環境変数にTUIST_TOKEN`
として設定してください。

### アカウントトークンの管理{#managing-account-tokens}

アカウントのすべてのトークンを一覧表示するには：

```bash
tuist account tokens list my-account
```

名前でトークンを無効にするには：

```bash
tuist account tokens revoke my-account ci-cache-token
```

### アカウントトークンの使用{#using-account-tokens}

アカウントトークンは、環境変数として定義する必要があります。`TUIST_TOKEN`:

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
必要な場合は、アカウントトークンを使用してください：
- OIDCをサポートしていないCI環境での認証
- トークンが実行できる操作を細かく制御する
- アカウント内の複数のプロジェクトにアクセスできるトークン
- 自動的に失効する期間限定トークン
<!-- -->
:::
