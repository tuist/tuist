---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# セルフホストインストール {#self-host-installation}

私たちは、インフラストラクチャをよりコントロールする必要がある組織向けに、Tuistサーバーのセルフホストバージョンを提供しています。このバージョンでは、お客様のインフラストラクチャ上でTuistをホストすることができ、お客様のデータが安全かつプライベートに保たれることを保証します。

> [重要] ライセンスの必要性
> Tuistのセルフホスティングには、法的に有効な有償ライセンスが必要です。Tuistのオンプレミスバージョンは、Enterpriseプランの組織でのみご利用いただけます。このバージョンにご興味のある方は、[contact@tuist.dev](mailto:contact@tuist.dev)までご連絡ください。

## リリースケイデンス{#release-cadence}。

Tuistの新バージョンは、新しいリリース可能な変更がmainに載るたびに継続的にリリースしています。私たちは[semantic
versioning](https://semver.org/)に従って、予測可能なバージョニングと互換性を保証します。

この主要なコンポーネントは、オンプレミスのユーザーとの調整が必要となるTuistサーバーの変更にフラグを立てるために使用されます。私たちがそれを使うことを期待しないでください。万が一必要になったとしても、私たちはスムーズな移行ができるよう協力しますのでご安心ください。

## 継続的デプロイメント{#continuous-deployment}。

Tuistの最新バージョンを毎日自動的にデプロイする継続的デプロイメントパイプラインを設定することを強くお勧めします。これにより、常に最新の機能、改善、セキュリティアップデートにアクセスできるようになります。

毎日新しいバージョンをチェックしてデプロイする GitHub Actions のワークフローの例です：

```yaml
name: Update Tuist Server
on:
  schedule:
    - cron: '0 3 * * *' # Run daily at 3 AM UTC
  workflow_dispatch: # Allow manual runs

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - name: Check and deploy latest version
        run: |
          # Your deployment commands here
          # Example: docker pull ghcr.io/tuist/tuist:latest
          # Deploy to your infrastructure
```

## ランタイム要件 {#runtime-requirements}

このセクションでは、Tuistサーバーをお客様のインフラストラクチャでホスティングするための要件を概説します。

### Docker-仮想化イメージの実行 {#running-dockervirtualized-images}。

サーバーは[Docker](https://www.docker.com/)イメージとして[GitHub's Container
Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)経由で配布します。

これを実行するには、インフラがDockerイメージの実行をサポートしていなければならない。ほとんどのインフラ・プロバイダーがDockerをサポートしているのは、Dockerが本番環境でソフトウェアを配布・実行するための標準的なコンテナになっているからだ。

### Postgresデータベース{#postgres-database}。

Dockerイメージの実行に加えて、リレーショナルデータを保存するための[Postgresデータベース](https://www.postgresql.org/)が必要です。ほとんどのインフラプロバイダーはPosgresデータベースを提供しています（例えば[AWS](https://aws.amazon.com/rds/postgresql/)や[Google
Cloud](https://cloud.google.com/sql/docs/postgres)）。

パフォーマンス分析には、[Timescale Postgres
extension](https://www.timescale.com/)を使用します。Postgresデータベースを実行しているマシンにTimescaleDBがインストールされていることを確認する必要があります。詳しくは[こちら](https://docs.timescale.com/self-hosted/latest/install/)のインストール手順に従ってください。Timescaleエクステンションをインストールできない場合は、Prometheusメトリクスを使用して独自のダッシュボードを設定することができます。

> [Docker イメージのエントリーポイントは、サービスを開始する前に、保留中のスキーマ・マイグレーションを自動的に実行します。

### クリックハウスデータベース {#clickhouse-database}

大量のデータを保存するために、私たちは[ClickHouse](https://clickhouse.com/)を使用しています。ビルドインサイトのようないくつかの機能は、ClickHouseが有効でなければ動作しません。ClickHouseは最終的にTimescale
Postgresエクステンションに取って代わる予定です。ClickHouseをセルフホストするか、ホスティングサービスを利用するかを選択できます。

> [Docker イメージのエントリーポイントは、サービスを開始する前に、保留中のClickHouseスキーマ・マイグレーションを自動的に実行します。

### ストレージ {#storage}

また、ファイル（フレームワークやライブラリのバイナリなど）を保存するソリューションも必要です。現在、私たちはS3に準拠したストレージをサポートしています。

## コンフィギュレーション {#configuration}

サービスのコンフィギュレーションは、環境変数を通して実行時に行われます。これらの変数は機密性が高いため、暗号化して安全なパスワード管理ソリューションに保存することをお勧めします。ご安心ください、Tuistはこれらの変数を細心の注意を払って扱い、ログに表示されることがないようにしています。

> [必要な変数は起動時に確認されます。欠落している変数がある場合、起動は失敗し、エラーメッセージに欠落している変数の詳細が表示されます。

### ライセンス設定 {#license-configuration}

オンプレミスのユーザーとして、環境変数として公開する必要があるライセンスキーを受け取ります。このキーは、ライセンスを検証し、サービスが契約条件の範囲内で実行されていることを確認するために使用されます。

| 環境変数                               | 説明                                                                                                                                      | 必須  | デフォルト | 例                                         |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | --- | ----- | ----------------------------------------- |
| `TUIST_LICENSE`                    | サービスレベル契約締結後に提供されるライセンス                                                                                                                 | はい  |       | `******`                                  |
| `tuist_license_certificate_base64` | ****`TUIST_LICENSE` の例外的な代替手段。Base64 エンコードされた公開証明書で、サーバーが外部サービスと通信できないエアギャップ環境でオフラインのライセンス検証を行います。 TUIST_LICENSE が使用できない場合のみ使用してください。`` | はい  |       | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\*`TUIST_LICENSE` または`TUIST_LICENSE_CERTIFICATE_BASE64`
のどちらかを提供する必要がありますが、両方を提供する必要はありません。標準的なデプロイメントには`TUIST_LICENSE` を使用してください。

> [重要】有効期限
> ライセンスには有効期限があります。ライセンスの有効期限が30日未満である場合、サーバーと相互作用するTuistコマンドの使用中に警告が表示されます。ライセンスの更新をご希望の場合は、[contact@tuist.dev](mailto:contact@tuist.dev)までご連絡ください。

### ベース環境設定{#base-environment-configuration}。

| 環境変数                                  | 説明                                                                                             | 必須  | デフォルト                              | 例                                                                    |                                                                                                                                    |
| ------------------------------------- | ---------------------------------------------------------------------------------------------- | --- | ---------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | インターネットからインスタンスにアクセスするためのベースURL                                                                | はい  |                                    | https://tuist.dev                                                    |                                                                                                                                    |
| `tuist_secret_key_base`               | 情報の暗号化に使用するキー（クッキーのセッションなど）                                                                    | はい  |                                    |                                                                      | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `tuist_secret_key_password`           | ハッシュ化されたパスワードを生成するペッパー                                                                         | いいえ | `tuist_secret_key_base。`           |                                                                      |                                                                                                                                    |
| `tuist_secret_key_tokens`             | ランダム・トークンを生成するためのシークレット・キー                                                                     | いいえ | `tuist_secret_key_base。`           |                                                                      |                                                                                                                                    |
| `tuist_secret_key_encryption`         | 機密データのAES-GCM暗号化のための32バイトのキー                                                                   | いいえ | `tuist_secret_key_base。`           |                                                                      |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | `1` 、IPv6アドレスを使用するようにアプリを設定する。                                                                 | いいえ | `0`                                | `1`                                                                  |                                                                                                                                    |
| `tuist_log_level`                     | アプリに使用するログレベル                                                                                  | いいえ | `インフォメーション`                        | [ログレベル](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels)。 |                                                                                                                                    |
| `tuist_github_app_private_key_base64` | GitHubアプリで、PRコメントの自動投稿などの追加機能のロックを解除するために使用する、base64エンコードされた秘密鍵。                               | いいえ | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                      |                                                                                                                                    |
| `tuist_github_app_private_key`        | GitHub アプリで、PR コメントの自動投稿などの追加機能のロックを解除するために使用する秘密鍵。**特殊文字の問題を避けるため、base64 エンコード版を使うことを推奨します。** | いいえ | `-----RSAを開始する。`                   |                                                                      |                                                                                                                                    |
| `tuist_ops_user_handles`              | 操作URLにアクセスできるユーザーハンドルのカンマ区切りリスト。                                                               | いいえ |                                    | `ユーザー1,ユーザー2`                                                        |                                                                                                                                    |
| `TUIST_WEB`                           | ウェブ・サーバー・エンドポイントを有効にする                                                                         | いいえ | `1`                                | `1` または`0`                                                           |                                                                                                                                    |

### データベース設定 {#database-configuration}

以下の環境変数は、データベース接続の設定に使用されます：

| 環境変数                                | 説明                                                                                                                                                 | 必須  | デフォルト     | 例                                                                      |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | --- | --------- | ---------------------------------------------------------------------- |
| `DATABASE_URL`                      | PostgresデータベースにアクセスするためのURL。URLには認証情報を含める必要があることに注意してください。                                                                                         | はい  |           | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `tuist_clickhouse_url`              | ClickHouseデータベースにアクセスするためのURLです。URLには認証情報を含める必要があります。                                                                                              | いいえ |           | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `tuist_use_ssl_for_database。`       | trueの場合、データベースへの接続に[SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security)を使用する。                                                             | いいえ | `1`       | `1`                                                                    |
| `tuist_database_pool_size`          | コネクションプールで開いておくコネクション数                                                                                                                             | いいえ | `10`      | `10`                                                                   |
| `tuist_database_queue_target`       | プールからチェックアウトされたすべての接続がキュー間隔以上かかったかどうかをチェックする間隔 (ミリ秒単位) [(詳細)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)。       | いいえ | `300`     | `300`                                                                  |
| `tuist_database_queue_interval`     | プールが新しいコネクションのドロップを開始すべきかどうかを決定するために使用する、キュー内のしきい値時間 (ミリ秒単位) [(詳細)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)。 | いいえ | `1000`    | `1000`                                                                 |
| `tuist_クリックハウス_フラッシュ_インターバル_ms`     | ClickHouseバッファフラッシュ間のミリ秒単位の時間間隔                                                                                                                    | いいえ | `5000`    | `5000`                                                                 |
| `tuist_clickhouse_max_buffer_size`  | フラッシュを強制する前のClickHouseバッファの最大サイズ（バイト単位                                                                                                             | いいえ | `1000000` | `1000000`                                                              |
| `tuist_clickhouse_buffer_pool_size` | ClickHouseバッファプロセスの実行数                                                                                                                             | いいえ | `5`       | `5`                                                                    |

### 認証環境設定{#authentication-environment-configuration}。

IDプロバイダ(IdP)](https://en.wikipedia.org/wiki/Identity_provider)を介した認証を容易にします。これを利用するには、選択したプロバイダに必要なすべての環境変数がサーバの環境に存在することを確認してください。****
変数が欠落していると、Tuist はそのプロバイダをバイパスすることになります。

#### ギットハブ {#github}

GitHub
App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)を使った認証を推奨しますが、[OAuth
App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)を使うこともできます。サーバー環境には、GitHubが指定する必須環境変数をすべて含めるようにしてください。変数がないと、TuistはGitHub認証を見落としてしまいます。GitHubアプリを適切に設定するには：
- GitHubアプリの一般設定：
    - `クライアント ID` をコピーし、`TUIST_GITHUB_APP_CLIENT_ID として設定します。`
    - 新しい`クライアントシークレット` を作成・コピーし、`TUIST_GITHUB_APP_CLIENT_SECRET として設定します。`
    - `コールバックURL` を`http://YOUR_APP_URL/users/auth/github/callback`
      のように設定します。`YOUR_APP_URL` には、サーバーのIPアドレスを指定することもできます。
- 以下のパーミッションが必要です：
  - リポジトリ：
    - プルリクエスト読み書き
  - アカウント
    - メールアドレス読み取り専用

`Permissions and events`'s`Account permissions` section, set`Email addresses`
permission to`Read-only`.

次に、Tuistサーバーが動作する環境で以下の環境変数を公開する必要がある：

| 環境変数                             | 説明                      | 必須  | デフォルト | 例                                          |
| -------------------------------- | ----------------------- | --- | ----- | ------------------------------------------ |
| `tuist_github_app_client_id`     | GitHubアプリケーションのクライアントID | はい  |       | `Iv1.a629723000043722`                     |
| `tuist_github_app_client_secret` | アプリケーションのクライアントシークレット   | はい  |       | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### グーグル

OAuth
2](https://developers.google.com/identity/protocols/oauth2)を使用してGoogleとの認証を設定できます。そのためには、OAuthクライアントIDタイプの新しいクレデンシャルを作成する必要がある。クレデンシャルを作成する際、アプリケーションタイプとして
"Web Application "を選択し、名前を`Tuist`
とし、リダイレクトURIを`{base_url}/users/auth/google/callback` に設定する。`base_url`
は、ホストしているサービスが稼働しているURLである。アプリを作成したら、クライアントIDとシークレットをコピーし、それぞれ環境変数`GOOGLE_CLIENT_ID`
と`GOOGLE_CLIENT_SECRET` に設定する。

> [注意]同意画面スコープ 同意画面を作成する必要があるかもしれない。その際、`userinfo.email` と`openid`
> スコープを追加し、アプリを内部としてマークすることを確認してください。

#### Okta {#okta}

OAuth2.0](https://oauth.net/2/)プロトコルにより、Oktaで認証を有効にすることができます。3}以下の手順に従って、Okta上で[アプリを作成](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)する必要があります</LocalizedLink>。

Oktaアプリケーションのセットアップ時にクライアントIDとシークレットを取得したら、以下の環境変数を設定する必要があります：

| 環境変数                         | 説明                                        | 必須  | デフォルト | 例   |
| ---------------------------- | ----------------------------------------- | --- | ----- | --- |
| `tuist_okta_1_client_id`     | Oktaと認証するためのクライアントID。この番号は組織IDでなければなりません。 | はい  |       |     |
| `tuist_okta_1_client_secret` | Oktaと認証するためのクライアントシークレット                  | はい  |       |     |

`1` の数字を組織IDに置き換える必要がある。これは通常1ですが、データベースで確認してください。

### ストレージ環境設定 {#storage-environment-configuration}。

Tuistは、APIを通じてアップロードされた成果物を格納するストレージを必要とする。**Tuistが効果的に動作するためには、サポートされているストレージソリューション**
のいずれかを設定することが不可欠である。

#### S3 準拠のストレージ {#s3compliant-storages}.

アーティファクトの保存には、任意の S3
準拠のストレージ・プロバイダを使用できます。ストレージプロバイダとの統合を認証および構成するには、以下の環境変数が必要です：

| 環境変数                                                 | 説明                                                            | 必須  | デフォルト           | 例                                          |
| ---------------------------------------------------- | ------------------------------------------------------------- | --- | --------------- | ------------------------------------------ |
| `TUIST_ACCESS_KEY_ID` または`AWS_ACCESS_KEY_ID`         | ストレージ・プロバイダに対して認証するためのアクセス・キーID。                              | はい  |                 | `アキアイオスフォード`                               |
| `TUIST_SECRET_ACCESS_KEY` または`AWS_SECRET_ACCESS_KEY` | ストレージ・プロバイダに対して認証するための秘密のアクセス・キー。                             | はい  |                 | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` または`AWS_REGION`                    | バケツがある地域                                                      | いいえ | `オート`           | `米西2`                                      |
| `TUIST_S3_ENDPOINT` または`AWS_ENDPOINT`                | ストレージ・プロバイダのエンドポイント                                           | はい  |                 | `https://s3.us-west-2.amazonaws.com`       |
| `tuist_s3_バケット名`                                     | 成果物が保存されるバケツの名前                                               | はい  |                 | `ツイスト・アーティファクト`                            |
| `tuist_s3_connect_timeout`                           | ストレージ・プロバイダへの接続を確立するためのタイムアウト（ミリ秒）。                           | いいえ | `3000`          | `3000`                                     |
| `tuist_s3_receive_timeout`                           | ストレージ・プロバイダからデータを受信するタイムアウト（ミリ秒単位                             | いいえ | `5000`          | `5000`                                     |
| `tuist_s3_pool_timeout`                              | ストレージ・プロバイダへの接続プールのタイムアウト（ミリ秒）。タイムアウトなしの場合は`infinity` を使用します。 | いいえ | `5000`          | `5000`                                     |
| `tuist_s3_pool_max_idle_time`                        | プール内の接続の最大アイドル時間 (ミリ秒単位)。接続を無期限に維持するには`infinity` を使用する。       | いいえ | `インフィニティ`       | `60000`                                    |
| `tuist_s3_pool_size`                                 | プールあたりの最大接続数                                                  | いいえ | `500`           | `500`                                      |
| `tuist_s3_pool_count`                                | 使用するコネクションプールの数                                               | いいえ | システム・スケジューラの数   | `4`                                        |
| `tuist_s3_protocol`                                  | ストレージ・プロバイダに接続する際に使用するプロトコル (`http1` または`http2`)              | いいえ | `エイチティーティーピーワン` | `エイチティーティーピーワン`                            |
| `tuist_s3_virtual_host`                              | バケツ名をサブドメイン(バーチャルホスト)として URL を構築するかどうか。                       | いいえ | `擬似`            | `1`                                        |

> [!注意] 環境変数からのWeb Identity TokenによるAWS認証 ストレージプロバイダがAWSで、Web Identity
> Tokenを使用して認証したい場合、環境変数`TUIST_S3_AUTHENTICATION_METHOD`
> を`aws_web_identity_token_from_env_vars`
> に設定すると、Tuistは従来のAWS環境変数を使用してその方法を使用します。

#### Google Cloud Storage {#google-cloud-storage}。
Google Cloud
Storageの場合は、[これらのドキュメント](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)に従って、`AWS_ACCESS_KEY_ID`
と`AWS_SECRET_ACCESS_KEY` のペアを取得する。`AWS_ENDPOINT`
は`https://storage.googleapis.com` に設定する。その他の環境変数は、他のS3準拠のストレージと同じである。

### Gitプラットフォームの設定 {#git-platform-configuration}

Tuistは<LocalizedLink href="/guides/server/authentication">Gitプラットフォーム</LocalizedLink>と統合して、プルリクエストにコメントを自動的に投稿するなどの追加機能を提供することができる。

#### ギットハブ {#platform-github}

GitHub
アプリを作成する](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)
必要があります。OAuth GitHub アプリを作成したのでなければ、認証用に作成したものを再利用できます。`Permissions and
events`'の`Repository permissions` セクションで、さらに`Pull requests` permission を`Read
and write` に設定する必要があります。

`TUIST_GITHUB_APP_CLIENT_ID` と`TUIST_GITHUB_APP_CLIENT_SECRET` の上に、以下の環境変数が必要です：

| 環境変数                           | 説明                 | 必須  | デフォルト | 例                         |
| ------------------------------ | ------------------ | --- | ----- | ------------------------- |
| `tuist_github_app_private_key` | GitHubアプリケーションの秘密鍵 | はい  |       | `-----RSA秘密鍵の開始------...` |

## デプロイメント{#deployment}。

公式のTuist Dockerイメージは以下で入手できる：
```
ghcr.io/tuist/tuist
```

### Dockerイメージのプル{#pulling-the-docker-image}。

以下のコマンドを実行すれば、画像を取り出すことができる：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

あるいは特定のバージョンを引き出す：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Dockerイメージをデプロイする {#deploying-the-docker-image}

Dockerイメージのデプロイプロセスは、選択したクラウドプロバイダと組織の継続的なデプロイアプローチによって異なります。Kubernetes](https://kubernetes.io/)のようなほとんどのクラウドソリューションやツールは、基本的な単位としてDockerイメージを利用しているため、このセクションの例は既存のセットアップとうまく一致するはずです。

> [重要]デプロイメントパイプラインでサーバーが稼働していることを検証する必要がある場合、`GET` HTTPリクエストを`/ready`
> に送り、レスポンスで`200` ステータスコードをアサートすることができる。

#### 飛ぶ {#fly}

アプリを [Fly](https://fly.io/) にデプロイするには、`fly.toml`
設定ファイルが必要です。継続的デプロイメント（CD）パイプライン内で動的に生成することを検討してください。以下に参考例を示します：

```toml
app = "tuist"
primary_region = "fra"
kill_signal = "SIGINT"
kill_timeout = "5s"

[experimental]
  auto_rollback = true

[env]
  # Your environment configuration goes here
  # Or exposed through Fly secrets

[processes]
  app = "/usr/local/bin/hivemind /app/Procfile"

[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = false
  auto_start_machines = false
  processes = ["app"]
  http_options = { h2_backend = true }

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]
  [services.concurrency]
    type = "connections"
    hard_limit = 100
    soft_limit = 80

  [[services.http_checks]]
    interval = 10000
    grace_period = "10s"
    method = "get"
    path = "/ready"
    protocol = "http"
    timeout = 2000
    tls_skip_verify = false
    [services.http_checks.headers]

[[statics]]
  guest_path = "/app/public"
  url_prefix = "/"
```

その後、`fly launch --local-only --no-deploy` を実行してアプリを起動できます。以降のデプロイでは、`fly launch
--local-only` を実行する代わりに、`fly deploy --local-only`
を実行する必要があります。Fly.ioではプライベートなDockerイメージをプルできないため、`--local-only` フラグを使用する必要があります。

### Docker Compose {#docker-compose}.

以下は、`docker-compose.yml` ファイルの例で、サービスをデプロイする際のリファレンスとして使用できます：

```yaml
version: '3.8'
services:
  db:
    image: timescale/timescaledb-ha:pg16
    restart: always
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - PGDATA=/var/lib/postgresql/data/pgdata
    ports:
      - '5432:5432'
    volumes:
      - db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  pgweb:
    container_name: pgweb
    restart: always
    image: sosedoff/pgweb
    ports:
      - "8081:8081"
    links:
      - db:db
    environment:
      PGWEB_DATABASE_URL: postgres://postgres:postgres@db:5432/postgres?sslmode=disable
    depends_on:
      - db

  tuist:
    image: ghcr.io/tuist/tuist:latest
    container_name: tuist
    depends_on:
      - db
    ports:
      - "80:80"
      - "8080:8080"
      - "443:443"
    expose:
      - "80"
      - "8080"
      - "443:443"
    environment:
      # Base Tuist Env - https://docs.tuist.io/en/guides/dashboard/on-premise/install#base-environment-configuration
      TUIST_USE_SSL_FOR_DATABASE: "0"
      TUIST_LICENSE:  # ...
      DATABASE_URL: postgres://postgres:postgres@db:5432/postgres?sslmode=disable
      TUIST_APP_URL: https://localhost:8080
      TUIST_SECRET_KEY_BASE: # ...
      WEB_CONCURRENCY: 80

      # Auth - one method
      # GitHub Auth - https://docs.tuist.io/en/guides/dashboard/on-premise/install#github
      TUIST_GITHUB_OAUTH_ID:
      TUIST_GITHUB_APP_CLIENT_SECRET:

      # Okta Auth - https://docs.tuist.io/en/guides/dashboard/on-premise/install#okta
      TUIST_OKTA_SITE:
      TUIST_OKTA_CLIENT_ID:
      TUIST_OKTA_CLIENT_SECRET:
      TUIST_OKTA_AUTHORIZE_URL: # Optional
      TUIST_OKTA_TOKEN_URL: # Optional
      TUIST_OKTA_USER_INFO_URL: # Optional
      TUIST_OKTA_EVENT_HOOK_SECRET: # Optional

      # Storage
      AWS_ACCESS_KEY_ID: # ...
      AWS_SECRET_ACCESS_KEY: # ...
      AWS_S3_REGION: # ...
      AWS_ENDPOINT: # https://amazonaws.com
      TUIST_S3_BUCKET_NAME: # ...

      # Other

volumes:
  db:
    driver: local
```

## プロメテウスのメトリクス{#prometheus-metrics}。

Tuistは`/metrics`
でPrometheusのメトリクスを公開しており、セルフホストインスタンスの監視に役立ちます。これらのメトリクスには以下が含まれます：

### FinchのHTTPクライアントメトリクス{#finch-metrics}。

TuistはHTTPクライアントとして[Finch](https://github.com/sneako/finch)を使用し、HTTPリクエストに関する詳細なメトリクスを公開している：

#### リクエスト・メトリクス
- `tuist_prom_ex_finch_request_count_total` - フィンチのリクエスト総数（カウンター）。
  - ラベル：`フィンチ名`,`方法`,`スキーム`,`ホスト`,`ポート`,`ステータス`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP リクエストの持続時間 (ヒストグラム)
  - ラベル：`フィンチ名`,`方法`,`スキーム`,`ホスト`,`ポート`,`ステータス`
  - バケット10ms、50ms、100ms、250ms、500ms、1s、2.5s、5s、10s
- `tuist_prom_ex_finch_request_exception_count_total` - フィンチのリクエスト例外の総数 (カウンター)
  - ラベル：`フィンチ名`,`方法`,`スキーム`,`ホスト`,`ポート`,`種類`,`理由`

#### 接続プールのキュー・メトリクス
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 接続プールのキューで待機していた時間
  (ヒストグラム)
  - ラベル：`フィンチ名` 、`スキーム` 、`ホスト` 、`ポート` 、`プール`
  - バケット1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms、1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` -
  接続が使用される前にアイドル状態であった時間（ヒストグラム）。
  - ラベル：`フィンチ名` 、`スキーム` 、`ホスト` 、`ポート` 、`プール`
  - バケット10ms、50ms、100ms、250ms、500ms、1s、5s、10s
- `tuist_prom_ex_finch_queue_exception_count_total` - フィンチ・キュー例外の総数 (カウンター)
  - ラベル：`フィンチ名`,`スキーム`,`ホスト`,`ポート`,`種類`,`理由`

#### コネクション・メトリクス
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 接続確立に要した時間（ヒストグラム）。
  - ラベル：`フィンチ名`,`スキーム`,`ホスト`,`ポート`,`エラー`
  - バケット10ms、50ms、100ms、250ms、500ms、1s、2.5s、5s
- `tuist_prom_ex_finch_connect_count_total` - 接続試行回数の合計（カウンター）。
  - ラベル：`フィンチ名` 、`スキーム` 、`ホスト` 、`ポート`

#### メトリクスの送信
- `tuist_prom_ex_finch_send_duration_milliseconds` - リクエスト送信にかかった時間（ヒストグラム）。
  - ラベル：`フィンチ名`,`方法`,`スキーム`,`ホスト`,`ポート`,`エラー`
  - バケット1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms、1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` -
  接続が送信前にアイドル状態であった時間（ヒストグラム）。
  - ラベル：`フィンチ名`,`方法`,`スキーム`,`ホスト`,`ポート`,`エラー`
  - バケット1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms

すべてのヒストグラム・メトリクスは、`_bucket` 、`_sum` 、`_count` のバリアントを提供し、詳細な分析を行う。

### その他の指標

フィンチのメトリクスに加え、トゥイストは以下のメトリクスを公開している：
- BEAM仮想マシンのパフォーマンス
- カスタム・ビジネス・ロジックのメトリクス（ストレージ、アカウント、プロジェクトなど）
- データベース・パフォーマンス（Tuistホスト・インフラストラクチャ使用時）

## オペレーション {#operations}

Tuistは、`/ops/` の下に、インスタンスを管理するために使用できる一連のユーティリティを提供しています。

> [!IMPORTANT] 権限`TUIST_OPS_USER_HANDLES` 環境変数にリストされているハンドルを持つ人だけが、`/ops/`
> エンドポイントにアクセスできる。

- **エラー (`/ops/errors`)：**
  アプリケーションで発生した予期せぬエラーを見ることができます。これはデバッグや何が問題だったのかを理解するのに便利で、もしあなたが問題に直面しているのであれば、私たちとこの情報を共有するようお願いするかもしれません。
- **ダッシュボード (`/ops/dashboard`)：** アプリケーションのパフォーマンスと健全性
  (メモリ消費量、実行中のプロセス、リクエスト数など)
  に関する洞察を提供するダッシュボードを見ることができます。このダッシュボードは、使用しているハードウェアが負荷を処理するのに十分かどうかを理解するのに非常に役立ちます。
