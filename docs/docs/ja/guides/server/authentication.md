---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 認証{#authentication}

サーバーと対話するために、CLIは[ベアラ認証](https://swagger.io/docs/specification/authentication/bearer-authentication/)を使用してリクエストを認証
する必要がある。CLIはユーザー認証、アカウント認証、OIDCトークン認証をサポートしている。

## ユーザーとして{#as-a-user}

お使いのマシンでCLIをローカルに使用する場合は、ユーザーとして認証することをお勧めします。ユーザーとして認証するには、以下のコマンドを実行する必要があります：

```bash
tuist auth login
```

このコマンドは、Webベースの認証フローを実行する。認証が完了すると、CLIは、`~/.config/tuist/credentials`
の下に、長期間のリフレッシュ・トークンと短期間のアクセストークンを保存します。このディレクトリの各ファイルは、認証したドメインを表し、デフォルトでは`tuist.dev.json`
になります。そのディレクトリに保存されている情報は機密なので、**安全を確保してください** 。

CLI は、サーバへのリクエスト時に自動的に認証情報を検索します。アクセストークンの有効期限が切れている場合、CLI
はリフレッシュトークンを使用して新しいアクセストークンを取得します。

## OIDCトークン{#oidc-tokens}

OpenID Connect
(OIDC)をサポートするCI環境では、Tuistは長期間のシークレットを管理することなく自動的に認証を行うことができます。サポートされているCI環境で実行すると、CLIは自動的にOIDCトークンプロバイダを検出し、CIが提供するトークンをTuistのアクセストークンと交換する。

### CIプロバイダー{#supported-ci-providers}

- GitHub アクション
- サークルCI
- ビットライズ

### OIDC認証の設定{#setting-up-oidc-authentication}

1. **リポジトリをTuistに接続する**:
   <LocalizedLink href="/guides/integrations/gitforge/github">GitHub統合ガイド</LocalizedLink>に従って、GitHubリポジトリをTuistプロジェクトに接続します。

2. **tuist auth login`** を実行してください：CI ワークフローでは、認証が必要なコマンドの前に`tuist auth login`
   を実行してください。CLIは自動的にCI環境を検出し、OIDCを使って認証します。

プロバイダー固有の設定例については、<LocalizedLink href="/guides/integrations/continuous-integration">Continuous Integrationガイド</LocalizedLink>を参照してください。

### OIDCトークンのスコープ{#oidc-token-scopes}

OIDC トークンは`ci` スコープグループに付与され、リポジトリに接続されているすべてのプロジェクトへのアクセスを提供します。`ci`
スコープに含まれるものの詳細については、[スコープグループ](#scope-groups) を参照してください。

::: tip SECURITY BENEFITS
<!-- -->
OIDC認証は、長期間のトークンよりも安全である：
- ローテーションや管理に秘密はない
- トークンは短命で、個々のワークフロー実行にスコープされる
- 認証はリポジトリIDに紐づく
<!-- -->
:::

## アカウント・トークン{#account-tokens}

OIDCをサポートしていないCI環境や、パーミッションのきめ細かな制御が必要な場合は、アカウントトークンを使うことができます。アカウントトークンでは、トークンがアクセスできるスコープやプロジェクトを厳密に指定することができます。

### アカウント・トークンの作成{#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

このコマンドは以下のオプションを受け付ける：

| オプション      | 説明                                                                                   |
| ---------- | ------------------------------------------------------------------------------------ |
| `--スコープ`   | 必須。トークンを付与するスコープのカンマ区切りリスト。                                                          |
| `--名前`     | 必須。トークンの一意な識別子(1-32文字、英数字、ハイフン、アンダースコアのみ)。                                           |
| `--期限切れ`   | オプション。トークンの有効期限。`30d` (日)、`6m` (月)、`1y` (年)のようなフォーマットを使用します。指定しない場合、トークンの有効期限はありません。 |
| `--プロジェクト` | トークンを特定のプロジェクト・ハンドルに限定します。指定しない場合は、トークンはすべてのプロジェクトにアクセスできます。                         |

### 使用可能なスコープ{#available-scopes}

| スコープ                                   | 説明                     |
| -------------------------------------- | ---------------------- |
| `アカウント:メンバー:読み取り`                      | アカウントメンバーを読む           |
| `アカウント:メンバー:書き込み`                      | アカウントメンバーの管理           |
| `アカウント:レジストリ:読み取り`                     | Swiftのパッケージレジストリから読み込む |
| `アカウント:レジストリ:書き込み`                     | Swiftのパッケージレジストリに公開する  |
| `プロジェクト:プレビュー:読む`                      | プレビューのダウンロード           |
| `project:previews:書き込み`                | プレビューのアップロード           |
| `プロジェクト:admin:read`                    | プロジェクトの設定を読む           |
| `project:admin:書き込み`                   | プロジェクト設定の管理            |
| `project:cache:read（プロジェクトキャッシュ`       | キャッシュされたバイナリをダウンロードする  |
| `プロジェクト:キャッシュ:書き込み`                    | キャッシュされたバイナリをアップロードする  |
| `project:bundles:read（プロジェクト：バンドル：リード` | バンドルを見る                |
| `プロジェクト:バンドル:書き込み`                     | バンドルのアップロード            |
| `project:tests:read`                   | テスト結果を読む               |
| `project:tests:write`                  | テスト結果のアップロード           |
| `project:builds:read（プロジェクト：ビルド：リード`   | ビルドアナリティクスを読む          |
| `プロジェクト:ビルド:書き込み`                      | ビルド分析のアップロード           |
| `project:runs:read（プロジェクト・ランズ・リード`     | 読み取りコマンドの実行            |
| `project:runs:write（プロジェクト：ランズ：ライト`    | コマンドランの作成と更新           |

### スコープグループ{#scope-groups}

スコープグループは、関連する複数のスコープに単一の識別子を付与する便利な方法です。スコープグループを使用すると、スコープグループは自動的に拡張され、スコープグループに含まれるすべてのスコープを含むようになります。

| スコープグループ | 付属スコープ                                                                                                                                   |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `ci`     | `project:cache:write`,`project:previews:write`,`project:bundles:write`,`project:tests:write`,`project:builds:write`,`project:runs:write` |

### 継続的インテグレーション{#continuous-integration}

OIDCをサポートしていないCI環境では、`ci` scope groupでアカウントトークンを作成し、CIワークフローを認証することができます：

```bash
tuist account tokens create my-account --scopes ci --name ci
```

これにより、典型的なCI操作（キャッシュ、プレビュー、バンドル、テスト、ビルド、実行）に必要なすべてのスコープを持つトークンが生成されます。生成されたトークンを
CI 環境のシークレットとして保存し、`TUIST_TOKEN` 環境変数として設定します。

### アカウントトークンの管理{#managing-account-tokens}

アカウントのすべてのトークンを一覧表示する：

```bash
tuist account tokens list my-account
```

トークンを名前で取り消す：

```bash
tuist account tokens revoke my-account ci-cache-token
```

### アカウントトークンの使用{#using-account-tokens}

アカウント・トークンは環境変数`TUIST_TOKEN` として定義されることが期待される：

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
必要なときにアカウントトークンを使う：
- OIDCをサポートしないCI環境での認証
- トークンが実行できる操作のきめ細かな制御
- アカウント内の複数のプロジェクトにアクセスできるトークン
- 自動的に失効する時間制限付きトークン
<!-- -->
:::
