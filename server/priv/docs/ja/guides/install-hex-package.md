---
{
  "title": "Hexパッケージのインストール",
  "titleTemplate": ":title · ガイド · Tuist",
  "description": "ElixirプロジェクトでTuistのHexパッケージをインストールおよび設定する方法を学びます。"
}
---
# Hexパッケージのインストール {#install-the-hex-package}

Tuistは[Hex](https://hex.pm/packages/tuist_ex)パッケージである`tuist_ex`を提供しており、これをElixirプロジェクトに統合することで、<.localized_link href="/guides/features/build-insights/elixir">ビルドインサイト</.localized_link>や<.localized_link href="/guides/features/test-insights/elixir">テストインサイト</.localized_link>などの機能を利用できます。このガイドでは、そのインストールと設定手順を説明します。

このパッケージにはElixir 1.18以降が必要です。Tuistのコマンドラインインターフェースは不要です。

## 1. プロジェクトの作成 {#create-the-project}

Tuistダッシュボードでプロジェクトを作成し、ビルドシステムとして**Mix (Elixir)** を選択します。ハンドル（`account/project`）が、MixプロジェクトとTuistプロジェクトを紐付ける鍵となります。

## 2. パッケージの追加 {#add-the-package}

`tuist_ex`を`mix.exs`のdependenciesに追加します。

<!-- @snippet: ./_tuist-ex-dependency -->

次に、パッケージを取得します。

```bash
mix deps.get
```

`runtime: false`により、Tuistを実行中のアプリケーションから除外します。<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Get started with Elixir</.localized_link>に進み、キャッシュ、ビルドインサイト、テストインサイトをまとめて設定してください。以下のセクションでは、認証と設定の詳細について説明します。

## 3. チームとCIの認証 {#authenticate}

各チームメンバーは、マシン上でTuistの機能を利用するために次のコマンドを実行します。

```bash
mix tuist.login
```

短いサインインコードが表示され、ブラウザが開いてコードの入力を求め、承認を待ちます。ブラウザを使わずにログインするには、認証情報を渡します。

```bash
mix tuist.login --email person@example.com --password secret
```

セルフホスト型またはローカルのTuistサーバーを使用する場合は、`mix.exs`でベースURLを設定するか、`--url`で指定します。

```bash
mix tuist.login --url http://localhost:8080
```

ホスト名の表記を一貫させてください。例えば、`localhost`用に保存されたログイン情報は、`127.0.0.1`用に保存されたものとは別扱いになります。

GitHub Actions、CircleCI、Bitriseでは、CIにログイン手順は不要です。タスクが初めてレポートを送信する際、プロバイダーのOpenID ConnectトークンとTuistトークンを交換します。<.localized_link href="/guides/integrations/gitforge/github">Connect your GitHub repository</.localized_link>でGitHubリポジトリをTuistプロジェクトに接続し、GitHub Actionsではジョブに`id-token: write`権限を付与します。

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

Fly.io Machinesなどの他のOpenID Connectアイデンティティプロバイダーを使用する場合は、アカウントの**Settings → Authentication**ページにある**Workload identities**セクションでワークロードアイデンティティ信頼ポリシーを設定し、そのアカウントが所有する現在および将来のすべてのプロジェクトに対してCIアクセスを許可します。`TUIST_OIDC_ACCOUNT`をプロジェクトを所有するTuistアカウントに設定し、`TUIST_OIDC_TOKEN`を通じてポリシーのaudienceを持つ新しく発行されたアイデンティティトークンを提供します。アカウントトークンや有効な保存済みログイン情報がない場合、統合機能は自動的にこれを交換します。`mix tuist.login`でもCI環境外でこれを受け付けます。自動交換では、同じサーバー、アカウント、提供されたアイデンティティトークンに対してのみ、有効期限内のセッションを再利用します。アイデンティティを変更すると新しい交換が発生し、空のアイデンティティが提供された場合は以前のセッションを再利用せず失敗します。Tuistのセッションはリフレッシュトークンなしで1時間有効なので、長時間実行されるワークロードの場合は、セッションの有効期限が切れる前に新しいアイデンティティトークンを発行して`mix tuist.login`を再度実行してください。<.localized_link href="/guides/server/authentication#workload-identity-trust-policies">workload identity setup</.localized_link>および<.localized_link href="/guides/server/authentication#flyio-machines">Fly.io example</.localized_link>を参照してください。

フォークからのプルリクエストにはOpenID Connectトークンが付与されないため、それらの実行はレポートされず、通常どおり合格または不合格となります。他のプロバイダーでは、`TUIST_TOKEN`環境変数をアカウントトークンに設定してください。トークンの作成方法は<.localized_link href="/guides/server/authentication#continuous-integration">continuous integration authentication guide</.localized_link>を参照してください。

## 4. `mix test`と`mix compile`を引き続き使用する {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">shared setup</.localized_link>により、コンパイルおよびテストのエイリアスがインストールされます。`mix test test/my_app_test.exs:12 --trace`は、同じ出力と終了コードで実行をレポートし、コンパイル統合は`mix test`または`mix phx.server`によってトリガーされたビルドを対象とします。行うべきコンパイル作業がない場合はレポートされません。

これらのタスクは、独自の名前で呼び出した場合も動作します。Mixはそのような入力方法でタスクを`dev`環境で開始するため、テスト環境用には別のプロセスで最初から開始する必要があります。これを回避するには、タスクを優先環境に追加します。

```elixir
def cli do
  [preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]]
end
```

## 設定リファレンス {#configuration-reference}

`mix.exs`のプロジェクトオプションにある`tuist`の下で、以下のオプションが利用可能です。

| オプション | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `project` | `String` | なし（必須） | `account/project`形式のプロジェクト識別子。 |
| `url` | `String` | `"https://tuist.dev"` | TuistサーバーのベースURL。 |
| `cache` | `boolean`またはキーワードリスト | 無効 | セットアップにより依存関係のキャッシュが有効になります。除外事項や追加の入力については<.localized_link href="/guides/features/cache/elixir">Elixir cache</.localized_link>を参照してください。 |
| `test_retries` | `integer` | `0` | 失敗したテストを再試行する回数。<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">test retries</.localized_link>を参照してください。 |
| `tags` | `String`のリスト | `[]` | すべてのビルドに付与するタグ。<.localized_link href="/guides/features/build-insights/elixir#custom-metadata">custom metadata</.localized_link>を参照してください。 |
| `values` | マップ | `%{}` | すべてのビルドに付与するキー・バリューデータ。 |

環境変数は`mix.exs`よりも優先されます。

| 変数 | 説明 |
| --- | --- |
| `TUIST_PROJECT` | `account/project`形式のプロジェクト識別子。 |
| `TUIST_URL` | TuistサーバーのベースURL。 |
| `TUIST_TOKEN` | 保存されたログイン情報の代わりに認証に使用するトークン。 |
| `TUIST_OIDC_TOKEN` | 新しく発行されたOpenID Connect IDトークンで、Tuistトークンと交換されます。GitHub ActionsおよびBitriseではそのオーディエンスが`tuist`である必要があり、他のプロバイダーではアカウントのワークロードIDと一致している必要があります。`mix tuist.login`で使用されるか、アカウントトークンや有効な保存済みログイン情報がない場合のフォールバックとして使用されます。 |
| `TUIST_OIDC_ACCOUNT` | プロジェクトを所有するTuistアカウントハンドル。アカウントのワークロードIDを通じてトークンを交換する際に必要です。既存のワークロードIDの中から選択しますが、それ自体でアクセス権を付与するものではありません。 |
| `TUIST_TEST_RETRIES` | 失敗したテストを再試行する回数。 |
| `TUIST_TAGS` | ビルドに付与するカンマ区切りのタグ。 |
| `TUIST_VALUES` | ビルドに付与するカンマ区切りの`key=value`ペア。 |
| `TUIST_DEBUG` | レポートを送信できなかった理由を表示するには`1`に設定します。 |

レポート送信は`mix test`または`mix compile`の終了コードを変更しません。レポートを送信できない場合、`TUIST_DEBUG=1`が設定されていない限りタスクは何も出力しません。

## 次のステップ {#next-steps}

パッケージのインストールと設定が完了すると、以下を使用できます。

- コンパイル済みの依存関係をローカルおよびCIビルド間で再利用するための<.localized_link href="/guides/features/cache/elixir">Dependency caching</.localized_link>。
- コンパイル時間、警告、およびビルドのボトルネックを追跡するための<.localized_link href="/guides/features/build-insights/elixir">Build insights</.localized_link>。
- 各テストまで詳細にテストパフォーマンスを追跡するための<.localized_link href="/guides/features/test-insights/elixir">Test insights</.localized_link>。
- 断続的に失敗するテストを検出・追跡するための<.localized_link href="/guides/features/test-insights/flaky-tests/elixir">Flaky tests</.localized_link>。
- テストを複数の継続的インテグレーションランナーに分散させるための<.localized_link href="/guides/features/test-sharding/elixir">Test sharding</.localized_link>。
