---
{
  "title": "Install the Hex package",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Learn how to install and configure Tuist's Hex package in your Elixir project."
}
---
# Hexパッケージをインストールする {#install-the-hex-package}

Tuistは、[Hex](https://hex.pm/packages/tuist_ex)パッケージ`tuist_ex`を提供しており、これをElixirプロジェクトに統合することで、<.localized_link href="/guides/features/build-insights/elixir">ビルドインサイト</.localized_link>や<.localized_link href="/guides/features/test-insights/elixir">テストインサイト</.localized_link>などの機能を有効にできます。このガイドでは、そのインストールと設定手順を説明します。

このパッケージにはElixir 1.18以降が必要です。Tuistのコマンドラインインターフェースは不要です。

## 1. プロジェクトを作成する {#create-the-project}

Tuist ダッシュボードでプロジェクトを作成し、ビルドシステムとして **Mix (Elixir)** を選択します。そのハンドルである `account/project` が、Mix プロジェクトと Tuist プロジェクトを接続します。

## 2. パッケージを追加する {#add-the-package}

`mix.exs`内の依存関係に`tuist_ex`を追加します:

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

次に、取得します:

```bash
mix deps.get
```

`runtime: false`により、実行中のアプリケーションからTuistが除外されます。<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Elixirでの始め方</.localized_link>に進み、キャッシング、ビルドインサイト、テストインサイトを一緒に設定してください。以下のセクションでは、認証と設定の詳細について説明します。

## 3. チームと継続的インテグレーションの認証 {#authenticate}

各チームメンバーは、マシン上でTuistの機能にアクセスするために次のコマンドを実行します:

```bash
mix tuist.login
```

ブラウザが開き、承認を待ちます。ブラウザなしでログインするには、資格情報を渡します:

```bash
mix tuist.login --email person@example.com --password secret
```

セルフホスト型またはローカルのTuistサーバーを使用する場合は、`mix.exs`でベースURLを設定するか、`--url`で渡します:

```bash
mix tuist.login --url http://localhost:8080
```

ホスト名の表記を一貫させてください。例えば、`localhost`用に保存されたログインは、`127.0.0.1`用に保存されたものとは別物です。

GitHub Actions、CircleCI、Bitrise では、継続的インテグレーションにログイン手順は不要です。タスクが初めてレポートを送信する際、プロバイダーの OpenID Connect トークンが Tuist トークンと交換されます。<.localized_link href="/guides/integrations/gitforge/github">GitHub リポジトリを</.localized_link> Tuist プロジェクトに接続し、GitHub Actions ではジョブに `id-token: write` 権限を付与します:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix test
```

Fly.io Machinesなどの他のOpenID Connectアイデンティティプロバイダーを使用する場合は、アカウントの**Settings → Authentication**ページにある**Workload identities**セクションでワークロードアイデンティティ信頼ポリシーを設定します。これにより、そのアカウントが所有する現在および将来のすべてのプロジェクトに対するCIアクセスが許可されます。`TUIST_OIDC_ACCOUNT`をプロジェクトを所有するTuistアカウントに設定し、ポリシーのオーディエンスを持つ新しく発行されたアイデンティティトークンを`TUIST_OIDC_TOKEN`を通じて提供します。アカウントトークンや有効な保存済みログインがない場合、インテグレーションは自動的にこれを交換します。`mix tuist.login`もCI以外でこれを受け入れます。自動交換は、同じサーバー、アカウント、および提供されたアイデンティティトークンに対してのみ、未期限のセッションを再利用します。そのアイデンティティを変更すると新しい交換がトリガーされ、空のアイデンティティが提供された場合は以前のセッションを再利用せず失敗します。Tuistセッションはリフレッシュトークンなしで1時間持続するため、長期間実行されるワークロードの場合は、セッションの有効期限が切れる前に新しいアイデンティティトークンを発行し、`mix tuist.login`を再度実行してください。<.localized_link href="/guides/server/authentication#workload-identity-trust-policies">ワークロードアイデンティティの設定</.localized_link>および<.localized_link href="/guides/server/authentication#flyio-machines">Fly.ioの例</.localized_link>に従ってください。

フォークからのプルリクエストにはOpenID Connectトークンが付与されないため、それらの実行はレポートされず、通常通り成功または失敗します。他のプロバイダーでは、`TUIST_TOKEN`環境変数をアカウントトークンに設定してください。作成方法については、<.localized_link href="/guides/integrations/continuous-integration#authentication">継続的インテグレーションの認証ガイド</.localized_link>に従ってください。

## 4. `mix test`と`mix compile`を引き続き使用する {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">共有セットアップ</.localized_link>により、コンパイルおよびテストのエイリアスがインストールされます。`mix test test/my_app_test.exs:12 --trace`は、同じ出力と終了コードで実行をレポートし、コンパイルインテグレーションは`mix test`または`mix phx.server`によってトリガーされたビルドをカバーします。行うべきことがないコンパイルはレポートされません。

タスクは独自の名前で呼び出した場合も動作します。Mixはそのように入力されたタスクを`dev`環境で開始するため、テスト環境用のタスクは2番目のプロセスで最初から開始する必要があります。これを回避するには、タスクを優先環境に追加します:

```elixir
def cli do
  [preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]]
end
```

## 設定リファレンス {#configuration-reference}

`mix.exs`のプロジェクトオプションにある`tuist`の下で、以下のオプションを利用できます:

| オプション | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `project` | `String` | なし（必須） | `account/project`形式のプロジェクト識別子。 |
| `url` | `String` | `"https://tuist.dev"` | TuistサーバーのベースURL。 |
| `cache` | `boolean`またはキーワードリスト | 無効 | セットアップにより依存関係のキャッシングが有効になります。除外事項と追加入力については、<.localized_link href="/guides/features/cache/elixir">Elixirキャッシュ</.localized_link>を参照してください。 |
| `test_retries` | `integer` | `0` | 失敗したテストを再試行する回数。<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">テストの再試行</.localized_link>を参照してください。 |
| `tags` | `String`のリスト | `[]` | すべてのビルドに付加するタグ。<.localized_link href="/guides/features/build-insights/elixir#custom-metadata">カスタムメタデータ</.localized_link>を参照してください。 |
| `values` | マップ | `%{}` | すべてのビルドに付加するキー・バリューデータ。 |

環境変数は`mix.exs`よりも優先されます:

| 変数 | 説明 |
| --- | --- |
| `TUIST_PROJECT` | `account/project`形式のプロジェクト識別子。 |
| `TUIST_URL` | TuistサーバーのベースURL。 |
| `TUIST_TOKEN` | 保存されたログインの代わりに使用する認証トークン。 |
| `TUIST_OIDC_TOKEN` | Tuistトークンと交換される、新しく発行されたOpenID Connect IDトークン。GitHub ActionsおよびBitriseの場合、そのオーディエンスは`tuist`である必要があります。他のプロバイダーの場合は、プロジェクトの信頼ポリシーと一致している必要があります。`mix tuist.login`で使用されるか、アカウントトークンや有効な保存済みログインが存在しない場合のフォールバックとして使用されます。 |
| `TUIST_OIDC_ACCOUNT` | プロジェクトを所有するTuistアカウントハンドル。プロジェクトの信頼ポリシーを通じてトークンを交換する際に必須です。既存の信頼ポリシーの中から選択しますが、それ自体でアクセス権を付与するものではありません。 |
| `TUIST_TEST_RETRIES` | 失敗したテストを再試行する回数。 |
| `TUIST_TAGS` | ビルドに付加するカンマ区切りのタグ。 |
| `TUIST_VALUES` | ビルドに付加するカンマ区切りの`key=value`ペア。 |
| `TUIST_DEBUG` | レポートを送信できなかった理由を表示するには、`1`に設定します。 |

レポート機能は、`mix test`または`mix compile`の終了コードを変更しません。レポートを送信できない場合、`TUIST_DEBUG=1`が設定されていない限り、タスクは何も表示しません。

## 次のステップ {#next-steps}

パッケージのインストールと設定が完了したら、以下を使用できます:

- コンパイル済みの依存関係をローカルおよびCIビルド間で再利用するための、<.localized_link href="/guides/features/cache/elixir">依存関係キャッシュ</.localized_link>。
- コンパイル時間、警告、ビルドのボトルネックを追跡するための、<.localized_link href="/guides/features/build-insights/elixir">ビルドインサイト</.localized_link>。
- 各テストまでのテストパフォーマンスを追跡するための、<.localized_link href="/guides/features/test-insights/elixir">テストインサイト</.localized_link>。
- 断続的に失敗するテストを検出・追跡するための、<.localized_link href="/guides/features/test-insights/flaky-tests/elixir">不安定なテスト</.localized_link>。
- 継続的インテグレーションランナー間でテストを分散するための、<.localized_link href="/guides/features/test-sharding/elixir">テストシャーディング</.localized_link>。
