---
{
  "title": "Hexパッケージのインストール",
  "titleTemplate": ":title · ガイド · Tuist",
  "description": "ElixirプロジェクトでTuistのHexパッケージをインストールおよび設定する方法を学びます。"
}
---
# Hex パッケージをインストールする {#install-the-hex-package}

Tuist は、[Hex](https://hex.pm/packages/tuist_ex) パッケージ `tuist_ex` を提供しており、これを Elixir プロジェクトに統合することで、<.localized_link href="/guides/features/build-insights/elixir">ビルドインサイト</.localized_link> や <.localized_link href="/guides/features/test-insights/elixir">テストインサイト</.localized_link> などの機能が利用可能になります。このガイドでは、そのインストールと設定の手順を説明します。

このパッケージには Elixir 1.18 以降が必要です。Tuist のコマンドラインインターフェースは不要です。

## 1. プロジェクトを作成する {#create-the-project}

Tuist ダッシュボードでプロジェクトを作成し、ビルドシステムとして **Mix (Elixir)** を選択してください。ハンドル `account/project` が、あなたの Mix プロジェクトと Tuist プロジェクトを結びつけます。

## 2. パッケージを追加する {#add-the-package}

`tuist_ex` を `mix.exs` の依存関係に追加してください:

<!-- @snippet: ./_tuist-ex-dependency -->

次に、取得します:

```bash
mix deps.get
```

`runtime: false` により、Tuist が実行中のアプリケーションに含まれないようにします。<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Elixir で始める</.localized_link> に進み、キャッシュ、ビルドインサイト、テストインサイトをまとめて設定してください。以下のセクションでは、認証と設定の詳細について説明します。

## 3. チームと継続的インテグレーションの認証 {#authenticate}

各チームメンバーは、自分のマシンで Tuist の機能を利用するために次のコマンドを実行します:

```bash
mix tuist.login
```

短いサインインコードが表示され、ブラウザが開いてコードの入力を求め、承認待ちになります。ブラウザを使わずにログインするには、認証情報を渡してください:

```bash
mix tuist.login --email person@example.com --password secret
```

セルフホスト型またはローカルの Tuist サーバーを使用する場合は、`mix.exs` でベース URL を設定するか、`--url` で指定してください:

```bash
mix tuist.login --url http://localhost:8080
```

ホスト名の表記を一貫させてください。例えば、`localhost` に保存されたログイン情報は、`127.0.0.1` に保存されたものとは別物です。

GitHub Actions、CircleCI、Bitrise では、継続的インテグレーションにログイン手順は不要です。タスクが初めてレポートを送信する際、プロバイダーの OpenID Connect トークンを Tuist トークンと交換します。<.localized_link href="/guides/integrations/gitforge/github">GitHub リポジトリを接続</.localized_link> し、GitHub Actions ではジョブに `id-token: write` 権限を付与してください:

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

Fly.io Machines など、他の OpenID Connect アイデンティティプロバイダーを使用する場合は、アカウントの **設定 → 認証** ページにある **ワークロードアイデンティティ** セクションでワークロードアイデンティティ信頼ポリシーを設定し、そのアカウントが所有する現在および将来のすべてのプロジェクトに対する CI アクセスを許可します。`TUIST_OIDC_ACCOUNT` にプロジェクトを所有する Tuist アカウントを設定し、`TUIST_OIDC_TOKEN` を介してポリシーのオーディエンスを持つ新しく発行されたアイデンティティトークンを提供してください。アカウントトークンや有効な保存済みログイン情報がない場合、統合機能は自動的にこれを交換します。`mix tuist.login` も CI 以外でこれを受け付けます。自動交換では、同じサーバー、アカウント、および提供されたアイデンティティトークンに対してのみ、有効期限切れでないセッションを再利用します。アイデンティティを変更すると新しい交換がトリガーされ、空のアイデンティティを提供した場合は以前のセッションを再利用せず失敗します。Tuist のセッションはリフレッシュトークンなしで 1 時間有効であるため、長時間実行されるワークロードの場合は、セッションの有効期限が切れる前に新しいアイデンティティトークンを発行し、`mix tuist.login` を再度実行してください。<.localized_link href="/guides/server/authentication#workload-identity-trust-policies">ワークロードアイデンティティの設定</.localized_link> および <.localized_link href="/guides/server/authentication#flyio-machines">Fly.io の例</.localized_link> を参照してください。

フォークからのプルリクエストには OpenID Connect トークンが付与されないため、その実行はレポートされず、通常どおり合格または不合格となります。他のプロバイダーでは、`TUIST_TOKEN` 環境変数にアカウントトークンを設定してください。トークンの作成方法については、<.localized_link href="/guides/server/authentication#continuous-integration">継続的インテグレーションの認証ガイド</.localized_link> を参照してください。

## 4. `mix test` と `mix compile` を引き続き使用する {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">共通セットアップ</.localized_link> により、コンパイルとテストのエイリアスがインストールされます。`mix test test/my_app_test.exs:12 --trace` は、同じ出力と終了コードで実行をレポートし、コンパイル統合は `mix test` または `mix phx.server` によってトリガーされたビルドを対象とします。実行すべき作業が見つからないコンパイルはレポートされません。

これらのタスクは、独自の名前で呼び出した場合にも動作します。Mix は、そのように入力されたタスクを `dev` 環境で開始するため、テスト環境用には別のプロセスで最初から開始する必要があります。これを回避するには、タスクを優先環境に追加してください:

```elixir
def cli do
  [preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]]
end
```

## 設定リファレンス {#configuration-reference}

`mix.exs` のプロジェクトオプション内の `tuist` で、以下のオプションが利用可能です:

| オプション | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `project` | `String` | なし (必須) | `account/project` 形式のプロジェクト識別子。 |
| `url` | `String` | `"https://tuist.dev"` | Tuist サーバーのベース URL。 |
| `cache` | `boolean` またはキーワードリスト | 無効 | セットアップにより依存関係のキャッシュが有効になります。除外事項と追加入力については <.localized_link href="/guides/features/cache/elixir">Elixir キャッシュ</.localized_link> を参照してください。 |
| `test_retries` | `integer` | `0` | 失敗したテストを再試行する回数。<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">テストの再試行</.localized_link> を参照してください。 |
| `tags` | `String` のリスト | `[]` | すべてのビルドに付加するタグ。<.localized_link href="/guides/features/build-insights/elixir#custom-metadata">カスタムメタデータ</.localized_link> を参照してください。 |
| `values` | マップ | `%{}` | すべてのビルドに付加するキーと値のデータ。 |

環境変数は `mix.exs` よりも優先されます:

| 変数 | 説明 |
| --- | --- |
| `TUIST_PROJECT` | `account/project` 形式のプロジェクト識別子。 |
| `TUIST_URL` | Tuist サーバーのベース URL。 |
| `TUIST_TOKEN` | 保存されたログインの代わりに使用する認証トークン。 |
| `TUIST_OIDC_TOKEN` | 新しく発行された OpenID Connect ID トークンで、Tuist トークンと交換されます。GitHub Actions および Bitrise では対象が `tuist` である必要があり、他のプロバイダーではアカウントのワークロード ID と一致している必要があります。`mix tuist.login` で使用されるほか、アカウントトークンや有効な保存済みログインが存在しない場合のフォールバックとしても利用されます。 |
| `TUIST_OIDC_ACCOUNT` | プロジェクトを所有する Tuist アカウントハンドル。アカウントのワークロード ID を介してトークンを交換する際に必須です。既存のワークロード ID から選択しますが、これ自体はアクセス権を付与しません。 |
| `TUIST_TEST_RETRIES` | 失敗したテストを再試行する回数。 |
| `TUIST_TAGS` | ビルドに付加するカンマ区切りのタグ。 |
| `TUIST_VALUES` | ビルドに付加するカンマ区切りの `key=value` ペア。 |
| `TUIST_DEBUG` | レポートを送信できなかった理由を表示するには `1` に設定します。 |

レポート送信は `mix test` や `mix compile` の終了コードを変更しません。レポートを送信できない場合、`TUIST_DEBUG=1` が設定されていない限りタスクは何も出力しません。

## 次のステップ {#next-steps}

パッケージのインストールと設定が完了したら、以下を利用できます:

- コンパイル済みの依存関係をローカルおよび CI ビルド間で再利用するための <.localized_link href="/guides/features/cache/elixir">依存関係のキャッシュ</.localized_link>。
- コンパイル時間、警告、およびビルドのボトルネックを追跡するための <.localized_link href="/guides/features/build-insights/elixir">ビルドインサイト</.localized_link>。
- 各テストまで詳細にテストパフォーマンスを追跡するための <.localized_link href="/guides/features/test-insights/elixir">テストインサイト</.localized_link>。
- 断続的に失敗するテストを検出して追跡するための <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">不安定なテスト</.localized_link>。
- 継続的インテグレーションの実行エージェント間でテストを分散するための <.localized_link href="/guides/features/test-sharding/elixir">テストシャーディング</.localized_link>。
