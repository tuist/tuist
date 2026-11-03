---
{
  "title": "サーバー",
  "titleTemplate": ":title | セルフホスティング | サーバー | ガイド | Tuist",
  "description": "Tuistサーバーをインフラストラクチャにデプロイする方法を学びます。"
}
---
# サーバー {#server}

インフラストラクチャの管理により高い制御を必要とする組織向けに、Tuist サーバーのセルフホスティング版を提供しています。このバージョンでは、Tuist を独自のインフラストラクチャ上でホストでき、データの安全性とプライバシーを確保できます。

> [!WARNING]
> **ライセンスが必要**
>
> Tuist のセルフホスティングには、法的に有効な有料ライセンスが必要です。オンプレミス版の Tuist は、Enterprise プランの組織のみ利用可能です。このバージョンに関心がある場合は、[contact@tuist.dev](mailto:contact@tuist.dev) までお問い合わせください。

> [!WARNING]
> **レガシーキャッシュサービス**
>
> 従来のセルフホスティング型キャッシュノード技術は、新規インストールでは非推奨となりました。最新のセルフホスティングキャッシュインフラストラクチャについては、<.localized_link href="/guides/features/cache/self-hosting">セルフホスティングキャッシュガイド</.localized_link> を参照してください。
>
> 既存のデプロイメントでは、GitHub の Markdown ビューアーでレガシーソースドキュメントを引き続き参照できます。[キャッシュノード](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/self-host.md) および [キャッシュアーキテクチャ](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/architecture.md)

## リリースサイクル {#release-cadence}

Tuist サーバーと Kura キャッシュサーバーは、3 つの GHCR イメージチャネルを通じて提供されます。**canary**（`main` へのすべてのコミット）、**release candidate**（毎週月曜日に作成され、1 週間浸透）、および **stable**（翌週の月曜日に昇格）。安定版リリースのみが `:latest` に移動し、デフォルトで解決されます。カナリア版とリリース候補版は GitHub のプレリリースであり、タグを固定することでオプトインします。サーバーと Kura は同じ週次リリースサイクルに従い、[Tuist CLI のリリーススケジュール](/en/cli/release-channels) と連動しています。

予測可能なバージョニングと互換性を確保するため、[セマンティックバージョニング](https://semver.org/) に従っています。メジャーバージョンは、セルフホスティングユーザーとの調整が必要な Tuist サーバーの破壊的変更を示すために使用されます。通常はこのコンポーネントを使用しないことを想定していますが、万一必要な場合は、移行をスムーズに行えるよう支援いたします。

各チャネルの作成方法、デプロイメントでの固定方法、そして本番環境を安定した低速移動ラインに保ちながらステージング環境で次のリリースを浸透させるための推奨戦略については、<.localized_link href="/guides/server/self-host/release-channels">リリースチャネル</.localized_link> ページを参照してください。

## OAuth アップグレードとロールバックの境界 {#oauth-upgrade-and-rollback-boundary}

OAuth エンティティキャッシュの削除には、既存のインストールに対する段階的なアップグレードが必要です。OAuth キャッシュの無効化を停止するバージョンをデプロイする前に、まず [#14040](https://github.com/tuist/tuist/pull/14040) からの権威ある読み取り互換性リリースを **すべての OAuth リーダーおよびライター** にデプロイしてください。この互換性ステージは **1.355** リリースラインで初めて登場します。`ghcr.io/tuist/tuist:1.355.0-rc.1` に含まれており、本番デプロイメントでは昇格後に安定した `1.355.x` リリースを使用すべきです。1.354 以前にインストールされている場合は、削除を含む後続のリリースにアップグレードする前に、このステージを完了する必要があります。1.355 ラインは互換性専用に保ち、無効化の削除をバックポートしないでください。

元の互換性コミットは `ghcr.io/tuist/tuist:sha-c8e54471a425` としても利用可能です。別のイメージが互換性ステージとして適しているのは、古いコンシューマーが残っている間、権威ある読み取りを維持し **レガシーな無効化を保持** する場合に限ります。トラフィックを提供する前に、リフレッシュトークンのルックアップインデックスを含む、そのステージの通常のデータベースマイグレーションを実行してください。

各環境内のすべての Web レプリカ、バックグラウンドワーカー、スケジュールされたジョブ、および個別に固定されたプロセッサーイメージを確認してください。互換性のロールアウトが完了するのを待ち、無効化を削除する前にキャッシュ読み取りバイナリが残っていないことを確認してください。自動アップグレード中に浮動イメージタグがこのステージをスキップしないようにしてください。古いコンシューマーのない新規インストールには、中間デプロイメントは不要です。

> [!WARNING]
> **権威ある読み取りのロールバックターゲットを保持**
>
> 無効化が削除された後、通常のローリングロールバックは #14040 または他の権威ある読み取りバージョンをターゲットにする必要があります。すべての非無効化プロセスが停止した後でも、保持された OAuth キャッシュエントリは古くなっている可能性があり、再起動したキャッシュ読み取りレプリカはそれらをピアからインポートする可能性があります。
>
> さらにロールバックするには、**すべて** の非無効化 OAuth コンシューマーを停止してドレインし、キャッシュ読み取りコンシューマーを開始する前に **すべての** 保持された Boruta キャッシュ参加者をクリアまたは置き換える必要があります。保持された参加者が再参加しないようにしてください。イングレスのみをドレインするか、Web レプリカのみを再起動するのは不十分です。キャッシュをクリアしたり、データベースマイグレーションを自動的にロールバックしたりするのではなく、この復旧作業は Tuist サポート担当者との連携で行ってください。

## マルチレプリクラスターリング {#multi-replica-clustering}

サポートされているマルチレプリカ Web デプロイメントでは、認証の権限としてではなく、クロスレプリカの Phoenix PubSub および Oban PG 通知のために Erlang クラスタリングが必要です。`server.cluster.enabled` が false の場合、チャートは 1 つを超えるレプリカに成長できるオートスケーラーを含め、複数のレプリカを拒否します。以前に承認された非クラスター化デプロイメントは、ガードを回避するのではなく、このアップグレードを計画する必要があります。メンバーシップを変更する前に、<.localized_link href="/guides/server/self-host/server#oauth-upgrade-and-rollback-boundary">OAuth アップグレード手順</.localized_link>（無効化の削除を含む）を完了してください。

シークレットマネージャーを使用してリリースネームスペース内にプライベート Cookie シークレットを作成し、その名前とキーを設定します。

```yaml
server:
  replicaCount: 2
  cluster:
    enabled: true
    distributionPort: 9100
    cookieExistingSecret: tuist-server-cluster
    cookieExistingSecretKey: release-cookie
```

Cookie は高エントロピーである必要があり、参加するすべての Web レプリカで共有されなければなりません。公開イメージに埋め込まれた Cookie を使用しないでください。配布 Cookie を所持すると、そのノードでのリモート実行が可能になります。分散リリースの起動 now refuses a missing private `RELEASE_COOKIE` or an invalid port, including explicitly configured `RELEASE_DISTRIBUTION=name` or `sname` without DNS discovery. Non-chart deployments must also configure `TUIST_CLUSTER_DNS_SERVICE`, `TUIST_CLUSTER_APP_NAME` and the pod IP/node name consistently. Discovery currently uses IPv4 A records.

通常のサーバー接続 `helm upgrade` では、`cookieExistingSecret` を空のままにすると Cookie シークレットが作成され、後のアップグレードでその現在の値が再利用されます。オフライン `helm template`、Argo CD、およびライブシークレットルックアップのない他の GitOps レンダラーは、生成された値を保持できません。別途管理された安定したシークレットでバックアップされた `cookieExistingSecret` を使用する必要があります。Cookie キーを変更してライブクラスターを暗黙的に回転させないでください。Cookie の回転には、すべての参加者の調整されたマイグレーション/再起動が必要です。シークレットを更新するだけでは、既存のプロセスは更新されません。

イメージに焼き込まれた Cookie からの最初のロールアウトでは、すべての Web レプリカがプライベートシークレットを使用するまで、新旧のメンバーシップアイランドが分離されます。リアルタイム更新のための移行ウィンドウを計画してください。後続のローリングデプロイメントでは混合バージョンのクラスターが形成されるため、実際の新旧バージョン間で PubSub、Oban 通知、およびピア置換を検証してください。これらの通知は永続的な配信保証ではありません。互換性のあるバージョンにロールバックする際は、信頼できる読み取り元のロールバックイメージを保持し、同じプライベート Cookie を維持してください。

EPMD（TCP 4369）と設定された配布ポートへのアクセスは、信頼できるサーバーピア間でのみ許可し、テナントワークロードやパブリックネットワークからは決して許可しないでください。環境における実際のイングレス/エグレスの分離を検証してください。NetworkPolicy をレンダリングしても、強制適用やバックエンドへの到達可能性が証明されるわけではありません。連続負荷下での 2 レプリカのカナリアデプロイメントは、昇格前に参加、ローリング置換、および障害/回復を通過する必要があります。DNS はピアの検出に使用され、一時的な失敗や部分的な応答によって正常なノードを切断するためには使用されません。実際のノード損失と OTP パーティション防止は依然として適用されます。libcluster は、接続を閉じなくても保持コールバックに対して成功した「切断」操作をログに記録することがあります。そのログ行だけでなく、ノードのアップ/ダウンイベントまたは `Node.list()` から実際のメンバーシップを確立してください。

## 継続的デプロイメント {#continuous-deployment}

本番環境を安定したマイナーライン（例：`ghcr.io/tuist/tuist:1.351`）に固定し、日々のアップグレードではバックポートされた修正のみを提供することを推奨します。安定ラインは、リリース候補チャネルでの 1 週間のソーク期間後、毎週月曜日の 06:00 UTC に昇格されます。カナリーまたは現在のリリース候補タグを使用したステージング環境により、ユーザーに影響が出る前に回帰を検出できます。推奨されるピン留め戦略については、<.localized_link href="/guides/server/self-host/release-channels">リリースチャネル</.localized_link>を参照してください。

マニフェストに触れることなく、新機能が安定するたびに吸収したい場合は、`:latest` に固定してください。このタグは毎週月曜日の朝に移動するため、それに合わせてデプロイウィンドウをスケジュールしてください。以下は、その頻度で最新の安定イメージをチェックしてデプロイする GitHub Actions ワークフローの例です。

```yaml
name: Update Tuist Server
on:
  schedule:
    - cron: '0 8 * * 1' # Mondays 08:00 UTC, after the weekly stable promote
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

<span id="network-trusted-report-publishing"></span>
<span id="network-trusted-cache-access"></span>

## ネットワーク信頼アクセス {#network-trusted-access}

セルフホストインストールでは、信頼できるネットワーク上の開発者がサインインせずにインサイトを送信したり、キャッシュを使用したり、あるいはその両方を行うことを許可できます。ダッシュボードと管理機能には引き続き認証が必要です。

必要な機能のみを有効にしてください。

| サーバー環境変数 | サインインなしで許可 |
| --- | --- |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` | ビルドおよびテストインサイトの送信 |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS=true` | キャッシュされたビルド出力の読み取りと書き込み |

両方の設定はデフォルトで**オフ**であり、独立しており、プライベートプロジェクトを含むすべてのアカウントとプロジェクトにインスタンス全体で適用されます。これらはホスト型 Tuist では利用できず、セルフホスティングライセンスの代わりにはなりません。

以前の `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING` 名は、`TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` が設定されていない場合の互換性フォールバックとして残ります。

> [!WARNING]
> これらの設定は、強制された社内ネットワークまたは VPN の境界内でのみ有効にしてください。有効なエンドポイントに到達できる anyone は、レポートを送信したり、キャッシュアクセスが有効になっている場合はキャッシュされた出力を読み取って上書きしたりできます。これにより、偽造されたテレメトリ、キャッシュポイズニング、および容量枯渇が可能になります。レポートの応答は、プライベートプロジェクトのハンドルやビルドシステムを公開する可能性があります。Tuist は VPN メンバーシップを検証せず、転送された IP ヘッダーをメンバーシップの証拠として信頼しません。

### インスタンスの設定 {#network-trusted-instance-configuration}

1. ファイアウォールまたはプライベートイングレスを使用して、Tuist サーバー、すべての Kura HTTP/gRPC リスナー、および Bazel BES イングレスを信頼できるネットワークに制限してください。
2. クライアントをアップグレードする前に、すべてのサーバーおよび Kura レプリカをアップグレードしてください。`KURA_AUTH_TUIST_URL` とそのコントロールプレーンの資格情報を使用して Kura 認証を有効にしたままにしてください。これを無効にすると、これらの制限がバイパスされます。キャッシュエンドポイントは <.localized_link href="/guides/features/cache/self-hosting">セルフホストキャッシュガイド</.localized_link> を使用して設定してください。
3. 上記の希望する変数を関連するすべての Tuist サーバーレプリカに設定し、それらを再起動または再デプロイしてください。正確な値 `true` だけが設定を有効にします。ダッシュボードのトグルや個別の Kura フラグはありません。

### クライアントの設定 {#network-trusted-client-configuration}

互換性のある各クライアントで、最終的なセルフホストサーバー URL とプロジェクトを設定してください。クライアントは、資格情報がない場合にどの機能が有効になっているかを自動的に検出します。クライアント側のオプトインは不要です。検出はリダイレクトに従いません。既存の資格情報は引き続き使用され、無効または更新に失敗した資格情報は匿名フォールバックではなくエラーを引き起こします。回復するには、再度サインインするか、明示的にサインアウトしてください。

インサイトアクセスを有効にする前に、資格情報を共有するすべてのツールを、破損または拒否された資格情報を保持し、読み取り不可能な資格情報ディレクトリを拒否し、署名されていないレポートから Git 起源を省略するバージョンにアップグレードしてください。古いツールは資格情報を削除し、意図せず匿名フォールバックを許可する可能性があります。サーバーのみのアップグレードではこれを修正できません。サーバーに検出サポートがない場合、または古いバージョンにロールバックされた場合、クライアントは認証する必要があります。以前の `TUIST_NETWORK_TRUSTED_PUBLISHING` クライアント設定はもう適用されません。

- **インサイト:** アーカイブ、添付ファイル、カバレッジ、シャードプランニング、または既存のレポートアクセスなしで、完了した Xcode、Gradle、Elixir/Mix、および Bazel レポートのみを送信してください。アクターの主張は検証されていません。署名されていないテレメトリは、信頼できるテスト証拠や自動化を促進しません。クライアントの設定とプライバシーの詳細については、<.localized_link href="/guides/features/build-insights/xcode#network-trusted-publishing">Xcode</.localized_link>、<.localized_link href="/guides/features/build-insights/gradle#network-trusted-publishing">Gradle</.localized_link>、および <.localized_link href="/guides/features/build-insights/elixir#network-trusted-publishing">Elixir</.localized_link> ガイドを参照してください。
- **キャッシュ:** CLI コンパイル/モジュールキャッシング、Bazel キャッシング、および Gradle タスクキャッシングをサポートしています。キャッシュのパージとリモートアセットのダウンロードには引き続き資格情報が必要です。サポートのないクライアントは認証を続ける必要があります。
- **Bazel:** レポートには明示的な `TUIST_BAZEL_BES_BACKEND` と互換性のある Kura が必要です。キャッシュとレポートのオプションは独立して有効になります。資格情報またはいずれかの設定を変更した後、`tuist bazel setup` を再実行してください。コンパイルキャッシュの設定変更には `tuist cache config` を再実行してください。

レポートリクエストはプロジェクトあたり 8 MB、毎分 60 リクエスト、毎日 10,000 リクエストに制限されています。複数のレプリカを持つデプロイメント全体のクォータには共有 Valkey を構成してください。そうでない場合、制限はプロセス単位となります。構成された共有クォータバックエンドが利用できない場合、署名されていないレポートは拒否されます。イングレス接続、ボディ、およびレート制限も追加してください。

### ネットワーク信頼アクセスの無効化 {#disable-network-trusted-publishing}

関連する変数を `false` に設定し、**該当するすべてのサーバーレプリカ** を再起動してください。古いレプリカは、置き換えられるまで資格情報不要のリクエストを受け入れ続けることができます。最後のレプリカの切り替え後60秒以内に新しいリクエストに対するキャッシュアクセスが停止しますが、進行中の転送はキャンセルされません。即時の取り消しが必要な場合は、まずイングレスでトラフィックをブロックしてください。既存のレポートは通常の可視性と保持期間を維持し、認証済みクライアントは引き続き動作します。

## ランタイム要件 {#runtime-requirements}

このセクションでは、インフラストラクチャ上で Tuist サーバーをホストするための要件について説明します。

### 互換性マトリクス {#compatibility-matrix}

Tuist サーバーはテスト済みであり、以下の最小バージョンと互換性があります。

| コンポーネント | 最小バージョン | 注記 |
| --- | --- | --- |
| PostgreSQL | 15 | |
| ClickHouse | {{minimum_supported_clickhouse_version}} | アナリティクスに必要 |

### Docker 仮想化イメージの実行 {#running-dockervirtualized-images}

サーバーは [Docker](https://www.docker.com/) イメージとして [GitHub の Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) を介して配布されています。

実行するには、インフラストラクチャが Docker イメージの実行をサポートしている必要があります。ほとんどのインフラプロバイダーはこれをサポートしています。これは、本番環境でソフトウェアを配布および実行するための標準的なコンテナとなっているためです。

### Postgres データベース {#postgres-database}

Docker イメージの実行に加えて、リレーショナルデータを保存するために [Postgres データベース](https://www.postgresql.org/) が必要です。ほとんどのインフラプロバイダーは、オファリングに Postgres データベースを含めています（例：[AWS](https://aws.amazon.com/rds/postgresql/) および [Google Cloud](https://cloud.google.com/sql/docs/postgres)）。

> [!NOTE]
> **マイグレーション**
>
> Docker イメージのエントリポイントは、サービスを開始する前に、未適用のスキーママイグレーションを自動的に実行します。


### ClickHouse データベース {#clickhouse-database}

Tuist は大量のアナリティクスデータの保存とクエリのために [ClickHouse](https://clickhouse.com/) を使用します。ビルドインサイトなどの機能には ClickHouse が **必要** です。ClickHouse をセルフホストするか、ホスト型サービスを使用するかを選択できます。

> [!NOTE]
> **マイグレーション**
>
> Docker イメージのエントリポイントは、サービスを開始する前に、未適用の ClickHouse スキーママイグレーションを自動的に実行します。

バンドルされた Docker Compose および Helm の埋め込み ClickHouse 構成は、ClickHouse のテキストログレベルをイメージのデフォルトである `trace` から `information` に下げます。これが `system.text_log` ボリュームの大部分を占めます。また、どちらも ClickHouse 独自の `system.*` 運用ログテーブルの上限を設定できますが、これらはデフォルトでは無効になっています（詳細は以下を参照）。外部の ClickHouse デプロイメントでは、これらの運用ログを ClickHouse サービスで直接構成する必要があります。

#### ClickHouse レプリケーショントポロジ {#clickhouse-replication-topology}

Tuist 背後のマルチレプリカ ClickHouse は ClickHouse Cloud でのみサポートされています。セルフマネージド型の ClickHouse はシングルレプリカです。

インジェストマイグレーションはプレーンな `MergeTree` エンジンを出力します。Cloud では、これが透過的に `SharedMergeTree` になり、書き込みは共有オブジェクトストレージに保存され、任意のレプリカ数で動作します。セルフマネージド型の ClickHouse では、`MergeTree` は1つのレプリカのローカルディスクにのみ書き込みます。マルチレプリカ構成では、レプリカ間でインジェストがサイレントに分割されるか、接続ユーザーの `database_replicated_allow_only_replicated_engine` の設定方法に応じて、`UNKNOWN_STORAGE: Only tables with a Replicated engine or tables which do not store data on disk are allowed in a Replicated database.` で CREATE が拒否されます。

セルフマネージド型の ClickHouse では、1つのシャードを1つのレプリカで実行し、ClickHouse データディレクトリの定期的なバックアップを取得してください。ノードが失われた場合、フォールバック先の第2レプリカはありません。

#### 運用ログの保持期間の制限 {#capping-operational-log-retention}

保持期間は `system.text_log`、`system.query_log`、`system.query_thread_log`、`system.query_views_log`、`system.trace_log`、`system.metric_log`、`system.asynchronous_metric_log`、および `system.part_log` に適用できます。

有効化は、すでにデータを持つインスタンスに対して一度きりの一方向のステップであるため、どちらのバンドルもこれを行いません。保持ウィンドウを設定すると、これらのテーブル定義が構成と一致しなくなるため、ClickHouse はそれぞれをリネームして aside に退避させ、新しいテーブルを開始します。これは [旧世代ログテーブル](#superseded-log-tables) で説明されています。残された世代はこれまで蓄積されたすべてを保持し、独自の保持期間を持ちません。したがって、同じステップで回収しない限り、ディスク上に永久に残り、新しいウィンドウはそれ以降に書き込まれた行のみを制限します。両方を同時に有効にしてください。

```yaml
clickhouse:
  embedded:
    systemLogs:
      ttlDays: 14
      supersededTables: delete
```

その単一の `helm upgrade` は自己完結型です。`ttlDays` を空白から設定値に変更すると、ドロップインマウントが追加され、ClickHouse ポッドがローリングされます。ポッドは再起動し、テーブルを旧世代化し、アップグレード後のジョブがそれらを削除します。`helm upgrade --wait` でデプロイし、ジョブの実行前にポッドがローリングされるようにしてください。そうしないと、ジョブが確認した後に世代が現れ、次の `helm upgrade` でそれらが回収されます。

Docker Compose では、`docker-compose.yml` の `clickhouse` サービスにある `clickhouse-log-ttl.xml` ボリュームのコメントを外し、`.env` の両方の変数を設定してください。

```bash
CLICKHOUSE_SYSTEM_LOG_TTL_DAYS=14
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

スペースが回収されたら、`supersededTables`/`CLICKHOUSE_SUPERSEDED_LOG_TABLES` を `ignore` に戻すことができます。これにより、後の ClickHouse アップグレードが履歴を独自に破棄することを防ぎます。

#### 旧世代ログテーブル {#superseded-log-tables}

ClickHouse は起動時に、各システムログテーブルが構成と一致しているかどうかを確認します。一致しない場合、既存のテーブルを `system.<name>_0`、次に `_1`、`_2` などにリネームし、新しいテーブルを開始します。これは、保持ウィンドウを変更したとき、またはシステムログスキーマを変更する ClickHouse アップグレード時に発生します。

テーブルのリネームはデータをコピーしないため、追加のディスク容量を消費しません。旧世代化されたテーブルにその後何が起こるかは、元のテーブルに依存します。それは、旧世代化された瞬間にライブテーブルが持っていた保持期間を維持するためです。初めて保持を有効にしたとき、旧世代化されるテーブルには保持期間がないため、これまで蓄積されたすべての履歴を保持し、無期限に維持します。ウィンドウへの後続の変更は、すでに TTL を持つテーブルを旧世代化するため、それらは独自に期限切れになり、空のテーブルを残します。ClickHouse はテーブル自体を削除することはないため、長寿命のインスタンスではいずれの場合でも蓄積されます。

旧世代化されたテーブルはデフォルトで保持されるため、アップグレードが独自に運用履歴を破棄することはありません。代わりにそれらを削除するには、ポリシーを `delete` に設定してください。これは `docker compose up` および各 `helm upgrade` で発生します。

```bash
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

Helm チャートでは、同じポリシーを値として構成します。

```yaml
clickhouse:
  embedded:
    systemLogs:
      supersededTables: delete
```

旧世代化されたテーブルを削除すると、そのディスクスペースが回収されます。ライブテーブルには一切触れられず、旧世代化されてから書き込まれた行にも影響はありません。

ポリシーを変更せずに一度だけスペースを回収するには、手動でテーブルを削除します。

```sql
SELECT name FROM system.tables WHERE database = 'system' AND match(name, '_log_[0-9]+$');
DROP TABLE IF EXISTS system.text_log_0 SYNC;
```

`system` データベースは `Atomic` エンジンを使用しており、通常の `DROP TABLE` を `database_atomic_delay_before_drop_table_sec`（デフォルトでは8分）だけ延期します。`SYNC` はデータを直ちに削除するため、ディスクがいっぱいになってこれらのテーブルを削除する際に適しています。


### ストレージ {#storage}

ファイル（フレームワークやライブラリのバイナリなど）を保存するためのソリューションも必要です。Tuist サーバーは、サーバー所有のアーティファクト用に S3 互換ストレージと Azure Blob Storage をサポートしています。

> [!TIP]
> **最適化されたキャッシング**
>
> キャッシュレイテンシの削減が主な目的であれば、サーバー全体をセルフホストする必要はないかもしれません。CI または開発者ネットワークの近くにセルフホスト型 Kura ノードをデプロイし、それらをホスト型 Tuist サーバーまたはセルフホスト型サーバーに接続できます。
>
> <.localized_link href="/guides/cache/self-host">セルフホスト型キャッシュガイド</.localized_link>を参照してください。


### セルフホスト型 Kura ノード {#self-hosted-cache-nodes}

セルフホスト型 Tuist サーバーでセルフホスト型 Kura ノードを使用するには：

1. Tuist サーバーで `KURA_CONTROL_PLANE_CLIENT_ID` と `KURA_CONTROL_PLANE_CLIENT_SECRET` を構成します。クライアント ID **は UUID でなければなりません**。<.localized_link href="/guides/cache/self-host#control-plane-client">セルフホスト型キャッシュガイド</.localized_link>のコマンドを使用して UUID とランダムなシークレットを生成し、デプロイメントのシークレットに保存してください。
2. 同じコントロールプレーンの認証情報を使用して、<.localized_link href="/guides/cache/self-host">セルフホスト型キャッシュガイド</.localized_link>に従って Kura ノードをデプロイします。
3. 各 Kura ノードを `KURA_REGISTRATION_URL` と `KURA_ADVERTISED_HTTP_URL` で構成します。登録用ハートビートにより、サーバーは CLI にアドバタイズできる、準備完了でクライアント向けの Kura エンドポイントを識別します。

## 構成 {#configuration}

サービスの構成は、環境変数を通じて実行時に行われます。これらの変数は機密性が高いため、暗号化して安全なパスワード管理ソリューションに保存することをお勧めします。Tuist はこれらの変数を細心の注意を払って扱い、ログに表示されないようにしています。

> [!NOTE]
> **起動時チェック**
>
> 必要な変数は起動時に検証されます。不足している変数がある場合、起動は失敗し、エラーメッセージに欠落している変数が詳細に表示されます。


### ライセンス構成 {#license-configuration}

オンプレミスユーザーとして、環境変数として公開する必要のあるライセンスを受け取ります。このライセンスは、デプロイメントを検証し、サービスが契約条件の範囲内で実行されていることを確認するために使用されます。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | サービスレベル契約に署名した後に提供されるライセンス。標準のライセンスキー、またはサーバーが外部サービスに接続できないエアギャップ環境で使用される base64 エンコードされた証明書のいずれかを受け入れます。 | はい | | `******` |

> [!WARNING]
> **有効期限**
>
> ライセンスには有効期限があります。ライセンスの有効期限が30日未満の場合、サーバーと対話する Tuist コマンドを使用している間に警告が表示されます。ライセンスの更新に関心がある場合は、[contact@tuist.dev](mailto:contact@tuist.dev) までご連絡ください。


### 基本環境構成 {#base-environment-configuration}

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_APP_URL` | インターネットからインスタンスにアクセスするためのベース URL | はい | | https://tuist.dev |
| `TUIST_SECRET_KEY_BASE` | 情報（Cookie 内のセッションなど）を暗号化するために使用するキー | はい | | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD` | ハッシュ化されたパスワードを生成するためのペッパー | いいえ | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS` | ランダムなトークンを生成するためのシークレットキー | いいえ | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_ENCRYPTION` | 機密データの AES-GCM 暗号化に使用する 32 バイトのキー | いいえ | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_USE_IPV6` | `1` の場合、アプリが IPv6 アドレスを使用するように構成されます | いいえ | `0` | `1`|
| `TUIST_LOG_LEVEL` | アプリで使用するログレベル | いいえ | `info` | [ログレベル](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |
| `TUIST_GITHUB_APP_NAME` | GitHub アプリのスラッグ（`https://github.com/apps/<slug>` から取得）。アプリのインストールに必要です。<.localized_link href="/guides/server/self-host/server#platform-github">GitHub</.localized_link> を参照してください | いいえ | | `my-app` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 自動 PR コメントの投稿など、追加機能を有効にするために GitHub アプリで使用される base64 エンコードされた秘密鍵 | いいえ | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` | |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | 自動 PR コメントの投稿など、追加機能を有効にするために GitHub アプリで使用される秘密鍵。**特殊文字の問題を避けるため、base64 エンコードされたバージョンの使用をお勧めします** | いいえ | `-----BEGIN RSA...` | |
| `TUIST_OPERATOR_EMAIL_DOMAIN` | メールアドレスが `@<this-domain>` で終わる確認済みユーザーは、操作 URL（`/ops/*`）にアクセスできます | いいえ | `tuist.dev` | `example.com` |
| `TUIST_SERVER_VERSION_IDENTIFIER` | サーバーインスタンスを識別するためにダッシュボードのナビゲーションバーにバッジとして表示されるラベル（例：バージョン番号またはブランチ名） | いいえ | 開発環境の Git ブランチ | `v1.2.3` |
| `TUIST_WEB` | Web サーバーのエンドポイントを有効にする | いいえ | `1` | `1` または `0` |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` | サインインせずにビルドおよびテストのインサイトを送信できるようにします。設定とセキュリティ要件については、[ネットワーク信頼アクセス](#network-trusted-access) を参照してください。 | いいえ | `false` | `true` |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS` | サインインせずにキャッシュの読み取りと書き込みを許可します。設定とセキュリティ要件については、[ネットワーク信頼アクセス](#network-trusted-access) を参照してください。 | いいえ | `false` | `true` |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | トレースを送信するための OpenTelemetry Collector の gRPC エンドポイント | いいえ | | `http://localhost:4317` |
| `TUIST_LOKI_URL` | ログを送信するための Loki 互換エンドポイントのベース URL（例：Grafana Alloy または Loki） | いいえ | | `http://localhost:3100` |

> [!WARNING]
> **アプリを HTTPS 経由で提供**
>
> セッション Cookie には `Secure` フラグが設定されているため、プレーンな `http://` ではブラウザによって拒否され、ユーザーはサインインできません。サーバーの前段で TLS を終端し（内部 CA の証明書を持つリバースプロキシで十分）、内部または VPN のみのデプロイメントであっても `TUIST_APP_URL` を `https://` URL に設定してください。

### データベース構成 {#database-configuration}

データベース接続を構成するには、次の環境変数を使用します。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | Postgres データベースにアクセスするための URL。URL には認証情報を含める必要があることに注意してください | はい | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_SCHEMA` | Tuist のアプリケーションテーブルで使用される PostgreSQL スキーマ。データベースポリシーで `public` スキーマの使用が許可されていない場合に設定してください。スキーマ名は引用符なしの PostgreSQL 識別子である必要があります。 | いいえ | `public` | `tuist` |
| `TUIST_MIGRATION_DATABASE_URL` | `Tuist.Release.migrate` でのみ使用されるオプションの Postgres URL。`DATABASE_URL` がより制限されたランタイムロールを指している場合は、所有者ロールの URL に設定してください。 | いいえ | `DATABASE_URL` | `postgres://owner:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_RUNTIME_ROLE` | マイグレーション完了後にアプリケーションテーブルの権限を付与すべきランタイム Postgres ロール。Web サーバーがスキーマ所有者として接続すべきでない場合は、`TUIST_MIGRATION_DATABASE_URL` と併用してください。 | いいえ | | `tuist_web` |
| `TUIST_CLICKHOUSE_URL` | ClickHouse データベースにアクセスするための URL。URL には認証情報を含める必要があることに注意してください | いいえ | | `http://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | true の場合、データベースへの接続に [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) を使用します | いいえ | `1` | `1` |
| `TUIST_DATABASE_POOL_SIZE` | コネクションプールで開いたままにする接続数 | いいえ | `10` | `10` |
| `TUIST_DATABASE_QUEUE_TARGET` | プールからチェックアウトされたすべての接続がキュー間隔を超えたかどうかを確認する間隔（ミリ秒）[（詳細情報）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | いいえ | `300` | `300` |
| `TUIST_DATABASE_QUEUE_INTERVAL` | プールが新しい接続のドロップを開始するかどうかを判断するために使用するキュー内のしきい値時間（ミリ秒）[（詳細情報）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | いいえ | `1000` | `1000` |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse バッシャーフラッシュ間の時間間隔（ミリ秒） | いいえ | `5000` | `5000` |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE` | 強制フラッシュ前の最大 ClickHouse バッファサイズ（バイト） | いいえ | `1000000` | `1000000` |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE` | 実行する ClickHouse バッファプロセスの数 | いいえ | `5` | `5` |

`TUIST_DATABASE_SCHEMA` が `public` ではない場合、リリースマイグレーションは Ecto マイグレーションチェーンを実行する前に、スキーマが存在しなければ作成します。マイグレーションロールがスキーマを作成できない場合は、事前にスキーマを作成し、マイグレーションロールをその所有者にしてください。

Tuist はセッション `search_path` を設定することで、カスタムスキーマへの接続をポイントします。一部のプールまたはプロキシされた Postgres 設定（例えば PgBouncer や、起動パラメータを制限するマネージドデータベース）ではこれが適用されず、セッションは `public` にフォールバックします。これはマイグレーション中に `permission denied for schema public` として表面化します。このような設定を通じて接続する場合は、プロキシに関係なくすべてのセッションがそこから開始されるように、ロール自体にスキーマをピン留めしてください：

```sql
CREATE SCHEMA IF NOT EXISTS tuist AUTHORIZATION <migration_role>;
ALTER ROLE <migration_role> IN DATABASE <database> SET search_path = tuist;
-- If the web server connects as a separate runtime role (TUIST_DATABASE_RUNTIME_ROLE):
ALTER ROLE <runtime_role> IN DATABASE <database> SET search_path = tuist;
```

### 認証環境構成 {#authentication-environment-configuration}

[アイデンティティプロバイダー (IdP)](https://en.wikipedia.org/wiki/Identity_provider) を介して認証を容易にします。これを利用するには、選択したプロバイダーに必要なすべての環境変数がサーバー環境に存在することを確認してください。**変数が欠落している**と、Tuist はそのプロバイダーを bypass します。

#### メールとパスワード {#email-and-password}

メールとパスワードによるサインインおよびセルフサービス登録は組み込まれており、デフォルトで有効です。アイデンティティプロバイダーを必須にしたいインスタンス（例えば SSO を強制する場合）では、これらを完全に無効にできます。これにより、ログインエクスペリエンスからメール/パスワードフォーム、サインアップリンク、パスワードリセットフローが削除され、CLI が使用するメール/パスワードエンドポイント（`tuist auth`）を含む、一致するすべてのサーバーサイドエンドポイントが閉じられます。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_EMAIL_AUTH_ENABLED` | メールとパスワードを使用してサインインおよび登録できるかどうか。ログインページからメール/パスワードフォーム、サインアップリンク、パスワードリセットフローを削除し、一致するサーバーサイドエンドポイントを閉じるには `0` に設定してください | いいえ | `1` | `0` |

#### 構成済みアイデンティティプロバイダーの無効化 {#disabling-a-configured-identity-provider}

デフォルトでは、プロバイダーは構成されるとサインインオプションとして表示されます。プロバイダーを構成されたままにし（資格情報は設定されたまま）、ログインおよびサインアップページから削除するには、対応するレバーを `0` に設定してください。GitHub、Google、Apple の場合、これによりサインインコールバックも閉じられるため、この方法はエンドツーエンドで利用できなくなります。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_AUTH_ENABLED` | GitHub を使用してサインインできるかどうか（アプリがサインインと資格情報を共有する理由については [GitHub](#github) セクションを参照） | いいえ | `1` | `0` |
| `TUIST_GOOGLE_AUTH_ENABLED` | Google を使用してサインインできるかどうか | いいえ | `1` | `0` |
| `TUIST_OKTA_AUTH_ENABLED` | 構成済みの Okta プロバイダーがサインインオプションとして表示されるかどうか | いいえ | `1` | `0` |
| `TUIST_APPLE_AUTH_ENABLED` | Apple を使用してサインインできるかどうか | いいえ | `1` | `0` |

#### GitHub {#github}

[GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) を使用した認証を推奨しますが、[OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app) も使用できます。サーバー環境に GitHub が指定するすべての必須環境変数を含めるようにしてください。変数が欠落している場合、Tuist は GitHub 認証を無視します。GitHub アプリを正しく設定するには:
- GitHub アプリの一般設定で:
    - `Client ID` をコピーし、`TUIST_GITHUB_APP_CLIENT_ID` として設定します
    - 新しい `client secret` を作成してコピーし、`TUIST_GITHUB_APP_CLIENT_SECRET` として設定します
    - `Callback URL` を `http://YOUR_APP_URL/users/auth/github/callback` に設定します。`YOUR_APP_URL` にはサーバーの IP アドレスも指定できます。
- 以下の権限が必要です:
  - リポジトリ:
    - プルリクエスト: 読み取りおよび書き込み
  - アカウント:
    - メールアドレス: 読み取り専用

`Permissions and events` の `Account permissions` セクションで、`Email addresses` 権限を `Read-only` に設定します。

次に、Tuist サーバーが実行される環境で以下の環境変数を公開する必要があります:

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub アプリケーションのクライアント ID | はい | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | アプリケーションのクライアントシークレット | はい | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_AUTH_ENABLED` | GitHub を使用してサインインできるかどうか。プラットフォーム統合（PR コメントなど）用に構成した GitHub App は、サインインとクライアント資格情報を共有するため、ログインオプションとして表示されます。アプリを残しながらログインページから GitHub を削除するには `0` に設定してください | いいえ | `1` | `0` |

#### Google {#google}

[OAuth 2](https://developers.google.com/identity/protocols/oauth2) を使用して Google での認証を設定できます。そのためには、OAuth クライアント ID タイプの新しい認証情報を作成する必要があります。認証情報を作成する際は、アプリケーションタイプとして「Web アプリケーション」を選択し、名前を `Tuist` に設定し、リダイレクト URI を `{base_url}/users/auth/google/callback` に設定します。ここで `base_url` はホストされているサービスが実行されている URL です。アプリを作成したら、クライアント ID とシークレットをコピーし、それぞれ環境変数 `GOOGLE_CLIENT_ID` および `GOOGLE_CLIENT_SECRET` として設定します。

> [!NOTE]
> **同意画面のスコープ**
>
> 同意画面を作成する必要がある場合があります。その際は、`userinfo.email` および `openid` スコープを追加し、アプリを内部用としてマークしてください。


#### Okta {#okta}

[OAuth 2.0](https://oauth.net/2/) プロトコルを使用して Okta での認証を有効にできます。Okta で [アプリを作成](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)し、<.localized_link href="/guides/integrations/authentication/sso#okta">これらの手順</.localized_link>に従ってください。

Okta アプリケーションの設定中にクライアント ID とシークレットを取得したら、以下の環境変数を設定する必要があります:

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID` | Okta に対して認証するためのクライアント ID。番号は組織 ID にする必要があります | はい | | |
| `TUIST_OKTA_1_CLIENT_SECRET` | Okta に対して認証するためのクライアントシークレット | はい | | |

番号 `1` は組織 ID に置き換える必要があります。通常は 1 ですが、データベースで確認してください。

### ストレージ環境設定 {#storage-environment-configuration}

 Tuist は API を経由してアップロードされたアーティファクトを保存するためにストレージが必要です。Tuist を効果的に運用するには、**サポートされているストレージソリューションのいずれかを構成することが不可欠**です。

サーバーアーティファクトのバックエンドを選択するには `TUIST_OBJECT_STORAGE_PROVIDER` を設定します:

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_OBJECT_STORAGE_PROVIDER` | サーバーアーティファクトのストレージバックエンド。S3 互換ストレージには `s3` を、Azure Blob Storage には `azure_blob` を使用します | いいえ | `s3` | `azure_blob` |

#### S3 準拠ストレージ {#s3compliant-storages}

アーティファクトを保存するために、S3 準拠の任意のストレージプロバイダーを使用できます。ストレージプロバイダーとの統合を認証および構成するには、以下の環境変数が必要です:

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_S3_ACCESS_KEY_ID` または `AWS_ACCESS_KEY_ID` | ストレージプロバイダーに対して認証するためのアクセスキー ID | はい | | `AKIAIOSFOD` |
| `TUIST_S3_SECRET_ACCESS_KEY` または `AWS_SECRET_ACCESS_KEY` | ストレージプロバイダーに対して認証するためのシークレットアクセスキー | はい | | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` または `AWS_REGION` | バケットが配置されているリージョン | いいえ | `auto` | `us-west-2` |
| `TUIST_S3_ENDPOINT` または `AWS_ENDPOINT` | ストレージプロバイダーのエンドポイント | はい | | `https://s3.us-west-2.amazonaws.com` |
| `TUIST_S3_BUCKET_NAME` | アーティファクトが保存されるバケットの名前 | はい | | `tuist-artifacts` |
| `TUIST_S3_CA_CERT_PEM` | S3 HTTPS 接続を検証するための PEM エンコードされた CA 証明書。自己署名証明書や内部認証局を使用するエアギャップ環境で役立ちます。 | いいえ | システム CA バンドル | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT` | ストレージプロバイダーへの接続を確立するためのタイムアウト（ミリ秒） | いいえ | `3000` | `3000` |
| `TUIST_S3_RECEIVE_TIMEOUT` | ストレージプロバイダーからデータを受信するためのタイムアウト（ミリ秒） | いいえ | `5000` | `5000` |
| `TUIST_S3_POOL_TIMEOUT` | ストレージプロバイダーへの接続プールのタイムアウト（ミリ秒）。タイムアウトなしにするには `infinity` を使用します | いいえ | `5000` | `5000` |
| `TUIST_S3_POOL_MAX_IDLE_TIME` | プール内の接続の最大アイドル時間（ミリ秒）。接続を無期限に維持するには `infinity` を使用します | いいえ | `infinity` | `60000` |
| `TUIST_S3_POOL_SIZE` | プールあたりの最大接続数 | いいえ | `500` | `500` |
| `TUIST_S3_POOL_COUNT` | 使用する接続プールの数 | いいえ | システムスケジューラーの数 | `4` |
| `TUIST_S3_PROTOCOL` | ストレージプロバイダーへの接続時に使用するプロトコル（`http1` または `http2`） | いいえ | `http1` | `http1` |
| `TUIST_S3_VIRTUAL_HOST` | URL をバケット名をサブドメイン（仮想ホスト）として構築するかどうか | いいえ | `false` | `1` |

> [!NOTE]
> **環境変数からの Web ID トークンによる AWS 認証**
>
> ストレージプロバイダーが AWS で、Web ID トークンを使用して認証したい場合は、環境変数 `TUIST_S3_AUTHENTICATION_METHOD` を `aws_web_identity_token_from_env_vars` に設定できます。Tuist は従来の AWS 環境変数を使用してそのメソッドを利用します。


#### Google Cloud Storage {#google-cloud-storage}
Google Cloud Storage の場合、[これらのドキュメント](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)に従って `AWS_ACCESS_KEY_ID` と `AWS_SECRET_ACCESS_KEY` のペアを取得してください。`AWS_ENDPOINT` は `https://storage.googleapis.com` に設定する必要があります。他の環境変数は、他の S3 準拠ストレージと同じです。

#### Azure Blob Storage {#azure-blob-storage}

Azure Blob Storage の場合、`TUIST_OBJECT_STORAGE_PROVIDER=azure_blob` を設定し、Azure ストレージアカウントの認証情報を構成します:

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_AZURE_STORAGE_ACCOUNT_NAME` | Azure Storage アカウント名 | はい | | `tuiststorage` |
| `TUIST_AZURE_STORAGE_ACCOUNT_KEY` | Azure Blob REST リクエストと SAS URL に署名するために使用されるストレージアカウントのアクセスキー | はい | | `******` |
| `TUIST_AZURE_BLOB_CONTAINER_NAME` | サーバーアーティファクトが保存されるコンテナー | はい | | `tuist-artifacts` |
| `TUIST_AZURE_BLOB_ENDPOINT` | Blob サービスのエンドポイント。省略すると `https://<account>.blob.core.windows.net` が使用されます | いいえ | アカウント名から派生 | `https://tuiststorage.blob.core.windows.net` |
| `TUIST_AZURE_BLOB_SERVICE_VERSION` | 署名付きリクエストと SAS URL に使用される Azure Blob REST API バージョン | いいえ | `2020-12-06` | `2020-12-06` |

Helm チャートを使用する場合は、`server.storage.provider=azure_blob` を設定し、`server.azureBlob.*` を入力してください。チャートのトップレベルの `objectStorage` 設定は S3 互換のままです。これは、オプションのキャッシュおよびレジストリミラーのワークロードが引き続き S3 互換ストレージを想定しているためです。これらのワークロードが無効でサーバーが Azure Blob を使用する場合は、`objectStorage.mode=external` を設定し、外部オブジェクトストレージのエンドポイントと認証情報を空にして、組み込みの MinIO サービスのデプロイを回避してください。

#### アーティファクトの保持 {#artifact-retention}

セルフホストインスタンスでは、アーティファクトのクリーンアップはデフォルトで無効になっています。サポートされている各アーティファクトタイプには独自の環境変数があります。そのアーティファクトタイプのクリーンアップを有効にするには、変数を正の整数の日数に設定します。変数を未設定または空白のままにすると、そのアーティファクトタイプのクリーンアップのみが無効になります。

```bash
TUIST_CACHE_ARTIFACT_RETENTION_DAYS=30
TUIST_APP_PREVIEW_RETENTION_DAYS=30
TUIST_BUILD_ARCHIVE_RETENTION_DAYS=60
TUIST_RUN_ARTIFACT_RETENTION_DAYS=30
TUIST_TEST_ATTACHMENT_RETENTION_DAYS=30
TUIST_SHARD_BUNDLE_RETENTION_DAYS=14
```

Helm チャートを使用する場合、同じ期間をマップとして構成します:

```yaml
server:
  artifactRetentionDays:
    cacheArtifacts: 30
    appPreviews: 30
    buildArchives: 60
    runArtifacts: 30
    testAttachments: 30
    shardBundles: 14
```

6つのキーはすべてオプションです。この例では、サポートされているすべてのアーティファクトタイプが独立した保持期間で有効になります。そのアーティファクトタイプのクリーンアップを無効にしたままにするには、キーを省略するか、その値を空白にしてください。セルフホストの保持期間には30日の上限はありません。正の整数ではない値を設定すると、サーバーの起動時に失敗します。

保持変数を変更した後、サーバーを再起動してください。キューに入れられたセルフホストのクリーンアップバッチはすべて、ファイルを削除する前に現在の構成を確認するため、変数の設定解除や空白化、または期間の延長を行うと、再起動後の保留中のジョブからもファイルが保護されます。

| 環境変数 | オブジェクトストレージから削除されるアーティファクトファイル |
| --- | --- |
| `TUIST_CACHE_ARTIFACT_RETENTION_DAYS` | Xcode キャッシュ、レガシーなコンテンツアドレサブルストレージキャッシュ、モジュールキャッシュ、および Gradle キャッシュファイル |
| `TUIST_APP_PREVIEW_RETENTION_DAYS` | アプリプレビューのビルドとアイコン |
| `TUIST_BUILD_ARCHIVE_RETENTION_DAYS` | 現在およびレガシーなビルドアーカイブ |
| `TUIST_RUN_ARTIFACT_RETENTION_DAYS` | 期限切れの実行のアーティファクトプレフィックスの下に保存されたすべてのオブジェクト（結果バンドル、呼び出し記録、セッションアーカイブを含む） |
| `TUIST_TEST_ATTACHMENT_RETENTION_DAYS` | テスト実行の添付ファイル |
| `TUIST_SHARD_BUNDLE_RETENTION_DAYS` | テストシャードバンドル |

スケジュールされたクリーンアップはアーティファクトブロブのみを削除します。対応する PostgreSQL および ClickHouse の行は保持されるため、ダウンロードの有効期限が切れた後でも、ビルド、テスト、実行、プレビュー、およびシャードのメタデータはダッシュボードで表示されたままになります。この構成は ClickHouse テーブルの保持ルールを変更しません。

### メール設定 {#email-configuration}

Tuist は、ユーザー認証およびトランザクション通知（パスワードのリセット、アカウント通知など）のためにメール機能を必要とします。現在、メールプロバイダーとして **Mailgun のみがサポートされています**。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_MAILGUN_API_KEY` | Mailgun で認証するための API キー | はい* | | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN` | メールの送信元となるドメイン | はい* | | `mg.tuist.io` |
| `TUIST_MAILING_FROM_ADDRESS` | 「From」フィールドに表示されるメールアドレス | はい* | | `noreply@tuist.io` |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | ユーザーからの返信用のオプションの返信先アドレス | いいえ | | `support@tuist.dev` |
| `TUIST_SKIP_EMAIL_CONFIRMATION` | 新規ユーザー登録時のメール確認をスキップします。有効にすると、ユーザーは自動的に確認され、登録後すぐにログインできます | いいえ | メールが設定されていない場合は `true`、メールが設定されている場合は `false` | `true`, `false`, `1`, `0` |

\* メール設定変数は、メールを送信したい場合にのみ必要です。設定されていない場合、メール確認は自動的にスキップされます

> [!NOTE]
> **SMTP サポート**
>
> 一般的な SMTP サポートは現在利用できません。オンプレミス環境で SMTP サポートが必要な場合は、[contact@tuist.dev](mailto:contact@tuist.dev) までご連絡いただき、要件についてご相談ください。


> [!NOTE]
> **エアギャップ環境でのデプロイ**
>
> インターネットアクセスやメールプロバイダーの設定がないオンプレミス環境では、デフォルトでメール確認が自動的にスキップされます。ユーザーは登録後すぐにログインできます。メールを設定している場合でも確認をスキップしたい場合は、`TUIST_SKIP_EMAIL_CONFIRMATION=true` を設定してください。メールが設定されている場合にメール確認を必須にするには、`TUIST_SKIP_EMAIL_CONFIRMATION=false` を設定してください。

> [!NOTE]
> **メールのクォータとパスワードリセットリンク**
>
> メールが設定されている場合、招待メール（作成、一括送信、再送信）は受信者ごとに 5 分間に 1 通まで、かつ組織および招待者ごとに 1 時間あたり 50 通のバースト制限（50 通ずつ補充）となります。招待をキャンセルしてもクォータは回復せず、招待 API はクォータ枯渇時に `429` および `Retry-After` で応答します。複数のレプリカを使用する場合は、デプロイ全体でクォータを共有するために共有 Valkey を構成してください。構成されていても利用できない場合、招待メールは拒否されます。パスワードリセットリンクは 15 分後に有効期限が切れます。


### Git プラットフォームの設定 {#git-platform-configuration}

Tuist は <.localized_link href="/guides/server/authentication">Git プラットフォームと統合</.localized_link> し、プルリクエストへのコメント自動投稿などの追加機能を提供できます。

#### GitHub {#platform-github}

セルフホスト型の Tuist サーバーは、`https://tuist.dev` で動作する GitHub App をインストールできません。GitHub App は登録したサーバーに紐付けられるため、デプロイには github.com 上で独自の App が必要です。

##### App の登録 {#platform-github-registering-the-app}

GitHub 組織が所有する [GitHub App を作成](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) してください。OAuth App を作成した場合を除き、認証用に作成した App を再利用できます。`YOUR_APP_URL` を `TUIST_APP_URL` の値に置き換えて、以下のように設定してください：

| 設定 | 値 |
| --- | --- |
| コールバック URL | `YOUR_APP_URL/users/auth/github/callback` および `YOUR_APP_URL/integrations/github/authorize` |
| セットアップ URL | `YOUR_APP_URL/integrations/github/setup` |
| 更新時のリダイレクト | 有効 |
| Webhook URL | `YOUR_APP_URL/webhooks/github` |
| Webhook シークレット | 任意のランダムな文字列。これを `TUIST_GITHUB_APP_WEBHOOK_SECRET` として設定します |

以下のリポジトリ権限を付与してください：

| 権限 | アクセス |
| --- | --- |
| コンテンツ | 読み取り専用 |
| メタデータ | 読み取り専用 |
| Issues | 読み取りおよび書き込み |
| プルリクエスト | 読み取りおよび書き込み |
| Checks | 読み取りおよび書き込み |

さらに、**メンバー: 読み取り専用** の組織権限も付与してください。github.com のセットアップ中、Tuist は組織のインストールを接続する人が単なるリポジトリアクセス権を持つユーザーではなく、アクティブな GitHub 組織オーナーであることを確認します。

App を `Check run`、`Pull request`、および `Issue comment` イベントに登録してください。

GitHub がインストーラーをセットアップ URL に送信できるよう、**インストール中にユーザー承認（OAuth）を要求** は無効にしたままにしてください。Tuist は追加の `/integrations/github/authorize` コールバックを使用して別の承認ステップを開始し、インストールの所有権を検証します。GitHub でインストールが開始されると、インストーラーは Tuist 組織を選択します。Tuist で開始されたインストールは、その組織を保持します。

##### サーバーの設定 {#platform-github-configuring-the-server}

以下の環境変数を設定し、サーバーを再起動してください：

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_NAME` | App のスラッグ。公開ページ URL `https://github.com/apps/<slug>` の最後のパス要素です | はい | | `my-company-tuist` |
| `TUIST_GITHUB_APP_ID` | インストールの所有権を検証するために使用される数値の App ID | はい | | `123456` |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub アプリケーションのクライアント ID | はい | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | アプリケーションのクライアントシークレット | はい | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub アプリケーションの base64 エンコードされた秘密鍵。改行の扱いがプラットフォームに依存する `TUIST_GITHUB_APP_PRIVATE_KEY` より優先されます | はい | | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |
| `TUIST_GITHUB_APP_WEBHOOK_SECRET` | GitHub アプリケーションで設定された Webhook シークレット | いいえ | | `a4c1e0f2b8d6...` |

> [!IMPORTANT]
> **必要な App 認証情報をすべて設定**
>
> 組織の統合ページにある **Install GitHub App** ボタンは、`TUIST_GITHUB_APP_NAME`、`TUIST_GITHUB_APP_CLIENT_ID`、`TUIST_GITHUB_APP_CLIENT_SECRET`、および秘密鍵がすべて設定されるまで無効のままです。インストールの所有権を検証するには、数値の `TUIST_GITHUB_APP_ID` も必要です。インストール URL には App スラッグが含まれるため、特に `TUIST_GITHUB_APP_NAME` が欠落していると、GitHub から 404 が返されるリンクになります。

サーバーの再起動後、組織の管理者は <.localized_link href="/guides/integrations/gitforge/github">GitHub 統合ガイド</.localized_link> に従って App をインストールし、リポジトリをプロジェクトに接続します。

##### OIDC 認証はこれに依存します {#platform-github-oidc}

<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 認証</.localized_link> は、CI トークンのリポジトリクレームをプロジェクトに接続されたリポジトリと照合し、接続はインストール済みの GitHub App を介してのみ作成できます。CI ワークフローがトークンなしで `tuist auth login` を実行する前に、上記の設定を完了してください。

Tuist サーバーは、署名鍵を取得するために CI プロバイダーの OIDC イシューアーへのアウトバウンドアクセスも必要です：

| CI プロバイダー | ホスト |
| --- | --- |
| GitHub Actions | `token.actions.githubusercontent.com` |
| CircleCI | `oidc.circleci.com` |
| Bitrise | `token.builds.bitrise.io` |

##### GitHub Enterprise Server {#platform-github-enterprise-server}

上記の環境変数は Tuist の github.com App のみを設定します。代わりに GitHub Enterprise Server（GHES）インスタンスと Tuist を統合するには、組織の管理者は統合ページの **Enterprise server** タブに切り替え、GHES のベース URL を入力します。Tuist は GitHub の [App マニフェストフロー](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) に沿って、GHES インスタンスに新しい Tuist App を登録する手順を案内します。新しい App の認証情報はインストールごとに暗号化されて保存され、追加の `TUIST_GITHUB_APP_*` 環境変数は不要です。

#### Origin {#platform-origin}

セルフホスト型の Tuist サーバーには、デプロイの URL と署名鍵で設定された独自の Origin app が必要です。インストールと認証情報が独立した状態を保つよう、Tuist 環境ごとに個別の App を登録してください。

##### App の登録 {#platform-origin-registering-the-app}

1. Ed25519 サポート付きの OpenSSL を使用して Ed25519 署名鍵ペアを生成します：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out origin-app-private.pem
   openssl pkey -in origin-app-private.pem -pubout -out origin-app-public.pem
   ```

2. [Origin app settings](https://cursor.com/codebase/settings/apps) で App を作成します。`origin-app-public.pem` の内容を公開署名鍵として登録します。`origin-app-private.pem` は秘密に保ち、Cursor にアップロードせず、Tuist サーバーに提供してください。
3. 以下の設定を行い、`YOUR_APP_URL` を Tuist デプロイの HTTPS ベース URL に置き換えます：

   | 設定 | 値 |
   | --- | --- |
   | ホームページ URL | `YOUR_APP_URL` |
   | リダイレクト URI | `YOUR_APP_URL/integrations/origin/setup` |
   | Webhook URL | `YOUR_APP_URL/webhooks/origin` |

4. `app_` で始まる登録済み App ID をコピーします。

Tuist はインストール中に以下の権限を要求します：

| スコープ | 用途 |
| --- | --- |
| `repository:pull_requests:read` | プルリクエストと現在のヘッドコミットを検索します。 |
| `repository:pull_requests:reviews:write` | レポートコメントの読み取り、投稿、更新を行います。Origin には対応する review-read 権限が含まれています。 |
| `repository:metadata:read` | リポジトリを検出し、デフォルトブランチを読み取ります。Origin によって自動的に付与されます。 |

オプションのリポジトリ Webhook イベントは選択しないでください。インストールのライフサイクル通知で十分です。ソースコードへのアクセス、マージ権限、およびチェック実行権限は不要です。

##### サーバーの設定 {#platform-origin-configuring-the-server}

以下の環境変数を設定し、サーバーを再起動してください：

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_ORIGIN_APP_ID` | Origin app settings からコピーした App ID。 | はい | | `app_...` |
| `TUIST_ORIGIN_APP_PRIVATE_KEY` | `origin-app-private.pem` の完全な内容。`BEGIN PRIVATE KEY` と `END PRIVATE KEY` の行、およびすべての改行を含みます。 | はい | | `-----BEGIN PRIVATE KEY-----...` |

秘密鍵はデプロイのシークレットマネージャーに保存してください。複数行の PEM 形式を維持する必要があり、この設定は Base64 エンコードされた代替を受け付けません。鍵をソース管理にコミットしたり、ログに公開したりしないでください。両方の変数は同じ登録済み App に属している必要があります。

Tuist サーバーは `api.cursor.com` へのアウトバウンド HTTPS アクセスが必要です。Cursor は Webhook URL にリクエストを配信できる必要があり、管理者はブラウザでリダイレクト URI に戻れる必要があります。登録された両方の URL は、デプロイの HTTPS ベース URL と一致している必要があります。

##### App のインストール {#platform-origin-installing-the-app}

サーバーが再起動したら、管理者は **Settings → Integrations** を開き、Origin の下の **Connect** を選択して、適切な Origin アカウントとリポジトリへの App のアクセスを承認します。このフロー全体を通じて Tuist 組織は保持されます。代わりに Origin から直接開始されたインストールでは、管理者にログインを促し、接続する Tuist 組織を選択させます。その後、**Add new project connection** を選択して、Tuist プロジェクトをネイティブリポジトリにリンクします。

プロジェクト接続と結果アップロードの要件については、<.localized_link href="/guides/integrations/gitforge/origin">Origin 統合ガイド</.localized_link> に従ってください。App をインストールしてもビルドまたはテストワークフローは開始されません。これらのワークフローは引き続き結果を Tuist サーバーに報告します。

## ローカルでのテスト {#testing-locally}

インフラストラクチャにデプロイする前に、ローカルマシンで Tuist サーバーをテストするために必要なすべての依存関係を含む包括的な Docker Compose 構成を提供しています：

- PostgreSQL 15
- 分析用 ClickHouse 26.5
- 調整用 ClickHouse Keeper
- S3 互換ストレージ用 MinIO
- ローカルセルフホストキャッシュテスト用 Kura
- データベース管理用 pgweb

> [!CAUTION]
> **ライセンスが必要**
>
> Tuist サーバー（ローカル開発インスタンスを含む）を実行するには、有効な `TUIST_LICENSE` 環境変数が法的に必要です。ライセンスが必要な場合は、[contact@tuist.dev](mailto:contact@tuist.dev) までお問い合わせください。


**クイックスタート：**

1. 設定ファイルをダウンロードします：
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-level.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-ttl.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. 環境変数を設定します：
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE, TUIST_SECRET_KEY_BASE, and authentication credentials
   ```

   バンドルされた ClickHouse サービスは、以下のオプションの運用ログ制御を受け入れます：

   | 環境変数 | 説明 | デフォルト | 例 |
   | --- | --- | --- | --- |
   | `CLICKHOUSE_SYSTEM_LOG_TTL_DAYS` | `text_log`、`query_log`、`trace_log`、`metric_log`、`part_log` などの ClickHouse `system.*` ログテーブルの保持期間（日数） | `14` | `7` |
   | `CLICKHOUSE_TEXT_LOG_LEVEL` | ClickHouse サーバーロガーおよび `system.text_log` レベル | `information` | `warning` |
   | `CLICKHOUSE_SUPERSEDED_LOG_TABLES` | システムログテーブルを置き換えた際に ClickHouse が残す `<name>_N` テーブルの扱い。`ignore` はそれらを保持し、`delete` は削除します | `ignore` | `delete` |

3. すべてのサービスを開始します：
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

   Apple Silicon では、Docker Desktop が Tuist および依存関係イメージの `linux/arm64` バリアントを自動的にプルします。デバッグ用に amd64 エミュレーションを強制するには、`DOCKER_DEFAULT_PLATFORM=linux/amd64` を指定して Compose を実行してください。

   バンドルされた compose ファイルは永続データのために名前付き Docker ボリュームを使用します。これをホストバインドマウントに置き換える場合は、まずホストディレクトリを作成し、特に ClickHouse および ClickHouse Keeper のデータディレクトリをコンテナユーザーが書き込めるようにしてください。

4. サーバーには http://localhost:8080 でアクセスしてください

**サービスエンドポイント：**
- Tuist サーバー: http://localhost:8080
- Kura キャッシュ（HTTP + REAPI gRPC を同一ポートで提供）: http://localhost:4000
- MinIO コンソール: http://localhost:9003（認証情報: `tuist` / `tuist_dev_password`）
- MinIO API: http://localhost:9002
- pgweb（PostgreSQL UI）: http://localhost:8081
- Prometheus メトリクス: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**よく使うコマンド：**

サービスの状態を確認：
```bash
docker compose ps
# or: podman compose ps
```

ログを表示：
```bash
docker compose logs -f tuist
```

サービスを停止：
```bash
docker compose down
```

すべてリセット（全データを削除）：
```bash
docker compose down -v
```

**設定ファイル：**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - 完全な Docker Compose 設定
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse 設定
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml) - ClickHouse Keeper 設定
- [.env.example](/server/self-host/.env.example) - 環境変数の例

## Helm を使用した Kubernetes {#kubernetes-with-helm}

Tuist は Kubernetes へのデプロイ用公式 Helm チャートを提供しています。このチャートには Tuist サーバーとキャッシュサービスが含まれており、必要に応じて外部プロバイダーに置き換えられる埋め込みインフラストラクチャ依存関係もパッケージ化されています。

### チャートのインストール {#installing-the-chart}

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY"
```

特定のチャートバージョンを固定する場合：

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY" \
  --version 0.1.0
```

### ライセンス {#helm-license}

`server.license.key` の値には、標準のライセンスキーと、エアギャップ環境向けインストール用の Base64 エンコードされたライセンス証明書の両方を受け付けます。サーバーがどちらかを自動検出します。

`--set` でライセンスを渡すことでクイックインストールが可能です。値をバージョン管理下に置く場合は、ライセンスを Helm 外で管理する Kubernetes Secret（例：Vault、Sealed Secrets、SOPS を使用）に保存し、チャートからそれを参照するように設定します：

```yaml
# values.yaml
server:
  license:
    existingSecret: tuist-license
    existingSecretKeys:
      key: TUIST_LICENSE
      certificateBase64: ""
```

`existingSecretKeys.key` 以下のエントリは、ライセンス値（ライセンスキー、またはエアギャップ環境向けインストール用の Base64 エンコードされたライセンス証明書）を保持する Secret 内のフィールド名を指定します。`existingSecretKeys` 以下の各エントリはチャート独自のキー名にデフォルト設定されるため、Secret に含まれないエントリは上記の `certificateBase64` のように空文字列に設定してください。設定しないと、Pod が存在しないキーを参照して起動に失敗します。チャートをインストールまたはアップグレードする前に、リリース namespace に Secret を作成してください。

ライセンスは単一のソースからのみ設定してください：`server.license.key` または `server.license.existingSecret`。いずれも設定されていない場合、またはソースが組み合わされている場合、チャートのレンダリングは失敗します。`server.extraEnv` を介して渡されたライセンスはソースとしてカウントされないため、代わりに `existingSecret` を使用してください。

### インフラストラクチャ依存関係 {#helm-infrastructure-dependencies}

このチャートは `postgresql`、`clickhouse`、`objectStorage` の 3 つのインフラストラクチャ依存関係を管理します。それぞれはデフォルトで **embedded** モードであり、チャートがクラスター内にこれらをデプロイすることを意味します。代わりに独自の外部インスタンスを指す場合は、依存関係の `mode` を `external` に設定し、`values.yaml` に接続詳細を入力してください。例えば、外部 PostgreSQL データベースを使用する場合：

```yaml
# values.yaml
postgresql:
  mode: external
  external:
    host: your-db-host
    port: 5432
    database: tuist
    username: tuist
    password: your-password
```

PostgreSQL の認証情報を Helm 外で管理している場合は、代わりに既存の Kubernetes Secret をチャートから参照するように設定します：

```yaml
# values.yaml
postgresql:
  mode: external
  external:
    port: 5432
    database: tuist
    existingSecret: tuist-postgresql
    existingSecretKeys:
      host: host
      username: username
      password: password
```

チャートは Secret からホスト、ユーザー名、パスワードを読み取り、Kubernetes 環境変数置換を通じて `DATABASE_URL` を構成するため、パスワードは Helm マニフェストにレンダリングされません。Secret のパスワード値はデータベース URL に挿入されるため、URL セーフである必要があります。

同じパターンが `clickhouse` と `objectStorage` にも適用されます。設定可能なフィールドの完全な一覧については、チャートの `values.yaml` にある各セクションの `external` ブロックを参照してください。

### 共有スケジューリングとラベル {#helm-shared-scheduling-and-labels}

このチャートは `global` の下に少量の共有 Pod 設定を公開しており、オペレーターはすべてのワークロードで同じ値を繰り返すことなく、デプロイをクラスターに適応させることができます：

```yaml
global:
  podLabels:
    environment: production
  imagePullSecrets:
    - name: ghcr-pull-secret
  nodeSelector:
    nodepool: apps
  tolerations:
    - key: dedicated
      operator: Equal
      value: apps
      effect: NoSchedule
```

以下の必要がある場合に、これらの設定を使用します：

- すべての Pod にクラスター固有のラベルを追加する
- プライベートレジストリからミラーイメージを取得する
- 専用のノードプールを対象とする
- Tuist ワークロード用に予約された汚染されたノードへの Pod の配置を許可する

### ワークロードアイデンティティとサービスアカウント {#helm-workload-identity}

このチャートはアプリケーションワークロードごとにサービスアカウントのスコープを設定するため、必要な場所でのみアイデンティティを付与できます：

- `server.serviceAccount` は Tuist サーバーのデプロイメントと移行ジョブに適用されます
- `cache.serviceAccount` はキャッシュのデプロイメントに適用されます

例えば、キャッシュが EKS 上の外部 S3 バケットを使用する場合、埋め込みデータベースに同じ IAM ロールをアタッチすることなく、キャッシュワークロードに対して IRSA を有効にできます：

```yaml
cache:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/tuist-cache
```

### 互換性オーバーライド {#helm-compatibility-overrides}

このチャートはストレージおよびメッシュ固有の調整をオプトインとし、デフォルトがポータブルであることを維持します：

```yaml
cache:
  podSecurityContext:
    fsGroup: 990

clickhouse:
  embedded:
    service:
      nativePort: 9100
    systemLogs:
      ttlDays: 7
      supersededTables: delete
      level: warning
```

クラスターで必要とされる場合のみ、これらのオーバーライドを使用してください：

- `cache.podSecurityContext` はデフォルトで空です。ストレージクラスまたは CSI ドライバーがマウントされたボリューム上で共有グループ所有権を必要とする場合は、`fsGroup` を設定してください。
- `clickhouse.embedded.service.nativePort` は ClickHouse の標準的な `9000` ネイティブサービスポートにデフォルト設定され、サービスメッシュやプラットフォームの予約がこのポートと競合する場合に変更できます。
- `clickhouse.embedded.systemLogs.ttlDays` はデフォルトで空であり、`system.text_log`、`system.query_log`、`system.trace_log`、`system.metric_log`、`system.part_log` などの埋め込み内部ログテーブルに対する ClickHouse の無制限保持を残します。これを設定するとそれらのテーブルが一度上書きされるため、`supersededTables: delete` と併せて採用してください — <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">運用ログの保持上限</.localized_link> を参照。
- `clickhouse.embedded.systemLogs.level` は埋め込み ClickHouse サーバーロガーおよび `system.text_log` に対して `information` にデフォルト設定されます。`ttlDays` とは異なり、これはどのテーブル定義の一部でもないため、変更してもテーブルを上書きすることはありません。
- `clickhouse.embedded.systemLogs.supersededTables` は `ignore` にデフォルト設定され、システムログテーブルを上書きした際に ClickHouse が残す `<name>_N` テーブルの扱いを決定します。各 `helm upgrade` でこれらを削除するには、`delete` に設定してください。
- `ttlDays` と `level` の編集は、どちらも `subPath` マウントであり、ConfigMap が変更された際にチャートが StatefulSet をロールアウトしないため、ClickHouse Pod の次回再起動時に反映されます。

### 観測可能性 {#helm-observability}

このチャートにはオプションの観測スタック（OpenTelemetry Collector、Prometheus、Grafana、Loki、Tempo）が含まれています。これは **デフォルトで無効** です。`values.yaml` で有効にするには：

```yaml
# values.yaml
observability:
  enabled: true
```

有効にすると、Grafana は Logs、Traces、Metrics のドリルダウンが事前構成された状態で利用可能になります。外部観測機能を使用する場合は、これを無効にしたまま `server.extraEnv` を介してエンドポイントを構成してください：

```yaml
# values.yaml
server:
  extraEnv:
    - name: TUIST_OTEL_EXPORTER_OTLP_ENDPOINT
      value: "http://your-otel-collector:4317"
    - name: TUIST_LOKI_URL
      value: "http://your-loki:3100"
```

### 値のリファレンス {#helm-values-reference}

設定可能な値の完全な一覧については、チャートの [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml) を参照してください。

## デプロイメント {#deployment}

公式の Tuist Docker イメージは以下で利用可能です：
```
ghcr.io/tuist/tuist
```

公開されているイメージには `.xcactivitylog` アーカイブ用の埋め込み Linux ビルド処理が含まれているため、セルフホスト型デプロイメントは追加のサービスを実行せずにビルドを処理できます — `ProcessBuildWorker` Oban ジョブは各サーバー Pod 内でインプロセスで実行されます。ビルド処理を専用レプリカセットにオフロードしたい場合（例えば、Web 層とは独立して解析スループットをスケールさせるため）、Helm チャートで `processor.enabled: true` を設定してください：チャートはキュー専用コンシューマーとして同じイメージをデプロイします（`TUIST_PROCESSOR_MODE=true`）。設定項目の完全な一覧については [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml) を参照してください。

> [!NOTE]
> `.xcresult` の解析は Xcode の `xcresulttool` に依存しているため、macOS でのみ実行できます。CLI はセルフホスト型デプロイメントに対してこれを透過的に処理します：`tuist test` は `tuist.dev` 以外のサーバーに対して **local** 処理モードにデフォルト設定され、開発者マシン（ビルド自体のために既に Xcode を備えている）で xcresult を解析し、構造化された結果をアップロードします。テスト結果は追加のインフラなしで取り込まれます。

### Docker イメージの取得 {#pulling-the-docker-image}

以下のコマンドを実行してイメージを取得できます：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

このイメージは `linux/amd64` と `linux/arm64` の両方向けに公開されているため、Docker はホストのネイティブ Linux アーキテクチャを自動的に選択します。

または特定のバージョンを取得します：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Docker イメージのデプロイ {#deploying-the-docker-image}

Docker イメージのデプロイプロセスは、選択したクラウドプロバイダーと組織の継続的デプロイアプローチによって異なります。[Kubernetes](https://kubernetes.io/) のようなほとんどのクラウドソリューションやツールは Docker イメージを基本単位として利用するため、このセクションの例は既存のセットアップによく適合するはずです。

> [!WARNING]
> デプロイパイプラインでサーバーが稼働中であることを検証する必要がある場合は、`GET` HTTP リクエストを `/ready` に送信し、レスポンスで `200` ステータスコードであることをアサートできます。


#### Fly {#fly}

アプリを [Fly](https://fly.io/) にデプロイするには、`fly.toml` 構成ファイルが必要です。継続的デプロイ（CD）パイプライン内で動的に生成することを検討してください。以下は参考用の例です：

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

その後、`fly launch --local-only --no-deploy` を実行してアプリを起動できます。以降のデプロイでは、`fly launch --local-only` を実行する代わりに `fly deploy --local-only` を実行する必要があります。Fly.io はプライベート Docker イメージのプルを許可していないため、`--local-only` フラグを使用する必要があります。


## Prometheus メトリクス {#prometheus-metrics}

Tuist はセルフホスト型インスタンスのモニタリングに役立つ Prometheus メトリクスを `/metrics` で公開しています。これらのメトリクスには以下が含まれます：

### Finch HTTP クライアントメトリクス {#finch-metrics}

Tuist は HTTP クライアントとして [Finch](https://github.com/sneako/finch) を使用し、HTTP リクエストに関する詳細なメトリクスを公開しています：

#### リクエストメトリクス
- `tuist_prom_ex_finch_request_count_total` - Finch リクエストの総数（カウンター）
  - ラベル：`finch_name`、`method`、`scheme`、`host`、`port`、`status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP リクエストの継続時間（ヒストグラム）
  - ラベル：`finch_name`、`method`、`scheme`、`host`、`port`、`status`
  - バケット：10ms、50ms、100ms、250ms、500ms、1s、2.5s、5s、10s
- `tuist_prom_ex_finch_request_exception_count_total` - Finch リクエスト例外の総数（カウンター）
  - ラベル：`finch_name`、`method`、`scheme`、`host`、`port`、`kind`、`reason`

#### 接続プールキューメトリクス
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 接続プールキューでの待機時間（ヒストグラム）
  - ラベル：`finch_name`、`scheme`、`host`、`port`、`pool`
  - バケット：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms、1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 使用されるまでの接続のアイドル時間（ヒストグラム）
  - ラベル：`finch_name`、`scheme`、`host`、`port`、`pool`
  - バケット：10ms、50ms、100ms、250ms、500ms、1s、5s、10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch キュー例外の総数（カウンター）
  - ラベル：`finch_name`、`scheme`、`host`、`port`、`kind`、`reason`

#### 接続メトリクス
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 接続確立にかかった時間（ヒストグラム）
  - ラベル：`finch_name`、`scheme`、`host`、`port`、`error`
  - バケット：10ms、50ms、100ms、250ms、500ms、1s、2.5s、5s
- `tuist_prom_ex_finch_connect_count_total` - 接続試行の総数（カウンター）
  - ラベル：`finch_name`、`scheme`、`host`、`port`

#### 送信メトリクス
- `tuist_prom_ex_finch_send_duration_milliseconds` - リクエスト送信にかかった時間（ヒストグラム）
  - ラベル：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - バケット：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms、1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 送信前の接続のアイドル時間（ヒストグラム）
  - ラベル：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - バケット：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms

すべてのヒストグラムメトリクスは、詳細な分析のために `_bucket`、`_sum`、および `_count` の変種を提供します。

### その他のメトリクス

Finch メトリクスに加えて、Tuist は以下のメトリクスを公開しています：
- BEAM 仮想マシンのパフォーマンス
- カスタムビジネスロジックメトリクス（ストレージ、アカウント、プロジェクトなど）
- データベースパフォーマンス（Tuist がホストするインフラストラクチャを使用する場合）

## 運用 {#operations}

Tuist は、インスタンスを管理するために使用できるユーティリティ群を `/ops/` で提供しています。

> [!WARNING]
> **認証**
>
> メールアドレスのドメインが `TUIST_OPERATOR_EMAIL_DOMAIN` （デフォルトは `tuist.dev`）と一致する確認済みユーザーのみが、`/ops/` エンドポイントにアクセスできます。


- **エラー（`/ops/errors`）：** アプリケーションで発生した予期しないエラーを表示できます。これはデバッグや問題の原因を理解するのに役立ちます。問題が発生している場合、この情報を共有していただくようお願いすることがあります。
- **ダッシュボード（`/ops/dashboard`）：** アプリケーションのパフォーマンスと健全性（メモリ消費量、実行中のプロセス、リクエスト数など）に関する洞察を提供するダッシュボードを表示できます。このダッシュボードは、使用中のハードウェアが負荷を処理するのに十分かどうかを理解するのに非常に役立ちます。
