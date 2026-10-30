---
{
  "title": "サーバー",
  "titleTemplate": ":title | セルフホスティング | サーバー | ガイド | Tuist",
  "description": "インフラストラクチャ上にTuistサーバーをデプロイする方法を学びます。"
}
---
# サーバー {#server}

インフラストラクチャの管理をより細かく制御したい組織向けに、Tuist サーバーのセルフホスティング版を提供しています。このバージョンでは、Tuist を独自のインフラストラクチャでホストでき、データの安全性とプライバシーを確保できます。

> [!WARNING]
> **ライセンスが必要**
>
> Tuist のセルフホスティングには、法的に有効な有料ライセンスが必要です。オンプレミス版の Tuist は、Enterprise プランの組織のみ利用できます。このバージョンにご興味がある場合は、[contact@tuist.dev](mailto:contact@tuist.dev) までお問い合わせください。

> [!WARNING]
> **レガシーキャッシュサービス**
>
> 従来のセルフホスティング型キャッシュノード技術は、新規インストールでは非推奨となりました。最新のセルフホスティング型キャッシュインフラストラクチャについては、<.localized_link href="/guides/features/cache/self-hosting">セルフホスティングキャッシュガイド</.localized_link> を参照してください。
>
> 既存のデプロイメントでは、GitHub の Markdown ビューアーでレガシーソースドキュメントを参照できます：[キャッシュノード](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/self-host.md) および [キャッシュアーキテクチャ](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/architecture.md)。

## リリースサイクル {#release-cadence}

Tuist サーバーと Kura キャッシュサーバーは、3 つの GHCR イメージチャネルを通じて提供されます：**canary**（`main` へのすべてのコミット）、**release candidate**（毎週月曜日にカットされ、1 週間ソーキング）、および **stable**（翌週月曜日に昇格）。stable リリースのみが `:latest` に移動し、デフォルトで解決されます。canary と release candidate は GitHub のプレリリースであり、タグをピン留めすることでオプトインします。サーバーと Kura は同じ週次リリーストラックに従い、[Tuist CLI のリリーススケジュール](/en/cli/release-channels) と連動しています。

予測可能なバージョニングと互換性を確保するため、[セマンティックバージョニング](https://semver.org/) に準拠しています。メジャーバージョンは、Tuist サーバーの破壊的変更を示すために使用され、セルフホスティングユーザーとの調整が必要になります。当社がこのコンポーネントを使用することは稀ですが、必要な場合には円滑な移行をサポートいたします。

各チャネルのカット方法、デプロイメントでのピン留め方法、本番環境を安定したリリースラインに維持しつつステージング環境で次のリリースをソーキングするための推奨戦略については、<.localized_link href="/guides/server/self-host/release-channels">リリースチャネル</.localized_link> ページをご覧ください。

## OAuth アップグレードとロールバックの境界 {#oauth-upgrade-and-rollback-boundary}

OAuth エンティティキャッシュの削除には、既存のインストールに対する段階的なアップグレードが必要です。OAuth キャッシュの無効化を停止するバージョンをデプロイする前に、まず [#14040](https://github.com/tuist/tuist/pull/14040) の権威読み取り互換リリースを **すべての OAuth 読み取り側および書き込み側** にデプロイしてください。この互換性ステージは **1.355** リリースラインで初めて登場します。`ghcr.io/tuist/tuist:1.355.0-rc.1` に含まれており、本番デプロイメントでは昇格後に安定した `1.355.x` リリースを使用すべきです。1.354 以前にインストールされている場合は、削除を含む後続のリリースにアップグレードする前にこのステージを完了する必要があります。1.355 ラインは互換性専用として維持し、無効化の削除をバックポートしないでください。

元の互換性コミットは `ghcr.io/tuist/tuist:sha-c8e54471a425` としても利用可能です。別のイメージが互換性ステージとして適しているのは、古いコンシューマーが残っている間、権威読み取りを保持し **レガシー無効化を維持** する場合に限られます。トラフィックを提供する前に、そのステージの通常のデータベースマイグレーション（リフレッシュトークンルックアップインデックスを含む）を実行してください。

各環境のすべての Web レプリカ、バックグラウンドワーカー、スケジュールされたジョブ、および個別にピン留めされたプロセッサーイメージを確認してください。互換性のロールアウトが完了するのを待ち、無効化を削除する前にキャッシュ読み取りバイナリが残っていないことを確認してください。自動アップグレード中に浮動イメージタグがこのステージをスキップしないようにしてください。古いコンシューマーのない新規インストールでは、中間デプロイメントは不要です。

> [!WARNING]
> **権威読み取りのロールバックターゲットを維持**
>
> 無効化が削除された後、通常のローリングロールバックは #14040 または別の権威読み取りバージョンをターゲットにする必要があります。すべての無効化なしプロセスが停止した後でも、保持された OAuth キャッシュエントリは古くなっている可能性があり、再起動されたキャッシュ読み取りレプリカがピアからそれらをインポートする可能性があります。
>
> さらにロールバックするには、**すべての** 無効化なし OAuth コンシューマーを停止してドレインし、キャッシュ読み取りコンシューマーを開始する前に **すべての** 保持された Boruta キャッシュ参加者をクリアまたは置き換える必要があります。保持された参加者の再参加を防いでください。イングレスのみをドレインするか、Web レプリカのみを再起動するのは不十分です。キャッシュのクリアやデータベースマイグレーションの自動ロールバックではなく、Tuist サポート連絡先と調整してこの復旧を行ってください。

## マルチレプリクラスターリング {#multi-replica-clustering}

サポートされているマルチレプリカ Web デプロイメントでは、認証の権限としてではなく、クロスレプリカの Phoenix PubSub および Oban PG 通知のために Erlang クラスタリングが必要です。`server.cluster.enabled` が false の場合、チャートは 1 つを超えるレプリカに成長できるオートスケーラーを含む複数のレプリカを拒否します。以前に承認された非クラスター化デプロイメントは、ガードを回避するのではなく、このアップグレードを計画する必要があります。メンバーシップを変更する前に、<.localized_link href="/guides/server/self-host/server#oauth-upgrade-and-rollback-boundary">OAuth アップグレードシーケンス</.localized_link>（無効化の削除を含む）を完了してください。

シークレットマネージャーを使用してリリース名前空間にプライベート Cookie シークレットを作成し、その名前とキーを設定します。

```yaml
server:
  replicaCount: 2
  cluster:
    enabled: true
    distributionPort: 9100
    cookieExistingSecret: tuist-server-cluster
    cookieExistingSecretKey: release-cookie
```

Cookie は高エントロピーである必要があり、参加するすべての Web レプリカで共有されます。公開イメージに埋め込まれた Cookie を決して使用しないでください。配布 Cookie を所持していると、そのノードでのリモート実行が可能になります。分散リリースの起動 now refuses a missing private `RELEASE_COOKIE` or an invalid port, including explicitly configured `RELEASE_DISTRIBUTION=name` or `sname` without DNS discovery. Non-chart deployments must also configure `TUIST_CLUSTER_DNS_SERVICE`, `TUIST_CLUSTER_APP_NAME` and the pod IP/node name consistently. Discovery currently uses IPv4 A records.

通常のサーバー接続 `helm upgrade` では、`cookieExistingSecret` を空のままにすると Cookie シークレットが作成され、後のアップグレードでその現在の値が再利用されます。オフライン `helm template`、Argo CD、およびライブシークレットルックアップのない他の GitOps レンダラーは、生成された値を保持できません。別途管理された安定したシークレットでバックアップされた `cookieExistingSecret` を使用する必要があります。ライブクラスターを暗黙的にローテーションするために Cookie キーを変更しないでください。Cookie のローテーションには、すべての参加者の調整されたマイグレーション/再起動が必要です。シークレットを更新するだけでは、既存のプロセスは更新されません。

イメージに焼き込まれた Cookie からの最初のロールアウトでは、すべての Web レプリカがプライベートシークレットを使用するまで、新旧のメンバーシップ島が分離されます。リアルタイム更新のための移行ウィンドウを計画してください。後続のローリングデプロイメントでは混合バージョンのクラスターが形成されるため、実際の新旧バージョン間で PubSub、Oban 通知、およびピア置換を検証してください。これらの通知は耐久性のある配信保証ではありません。互換性のあるバージョンへのロールバック時には、権威ある読み取りを行うロールバックイメージを保持し、同じプライベート Cookie を維持してください。

EPMD（TCP 4369）と設定された配布ポートは、信頼できるサーバーピア間でのみ許可し、テナントワークロードやパブリックネットワークからは決して許可しないでください。環境における実際のイングレス/エグレスの隔離を検証してください。NetworkPolicy をレンダリングしても、強制実行やバックエンドへの到達可能性が証明されるわけではありません。継続的な負荷下にある 2 レプリカのカナリアは、昇格前に結合、ローリング置換、および障害/回復を通過する必要があります。DNS はピアの発見に使用され、一時的な失敗や部分的な応答で健全なノードを切断するためには使用されません。実際のノード損失と OTP パーティション防止は依然として適用されます。libcluster は、接続を閉じずに保持コールバックに対して成功した「切断」操作をログに記録することがあります。そのログ行だけでなく、ノードのアップ/ダウンイベントや `Node.list()` から実際のメンバーシップを確立してください。

## 継続的デプロイメント {#continuous-deployment}

本番環境を安定したマイナーライン（例：`ghcr.io/tuist/tuist:1.351`）に固定し、日常のアップグレードではバックポートされた修正のみを提供することをお勧めします。安定したラインは、リリース候補チャネルでの 1 週間の浸透テストの後、毎週月曜日の 06:00 UTC に促進されます。カナリーまたは現在のリリース候補タグ上のステージング環境は、ユーザーに影響が出る前に回帰を検出します。推奨されるピン留め戦略については、<.localized_link href="/guides/server/self-host/release-channels">リリースチャネル</.localized_link>を参照してください。

マニフェストに触れることなく新機能が安定するたびに吸収したい場合は、`:latest` をピン留めしてください。このタグは月曜日の朝に週に 1 回移動するため、それに応じてデプロイウィンドウをスケジュールしてください。以下は、その頻度で最新の安定イメージをチェックしてデプロイする GitHub Actions ワークフローの例です。

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

セルフホストされたインストールでは、信頼できるネットワーク上の開発者がサインインせずにインサイトを提出したり、キャッシュを使用したり、あるいはその両方を行うことができます。ダッシュボードと管理には引き続き認証が必要です。

必要な機能のみを有効にしてください。

| サーバー環境変数 | サインインなしで許可 |
| --- | --- |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` | ビルドおよびテストのインサイトを提出 |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS=true` | キャッシュされたビルド出力の読み取りと書き込み |

両方の設定はデフォルトで**オフ**であり、独立しており、プライベートプロジェクトを含むすべてのアカウントとプロジェクトにインスタンス全体で適用されます。これらはホストされた Tuist では利用できず、セルフホスティングライセンスの代わりにはなりません。

以前の `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING` 名は、`TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` が設定されていない場合の互換性フォールバックとして残ります。

> [!WARNING]
> これらの設定は、強制された社内ネットワークまたは VPN の境界内でのみ有効にしてください。有効化されたエンドポイントに到達できる任何人は、レポートを提出したり、キャッシュアクセスが有効になっている場合はキャッシュされた出力を読み取って上書きしたりできます。これにより、偽造されたテレメトリ、キャッシュポイズニング、および容量枯渇が可能になります。レポートの応答は、プライベートプロジェクトのハンドルやビルドシステムを公開する可能性もあります。Tuist は VPN メンバーシップを検証せず、転送された IP ヘッダーをメンバーシップの証明として信頼しません。

### インスタンスの設定 {#network-trusted-instance-configuration}

1. ファイアウォールまたはプライベートイングレスを使用して、Tuist サーバー、すべての Kura HTTP/gRPC リスナー、および Bazel BES イングレスを信頼できるネットワークに制限してください。
2. クライアントをアップグレードする前に、すべてのサーバーと Kura レプリカをアップグレードしてください。`KURA_AUTH_TUIST_URL` とそのコントロールプレーンの資格情報を使用して Kura 認証を有効にしたままにしてください。これを無効にすると、これらの制限を回避します。キャッシュエンドポイントは、<.localized_link href="/guides/features/cache/self-hosting">セルフホストキャッシュガイド</.localized_link>を使用して設定してください。
3. 上記の希望する変数を関連するすべての Tuist サーバーレプリカに設定し、再起動または再デプロイしてください。正確な値 `true` のみが設定を有効にします。ダッシュボードのトグルや個別の Kura フラグはありません。

### クライアントの設定 {#network-trusted-client-configuration}

各互換性のあるクライアントで、最終的なセルフホストサーバー URL とプロジェクトを設定してください。クライアントは、資格情報がない場合にどの機能が有効になっているかを自動的に検出します。クライアント側のオプトインは不要です。検出はリダイレクトに従いません。既存の資格情報は引き続き使用され、無効または更新に失敗した資格情報は匿名フォールバックではなくエラーを引き起こします。回復するには、再度サインインするか、明示的にサインアウトしてください。

インサイトアクセスを有効にする前に、資格情報を共有するすべてのツールを、破損または拒否された資格情報を保持し、読み取り不可能な資格情報ディレクトリを拒否し、署名されていないレポートから Git 起源を省略するバージョンにアップグレードしてください。古いツールは資格情報を削除し、意図せず匿名フォールバックを許可する可能性があります。サーバーだけのアップグレードではこれを修正できません。サーバーに検出サポートがない場合、または古いバージョンにロールバックされた場合、クライアントは認証する必要があります。以前の `TUIST_NETWORK_TRUSTED_PUBLISHING` クライアント設定はもう適用されません。

- **インサイト：** アーカイブ、添付ファイル、カバレッジ、シャード計画、または既存のレポートアクセスなしで、完了した Xcode、Gradle、Elixir/Mix、および Bazel レポートのみを提出してください。アクターの主張は未検証です。署名されていないテレメトリは、信頼されたテスト証拠や自動化を駆動しません。クライアントの設定とプライバシーの詳細については、<.localized_link href="/guides/features/build-insights/xcode#network-trusted-publishing">Xcode</.localized_link>、<.localized_link href="/guides/features/build-insights/gradle#network-trusted-publishing">Gradle</.localized_link>、および <.localized_link href="/guides/features/build-insights/elixir#network-trusted-publishing">Elixir</.localized_link> ガイドを参照してください。
- **キャッシュ：** CLI コンパレーション/モジュールキャッシング、Bazel キャッシング、および Gradle タスクキャッシングをサポートしています。キャッシュのパージとリモートアセットのダウンロードには引き続き資格情報が必要です。サポートのないクライアントは認証を続ける必要があります。
- **Bazel：** レポートには明示的な `TUIST_BAZEL_BES_BACKEND` と互換性のある Kura が必要です。キャッシュとレポートのオプションは独立して有効になります。資格情報またはいずれかの設定を変更した後は `tuist bazel setup` を再実行し、コンパレーションキャッシュの設定変更には `tuist cache config` を再実行してください。

レポートリクエストは、プロジェクトあたり 8 MB、1 分あたり 60 リクエスト、1 日あたり 10,000 リクエストに制限されています。複数のレプリカを持つデプロイメント全体のクォータには共有 Valkey を構成してください。そうでない場合、制限はプロセスごとになります。構成された共有クォータバックエンドが利用できない場合、署名されていないレポートは拒否されます。イングレス接続、ボディ、およびレート制限も追加してください。

### ネットワーク信頼アクセスの無効化 {#disable-network-trusted-publishing}

関連する変数を `false` に設定し、**該当するすべてのサーバーレプリカ** を再起動してください。古いレプリカは、置き換えられるまで資格情報不要のリクエストを受け入れ続けることができます。最後のレプリカの切り替え後 60 秒以内に、新しいリクエストに対するキャッシュアクセスが停止します。進行中の転送はキャンセルされません。即時の取り消しが必要な場合は、まずイングレスでトラフィックをブロックしてください。既存のレポートは通常の可視性と保持期間を維持し、認証済みクライアントは引き続き動作します。

## ランタイム要件 {#runtime-requirements}

このセクションでは、インフラストラクチャ上で Tuist サーバーをホストするための要件について説明します。

### 互換性マトリクス {#compatibility-matrix}

Tuist サーバーはテスト済みであり、以下の最小バージョンと互換性があります:

| コンポーネント | 最小バージョン | 注記 |
| --- | --- | --- |
| PostgreSQL | 15 | |
| ClickHouse | {{minimum_supported_clickhouse_version}} | アナリティクスに必要 |

### Docker 仮想化イメージの実行 {#running-dockervirtualized-images}

サーバーは [Docker](https://www.docker.com/) イメージとして [GitHub の Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) を介して配布されています。

実行するには、インフラストラクチャが Docker イメージの実行をサポートしている必要があります。ほとんどのインフラストラクチャプロバイダーはこれをサポートしています。これは、本番環境でソフトウェアを配布および実行するための標準的なコンテナとなっているためです。

### Postgres データベース {#postgres-database}

Docker イメージの実行に加えて、リレーショナルデータを保存するために [Postgres データベース](https://www.postgresql.org/) が必要です。ほとんどのインフラストラクチャプロバイダーは、オファリングに Postgres データベースを含めています（例: [AWS](https://aws.amazon.com/rds/postgresql/) および [Google Cloud](https://cloud.google.com/sql/docs/postgres)）。

> [!NOTE]
> **マイグレーション**
>
> Docker イメージのエントリーポイントは、サービスを開始する前に、保留中のスキーママイグレーションを自動的に実行します。


### ClickHouse データベース {#clickhouse-database}

Tuist は、大量のアナリティクスデータの保存とクエリに [ClickHouse](https://clickhouse.com/) を使用します。ビルドインサイトなどの機能には ClickHouse が **必要** です。ClickHouse をセルフホストするか、ホスト型サービスを使用するかを選択できます。

> [!NOTE]
> **マイグレーション**
>
> Docker イメージのエントリーポイントは、サービスを開始する前に、保留中の ClickHouse スキーママイグレーションを自動的に実行します。

バンドルされた Docker Compose および Helm 組み込みの ClickHouse 構成は、ClickHouse のテキストログレベルをイメージの `trace` デフォルトから `information` に下げます。これは、`system.text_log` ボリュームの大部分が発生する場所です。また、どちらも ClickHouse 独自の `system.*` 運用ログテーブルに上限を設定できます。これらは通常無制限ですが、デフォルトではオフになっています（下記参照）。外部 ClickHouse デプロイメントでは、これらの運用ログを ClickHouse サービスで直接構成する必要があります。

#### ClickHouse レプリケーショントポロジ {#clickhouse-replication-topology}

Tuist の背後にあるマルチレプリカ ClickHouse は、ClickHouse Cloud でのみサポートされています。セルフマネージド ClickHouse はシングルレプリカです。

インジェストマイグレーションはプレーンな `MergeTree` エンジンを出力します。Cloud では、これが透過的に `SharedMergeTree` になるため、書き込みは共有オブジェクトストレージに保存され、任意のレプリカ数で動作します。セルフマネージド ClickHouse では、`MergeTree` は 1 つのレプリカのローカルディスクにのみ書き込みます。マルチレプリカセットアップでは、レプリカ間でサイレントにインジェストが分割されるか、`UNKNOWN_STORAGE: Only tables with a Replicated engine or tables which do not store data on disk are allowed in a Replicated database.` で CREATE が拒否されます。これは、接続ユーザーに対して `database_replicated_allow_only_replicated_engine` がどのように設定されているかによります。

セルフマネージド ClickHouse では、1 つのシャードを 1 つのレプリカで実行し、ClickHouse データディレクトリの定期的なバックアップを取得してください。ノードが失われた場合、フォールバックするための 2 番目のレプリカはありません。

#### 運用ログの保持期間の制限 {#capping-operational-log-retention}

保持期間は `system.text_log`、`system.query_log`、`system.query_thread_log`、`system.query_views_log`、`system.trace_log`、`system.metric_log`、`system.asynchronous_metric_log`、および `system.part_log` に適用できます。

有効化は、すでにデータがあるインスタンスに対する一度きりの一方向のステップであるため、どちらのバンドルもこれを行いません。保持期間ウィンドウを設定すると、これらのテーブル定義が構成と一致しなくなるため、ClickHouse はそれぞれをリネームして aside に移動し、[廃止されたログテーブル](#superseded-log-tables) で説明されているように新しいテーブルを開始します。取り残された世代はこれまで蓄積されたすべてを保持し、独自の保持期間を持ちません。したがって、同じステップでそれを回収しない限り、それは永久にディスク上に残り、新しいウィンドウはそれ以降に書き込まれた行のみを制限します。両方を同時に有効にします:

```yaml
clickhouse:
  embedded:
    systemLogs:
      ttlDays: 14
      supersededTables: delete
```

その単一の `helm upgrade` は自己完結型です。`ttlDays` を空白から設定値に変更すると、ドロップインマウントが追加され、ClickHouse ポッドがロールアウトされるためです。ポッドは再起動し、テーブルを廃止し、アップグレード後のジョブがそれらを削除します。`helm upgrade --wait` でデプロイして、ジョブが実行される前にポッドがロールアウトされるようにしてください。そうしないと、ジョブが確認した後に世代が表示され、次の `helm upgrade` で代わりにそれらが回収されます。

Docker Compose を使用する場合、`docker-compose.yml` の `clickhouse` サービス上の `clickhouse-log-ttl.xml` ボリュームをコメント解除し、`.env` で両方の変数を設定します:

```bash
CLICKHOUSE_SYSTEM_LOG_TTL_DAYS=14
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

スペースが回収されたら、`supersededTables`/`CLICKHOUSE_SUPERSEDED_LOG_TABLES` を `ignore` に戻すことができます。これにより、後の ClickHouse アップグレードが独自に履歴を破棄することを防ぎます。

#### 廃止されたログテーブル {#superseded-log-tables}

ClickHouse は起動時に、各システムログテーブルが依然として構成と一致しているかどうかを確認します。一致しない場合、既存のテーブルを `system.<name>_0`、次に `_1`、`_2` などにリネームし、新しいテーブルを開始します。これは、保持期間ウィンドウを変更したとき、またはシステムログスキーマを変更する ClickHouse アップグレード時に発生します。

テーブルのリネームはデータをコピーしないため、追加のディスク容量を消費しません。廃止されたテーブルにその後何が起こるかは、元のテーブルによって異なります。廃止された瞬間にライブテーブルが持っていた保持期間を維持するためです。初めて保持期間を有効にしたとき、廃止されるテーブルには保持期間がないため、これまで蓄積されたすべての履歴を保持し、無期限に保持します。ウィンドウへの後続の変更は、すでに TTL を持つテーブルを廃止するため、それらは独自に期限切れになり、空のテーブルを残します。ClickHouse はテーブル自体を削除することはないため、長寿命のインスタンスではいずれにしても蓄積されます。

廃止されたテーブルはデフォルトで保持されるため、アップグレードが独自に運用履歴を破棄することはありません。代わりにそれらを削除するには、ポリシーを `delete` に設定します。これは `docker compose up` および各 `helm upgrade` で発生します:

```bash
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

Helm チャートでは、同じポリシーを値として構成します:

```yaml
clickhouse:
  embedded:
    systemLogs:
      supersededTables: delete
```

廃止されたテーブルを削除すると、そのディスクスペースが回収されます。ライブテーブルには決して触れられず、廃止されてから書き込まれた行にも触れられません。

ポリシーを変更せずに一度だけスペースを回収するには、手動でテーブルを削除します:

```sql
SELECT name FROM system.tables WHERE database = 'system' AND match(name, '_log_[0-9]+$');
DROP TABLE IF EXISTS system.text_log_0 SYNC;
```

`system` データベースは `Atomic` エンジンを使用しており、通常の `DROP TABLE` を `database_atomic_delay_before_drop_table_sec` （デフォルトでは8分）だけ延期します。`SYNC` はデータを直ちに削除するため、ディスクがいっぱいになってこれらのテーブルを削除する際に適しています。


### ストレージ {#storage}

ファイル（フレームワークやライブラリのバイナリなど）を保存するためのソリューションも必要です。Tuist サーバーは、サーバー所有のアーティファクト向けに S3 互換ストレージと Azure Blob Storage をサポートしています。

> [!TIP]
> **最適化されたキャッシング**
>
> 主な目的がキャッシュレイテンシの削減である場合、サーバー全体をセルフホストする必要はないかもしれません。CI や開発者ネットワークの近くにセルフホスト型 Kura ノードをデプロイし、ホスト型 Tuist サーバーまたはセルフホスト型サーバーに接続することができます。
>
> <.localized_link href="/guides/cache/self-host">セルフホスト型キャッシュガイド</.localized_link> を参照してください。


### セルフホスト型 Kura ノード {#self-hosted-cache-nodes}

セルフホスト型 Tuist サーバーでセルフホスト型 Kura ノードを使用するには:

1. Tuist サーバーで `KURA_CONTROL_PLANE_CLIENT_ID` と `KURA_CONTROL_PLANE_CLIENT_SECRET` を構成します。クライアント ID **は UUID でなければなりません**。<.localized_link href="/guides/cache/self-host#control-plane-client">セルフホスト型キャッシュガイド</.localized_link> に記載されているコマンドを使用して UUID とランダムなシークレットを生成し、デプロイメントのシークレットに保存してください。
2. 同じコントロールプレーンの認証情報を使用して、<.localized_link href="/guides/cache/self-host">セルフホスト型キャッシュガイド</.localized_link> に従って Kura ノードをデプロイします。
3. 各 Kura ノードを `KURA_REGISTRATION_URL` と `KURA_ADVERTISED_HTTP_URL` で構成します。登録用のハートビートにより、サーバーは CLI に広告できる準備完了のクライアント向け Kura エンドポイントを識別します。

## 構成 {#configuration}

サービスの構成は、環境変数を通じて実行時に行われます。これらの変数は機密性が高いため、暗号化して安全なパスワード管理ソリューションに保存することを推奨します。Tuist はこれらの変数を細心の注意を払って扱い、ログに表示されないようにしています。

> [!NOTE]
> **起動時のチェック**
>
> 必要な変数は起動時に検証されます。不足しているものがある場合、起動は失敗し、エラーメッセージに欠落している変数が詳細に表示されます。


### ライセンス構成 {#license-configuration}

オンプレミスユーザーとして、環境変数として公開する必要があるライセンスを受け取ります。このライセンスは、デプロイメントを検証し、サービスが契約条件の範囲内で実行されていることを確認するために使用されます。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | サービスレベル契約締結後に提供されるライセンス。標準のライセンスキー、またはサーバーが外部サービスに接続できないエアギャップ環境で使用される base64 エンコードされた証明書のいずれかを受け入れます。 | はい | | `******` |

> [!WARNING]
> **有効期限**
>
> ライセンスには有効期限があります。ライセンスの有効期限が30日未満の場合、サーバーと対話する Tuist コマンドを使用している間に警告が表示されます。ライセンスの更新をご希望の場合は、[contact@tuist.dev](mailto:contact@tuist.dev) までご連絡ください。


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
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 自動 PR コメント投稿などの追加機能を有効にするために GitHub アプリで使用される base64 エンコードされた秘密鍵 | いいえ | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` | |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | 自動 PR コメント投稿などの追加機能を有効にするために GitHub アプリで使用される秘密鍵。**特殊文字の問題を避けるため、base64 エンコードされたバージョンの使用を推奨します** | いいえ | `-----BEGIN RSA...` | |
| `TUIST_OPERATOR_EMAIL_DOMAIN` | メールアドレスが `@<this-domain>` で終わる確認済みユーザーは、運用用 URL（`/ops/*`）にアクセスできます | いいえ | `tuist.dev` | `example.com` |
| `TUIST_SERVER_VERSION_IDENTIFIER` | サーバーインスタンスを識別するためにダッシュボードのナビゲーションバーにバッジとして表示されるラベル（例：バージョン番号またはブランチ名） | いいえ | 開発環境での Git ブランチ | `v1.2.3` |
| `TUIST_WEB` | Web サーバーのエンドポイントを有効にする | いいえ | `1` | `1` または `0` |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` | サインインなしでビルドおよびテストのインサイトを送信できるようにします。セットアップとセキュリティ要件については [ネットワーク信頼アクセス](#network-trusted-access) を参照してください。 | いいえ | `false` | `true` |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS` | サインインなしでキャッシュの読み取りと書き込みを許可します。セットアップとセキュリティ要件については [ネットワーク信頼アクセス](#network-trusted-access) を参照してください。 | いいえ | `false` | `true` |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | トレースを送信する OpenTelemetry Collector の gRPC エンドポイント | いいえ | | `http://localhost:4317` |
| `TUIST_LOKI_URL` | ログをプッシュする Loki 互換エンドポイントのベース URL（例：Grafana Alloy または Loki） | いいえ | | `http://localhost:3100` |

> [!WARNING]
> **アプリを HTTPS で提供**
>
> セッション Cookie には `Secure` フラグが設定されているため、プレーンな `http://` ではブラウザがこれらを破棄し、ユーザーはサインインできません。サーバーの前段で TLS を終端させ（内部 CA の証明書を使用したリバースプロキシで十分）、内部または VPN 限定のデプロイメントであっても `TUIST_APP_URL` を `https://` URL に設定してください。

### データベース構成 {#database-configuration}

以下の環境変数はデータベース接続の構成に使用されます。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | Postgres データベースにアクセスするための URL。URL には認証情報を含める必要があることに注意してください | はい | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_SCHEMA` | Tuist のアプリケーションテーブルで使用される PostgreSQL スキーマ。データベースポリシーで `public` スキーマの使用が許可されていない場合に設定してください。スキーマ名は引用符なしの PostgreSQL 識別子である必要があります。 | いいえ | `public` | `tuist` |
| `TUIST_MIGRATION_DATABASE_URL` | `Tuist.Release.migrate` によってのみ使用されるオプションの Postgres URL。`DATABASE_URL` がより制限されたランタイムロールを指している場合、所有者ロールの URL に設定してください。 | いいえ | `DATABASE_URL` | `postgres://owner:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_RUNTIME_ROLE` | 移行完了後にアプリケーションテーブルの権限を付与すべきランタイム Postgres ロール。Web サーバーがスキーマ所有者として接続すべきでない場合は、`TUIST_MIGRATION_DATABASE_URL` と併用してください。 | いいえ | | `tuist_web` |
| `TUIST_CLICKHOUSE_URL` | ClickHouse データベースにアクセスするための URL。URL には認証情報を含める必要があることに注意してください | いいえ | | `http://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | true の場合、データベースへの接続に [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) を使用します | いいえ | `1` | `1` |
| `TUIST_DATABASE_POOL_SIZE` | コネクションプールで開いたまま維持する接続数 | いいえ | `10` | `10` |
| `TUIST_DATABASE_QUEUE_TARGET` | プールからチェックアウトされたすべての接続がキュー間隔を超えたかどうかを確認する間隔（ミリ秒）[（詳細情報）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | いいえ | `300` | `300` |
| `TUIST_DATABASE_QUEUE_INTERVAL` | プールが新しい接続のドロップを開始すべきかどうかを判断するために使用するキュー内のしきい値時間（ミリ秒）[（詳細情報）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | いいえ | `1000` | `1000` |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse バッシャーフラッシュ間の時間間隔（ミリ秒） | いいえ | `5000` | `5000` |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE` | 強制フラッシュ前の最大 ClickHouse バッファサイズ（バイト） | いいえ | `1000000` | `1000000` |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE` | 実行する ClickHouse バッファプロセスの数 | いいえ | `5` | `5` |

`TUIST_DATABASE_SCHEMA` が `public` ではない場合、リリース移行は Ecto 移行チェーンを実行する前に、スキーマが存在しなければ作成します。移行ロールがスキーマを作成できない場合は、事前にスキーマを作成し、移行ロールをその所有者にしてください。

Tuist はセッション `search_path` を設定することで、接続をカスタムスキーマに向けます。一部のプールまたはプロキシ経由の Postgres 構成（例えば PgBouncer や、起動パラメータを制限するマネージドデータベース）ではこれが適用されず、セッションは `public` にフォールバックします。これは移行中に `permission denied for schema public` として表面化します。このような構成を通じて接続する場合は、プロキシに関係なくすべてのセッションがそこで開始されるよう、ロール自体にスキーマを固定してください：

```sql
CREATE SCHEMA IF NOT EXISTS tuist AUTHORIZATION <migration_role>;
ALTER ROLE <migration_role> IN DATABASE <database> SET search_path = tuist;
-- If the web server connects as a separate runtime role (TUIST_DATABASE_RUNTIME_ROLE):
ALTER ROLE <runtime_role> IN DATABASE <database> SET search_path = tuist;
```

### 認証環境構成 {#authentication-environment-configuration}

[アイデンティティプロバイダー（IdP）](https://en.wikipedia.org/wiki/Identity_provider) を介した認証をサポートしています。これを利用するには、選択したプロバイダーに必要なすべての環境変数がサーバー環境に存在することを確認してください。**変数が欠落している**場合、Tuist はそのプロバイダーを bypass します。

#### メールとパスワード {#email-and-password}

メールとパスワードによるサインインおよびセルフサービス登録は組み込まれており、デフォルトで有効です。アイデンティティプロバイダーを必須にしたいインスタンス（例えば SSO を強制する場合）では、これらを完全に無効にできます。これにより、ログイン体験からメール/パスワードフォーム、サインアップリンク、パスワードリセットフローが削除され、CLI が使用するメール/パスワードエンドポイント（`tuist auth`）を含む、一致するすべてのサーバーサイドエンドポイントが閉じられます。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_EMAIL_AUTH_ENABLED` | メールとパスワードを使用してサインインおよび登録できるかどうか。ログインページからメール/パスワードフォーム、サインアップリンク、パスワードリセットフローを削除し、一致するサーバーサイドエンドポイントを閉じるには `0` に設定してください | いいえ | `1` | `0` |

#### 構成済みアイデンティティプロバイダーの無効化 {#disabling-a-configured-identity-provider}

デフォルトでは、プロバイダーは構成されるとサインインオプションとして表示されます。プロバイダーを構成されたままにし（認証情報は設定された状態）、ログインおよびサインアップページから削除するには、対応するレバーを `0` に設定してください。GitHub、Google、Apple の場合、これによりサインインコールバックも閉じられるため、この方法はエンドツーエンドで利用できなくなります。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_AUTH_ENABLED` | GitHub を使用してサインインできるかどうか（アプリがなぜサインインと認証情報を共有するかについては [GitHub](#github) セクションを参照） | いいえ | `1` | `0` |
| `TUIST_GOOGLE_AUTH_ENABLED` | Google を使用してサインインできるかどうか | いいえ | `1` | `0` |
| `TUIST_OKTA_AUTH_ENABLED` | 構成済みの Okta プロバイダーがサインインオプションとして表示されるかどうか | いいえ | `1` | `0` |
| `TUIST_APPLE_AUTH_ENABLED` | Apple を使用してサインインできるかどうか | いいえ | `1` | `0` |

#### GitHub {#github}

[GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) を使用した認証を推奨しますが、[OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app) も利用できます。サーバー環境に GitHub が指定するすべての必須環境変数を含めてください。変数が欠落していると、Tuist は GitHub 認証を無視します。GitHub アプリを正しく設定するには：
- GitHub アプリの一般設定で：
    - `Client ID` をコピーし、`TUIST_GITHUB_APP_CLIENT_ID` として設定します
    - 新しい `client secret` を作成してコピーし、`TUIST_GITHUB_APP_CLIENT_SECRET` として設定します
    - `Callback URL` を `http://YOUR_APP_URL/users/auth/github/callback` に設定します。`YOUR_APP_URL` にはサーバーの IP アドレスも指定できます。
- 以下の権限が必要です：
  - リポジトリ：
    - プルリクエスト：読み取りと書き込み
  - アカウント：
    - メールアドレス：読み取り専用

`Permissions and events` の `Account permissions` セクションで、`Email addresses` 権限を `Read-only` に設定します。

次に、Tuist サーバーが実行される環境で以下の環境変数を公開する必要があります：

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub アプリケーションのクライアント ID | はい | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | アプリケーションのクライアントシークレット | はい | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_AUTH_ENABLED` | GitHub を使用してサインインできるかどうか。プラットフォーム統合（PR コメントなど）用に構成した GitHub App は、サインインとクライアント認証情報を共有するため、それ以外の場合はログインオプションとして表示されます。App を維持しつつログインページから GitHub を削除するには `0` に設定してください | いいえ | `1` | `0` |

#### Google {#google}

[OAuth 2](https://developers.google.com/identity/protocols/oauth2) を使用して Google での認証を設定できます。そのためには、OAuth クライアント ID タイプの新しい認証情報を作成する必要があります。認証情報を作成する際は、アプリケーションタイプとして「Web アプリケーション」を選択し、名前を `Tuist` に設定し、リダイレクト URI を `{base_url}/users/auth/google/callback` に設定します。ここで `base_url` はホストされているサービスが実行されている URL です。アプリを作成したら、クライアント ID とシークレットをコピーし、それぞれ環境変数 `GOOGLE_CLIENT_ID` および `GOOGLE_CLIENT_SECRET` として設定します。

> [!NOTE]
> **同意画面のスコープ**
>
> 同意画面を作成する必要がある場合があります。その際は、`userinfo.email` および `openid` スコープを追加し、アプリを内部用としてマークしてください。


#### Okta {#okta}

[OAuth 2.0](https://oauth.net/2/) プロトコルを使用して Okta での認証を有効にできます。Okta で [アプリを作成](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)し、<.localized_link href="/guides/integrations/authentication/sso#okta">この手順</.localized_link>に従ってください。

Okta アプリケーションのセットアップ中にクライアント ID とシークレットを取得したら、以下の環境変数を設定する必要があります：

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID` | Okta に対して認証するためのクライアント ID。数値は組織 ID にする必要があります | はい | | |
| `TUIST_OKTA_1_CLIENT_SECRET` | Okta に対して認証するためのクライアントシークレット | はい | | |

数値 `1` は組織 ID に置き換える必要があります。通常は 1 ですが、データベースで確認してください。

### ストレージ環境の構成 {#storage-environment-configuration}

 Tuist は、API を介してアップロードされたアーティファクトを保存するためにストレージを必要とします。Tuist が効果的に動作するためには、**サポートされているストレージソリューションのいずれかを構成することが不可欠**です。

サーバーアーティファクトのバックエンドを選択するには `TUIST_OBJECT_STORAGE_PROVIDER` を設定します：

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_OBJECT_STORAGE_PROVIDER` | サーバーアーティファクトのストレージバックエンド。S3 互換ストレージには `s3` を、Azure Blob Storage には `azure_blob` を使用します | いいえ | `s3` | `azure_blob` |

#### S3 準拠のストレージ {#s3compliant-storages}

アーティファクトの保存には、S3 準拠の任意のストレージプロバイダーを使用できます。ストレージプロバイダーとの統合を認証および構成するには、以下の環境変数が必要です：

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
> ストレージプロバイダーが AWS で、Web ID トークンを使用して認証したい場合は、環境変数 `TUIST_S3_AUTHENTICATION_METHOD` を `aws_web_identity_token_from_env_vars` に設定できます。Tuist は従来の AWS 環境変数を使用してその方法を利用します。


#### Google Cloud Storage {#google-cloud-storage}
Google Cloud Storage の場合、[このドキュメント](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)に従って `AWS_ACCESS_KEY_ID` と `AWS_SECRET_ACCESS_KEY` のペアを取得してください。`AWS_ENDPOINT` は `https://storage.googleapis.com` に設定する必要があります。他の環境変数は、他の S3 準拠ストレージと同じです。

#### Azure Blob Storage {#azure-blob-storage}

Azure Blob Storage の場合、`TUIST_OBJECT_STORAGE_PROVIDER=azure_blob` を設定し、Azure ストレージアカウントの認証情報を構成します：

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_AZURE_STORAGE_ACCOUNT_NAME` | Azure ストレージアカウント名 | はい | | `tuiststorage` |
| `TUIST_AZURE_STORAGE_ACCOUNT_KEY` | Azure Blob REST リクエストと SAS URL に署名するために使用されるストレージアカウントのアクセスキー | はい | | `******` |
| `TUIST_AZURE_BLOB_CONTAINER_NAME` | サーバーアーティファクトが保存されるコンテナー | はい | | `tuist-artifacts` |
| `TUIST_AZURE_BLOB_ENDPOINT` | Blob サービスのエンドポイント。省略すると `https://<account>.blob.core.windows.net` が使用されます | いいえ | アカウント名から派生 | `https://tuiststorage.blob.core.windows.net` |
| `TUIST_AZURE_BLOB_SERVICE_VERSION` | 署名付きリクエストと SAS URL に使用される Azure Blob REST API バージョン | いいえ | `2020-12-06` | `2020-12-06` |

Helm チャートを使用する場合は、`server.storage.provider=azure_blob` を設定し、`server.azureBlob.*` を入力してください。チャートのトップレベルの `objectStorage` 設定は S3 互換のままです。これは、オプションのキャッシュおよびレジストリミラーのワークロードが引き続き S3 互換ストレージを想定しているためです。これらのワークロードが無効でサーバーが Azure Blob を使用する場合は、`objectStorage.mode=external` を設定し、外部オブジェクトストレージのエンドポイントと認証情報を空にして、埋め込み MinIO サービスのデプロイを回避してください。

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

Helm チャートを使用する場合、同じウィンドウをマップとして構成します：

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

6つのキーはすべて任意です。この例では、すべてのサポートされているアーティファクトタイプを独立した保持ウィンドウで有効にします。キーを省略するか、その値を空白のままにすると、そのアーティファクトタイプのクリーンアップは無効のままになります。セルフホストの保持ウィンドウには30日の最大値はありません。正の整数ではない設定値の場合、サーバーは起動時に失敗します。

保持変数を変更した後、サーバーを再起動してください。キューに入れられたセルフホストのクリーンアップバッチはすべて、ファイルを削除する前に現在の構成を確認するため、変数の設定解除や空白化、またはそのウィンドウの増加は、再起動後の保留中のジョブからもファイルを保護します。

| 環境変数 | オブジェクトストレージから削除されるアーティファクトファイル |
| --- | --- |
| `TUIST_CACHE_ARTIFACT_RETENTION_DAYS` | Xcode キャッシュ、レガシーコンテンツアドレス可能ストレージキャッシュ、モジュールキャッシュ、および Gradle キャッシュファイル |
| `TUIST_APP_PREVIEW_RETENTION_DAYS` | アプリプレビューのビルドとアイコン |
| `TUIST_BUILD_ARCHIVE_RETENTION_DAYS` | 現在およびレガシーのビルドアーカイブ |
| `TUIST_RUN_ARTIFACT_RETENTION_DAYS` | 期限切れの実行のアーティファクトプレフィックスの下に保存されているすべてのオブジェクト（結果バンドル、呼び出し記録、セッションアーカイブを含む） |
| `TUIST_TEST_ATTACHMENT_RETENTION_DAYS` | テスト実行の添付ファイル |
| `TUIST_SHARD_BUNDLE_RETENTION_DAYS` | テストシャードバンドル |

スケジュールされたクリーンアップはアーティファクトブロブのみを削除します。対応する PostgreSQL および ClickHouse の行は保持されるため、ダウンロードの有効期限が切れた後でも、ビルド、テスト、実行、プレビュー、およびシャードのメタデータはダッシュボードで表示され続けます。この構成は ClickHouse テーブルの保持ルールを変更しません。

### メール構成 {#email-configuration}

Tuist は、ユーザー認証とトランザクション通知（パスワードのリセット、アカウント通知など）のためにメール機能を必要とします。現在、メールプロバイダーとして **Mailgun のみがサポートされています**。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_MAILGUN_API_KEY` | Mailgun で認証するための API キー | はい* | | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN` | メール送信元のドメイン | はい* | | `mg.tuist.io` |
| `TUIST_MAILING_FROM_ADDRESS` | 「From」フィールドに表示されるメールアドレス | はい* | | `noreply@tuist.io` |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | ユーザーからの返信用のオプションの返信先アドレス | いいえ | | `support@tuist.dev` |
| `TUIST_SKIP_EMAIL_CONFIRMATION` | 新規ユーザー登録時のメール確認をスキップします。有効にすると、ユーザーは自動的に確認され、登録直後にログインできます | いいえ | メールが構成されていない場合は `true`、メールが構成されている場合は `false` | `true`, `false`, `1`, `0` |

\* メール構成変数は、メールを送信したい場合にのみ必要です。構成されていない場合、メール確認は自動的にスキップされます

> [!NOTE]
> **SMTP サポート**
>
> 汎用的な SMTP サポートは現在利用できません。オンプレミスデプロイメントで SMTP サポートが必要な場合は、[contact@tuist.dev](mailto:contact@tuist.dev) までご連絡いただき、要件についてご相談ください。


> [!NOTE]
> **エアギャップデプロイメント**
>
> インターネットアクセスやメールプロバイダーの構成がないオンプレミスインストールの場合、メール確認はデフォルトで自動的にスキップされます。ユーザーは登録直後にログインできます。メールが構成されているにもかかわらず確認をスキップしたい場合は、`TUIST_SKIP_EMAIL_CONFIRMATION=true` を設定してください。メールが構成されている場合にメール確認を必須にするには、`TUIST_SKIP_EMAIL_CONFIRMATION=false` を設定してください。


### Git プラットフォームの構成 {#git-platform-configuration}

Tuist は <.localized_link href="/guides/server/authentication">Git プラットフォームと統合</.localized_link> でき、プルリクエストへのコメントの自動投稿などの追加機能を提供します。

#### GitHub {#platform-github}

セルフホスト型の Tuist サーバーでは、`https://tuist.dev` で動作する GitHub App をインストールできません。GitHub App は登録したサーバーに紐付けられるため、あなたのデプロイメントには github.com 上で独自の App が必要です。

##### App の登録 {#platform-github-registering-the-app}

[GitHub App を作成し](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)、あなたの GitHub 組織が所有するようにします。OAuth App を作成した場合を除き、認証用に作成した App を再利用できます。以下のように構成し、`YOUR_APP_URL` を `TUIST_APP_URL` の値に置き換えてください。

| 設定 | 値 |
| --- | --- |
| コールバック URL | `YOUR_APP_URL/users/auth/github/callback` および `YOUR_APP_URL/integrations/github/authorize` |
| セットアップ URL | `YOUR_APP_URL/integrations/github/setup` |
| 更新時のリダイレクト | 有効 |
| Webhook URL | `YOUR_APP_URL/webhooks/github` |
| Webhook シークレット | 任意のランダムな文字列。`TUIST_GITHUB_APP_WEBHOOK_SECRET` として設定します |

以下のリポジトリ権限を付与してください。

| 権限 | アクセス |
| --- | --- |
| コンテンツ | 読み取り専用 |
| メタデータ | 読み取り専用 |
| Issue | 読み取りおよび書き込み |
| プルリクエスト | 読み取りおよび書き込み |
| チェック | 読み取りおよび書き込み |

**メンバー: 読み取り専用** の組織権限も付与してください。github.com のセットアップ中、Tuist は組織インストールを接続する人物が、そのリポジトリのいずれかにアクセスできるだけの人物ではなく、アクティブな GitHub 組織オーナーであることを確認します。

App を `Check run`、`Pull request`、および `Issue comment` イベントに登録してください。

**インストール中にユーザー認証 (OAuth) を要求** を無効にしたままにし、GitHub がインストーラーをセットアップ URL に送信するようにします。Tuist は、追加の `/integrations/github/authorize` コールバックを使用して個別の認証ステップを開始し、インストールの所有権を検証します。GitHub 上でインストールが開始されると、インストーラーは Tuist 組織を選択します。Tuist で開始されたインストールは、その組織を保持します。

##### サーバーの構成 {#platform-github-configuring-the-server}

以下の環境変数を設定し、サーバーを再起動してください。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_NAME` | App のスラッグ。公開ページ URL `https://github.com/apps/<slug>` の最後のパス成分です | はい | | `my-company-tuist` |
| `TUIST_GITHUB_APP_ID` | インストールの所有権を検証するために使用する数値の App ID | はい | | `123456` |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub アプリケーションのクライアント ID | はい | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | アプリケーションのクライアントシークレット | はい | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub アプリケーションの base64 エンコードされた秘密鍵。改行の扱いに依存する `TUIST_GITHUB_APP_PRIVATE_KEY` より優先されます | はい | | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |
| `TUIST_GITHUB_APP_WEBHOOK_SECRET` | GitHub アプリケーションで構成された Webhook シークレット | いいえ | | `a4c1e0f2b8d6...` |

> [!IMPORTANT]
> **必要な App 資格情報をすべて構成**
>
> 組織の統合ページにある **Install GitHub App** ボタンは、`TUIST_GITHUB_APP_NAME`、`TUIST_GITHUB_APP_CLIENT_ID`、`TUIST_GITHUB_APP_CLIENT_SECRET`、および秘密鍵がすべて設定されるまで無効のままです。インストールの所有権を検証するには、数値の `TUIST_GITHUB_APP_ID` も必要です。インストール URL には App スラッグが含まれるため、特に `TUIST_GITHUB_APP_NAME` が欠落している場合、GitHub は 404 で応答するリンクになります。

サーバーの再起動後、組織管理者は <.localized_link href="/guides/integrations/gitforge/github">GitHub 統合ガイド</.localized_link> に従って App をインストールし、リポジトリをプロジェクトに接続します。

##### OIDC 認証はこれに依存します {#platform-github-oidc}

<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 認証</.localized_link> は、CI トークンのリポジトリクレームをプロジェクトに接続されたリポジトリと照合し、接続はインストール済みの GitHub App を介してのみ作成できます。CI ワークフローがトークンなしで `tuist auth login` を実行する前に、上記のセットアップを完了してください。

Tuist サーバーは、署名キーを取得するために CI プロバイダーの OIDC イシューアーへのアウトバウンドアクセスも必要です。

| CI プロバイダー | ホスト |
| --- | --- |
| GitHub Actions | `token.actions.githubusercontent.com` |
| CircleCI | `oidc.circleci.com` |
| Bitrise | `token.builds.bitrise.io` |

##### GitHub Enterprise Server {#platform-github-enterprise-server}

上記の環境変数は Tuist の github.com App のみを構成します。代わりに GitHub Enterprise Server (GHES) インスタンスと Tuist を統合するには、組織管理者は統合ページの **Enterprise server** タブに切り替え、GHES ベース URL を入力します。Tuist は GitHub の [App マニフェストフロー](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) を案内し、GHES インスタンスに新しい Tuist App を登録します。新しい App の資格情報はインストールごとに暗号化されて保存され、追加の `TUIST_GITHUB_APP_*` 環境変数は不要です。

#### Origin {#platform-origin}

セルフホスト型の Tuist サーバーには、独自の Origin app が必要であり、デプロイメントの URL と署名キーで構成されます。インストールと資格情報が独立した状態を保つよう、各 Tuist 環境に対して個別の app を登録してください。

##### App の登録 {#platform-origin-registering-the-app}

1. Ed25519 サポート付きの OpenSSL を使用して Ed25519 署名キーペアを生成します。

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out origin-app-private.pem
   openssl pkey -in origin-app-private.pem -pubout -out origin-app-public.pem
   ```

2. [Origin app settings](https://cursor.com/codebase/settings/apps) で app を作成します。`origin-app-public.pem` の内容を公開署名キーとして登録します。`origin-app-private.pem` は秘密に保ち、Cursor にアップロードせず、Tuist サーバーに提供してください。
3. 以下の設定を構成し、`YOUR_APP_URL` を Tuist デプロイメントの HTTPS ベース URL に置き換えます。

   | 設定 | 値 |
   | --- | --- |
   | ホームページ URL | `YOUR_APP_URL` |
   | リダイレクト URI | `YOUR_APP_URL/integrations/origin/setup` |
   | Webhook URL | `YOUR_APP_URL/webhooks/origin` |

4. 登録された App ID (`app_` で始まる) をコピーします。

Tuist はインストール中に以下の権限を要求します。

| スコープ | 用途 |
| --- | --- |
| `repository:pull_requests:read` | プルリクエストとその現在のヘッドコミットを検出します。 |
| `repository:pull_requests:reviews:write` | レポートコメントの読み取り、投稿、更新を行います。Origin には対応する review-read 権限が含まれています。 |
| `repository:metadata:read` | リポジトリを検出し、デフォルトブランチを読み取ります。Origin によって自動的に付与されます。 |

オプションのリポジトリ Webhook イベントは選択しないでください。インストールのライフサイクル通知で十分であり、ソースコードへのアクセス、マージ権限、およびチェック実行権限は不要です。

##### サーバーの構成 {#platform-origin-configuring-the-server}

以下の環境変数を設定し、サーバーを再起動してください。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_ORIGIN_APP_ID` | Origin app settings からコピーした App ID。 | はい | | `app_...` |
| `TUIST_ORIGIN_APP_PRIVATE_KEY` | `origin-app-private.pem` の完全な内容。`BEGIN PRIVATE KEY` および `END PRIVATE KEY` の行とすべての改行を含みます。 | はい | | `-----BEGIN PRIVATE KEY-----...` |

秘密鍵をデプロイメントのシークレットマネージャーに保存してください。複数行の PEM 形式を維持する必要があります。この設定は base64 エンコードされた代替形式を受け付けません。鍵をソース管理にコミットしたり、ログに公開したりしないでください。両方の変数は同じ登録済み app に属している必要があります。

Tuist サーバーは `api.cursor.com` へのアウトバウンド HTTPS アクセスが必要です。Cursor は Webhook URL にリクエストを配信できる必要があり、管理者はブラウザでリダイレクト URI に戻れる必要があります。登録された両方の URL は、デプロイメントの HTTPS ベース URL と一致している必要があります。

##### App のインストール {#platform-origin-installing-the-app}

サーバーが再起動したら、管理者は **Settings → Integrations** を開き、Origin の下にある **Connect** を選択して、適切な Origin アカウントとリポジトリへの app のアクセスを承認します。このフロー全体を通じて Tuist 組織は保持されます。代わりに Origin から直接開始されたインストールでは、管理者にログインを促し、接続する Tuist 組織を選択させます。その後、**Add new project connection** を選択して、Tuist プロジェクトをネイティブリポジトリにリンクします。

プロジェクト接続と結果アップロードの要件については、<.localized_link href="/guides/integrations/gitforge/origin">Origin 統合ガイド</.localized_link> に従ってください。app をインストールしてもビルドまたはテストワークフローは開始されません。それらのワークフローは引き続き結果を Tuist サーバーに報告します。

## ローカルでのテスト {#testing-locally}

インフラストラクチャにデプロイする前に、ローカルマシンで Tuist サーバーをテストするために必要なすべての依存関係を含む包括的な Docker Compose 構成を提供しています。

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


**クイックスタート:**

1. 設定ファイルをダウンロードします。
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-level.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-ttl.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. 環境変数を構成します。
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE, TUIST_SECRET_KEY_BASE, and authentication credentials
   ```

   バンドルされた ClickHouse サービスは、以下のオプションの運用ログ制御を受け入れます。

   | 環境変数 | 説明 | デフォルト | 例 |
   | --- | --- | --- | --- |
   | `CLICKHOUSE_SYSTEM_LOG_TTL_DAYS` | `system.*` のような ClickHouse ログテーブル（`text_log`、`query_log`、`trace_log`、`metric_log`、`part_log` など）の保持期間（日数） | `14` | `7` |
   | `CLICKHOUSE_TEXT_LOG_LEVEL` | ClickHouse サーバーロガーおよび `system.text_log` レベル | `information` | `warning` |
   | `CLICKHOUSE_SUPERSEDED_LOG_TABLES` | システムログテーブルが置き換えられた際に ClickHouse が残す `<name>_N` テーブルの扱い。`ignore` はそれらを保持し、`delete` は削除します | `ignore` | `delete` |

3. すべてのサービスを開始します。
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

   Apple Silicon では、Docker Desktop が Tuist および依存関係イメージの `linux/arm64` バリアントを自動的にプルします。デバッグのために amd64 エミュレーションを強制するには、`DOCKER_DEFAULT_PLATFORM=linux/amd64` を指定して Compose を実行してください。

   バンドルされた compose ファイルは永続データ用に名前付き Docker ボリュームを使用します。これをホストバインドマウントに置き換える場合は、まずホストディレクトリを作成し、特に ClickHouse および ClickHouse Keeper のデータディレクトリについて、コンテナユーザーから書き込み可能にしてください。

4. http://localhost:8080 でサーバーにアクセス

**サービスエンドポイント:**
- Tuist Server: http://localhost:8080
- Kura キャッシュ（HTTP + REAPI gRPC を同一ポートで提供）: http://localhost:4000
- MinIO Console: http://localhost:9003 （認証情報: `tuist` / `tuist_dev_password`）
- MinIO API: http://localhost:9002
- pgweb（PostgreSQL UI）: http://localhost:8081
- Prometheus Metrics: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**よく使うコマンド:**

サービスのステータスを確認:
```bash
docker compose ps
# or: podman compose ps
```

ログを表示:
```bash
docker compose logs -f tuist
```

サービスを停止:
```bash
docker compose down
```

すべてをリセット（すべてのデータを削除）:
```bash
docker compose down -v
```

**設定ファイル:**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - 完全な Docker Compose 構成
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse 構成
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml) - ClickHouse Keeper 構成
- [.env.example](/server/self-host/.env.example) - 環境変数の例

## Helm を使用した Kubernetes {#kubernetes-with-helm}

Tuist は Kubernetes へのデプロイ用公式 Helm チャートを提供しています。このチャートには Tuist サーバーとキャッシュサービスが含まれており、必要に応じて外部プロバイダーに置き換え可能な組み込みインフラストラクチャ依存関係もパッケージ化されています。

### チャートのインストール {#installing-the-chart}

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY"
```

特定のチャートバージョンを固定する場合:

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY" \
  --version 0.1.0
```

### ライセンス {#helm-license}

`server.license.key` の値には、標準のライセンスキーと、エアギャップ環境用の Base64 エンコード済みライセンス証明書の両方が受け入れられ、サーバーが自動検出します。

`--set` でライセンスを渡すことで迅速なインストールが可能です。値をバージョン管理下に置く場合は、ライセンスを Helm 外で管理する Kubernetes Secret（Vault、Sealed Secrets、SOPS などを使用）に保存し、チャートからその Secret を参照するように設定してください。

```yaml
# values.yaml
server:
  license:
    existingSecret: tuist-license
    existingSecretKeys:
      key: TUIST_LICENSE
      certificateBase64: ""
```

`existingSecretKeys.key` のエントリは、ライセンス値（ライセンスキー、またはエアギャップ環境用の Base64 エンコード済みライセンス証明書）を保持する Secret 内のフィールド名を指定します。`existingSecretKeys` の各エントリはチャートのキー名にデフォルト設定されるため、Secret に含まれないエントリは上記の `certificateBase64` のように空文字列に設定してください。そうしないと、ポッドが存在しないキーを参照して起動に失敗します。チャートをインストールまたはアップグレードする前に、リリースネームスペースに Secret を作成してください。

ライセンスは単一のソースでのみ構成してください。`server.license.key` または `server.license.existingSecret` のいずれかです。どちらも設定されていない場合、またはソースが組み合わせられている場合、チャートのレンダリングに失敗します。`server.extraEnv` を介して渡されたライセンスはソースとしてカウントされないため、代わりに `existingSecret` を使用してください。

### インフラストラクチャ依存関係 {#helm-infrastructure-dependencies}

このチャートは `postgresql`、`clickhouse`、`objectStorage` の 3 つのインフラストラクチャ依存関係を管理します。それぞれはデフォルトで **embedded** モードであり、チャートがクラスター内にこれらをデプロイすることを意味します。独自の外部インスタンスを使用する場合は、依存関係の `mode` を `external` に設定し、`values.yaml` に接続詳細を入力してください。たとえば、外部 PostgreSQL データベースを使用する場合:

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

PostgreSQL の認証情報を Helm 外で管理している場合は、既存の Kubernetes Secret をチャートから参照するように設定してください。

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

チャートは Secret からホスト、ユーザー名、パスワードを読み取り、Kubernetes の環境変数置換を通じて `DATABASE_URL` を構成するため、パスワードは Helm マニフェストにレンダリングされません。Secret のパスワード値はデータベース URL に挿入されるため、URL セーフである必要があります。

同じパターンが `clickhouse` と `objectStorage` にも適用されます。設定可能なフィールドの全容については、チャートの `values.yaml` 内の各セクションにある `external` ブロックを参照してください。

### 共有スケジューリングとラベル {#helm-shared-scheduling-and-labels}

このチャートは `global` の下に少量の共有ポッド設定を公開しており、オペレーターはすべてのワークロードで同じ値を繰り返すことなく、デプロイメントをクラスターに適応させることができます。

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

次のような場合にこれらの設定を使用してください。

- すべてのポッドにクラスター固有のラベルを追加する
- プライベートレジストリからミラー化されたイメージをプルする
- 専用のノードプールをターゲットにする
- Tuist ワークロード用に予約された汚染されたノードへのポッド配置を許可する

### ワークロードアイデンティティとサービスアカウント {#helm-workload-identity}

このチャートはアプリケーションワークロードごとにサービスアカウントのスコープを設定するため、必要な場所でのみアイデンティティを付与できます。

- `server.serviceAccount` は Tuist サーバーのデプロイメントと移行ジョブに適用されます
- `cache.serviceAccount` はキャッシュのデプロイメントに適用されます

たとえば、キャッシュが EKS 上の外部 S3 バケットを使用する場合、組み込みデータベースに同じ IAM ロールをアタッチすることなく、キャッシュワークロードに対して IRSA を有効にできます。

```yaml
cache:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/tuist-cache
```

### 互換性オーバーライド {#helm-compatibility-overrides}

このチャートはストレージおよびメッシュ固有の微調整をオプトイン方式にしているため、デフォルト値はポータブルなままです。

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

クラスターで必要とされる場合のみ、これらのオーバーライドを使用してください。

- `cache.podSecurityContext` はデフォルトで空です。マウントされたボリュームで共有グループ所有権が必要なストレージクラスまたは CSI ドライバーを使用している場合は、`fsGroup` を設定してください。
- `clickhouse.embedded.service.nativePort` は ClickHouse の標準的な `9000` ネイティブサービスポートにデフォルト設定されており、サービスメッシュやプラットフォームの予約がそのポートと競合する場合に変更できます。
- `clickhouse.embedded.systemLogs.ttlDays` はデフォルトで空であり、`system.text_log`、`system.query_log`、`system.trace_log`、`system.metric_log`、`system.part_log` などの組み込み内部ログテーブルに対する ClickHouse の無制限の保持ポリシーが残ります。これを設定するとそれらのテーブルが一度上書きされるため、`supersededTables: delete` と併せて採用してください — <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">運用ログの保持期間を制限する</.localized_link> を参照してください。
- `clickhouse.embedded.systemLogs.level` は組み込み ClickHouse サーバーロガーおよび `system.text_log` に対して `information` にデフォルト設定されています。`ttlDays` とは異なり、これはどのテーブル定義の一部でもないため、変更してもテーブルを上書きすることはありません。
- `clickhouse.embedded.systemLogs.supersededTables` はデフォルトで `ignore` であり、ClickHouse がシステムログテーブルを上書きした際に残す `<name>_N` テーブルの処理方法を決定します。各 `helm upgrade` でこれらを削除するには、`delete` に設定してください。
- `ttlDays` と `level` への編集は、どちらも `subPath` マウントであり、ConfigMap が変更されたときにチャートが StatefulSet をローリングしないため、ClickHouse ポッドの次回再起動時に反映されます。

### オブザーバビリティ {#helm-observability}

このチャートにはオプションのオブザーバビリティスタック（OpenTelemetry Collector、Prometheus、Grafana、Loki、Tempo）が含まれています。デフォルトでは **無効** です。`values.yaml` で有効にするには:

```yaml
# values.yaml
observability:
  enabled: true
```

有効にすると、Grafana でログ、トレース、メトリクスのドリルダウンが事前構成された状態で利用可能になります。外部オブザーバビリティを使用する場合は、これを無効にしたまま、`server.extraEnv` を介してエンドポイントを構成してください。

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

設定可能な値の完全なリストについては、チャートの [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml) を参照してください。

## デプロイメント {#deployment}

公式の Tuist Docker イメージは以下で利用可能です。
```
ghcr.io/tuist/tuist
```

公開されているイメージには `.xcactivitylog` アーカイブ用の組み込み Linux ビルド処理が含まれているため、セルフホスト型デプロイメントでは追加のサービスを実行せずにビルドを処理できます — `ProcessBuildWorker` Oban ジョブは各サーバーポッド内でインプロセスで実行されます。ビルド処理を専用レプリカセットにオフロードしたい場合（たとえば、Web 層とは独立して解析スループットをスケールアップする場合）、Helm チャートで `processor.enabled: true` を設定してください。チャートは同じイメージをキュー専用コンシューマーとしてデプロイします（`TUIST_PROCESSOR_MODE=true`）。設定項目の全容については [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml) を参照してください。

> [!NOTE]
> `.xcresult` 解析は Xcode の `xcresulttool` に依存しているため、macOS でのみ実行できます。CLI はセルフホスト型デプロイメントに対してこれを透過的に処理します。`tuist test` は `tuist.dev` 以外のサーバーに対して **local** 処理モードにデフォルト設定されており、開発者マシン（ビルド自体のために既に Xcode がインストールされている）で xcresult を解析し、構造化された結果をアップロードします。テスト結果は追加のインフラストラクチャなしで取り込まれます。

### Docker イメージのプル {#pulling-the-docker-image}

以下のコマンドを実行してイメージを取得できます。

```bash
docker pull ghcr.io/tuist/tuist:latest
```

イメージは `linux/amd64` と `linux/arm64` の両方向けに公開されているため、Docker はホストのネイティブ Linux アーキテクチャを自動的に選択します。

または、特定のバージョンをプルします。
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Docker イメージのデプロイ {#deploying-the-docker-image}

Docker イメージのデプロイプロセスは、選択したクラウドプロバイダーと組織の継続的デプロイアプローチによって異なります。[Kubernetes](https://kubernetes.io/) などのほとんどのクラウドソリューションおよびツールは Docker イメージを基本単位として利用しているため、このセクションの例は既存のセットアップとよく整合するはずです。

> [!WARNING]
> デプロイパイプラインでサーバーが稼働中であることを検証する必要がある場合は、`/ready` に対して `GET` HTTP リクエストを送信し、レスポンスのステータスコードが `200` であることをアサートできます。


#### Fly {#fly}

[Fly](https://fly.io/) にアプリをデプロイするには、`fly.toml` 構成ファイルが必要です。継続的デプロイ（CD）パイプライン内で動的に生成することを検討してください。以下は参考用の例です。

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

その後、`fly launch --local-only --no-deploy` を実行してアプリを起動できます。以降のデプロイでは、`fly launch --local-only` を実行する代わりに、`fly deploy --local-only` を実行する必要があります。Fly.io はプライベート Docker イメージのプルを許可していないため、`--local-only` フラグを使用する必要があります。


## Prometheus メトリクス {#prometheus-metrics}

Tuist は `/metrics` で Prometheus メトリクスを公開しており、セルフホスト型インスタンスの監視に役立ちます。これらのメトリクスには以下が含まれます。

### Finch HTTP クライアントのメトリクス {#finch-metrics}

Tuist は HTTP クライアントとして [Finch](https://github.com/sneako/finch) を使用し、HTTP リクエストに関する詳細なメトリクスを公開します。

#### リクエストのメトリクス
- `tuist_prom_ex_finch_request_count_total` - Finch リクエストの総数（カウンター）
  - ラベル: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP リクエストの期間（ヒストグラム）
  - ラベル: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
  - バケット: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s
- `tuist_prom_ex_finch_request_exception_count_total` - Finch リクエスト例外の総数（カウンター）
  - ラベル: `finch_name`, `method`, `scheme`, `host`, `port`, `kind`, `reason`

#### 接続プールキューのメトリクス
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 接続プールキューでの待機時間（ヒストグラム）
  - ラベル: `finch_name`, `scheme`, `host`, `port`, `pool`
  - バケット: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 使用されるまでの接続のアイドル時間（ヒストグラム）
  - ラベル: `finch_name`, `scheme`, `host`, `port`, `pool`
  - バケット: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 5s, 10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch キュー例外の総数（カウンター）
  - ラベル: `finch_name`, `scheme`, `host`, `port`, `kind`, `reason`

#### 接続のメトリクス
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 接続確立にかかった時間（ヒストグラム）
  - ラベル: `finch_name`, `scheme`, `host`, `port`, `error`
  - バケット: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s
- `tuist_prom_ex_finch_connect_count_total` - 接続試行の総数（カウンター）
  - ラベル: `finch_name`, `scheme`, `host`, `port`

#### 送信のメトリクス
- `tuist_prom_ex_finch_send_duration_milliseconds` - リクエスト送信にかかった時間（ヒストグラム）
  - ラベル: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - バケット: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 送信前の接続のアイドル時間（ヒストグラム）
  - ラベル: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - バケット: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms

すべてのヒストグラムメトリクスは、詳細な分析のために `_bucket`、`_sum`、および `_count` の変体を提供します。

### その他のメトリクス

Finch のメトリクスに加えて、Tuist は以下のメトリクスを公開します。
- BEAM 仮想マシンのパフォーマンス
- カスタムビジネスロジックのメトリクス（ストレージ、アカウント、プロジェクトなど）
- データベースのパフォーマンス（Tuist がホストするインフラストラクチャを使用する場合）

## オペレーション {#operations}

Tuist は、インスタンスを管理するために使用できるユーティリティのセットを `/ops/` で提供しています。

> [!WARNING]
> **認証**
>
> メールアドレスのドメインが `TUIST_OPERATOR_EMAIL_DOMAIN`（デフォルトは `tuist.dev`）と一致する確認済みユーザーのみが、`/ops/` エンドポイントにアクセスできます。


- **エラー（`/ops/errors`）:** アプリケーションで発生した予期しないエラーを表示できます。これはデバッグや問題の原因を理解するのに役立ちます。問題が発生している場合、この情報を共有していただくようお願いすることがあります。
- **ダッシュボード（`/ops/dashboard`）:** アプリケーションのパフォーマンスと健全性（メモリ使用量、実行中のプロセス、リクエスト数など）に関する洞察を提供するダッシュボードを表示できます。このダッシュボードは、使用中のハードウェアが負荷を処理するのに十分かどうかを理解するのに非常に役立ちます。
