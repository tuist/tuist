---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 認証{#authentication}

サーバーとやり取りするには、CLIは[bearer
authentication](https://swagger.io/docs/specification/authentication/bearer-authentication/)を使用してリクエストを認証する必要があります。CLIはユーザーとして、アカウントとして、またはOIDCトークンを使用した認証をサポートしています。

## ユーザーとして{#as-a-user}

ローカルマシンでCLIを使用する際は、ユーザーとして認証することを推奨します。ユーザーとして認証するには、次のコマンドを実行する必要があります：

```bash
tuist auth login
```

このコマンドはウェブベースの認証フローを実行します。認証後、CLIは`~/.config/tuist/credentials`
に長期リフレッシュトークンと短期アクセストークンを保存します。ディレクトリ内の各ファイルは認証対象ドメインを表し、デフォルトでは`tuist.dev.json`
となります。このディレクトリに保存される情報は機密性が高いため、**安全に保管してください** 。

CLIはサーバーへのリクエスト時に自動的に認証情報を参照します。アクセストークンが期限切れの場合、CLIはリフレッシュトークンを使用して新しいアクセストークンを取得します。

## OIDCトークン{#oidc-tokens}

OpenID
Connect（OIDC）をサポートするCI環境では、Tuistは長期有効なシークレットを管理する必要なく自動的に認証できます。サポート対象のCI環境で実行する場合、CLIはOIDCトークンプロバイダーを自動的に検出し、CIが提供するトークンをTuistアクセストークンと交換します。

### サポートされているCIプロバイダー{#supported-ci-providers}

- GitHub Actions
- CircleCI
- Bitrise

### OIDC認証の設定{#setting-up-oidc-authentication}

1. **リポジトリをTuistに接続する**:
   <LocalizedLink href="/guides/integrations/gitforge/github">GitHub連携ガイド</LocalizedLink>に従い、GitHubリポジトリをTuistプロジェクトに接続してください。

2. **`tuist auth login` を実行**: CI ワークフロー内で、認証が必要なコマンドを実行する前に、`tuist auth login`
   を実行してください。CLI は CI 環境を自動的に検出し、OIDC を使用して認証を行います。

プロバイダー固有の設定例については、<LocalizedLink href="/guides/integrations/continuous-integration">継続的インテグレーションガイド</LocalizedLink>を参照してください。

### OIDCトークンスコープ{#oidc-token-scopes}

OIDCトークンには、リポジトリに接続されたすべてのプロジェクトへのアクセスを提供する`ci` スコープグループが付与されます。`ci`
スコープの詳細については、[Scope groups](#scope-groups)を参照してください。

::: tip SECURITY BENEFITS
<!-- -->
OIDC認証は、以下の理由から長期有効トークンよりも安全です：
- 回転や管理の秘訣などない
- トークンは短命であり、個々のワークフロー実行にスコープされます
- 認証はリポジトリの識別情報に関連付けられています
<!-- -->
:::

## アカウントトークン{#account-tokens}

OIDCをサポートしないCI環境、または権限を細かく制御する必要がある場合、アカウントトークンを使用できます。アカウントトークンでは、トークンがアクセスできるスコープとプロジェクトを正確に指定できます。

### アカウントトークンの作成{#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

このコマンドは以下のオプションを受け付けます：

| オプション       | 説明                                                                                      |
| ----------- | --------------------------------------------------------------------------------------- |
| `--scopes`  | 必須。トークンに付与するスコープのカンマ区切りリスト。                                                             |
| `--name`    | 必須。トークンの一意の識別子（1～32文字、英数字、ハイフン、アンダースコアのみ）。                                              |
| `--expires` | オプション。トークンの有効期限を指定します。形式は`30d` (日数)、`6m` (月数)、または`1y` (年数) を使用します。指定しない場合、トークンは永久に有効です。 |
| `--プロジェクト`  | トークンを特定のプロジェクトハンドルに限定してください。指定しない場合、トークンはすべてのプロジェクトにアクセスできます。                           |

### 利用可能なスコープ{#available-scopes}

| 適用範囲                     | 説明                    |
| ------------------------ | --------------------- |
| `account:members:read`   | アカウントメンバーを読む          |
| `account:members:write`  | アカウントメンバーを管理する        |
| `account:registry:read`  | Swiftパッケージレジストリから読み込み |
| `account:registry:write` | Swiftパッケージレジストリに公開する  |
| `project:previews:read`  | プレビューをダウンロード          |
| `project:previews:write` | プレビューをアップロード          |
| `project:admin:read`     | プロジェクト設定を読む           |
| `project:admin:write`    | プロジェクト設定を管理する         |
| `project:cache:read`     | キャッシュされたバイナリをダウンロード   |
| `project:cache:write`    | キャッシュされたバイナリをアップロード   |
| `project:bundles:read`   | バンドルを表示               |
| `project:bundles:write`  | バンドルをアップロード           |
| `project:tests:read`     | テスト結果を読む              |
| `project:tests:write`    | テスト結果をアップロード          |
| `project:builds:read`    | ビルド分析を読む              |
| `project:builds:write`   | ビルド分析データをアップロード       |
| `project:runs:read`      | コマンドの実行               |
| `project:runs:write`     | 作成および更新コマンドの実行        |

### スコープグループ{#scope-groups}

スコープグループは、単一の識別子で複数の関連スコープを付与する便利な方法を提供します。スコープグループを使用すると、含まれる個々のスコープが自動的に展開されます。

| スコープグループ | 対象範囲                                                                                                                                     |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `ci`     | `project:cache:write`,`project:previews:write`,`project:bundles:write`,`project:tests:write`,`project:builds:write`,`project:runs:write` |

### 継続的インテグレーション{#continuous-integration}

OIDCをサポートしていないCI環境では、CIワークフローの認証用に`ci` scope groupでアカウントトークンを作成できます：

```bash
tuist account tokens create my-account --scopes ci --name ci
```

これにより、一般的なCI操作に必要なすべてのスコープ（キャッシュ、プレビュー、バンドル、テスト、ビルド、実行）を含むトークンが生成されます。生成されたトークンをCI環境のシークレットとして保存し、環境変数```（`TUIST_TOKEN`）として設定してください。`

### アカウントトークンの管理{#managing-account-tokens}

アカウントの全トークンを一覧表示するには：

```bash
tuist account tokens list my-account
```

トークンを名前で無効化するには：

```bash
tuist account tokens revoke my-account ci-cache-token
```

### アカウントトークンの使用{#using-account-tokens}

アカウントトークンは環境変数として定義される必要があります：`TUIST_TOKEN`

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
必要な場合はアカウントトークンを使用してください：
- OIDCをサポートしないCI環境における認証
- トークンが実行できる操作を細かく制御する
- アカウント内の複数のプロジェクトにアクセスできるトークン
- 自動で期限切れになる時間制限付きトークン
<!-- -->
:::
