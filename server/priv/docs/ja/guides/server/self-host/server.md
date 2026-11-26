---
{
  "title": "サーバー",
  "titleTemplate": ":title | セルフホスティング | サーバー | ガイド | Tuist",
  "description": "インフラストラクチャ上にTuistサーバーをデプロイする方法を学びます。"
}
---
# サーバー {#server}

インフラストラクチャの管理により高い制御を必要とする組織向けに、Tuist サーバーのセルフホスティング版を提供しています。このバージョンでは、Tuist を独自のインフラストラクチャ上でホストできるため、データの安全性とプライバシーを確保できます。

> [!WARNING]
> **ライセンスが必要**
>
> Tuist のセルフホスティングには、法的に有効な有料ライセンスが必要です。オンプレミス版の Tuist は、Enterprise プランを利用している組織のみ利用可能です。このバージョンに関心がある場合は、[contact@tuist.dev](mailto:contact@tuist.dev) までお問い合わせください。

> [!WARNING]
> **レガシーキャッシュサービス**
>
> 古いセルフホスティング型キャッシュノード技術は、新しいインストールでは非推奨です。現在のセルフホスティング型キャッシュインフラストラクチャについては、<.localized_link href="/guides/features/cache/self-hosting">セルフホスティングキャッシュガイド</.localized_link>を参照してください。
>
> 既存のデプロイメントでは、GitHub の Markdown ビューアーでレガシーソースドキュメントを依然として参照できます。[キャッシュノード](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/self-host.md)および[キャッシュアーキテクチャ](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/architecture.md)

## リリースサイクル {#release-cadence}

Tuist サーバーと Kura キャッシュサーバーは、3 つの GHCR イメージチャネルを通じて提供されます。**canary**（`main`へのすべてのコミット）、**release candidate**（毎週月曜日に作成され、1 週間検証）、および**stable**（翌週の月曜日に昇格）。安定版リリースのみが`:latest`を更新し、デフォルトで解決されます。カナリア版とリリース候補版は GitHub のプレリリースであり、タグを固定することでオプトインします。サーバーと Kura は同じ週次リリースサイクルに従い、<.localized_link href="/cli/release/channels">Tuist CLI のリリーススケジュール</.localized_link>と連動しています。

予測可能なバージョニングと互換性を確保するため、[セマンティック バージョニング](https://semver.org/)に従っています。メジャーバージョンは、セルフホスティングユーザーとの調整が必要な Tuist サーバーの破壊的変更を示すために使用されます。当社がこの方法を使用することは想定しないでください。万一必要な場合は、円滑な移行を実現するために協力いたします。

各チャネルの作成方法、デプロイメントでの固定方法、本番環境を安定した低速移動ラインで維持しつつステージング環境で次のリリースを検証するための推奨戦略については、<.localized_link href="/guides/server/self-host/release/channels">リリースチャネル</.localized_link>ページを参照してください。

## ブラウザセッションのアップグレード {#browser-session-upgrade}

ブラウザセッションは、認証されたページリクエストまたは LiveView の操作がない状態で 7 日間経過するか、認証から 30 日を経過すると期限切れになります。「ログイン状態を保持」を選択しても同じサーバー側セッションが復元されるだけで、いずれの期限も延長できません。アクティビティは 1 分ごとにチェックポイントされるため、アイドル状態のセッションは最大 59 秒早く期限切れになる可能性があります。WebSocket のハートビート、自動再接続、バックグラウンド更新はアクティビティを更新しません。これらの期限は、マシン資格情報や API トークンの有効期間には影響しません。

アップグレードされたアプリケーションプロセスを開始する前に、追加的な`users_tokens`マイグレーションを実行してください。既存の行はバックフィルされません。作成時刻が非アクティブ期間と絶対有効期限を制限しており、SSO が強制されている組織にアクセスする前に再度認証する必要があります。コールバックのプロバイダー、発行者または検証済み Workspace、カスタム SSO 接続はサーバー側に保存され、組織の現在の設定と比較されます。リンクされたアカウントはセッション認証の証明ではありません。

ポリシーを強制適用する前に、すべての提供中 Web レプリカをアップグレードしてください。古いバイナリは以前の 60 日間のセッションを引き続き受け入れ、新しい LiveView の境界を強制しません。混合バージョンはスキーマ互換性がありますが、ポリシー同等ではありません。ユーザーは再度サインインする必要があります。古いバイナリへのロールバックはこれらの制御を弱めます。スキーマのロールバックが必要な場合は、新しいフィールドを読み取るすべてのバイナリを停止してから削除してください。再認証を回避するために古いセッションを延長したり、出所を推測したりしないでください。

## Authenticator アプリ MFA {#authenticator-app-mfa}

サーバーにはネイティブな Authenticator アプリ（TOTP）による二要素認証が含まれています。ダッシュボードにはまだリンクされていませんが、後のリリースで設定のエントリーポイントが追加されます。アクティベーションフラグ、ホスト型サービスの依存関係、または ID プロバイダーの資格情報は不要です。必要なのは PostgreSQL、以下のマイグレーション、TOTP 認証アプリ、およびすべての提供レプリカで共有される安定した暗号化キー（`TUIST_SECRET_KEY_ENCRYPTION`、 fallback は`TUIST_SECRET_KEY_BASE`）だけです。サーバーと認証アプリの時計を同期させてください。MFA 検証と、5 分間に 5 回の失敗コードという共有バジェットは、Redis ではなく PostgreSQL の行ロックを使用します。

セットアップには、過去 5 分以内のサインイン、TOTP 認証アプリへのセットアップキーの入力、およびアプリ生成コードの確認が必要です。10 個のワンタイムリカバリーコードが一度だけ表示されるため、安全に保管してください。ファクターの無効化にも、最近のサインインと未使用の認証アプリまたはリカバリーコードが必要です。ファクターの変更は他のブラウザセッションを取り消します。パスワードのリセットは MFA を削除せず、この実装では紛失したファクターに対してメールのみまたは管理者によるバイパスは提供されません。

登録後、フェデレーテッドサインインを含むすべての新しいブラウザサインインでは、セッションを受け取るかブラウザベースの CLI/デバイス認証を完了する前に、ネイティブな第二要素が必要です。直接のパスワードおよび Apple API ログインは登録済みユーザーを拒否し、ブラウザサインインの使用を指示します。登録済みユーザーに対する新しい Email エージェントのクレームには、MFA で検証されたブラウザセッションが必要です。メールボックスのみのレガシークレームは拒否されます。既存の API トークン、マシン資格情報、ワークロード ID、およびそれらの更新ルールは変更されません。これはユーザーごとのオプションサポートであり、組織全体の MFA 義務付けや、ID プロバイダー独自の MFA ポリシーの検証ではありません。組織の SSO では、ネイティブ要素に加えて、正しく構成されたプロバイダー/発行者が必要です。

登録、サインイン、リカバリーコードの使用、または MFA の無効化にはメールアドレスは必要ありません。ファクター変更の通知はベストエフォートです。配信の失敗は完了した変更を取り消しません。

新しいバイナリを導入する前に、個別の追加マイグレーション `user_mfa`/`users_tokens.mfa_verified_at` を実行してください。TOTP シークレットは既存の Vault 暗号化キーを使用するため、そのキーとバックアップを保持してください。**MFA 登録を許可する前に、認証を提供するすべてのレプリカのアップグレードを完了**させてください。古いバイナリはネイティブ MFA をバイパスできるため、登録後のロールバック対象としてはポリシー互換性がありません。MFA スキーマを削除すると登録状態とリカバリー状態が失われるため、まず読み取り処理を停止し、暗号化されたバックアップを保持してください。混合バージョンのスキーマ互換性は、MFA またはブラウザセッション制御が強制されていることを証明するものではありません。

## OAuth のアップグレードとロールバックの境界 {#oauth-upgrade-and-rollback-boundary}

OAuth エンティティキャッシュの削除には、既存のインストールに対して段階的なアップグレードが必要です。OAuth キャッシュの無効化を停止するバージョンをデプロイする前に、まず [#14040](https://github.com/tuist/tuist/pull/14040) の権威ある読み取り互換リリースを **すべての OAuth 読み取りおよび書き込みコンポーネント** にデプロイしてください。この互換性ステージは **1.355** リリースラインで初めて利用可能になります。`ghcr.io/tuist/tuist:1.355.0-rc.1` にはこれが含まれており、本番環境へのデプロイでは、昇格後に安定した `1.355.x` リリースを使用すべきです。1.354 以前にインストールされている場合は、削除を含む後続のリリースにアップグレードする前に、このステージを完了する必要があります。1.355 ラインは互換性専用として維持し、無効化の削除をそこにバックポートしないでください。

元の互換性コミットは `ghcr.io/tuist/tuist:sha-c8e54471a425` としても利用可能です。別のイメージが互換性ステージとして適しているのは、古いコンシューマーが残っている間、権威ある読み取りを維持し **レガシーな無効化処理も保持** する場合に限られます。トラフィックを提供する前に、リフレッシュトークンのルックアップインデックスを含む、そのステージの通常のデータベースマイグレーションを実行してください。

各環境のすべての Web レプリカ、バックグラウンドワーカー、スケジュールされたジョブ、および個別にピン留めされたプロセッサーイメージを確認してください。互換性のロールアウトが完了するのを待ち、無効化を削除する前にキャッシュを読み取るバイナリが残っていないことを確認してください。自動アップグレード中に浮動イメージタグがこのステージをスキップしないようにしてください。古いコンシューマーのない新規インストールでは、中間デプロイメントは必要ありません。

> [!WARNING]
> **権威ある読み取りが可能なロールバックターゲットを保持**
>
> 無効化が削除された後、通常のローリングロールバックは #14040 または他の権威ある読み取りバージョンをターゲットにする必要があります。保持された OAuth キャッシュエントリは、無効化を行わないすべてのプロセスが停止した後でも古くなっている可能性があり、再起動したキャッシュ読み取りレプリカがピアからそれらをインポートする場合があります。
>
> さらにロールバックするには、**すべて** の無効化を行わない OAuth コンシューマーを停止してドレインし、キャッシュを読み取るコンシューマーを開始する前に、保持されている **すべての** Boruta キャッシュ参加者をクリアまたは置き換える必要があります。保持された参加者の再参加を防いでください。イングレスのみをドレインしたり、Web レプリカのみを再起動したりすることは不十分です。キャッシュのクリアやデータベースマイグレーションの自動ロールバックではなく、Tuist サポート担当者との調整によりこの復旧作業を実施してください。

## マルチレプリクラスタリング {#multi-replica-clustering}

サポートされているマルチレプリカ Web デプロイメントでは、認証の権限としてではなく、レプリカ間の Phoenix PubSub および Oban PG 通知のために Erlang クラスタリングが必要です。`server.cluster.enabled` が false の場合、チャートは 1 つを超えるレプリカに成長できるオートスケーラーを含む複数のレプリカを拒否します。以前に承認されていた非クラスター化デプロイメントは、ガードをバイパスするのではなく、このアップグレードを計画する必要があります。メンバーシップを変更する前に、無効化の削除を含む <.localized_link href="/guides/server/self-host/server#oauth-upgrade-and-rollback-boundary">OAuth アップグレード手順</.localized_link> を完了してください。

シークレットマネージャーを使用してリリース名前空間にプライベートクッキーシークレットを作成し、その名前とキーを設定します。

```yaml
server:
  replicaCount: 2
  cluster:
    enabled: true
    distributionPort: 9100
    cookieExistingSecret: tuist-server-cluster
    cookieExistingSecretKey: release-cookie
```

クッキーは高エントロピーであり、参加するすべての Web レプリカで共有される必要があります。公開イメージに埋め込まれたクッキーは決して使用しないでください。配布用クッキーを所持していると、そのノードでのリモート実行が可能になります。分散リリースの起動 now は、欠落しているプライベート `RELEASE_COOKIE` または無効なポート、DNS 検出なしで明示的に構成された `RELEASE_DISTRIBUTION=name` または `sname` を拒否します。非チャートデプロイメントでも、`TUIST_CLUSTER_DNS_SERVICE`、`TUIST_CLUSTER_APP_NAME` およびポッド IP/ノード名を一貫して構成する必要があります。検出には現在 IPv4 A レコードが使用されています。

通常のサーバー接続型 `helm upgrade` では、`cookieExistingSecret` を空のままにするとクッキーシークレットが作成され、後のアップグレードでその現在の値が再利用されます。オフラインの `helm template`、Argo CD、およびライブシークレットルックアップのない他の GitOps レンダラーは、生成された値を保持できないため、別途管理された安定したシークレットで裏付けられた `cookieExistingSecret` を使用する必要があります。ライブクラスターを暗黙的にローテーションするためにクッキーキーを変更しないでください。クッキーのローテーションには、すべての参加者の調整されたマイグレーション/再起動が必要です。シークレットを更新するだけでは、既存のプロセスは更新されません。

イメージに焼き込まれたクッキーからの最初のロールアウトでは、すべての Web レプリカがプライベートシークレットを使用するまで、新旧のメンバーシップ島が分離されます。リアルタイム更新のための移行ウィンドウを計画してください。後続のローリングデプロイメントでは混合バージョンのクラスターが形成されるため、実際の新旧バージョン間で PubSub、Oban 通知、およびピア置換を適切に処理してください。これらの通知は耐久性のある配信保証ではありません。互換性のあるバージョンをロールバックする際は、権威ある読み取りが可能なロールバックイメージを保持し、同じプライベートクッキーを維持してください。

EPMD (TCP 4369) と構成された配布ポートは、信頼できるサーバーピア間でのみ許可し、テナントワークロードやパブリックネットワークからは決して許可しないでください。環境における実際のイングレス/エグレスの分離を検証してください。NetworkPolicy をレンダリングしても、強制執行やバックエンドへの到達可能性が証明されるわけではありません。連続負荷下での 2 レプリカのカナリアデプロイメントは、昇格前に結合、ローリング置換、および障害/復旧を通過する必要があります。DNS はピアを発見するために使用され、一時的な失敗または部分的な応答によって健全なノードを切断するためには使用されません。実際のノード損失と OTP パーティション防止は引き続き適用されます。libcluster は、接続を閉じなくても保持コールバックに対して成功した「切断」操作をログに記録する場合があります。そのログ行だけでなく、ノードのアップ/ダウンイベントまたは `Node.list()` から実際のメンバーシップを確立してください。

## 継続的デプロイメント {#continuous-deployment}

本番環境は安定したマイナーライン（例: `ghcr.io/tuist/tuist:1.351`）に固定し、日々のアップグレードではバックポートされた修正のみを提供することをお勧めします。安定ラインは、リリース候補チャネルでの1週間の浸透テスト後、毎週月曜日の06:00 UTCに昇格されます。カナリーまたは現在のリリース候補タグを使用したステージング環境により、ユーザーに影響が出る前に回帰を検出できます。推奨されるピン留め戦略については<.localized_link href="/guides/server/self-host/release/channels">リリースチャネル</.localized_link>をご覧ください。

マニフェストを変更せずに新機能が安定するのを待って取り込みたい場合は、`:latest`に固定してください。このタグは毎週月曜日の朝に更新されるため、それに合わせてデプロイウィンドウを計画してください。以下は、そのペースで最新の安定イメージをチェックしてデプロイするGitHub Actionsワークフローの例です:

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

セルフホストされたインストールでは、信頼できるネットワーク上の開発者がサインインせずにインサイトを送信したり、キャッシュを使用したり、あるいはその両方を行うことができます。ダッシュボードと管理機能には引き続き認証が必要です。

必要な機能のみを有効にしてください:

| サーバー環境変数 | サインインなしで許可 |
| --- | --- |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` | ビルドおよびテストのインサイトを送信 |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS=true` | キャッシュされたビルド出力の読み書き |

両方の設定は**デフォルトでオフ**であり、独立しており、プライベートプロジェクトを含むすべてのアカウントとプロジェクトにインスタンス全体で適用されます。これらはホスト型Tuistでは利用できず、セルフホスティングライセンスの代わりにはなりません。

以前の`TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING`名は、`TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS`が設定されていない場合の互換性フォールバックとして残っています。

> [!WARNING]
> これらの設定は、強制された社内ネットワークまたはVPN境界の背後でのみ有効にしてください。有効なエンドポイントに到達できる任何人は、レポートを送信したり、キャッシュアクセスが有効になっている場合はキャッシュされた出力を読み取って上書きしたりできます。これにより、偽造されたテレメトリ、キャッシュポイズニング、および容量枯渇が可能になります。レポート応答は、プライベートプロジェクトのハンドルやビルドシステムを公開する可能性もあります。TuistはVPNメンバーシップを検証せず、転送されたIPヘッダーをメンバーシップの証明として信頼しません。

### インスタンスの構成 {#network-trusted-instance-configuration}

1. ファイアウォールまたはプライベートイングレスを使用して、Tuistサーバー、すべてのKura HTTP/gRPCリスナー、およびBazel BESイングレスを信頼できるネットワークに制限してください。
2. クライアントをアップグレードする前に、すべてのサーバーおよびKuraレプリカをアップグレードしてください。`KURA_AUTH_TUIST_URL`とそのコントロールプレーン資格情報を使用してKura認証を有効にしたままにしてください。これを無効にすると、これらの制限をバイパスします。キャッシュエンドポイントは<.localized_link href="/guides/features/cache/self-hosting">セルフホストキャッシュガイド</.localized_link>を使用して構成してください。
3. 上記の希望する変数を関連するすべてのTuistサーバーレプリカに設定し、再起動または再デプロイしてください。正確な値`true`のみが設定を有効にします。ダッシュボードのトグルや個別のKuraフラグはありません。

### クライアントの構成 {#network-trusted-client-configuration}

互換性のある各クライアントで、最終的なセルフホストサーバーURLとプロジェクトを構成してください。クライアントは、資格情報がない場合にどの機能が有効になっているかを自動的に検出します。クライアント側のオプトインは不要です。検出はリダイレクトに従いません。既存の資格情報は引き続き使用され、無効または更新に失敗した資格情報は匿名フォールバックではなくエラーを引き起こします。回復するには、再度サインインするか、明示的にサインアウトしてください。

インサイトアクセスを有効にする前に、資格情報を共有するすべてのツールを、破損または拒否された資格情報を保持し、読み取り不可能な資格情報ディレクトリを拒否し、署名されていないレポートからGitオリジンを省略するバージョンにアップグレードしてください。古いツールは資格情報を削除し、意図せず匿名フォールバックを許可する可能性があります。サーバーのみのアップグレードではこれを修正できません。サーバーに検出サポートがない場合、または古いバージョンにロールバックされた場合、クライアントは認証する必要があります。以前の`TUIST_NETWORK_TRUSTED_PUBLISHING`クライアント設定はもう適用されません。

- **インサイト:** アーカイブ、添付ファイル、カバレッジ、シャード計画、または既存のレポートアクセスなしで、完了したXcode、Gradle、Elixir/Mix、およびBazelレポートのみを送信してください。アクタークレームは検証されていません。署名されていないテレメトリは、信頼されたテスト証拠や自動化を促進しません。クライアントセットアップとプライバシーの詳細については、<.localized_link href="/guides/features/build-insights/xcode#network-trusted-publishing">Xcode</.localized_link>、<.localized_link href="/guides/features/build-insights/gradle#network-trusted-publishing">Gradle</.localized_link>、および<.localized_link href="/guides/features/build-insights/elixir#network-trusted-publishing">Elixir</.localized_link>ガイドをご覧ください。
- **キャッシュ:** CLIコンパレーション/モジュールキャッシング、Bazelキャッシング、およびGradleタスクキャッシングをサポートしています。キャッシュのパージとリモートアセットのダウンロードには引き続き資格情報が必要です。サポートのないクライアントは認証を続ける必要があります。
- **Bazel:** レポートには明示的な`TUIST_BAZEL_BES_BACKEND`と互換性のあるKuraが必要です。キャッシュとレポートのオプションは独立して有効になります。資格情報またはいずれかの設定を変更した後、`tuist bazel setup`を再実行してください。コンパレーションキャッシュの構成変更には`tuist cache config`を再実行してください。

レポートリクエストはプロジェクトごとに8 MB、毎分60リクエスト、毎日10,000リクエストに制限されています。複数のレプリカを持つデプロイメント全体のクォータには共有Valkeyを構成してください。そうでない場合、制限はプロセスごとになります。構成された共有クォータバックエンドが利用できない場合、署名されていないレポートは拒否されます。イングレス接続、ボディ、およびレート制限も追加してください。

### ネットワーク信頼アクセスの無効化 {#disable-network-trusted-publishing}

関連する変数を`false`に設定し、**関連するすべてのサーバーレプリカ**を再起動してください。古いレプリカは、置き換えられるまで資格情報不要のリクエストを受け入れ続けることができます。最後のレプリカの切り替え後60秒以内に新しいリクエストに対するキャッシュアクセスが停止します。進行中の転送はキャンセルされません。即時の失効が必要な場合は、まずイングレスでトラフィックをブロックしてください。既存のレポートは通常の可視性と保持を維持し、認証されたクライアントは引き続き動作します。

## ランタイム要件 {#runtime-requirements}

このセクションでは、インフラストラクチャ上でTuistサーバーをホストするための要件について説明します。

### 互換性マトリックス {#compatibility-matrix}

Tuistサーバーはテスト済みであり、以下の最小バージョンと互換性があります:

| コンポーネント | 最小バージョン | 注記 |
| --- | --- | --- |
| PostgreSQL | 15 | |
| ClickHouse | {{minimum_supported_clickhouse_version}} | アナリティクスに必要 |

### Docker仮想化イメージの実行 {#running-dockervirtualized-images}

サーバーは[Docker](https://www.docker.com/)イメージとして[GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)経由で配布されています。

実行するには、インフラストラクチャがDockerイメージの実行をサポートしている必要があります。ほとんどのインフラストラクチャプロバイダーは、本番環境でソフトウェアを配布および実行するための標準コンテナとなっているため、これをサポートしています。

### Postgresデータベース {#postgres-database}

Dockerイメージの実行に加えて、リレーショナルデータを保存するために[Postgresデータベース](https://www.postgresql.org/)が必要です。ほとんどのインフラストラクチャプロバイダーは、その提供物にPostgresデータベースを含めています（例: [AWS](https://aws.amazon.com/rds/postgresql/)および[Google Cloud](https://cloud.google.com/sql/docs/postgres)）。

> [!NOTE]
> **マイグレーション**
>
> Dockerイメージのエントリーポイントは、サービス開始前に未適用のスキーママイグレーションを自動的に実行します。


### ClickHouseデータベース {#clickhouse-database}

Tuistは大量のアナリティクスデータの保存とクエリに[ClickHouse](https://clickhouse.com/)を使用します。ビルドインサイトなどの機能にはClickHouseが**必須**です。ClickHouseをセルフホストするか、ホスト型サービスを利用するかを選択できます。

> [!NOTE]
> **マイグレーション**
>
> Dockerイメージのエントリーポイントは、サービス開始前に未適用のClickHouseスキーママイグレーションを自動的に実行します。

同梱されているDocker ComposeおよびHelmの埋め込みClickHouse設定は、ClickHouseのテキストログレベルをイメージの`trace`デフォルトから`information`に下げます。`system.text_log`のボリュームの大部分はここから発生します。また、どちらもClickHouse独自の`system.*`運用ログテーブルに上限を設定できますが、これはデフォルトでは無効になっています（以下参照）。外部ClickHouseデプロイメントでは、これらの運用ログをClickHouseサービスで直接設定する必要があります。

#### ClickHouseレプリケーショントポロジー {#clickhouse-replication-topology}

Tuistの背後にあるマルチレプリカClickHouseは、ClickHouse Cloudでのみサポートされています。セルフマネージドのClickHouseはシングルレプリカです。

取り込みマイグレーションはプレーンな`MergeTree`エンジンを出力します。Cloud上では透過的に`SharedMergeTree`となり、書き込みは共有オブジェクトストレージに行われ、任意のレプリカ数で動作します。セルフマネージドのClickHouseでは、`MergeTree`は1つのレプリカのローカルディスクにのみ書き込みます。マルチレプリカ構成では、接続ユーザーの`database_replicated_allow_only_replicated_engine`の設定に応じて、取り込みがレプリカ間でサイレントに分割されるか、`UNKNOWN_STORAGE: Only tables with a Replicated engine or tables which do not store data on disk are allowed in a Replicated database.`でCREATEが拒否されます。

セルフマネージドのClickHouseでは、1つのシャードを1つのレプリカで実行し、ClickHouseデータディレクトリの定期的なバックアップを取得してください。ノードが失われた場合のフォールバック先となる2つ目のレプリカはありません。

#### 運用ログの保持期間の制限 {#capping-operational-log-retention}

保持期間は`system.text_log`、`system.query_log`、`system.query_thread_log`、`system.query_views_log`、`system.trace_log`、`system.metric_log`、`system.asynchronous_metric_log`、および`system.part_log`に適用できます。

有効化は、すでにデータが存在するインスタンスに対する一度きりの一方的な手順であるため、どちらのバンドルもこれを自動的に行いません。保持ウィンドウを設定すると、それらのテーブル定義が構成と一致しなくなるため、ClickHouseはそれぞれをリネームして新しいテーブルを開始します。詳細は[置き換えられたログテーブル](#superseded-log-tables)をご覧ください。残された世代にはこれまで蓄積されたすべてのデータが含まれており、独自の保持期間を持たないため、同じ手順で回収しない限りディスク上に永久に残り、新しいウィンドウはそれ以降に書き込まれた行のみを制限します。両方を同時に有効にしてください:

```yaml
clickhouse:
  embedded:
    systemLogs:
      ttlDays: 14
      supersededTables: delete
```

その単一の`helm upgrade`は自己完結型です。`ttlDays`を空白から設定値に変更すると、ドロップインマウントが追加され、ClickHouseポッドがローリング再起動されます。再起動によりテーブルが置き換えられ、アップグレード後のジョブによってそれらが削除されます。`helm upgrade --wait`を使用してデプロイし、ジョブの実行前にポッドがローリングされるようにしてください。そうしないと、ジョブが確認した後に世代が表示され、次の`helm upgrade`でそれらが回収されます。

Docker Composeを使用する場合、`docker-compose.yml`内の`clickhouse`サービスの`clickhouse-log-ttl.xml`ボリュームのコメントを外し、`.env`で両方の変数を設定します:

```bash
CLICKHOUSE_SYSTEM_LOG_TTL_DAYS=14
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

スペースが回収されたら、`supersededTables`/`CLICKHOUSE_SUPERSEDED_LOG_TABLES`を`ignore`に戻すことができます。これにより、後続のClickHouseアップグレードが履歴を独自に破棄しないようにします。

#### 置き換えられたログテーブル {#superseded-log-tables}

ClickHouseは起動時に、各システムログテーブルが構成と一致しているかどうかを確認します。一致しない場合、既存のテーブルを`system.<name>_0`、次に`_1`、`_2`などにリネームし、新しいテーブルを開始します。これは保持ウィンドウを変更したとき、またはシステムログスキーマを変更するClickHouseアップグレード時に発生します。

テーブルのリネームはデータをコピーしないため、追加のディスク容量を消費しません。置き換えられたテーブルの後続の処理は、元のテーブルに依存します。置き換えられた瞬間にライブテーブルが持っていた保持期間を引き継ぐためです。初めて保持を有効にした場合、置き換えられるテーブルには保持期間がないため、これまでに蓄積されたすべての履歴を保持し、無期限に維持されます。後でウィンドウを変更すると、すでにTTLを持つテーブルが置き換えられるため、それらは独自に期限切れになり、空のテーブルが残ります。ClickHouseはテーブル自体を削除することはないため、長期間稼働するインスタンスではいずれの場合でも蓄積されます。

置き換えられたテーブルはデフォルトで保持されるため、アップグレードが独自に運用履歴を破棄することはありません。代わりにそれらを削除するには、ポリシーを`delete`に設定します。これは`docker compose up`および各`helm upgrade`で実行されます:

```bash
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

Helmチャートでは、同じポリシーを値として設定します:

```yaml
clickhouse:
  embedded:
    systemLogs:
      supersededTables: delete
```

置き換えられたテーブルを削除すると、そのディスク領域が回収されます。ライブテーブルや、置き換えられてから書き込まれた行には影響しません。

ポリシーを変更せずに一度だけスペースを回収するには、手動でテーブルを削除します:

```sql
SELECT name FROM system.tables WHERE database = 'system' AND match(name, '_log_[0-9]+$');
DROP TABLE IF EXISTS system.text_log_0 SYNC;
```

`system`データベースは`Atomic`エンジンを使用しており、通常の`DROP TABLE`を`database_atomic_delay_before_drop_table_sec`（デフォルトでは8分）延期します。`SYNC`はデータを直ちに削除するため、ディスクがいっぱいになってこれらのテーブルを削除する場合に適しています。


### ストレージ {#storage}

ファイル（例: フレームワークおよびライブラリのバイナリ）を保存するためのソリューションも必要です。Tuistサーバーは、サーバー所有のアーティファクト用にS3互換ストレージおよびAzure Blob Storageをサポートしています。

> [!TIP]
> **最適化されたキャッシング**
>
> 主な目的がキャッシュレイテンシの削減である場合、サーバー全体をセルフホストする必要はないかもしれません。CIまたは開発者ネットワークの近くにセルフホスト型Kuraノードをデプロイし、ホスト型Tuistサーバーまたはセルフホスト型サーバーに接続できます。
>
> <.localized_link href="/guides/cache/self-host">セルフホスト型キャッシュガイド</.localized_link>をご覧ください。


### セルフホスト型Kuraノード {#self-hosted-cache-nodes}

セルフホスト型Tuistサーバーでセルフホスト型Kuraノードを使用するには:

1. Tuistサーバーで`KURA_CONTROL_PLANE_CLIENT_ID`および`KURA_CONTROL_PLANE_CLIENT_SECRET`を設定します。クライアントIDは**UUIDである必要があります**。<.localized_link href="/guides/cache/self-host#control-plane-client">セルフホスト型キャッシュガイド</.localized_link>のコマンドを使用してUUIDとランダムなシークレットを生成し、デプロイメントのシークレットに保存します。
2. 同じコントロールプレーンの認証情報を使用して、<.localized_link href="/guides/cache/self-host">セルフホスト型キャッシュガイド</.localized_link>に従ってKuraノードをデプロイします。
3. 各Kuraノードを`KURA_REGISTRATION_URL`および`KURA_ADVERTISED_HTTP_URL`で設定します。登録ハートビートにより、サーバーはCLIに広告できる準備完了のクライアント向けKuraエンドポイントを認識します。

## 設定 {#configuration}

サービスの設定は、環境変数を使用してランタイム時に行われます。これらの変数は機密性が高いため、暗号化して安全なパスワード管理ソリューションに保存することを推奨します。Tuistはこれらの変数を細心の注意を払って扱い、ログに表示されないようにしています。

> [!NOTE]
> **起動時のチェック**
>
> 必要な変数は起動時に検証されます。不足している変数がある場合、起動は失敗し、エラーメッセージで不足している変数が詳細に示されます。


### ライセンス設定 {#license-configuration}

オンプレミスユーザーとして、ライセンスが付与され、これを環境変数として公開する必要があります。ライセンスはデプロイメントの検証と、サービスが契約条件の範囲内で実行されていることを保証するために使用されます。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | サービスレベル契約に署名した後に提供されるライセンス。標準のライセンスキー、またはサーバーが外部サービスに接続できないエアギャップ環境で使用されるbase64エンコードされた証明書のいずれかを受け入れます。 | はい | | `******` |

> [!WARNING]
> **有効期限**
>
> ライセンスには有効期限があります。ライセンスの有効期限が30日未満の場合、サーバーと対話するTuistコマンドを使用している間に警告が表示されます。ライセンスの更新をご希望の場合は、[contact@tuist.dev](mailto:contact@tuist.dev)までお問い合わせください。


### 基本環境設定 {#base-environment-configuration}

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_APP_URL` | インターネットからインスタンスにアクセスするためのベースURL | はい | | https://tuist.dev |
| `TUIST_SECRET_KEY_BASE` | 情報（例: Cookie内のセッション）を暗号化するために使用するキー | はい | | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD` | ハッシュ化されたパスワードを生成するためのペッパー | いいえ | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS` | ランダムなトークンを生成するためのシークレットキー | いいえ | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS_PREVIOUS` | 以前の`TUIST_SECRET_KEY_TOKENS`。ローテーション前に発行されたトークンの検証を引き続き行います。有効期限が切れたら（30日後）削除してください。 | いいえ | | |
| `TUIST_SECRET_KEY_ENCRYPTION` | 機密データのAES-GCM暗号化用キー。32バイトを超える値は最初の32バイトに切り詰められます。`TUIST_SECRET_KEY_ENCRYPTION_KEYS`の使用を推奨します。 | いいえ | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_ENCRYPTION_KEYS` | カンマ区切りの`id:base64`暗号化キー。それぞれ32バイト（`openssl rand -base64 32`）。最初のキーが新しいデータを暗号化し、他のキーおよび`TUIST_SECRET_KEY_ENCRYPTION`（ID `V1`）は既存データの復号を引き続き行います。既存データを現在のキーに移行するには、`bin/tuist eval 'Tuist.Release.reencrypt_vault("<id>")'`を使用します。 | いいえ | | `k2:3q2+7w...` |
| `TUIST_SECRET_KEY_ENCRYPTION_CURRENT_KEY` | 新しいデータを暗号化するキーのID。`TUIST_SECRET_KEY_ENCRYPTION_KEYS`の最初のキーではない場合に指定します。 | いいえ | | `V1` |
| `TUIST_USE_IPV6` | `1`の場合、アプリがIPv6アドレスを使用するように構成されます。 | いいえ | `0` | `1`|
| `TUIST_LOG_LEVEL` | アプリで使用するログレベル | いいえ | `info` | [ログレベル](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |
| `TUIST_GITHUB_APP_NAME` | GitHubアプリのスラッグ。`https://github.com/apps/<slug>`から取得します。アプリのインストールに必要です。<.localized_link href="/guides/server/self-host/server#platform-github">GitHub</.localized_link>を参照してください | いいえ | | `my-app` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 自動PRコメントの投稿など、追加機能を有効化するためにGitHubアプリで使用されるbase64エンコードされた秘密鍵 | いいえ | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` | |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | 自動PRコメントの投稿など、追加機能を有効化するためにGitHubアプリで使用される秘密鍵。**特殊文字の問題を避けるため、base64エンコード版の使用を推奨します** | いいえ | `-----BEGIN RSA...` | |
| `TUIST_OPERATOR_EMAIL_DOMAIN` | メールアドレスが`@<this-domain>`で終わり、その所有権を確認したユーザーは、操作関連URL（`/ops/*`）にアクセスできます。未設定の場合、誰もアクセスできません。[Operations](#operations)を参照してください | いいえ | | `example.com` |
| `TUIST_SERVER_VERSION_IDENTIFIER` | サーバーインスタンスを識別するためにダッシュボードのナビゲーションバーにバッジとして表示されるラベル（例: バージョン番号またはブランチ名） | いいえ | 開発環境でのGitブランチ | `v1.2.3` |
| `TUIST_WEB` | Webサーバーのエンドポイントを有効化 | いいえ | `1` | `1`または`0` |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` | サインインなしでビルドおよびテストのインサイトを送信することを許可します。セットアップとセキュリティ要件については[Network-trusted access](#network-trusted-access)を参照してください。 | いいえ | `false` | `true` |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS` | サインインなしでキャッシュの読み書きを許可します。セットアップとセキュリティ要件については[Network-trusted access](#network-trusted-access)を参照してください。 | いいえ | `false` | `true` |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | トレースを送信するためのOpenTelemetry CollectorのgRPCエンドポイント | いいえ | | `http://localhost:4317` |
| `TUIST_LOKI_URL` | ログを送信するためのLoki互換エンドポイントのベースURL（例: Grafana AlloyまたはLoki） | いいえ | | `http://localhost:3100` |

> [!WARNING]
> **アプリをHTTPS経由で提供**
>
> セッションCookieには`Secure`フラグが設定されているため、通常の`http://`通信ではブラウザによって拒否され、ユーザーはサインインできません。サーバーの手前でTLSを終了し（内部CAの証明書を使用したリバースプロキシで十分）、内部またはVPN限定のデプロイメントであっても`TUIST_APP_URL`を`https://` URLに設定してください。

#### リバースプロキシ背後のクライアントアドレス {#client-addresses-behind-a-reverse-proxy}

サーバーはクライアントアドレスに基づいてサインインとAPIレート制限を管理し、リクエストをログに記録します。リバースプロキシの背後では、`X-Forwarded-For`からそのアドレスを読み取り、プライベートネットワーク（RFC 1918、キャリアグレードNAT、ループバック、リンクローカル、またはIPv6ユニークローカルアドレス）上のプロキシが書き込んだ情報だけを信頼します。ヘッダー内の最も右側にあるパブリックアドレスを採用するため、クライアントがヘッダーを送信して自身のアドレスを選択することはできません。`203.0.113.7:51234`のようにポートを含むエントリも読み取られます。

プロキシがパブリックアドレスからサーバーに接続する場合、サーバーはそのヘッダーを無視し、すべてのリクエストはプロキシからのものとして扱われるため、すべてのクライアントが1つのレート制限枠を共有します。クライアントごとの制限を維持するには、プライベートネットワーク経由でプロキシをサーバーに接続してください。以前のバージョンでは、どの接続からも左端の`X-Forwarded-For`エントリを取得していました。

### データベース設定 {#database-configuration}

以下の環境変数はデータベース接続の設定に使用されます。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | PostgresデータベースにアクセスするためのURL。URLには認証情報を含める必要があることに注意してください | はい | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_SCHEMA` | Tuistのアプリケーションテーブルで使用されるPostgreSQLスキーマ。データベースポリシーで`public`スキーマの使用が禁止されている場合に設定してください。スキーマ名は引用符のないPostgreSQL識別子である必要があります。 | いいえ | `public` | `tuist` |
| `TUIST_MIGRATION_DATABASE_URL` | `Tuist.Release.migrate`のみで使用されるオプションのPostgres URL。`DATABASE_URL`がより制限されたランタイムロールを指している場合、これを所有者ロールのURLに設定してください。 | いいえ | `DATABASE_URL` | `postgres://owner:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_RUNTIME_ROLE` | マイグレーション完了後にアプリケーションテーブルの権限を付与すべきランタイムPostgresロール。Webサーバーがスキーマ所有者として接続すべきでない場合に`TUIST_MIGRATION_DATABASE_URL`と併用してください。 | いいえ | | `tuist_web` |
| `TUIST_CLICKHOUSE_URL` | ClickHouseデータベースにアクセスするためのURL。URLには認証情報を含める必要があることに注意してください | いいえ | | `http://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | trueの場合、データベースへの接続に[SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security)を使用します。`TUIST_DATABASE_SSL_VERIFY`が有効でない限り、サーバー証明書は検証されません | いいえ | `1` | `1` |
| `TUIST_DATABASE_SSL_VERIFY` | trueの場合、データベースサーバー証明書は信頼されたCAにチェーンし、`DATABASE_URL`ホストと一致する必要があります。`TUIST_USE_SSL_FOR_DATABASE`が必要です。有効化することを推奨します | いいえ | `0` | `1` |
| `TUIST_DATABASE_SSL_CA_CERT_FILE` | データベースサーバーの検証に使用されるCA証明書を含むPEMファイルへのパス。未設定の場合、オペレーティングシステムのトラストストアが使用されます | いいえ | | `/etc/tuist/rds-global-bundle.pem` |
| `TUIST_DATABASE_POOL_SIZE` | コネクションプールで開いたままにするコネクション数 | いいえ | `10` | `10` |
| `TUIST_DATABASE_QUEUE_TARGET` | プールからチェックアウトされたすべてのコネクションがキュー間隔を超えたかどうかを確認する間隔（ミリ秒単位）[(詳細情報)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | いいえ | `300` | `300` |
| `TUIST_DATABASE_QUEUE_INTERVAL` | プールが新しいコネクションのドロップを開始すべきかを判断するために使用するキュー内の閾値時間（ミリ秒単位）[(詳細情報)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | いいえ | `1000` | `1000` |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouseバッシャーフラッシュ間の時間間隔（ミリ秒単位） | いいえ | `5000` | `5000` |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE` | 強制フラッシュ前の最大ClickHouseバッファサイズ（バイト単位） | いいえ | `1000000` | `1000000` |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE` | 実行するClickHouseバッファプロセスの数 | いいえ | `5` | `5` |

デフォルトでは、Tuistはデータベース接続を暗号化しますがサーバー証明書を検証しないため、ネットワーク経路上の攻撃者がデータベースになりすます可能性があります。これを検証するには`TUIST_DATABASE_SSL_VERIFY=1`を設定してください。Amazon RDSやGoogle Cloud SQLのようにプロバイダーが独自のCAで証明書に署名する場合、そのCAバンドルをダウンロードしてコンテナにマウントし、`TUIST_DATABASE_SSL_CA_CERT_FILE`でそれを指すようにしてください。`DATABASE_URL`内のホストは証明書内の名前またはIPアドレスと一致する必要があります。検証を有効にした場合、これらのチェックに失敗する証明書はすべてのデータベース接続を失敗させるため、有効化後はサーバーログで`Bad Certificate`または`Unknown CA`を確認してください。

`TUIST_DATABASE_SCHEMA`が`public`でない場合、リリースマイグレーションはEctoマイグレーションチェーンを実行する前に、スキーマが存在しなければ作成します。マイグレーションロールがスキーマを作成できない場合は、事前にスキーマを作成し、マイグレーションロールをその所有者にしてください。

Tuistはセッション`search_path`を設定することで、接続をカスタムスキーマに向けます。一部のプール型またはプロキシ型Postgres構成（例えばPgBouncer、または起動パラメーターを制限するマネージドデータベース）ではこれが適用されず、セッションは`public`にフォールバックします。これはマイグレーション中に`permission denied for schema public`として表面化します。このような構成を通じて接続する場合は、プロキシに関係なくすべてのセッションがそこから開始されるよう、ロール自体にスキーマを固定してください：

```sql
CREATE SCHEMA IF NOT EXISTS tuist AUTHORIZATION <migration_role>;
ALTER ROLE <migration_role> IN DATABASE <database> SET search_path = tuist;
-- If the web server connects as a separate runtime role (TUIST_DATABASE_RUNTIME_ROLE):
ALTER ROLE <runtime_role> IN DATABASE <database> SET search_path = tuist;
```

### 認証環境設定 {#authentication-environment-configuration}

[アイデンティティプロバイダー（IdP）](https://en.wikipedia.org/wiki/Identity_provider)を通じて認証を容易にします。これを利用するには、選択したプロバイダーに必要なすべての環境変数がサーバー環境に存在することを確認してください。**変数が欠落している**と、Tuistはそのプロバイダーを bypass します。

#### メールとパスワード {#email-and-password}

メールとパスワードによるサインインおよびセルフサービス登録は組み込まれており、デフォルトで有効です。アイデンティティプロバイダーを必須にしたいインスタンス（例えばSSOを強制する場合）では、これらを完全に無効にできます。これにより、ログイン体験からメール/パスワードフォーム、サインアップリンク、パスワードリセットフローが削除され、CLIが使用するメール/パスワードエンドポイント（`tuist auth`）を含む、一致するすべてのサーバーサイドエンドポイントが閉じられます。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_EMAIL_AUTH_ENABLED` | メールとパスワードを使用してサインインおよび登録できるかどうか。ログインページからメール/パスワードフォーム、サインアップリンク、パスワードリセットフローを削除し、一致するサーバーサイドエンドポイントを閉じるには`0`に設定してください | いいえ | `1` | `0` |

#### 設定済みアイデンティティプロバイダーの無効化 {#disabling-a-configured-identity-provider}

デフォルトでは、プロバイダーは設定されるとサインインオプションとして表示されます。プロバイダーを設定されたままにし（資格情報は設定された状態）、ログインおよびサインアップページから削除するには、対応するレバーを`0`に設定してください。GitHub、Google、Appleの場合、これによりサインインコールバックも閉じられるため、この方法はエンドツーエンドで利用できなくなります。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_AUTH_ENABLED` | GitHubを使用してサインインできるかどうか（アプリがサインインと資格情報を共有する理由については[GitHub](#github)セクションを参照） | いいえ | `1` | `0` |
| `TUIST_GOOGLE_AUTH_ENABLED` | Googleを使用してサインインできるかどうか | いいえ | `1` | `0` |
| `TUIST_OKTA_AUTH_ENABLED` | 設定済みのOktaプロバイダーがサインインオプションとして表示されるかどうか | いいえ | `1` | `0` |
| `TUIST_APPLE_AUTH_ENABLED` | Appleを使用してサインインできるかどうか | いいえ | `1` | `0` |

#### GitHub {#github}

[GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)を使用した認証を推奨しますが、[OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)も使用できます。GitHubが指定するすべての必須環境変数をサーバー環境に含めるようにしてください。変数が欠落している場合、TuistはGitHub認証を無視します。GitHubアプリを適切にセットアップするには：
- GitHubアプリの一般設定で：
    - `Client ID`をコピーして`TUIST_GITHUB_APP_CLIENT_ID`として設定します
    - 新しい`client secret`を作成してコピーし、`TUIST_GITHUB_APP_CLIENT_SECRET`として設定します
    - `Callback URL`を`http://YOUR_APP_URL/users/auth/github/callback`として設定します。`YOUR_APP_URL`にはサーバーのIPアドレスも指定できます。
- 以下の権限が必要です：
  - リポジトリ：
    - プルリクエスト：読み取りおよび書き込み
  - アカウント：
    - メールアドレス：読み取り専用

`Permissions and events`の`Account permissions`セクションで、`Email addresses`権限を`Read-only`に設定します。

次に、Tuistサーバーが実行される環境で以下の環境変数を公開する必要があります：

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHubアプリケーションのクライアントID | はい | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | アプリケーションのクライアントシークレット | はい | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_AUTH_ENABLED` | GitHubを使用してサインインできるかどうか。プラットフォーム統合（PRコメントなど）用に構成したGitHub Appは、サインインとクライアント資格情報を共有するため、 otherwise ログインオプションとして表示されます。Appを維持しながらログインページからGitHubを削除するには`0`に設定してください | いいえ | `1` | `0` |

#### Google {#google}

[OAuth 2](https://developers.google.com/identity/protocols/oauth2)を使用してGoogleでの認証をセットアップできます。そのためには、OAuthクライアントIDタイプの新しい資格情報を作成する必要があります。資格情報を作成する際は、アプリケーションタイプとして「Webアプリケーション」を選択し、名前を`Tuist`とし、リダイレクトURIを`{base_url}/users/auth/google/callback`に設定します。ここで`base_url`はホストされているサービスが実行されているURLです。アプリを作成したら、クライアントIDとシークレットをコピーし、それぞれ環境変数`GOOGLE_CLIENT_ID`および`GOOGLE_CLIENT_SECRET`として設定します。

> [!NOTE]
> **同意画面のスコープ**
>
> 同意画面を作成する必要がある場合があります。その際は、`userinfo.email`および`openid`スコープを追加し、アプリを内部向けとしてマークしてください。


#### Okta {#okta}

[OAuth 2.0](https://oauth.net/2/)プロトコルを使用してOktaでの認証を有効にできます。そのためには、<.localized_link href="/guides/integrations/authentication/sso#okta">これらの手順</.localized_link>に従ってOktaで[アプリを作成](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)する必要があります。

Oktaアプリケーションのセットアップ中にクライアントIDとシークレットを取得したら、以下の環境変数を設定する必要があります：

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID` | Oktaに対して認証するためのクライアントID。数値は組織IDである必要があります | はい | | |
| `TUIST_OKTA_1_CLIENT_SECRET` | Oktaに対して認証するためのクライアントシークレット | はい | | |

数値`1`は組織IDに置き換える必要があります。通常は1ですが、データベースで確認してください。

### ストレージ環境の構成 {#storage-environment-configuration}

 Tuistは、APIを通じてアップロードされたアーティファクトを保管するためにストレージが必要です。Tuistが効果的に動作するためには、**サポートされているストレージソリューションのいずれかを構成することが不可欠**です。

サーバーアーティファクトのバックエンドを選択するには`TUIST_OBJECT_STORAGE_PROVIDER`を設定します：

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_OBJECT_STORAGE_PROVIDER` | サーバーアーティファクトのストレージバックエンド。S3互換ストレージには`s3`、Azure Blob Storageには`azure_blob`を使用します | いいえ | `s3` | `azure_blob` |

#### S3準拠のストレージ {#s3compliant-storages}

アーティファクトの保存には、S3準拠のストレージプロバイダーを自由に使用できます。ストレージプロバイダーとの統合を認証および構成するには、以下の環境変数が必要です：

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_S3_ACCESS_KEY_ID`または`AWS_ACCESS_KEY_ID` | ストレージプロバイダーに対して認証するためのアクセスキーID | はい | | `AKIAIOSFOD` |
| `TUIST_S3_SECRET_ACCESS_KEY`または`AWS_SECRET_ACCESS_KEY` | ストレージプロバイダーに対して認証するためのシークレットアクセスキー | はい | | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION`または`AWS_REGION` | バケットが存在するリージョン | いいえ | `auto` | `us-west-2` |
| `TUIST_S3_ENDPOINT`または`AWS_ENDPOINT` | ストレージプロバイダーのエンドポイント | はい | | `https://s3.us-west-2.amazonaws.com` |
| `TUIST_S3_BUCKET_NAME` | アーティファクトが保存されるバケットの名前 | はい | | `tuist-artifacts` |
| `TUIST_S3_CA_CERT_PEM` | S3 HTTPS接続を検証するためのPEMエンコードCA証明書。自己署名証明書や内部認証局を使用するエアギャップ環境で役立ちます。 | いいえ | システムCAバンドル | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT` | ストレージプロバイダーへの接続確立のタイムアウト（ミリ秒） | いいえ | `3000` | `3000` |
| `TUIST_S3_RECEIVE_TIMEOUT` | ストレージプロバイダーからデータを受信するためのタイムアウト（ミリ秒） | いいえ | `5000` | `5000` |
| `TUIST_S3_POOL_TIMEOUT` | ストレージプロバイダーへの接続プールのタイムアウト（ミリ秒）。タイムアウトなしにするには`infinity`を使用します | いいえ | `5000` | `5000` |
| `TUIST_S3_POOL_MAX_IDLE_TIME` | プール内接続の最大アイドル時間（ミリ秒）。接続を無期限に維持するには`infinity`を使用します | いいえ | `infinity` | `60000` |
| `TUIST_S3_POOL_SIZE` | プールあたりの最大接続数 | いいえ | `500` | `500` |
| `TUIST_S3_POOL_COUNT` | 使用する接続プールの数 | いいえ | システムスケジューラーの数 | `4` |
| `TUIST_S3_PROTOCOL` | ストレージプロバイダーに接続する際に使用するプロトコル（`http1`または`http2`） | いいえ | `http1` | `http1` |
| `TUIST_S3_VIRTUAL_HOST` | URLをバケット名をサブドメイン（仮想ホスト）として構築するかどうか | いいえ | `false` | `1` |

> [!NOTE]
> **環境変数からのAWS Web ID認証**
>
> ストレージプロバイダーがAWSで、Web IDトークンを使用して認証したい場合は、環境変数`TUIST_S3_AUTHENTICATION_METHOD`を`aws_web_identity_token_from_env_vars`に設定できます。Tuistは従来のAWS環境変数を使用してそのメソッドを利用します。


#### Google Cloud Storage {#google-cloud-storage}
Google Cloud Storageの場合は、[こちらのドキュメント](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)に従って`AWS_ACCESS_KEY_ID`と`AWS_SECRET_ACCESS_KEY`のペアを取得してください。`AWS_ENDPOINT`は`https://storage.googleapis.com`に設定する必要があります。その他の環境変数は、他のS3準拠ストレージと同じです。

#### Azure Blob Storage {#azure-blob-storage}

Azure Blob Storageの場合、`TUIST_OBJECT_STORAGE_PROVIDER=azure_blob`を設定し、Azureストレージアカウントの資格情報を構成します：

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_AZURE_STORAGE_ACCOUNT_NAME` | Azure Storageアカウント名 | はい | | `tuiststorage` |
| `TUIST_AZURE_STORAGE_ACCOUNT_KEY` | Azure Blob RESTリクエストおよびSAS URLに署名するために使用されるストレージアカウントアクセスキー | はい | | `******` |
| `TUIST_AZURE_BLOB_CONTAINER_NAME` | サーバーのアーティファクトが保存されるコンテナ | はい | | `tuist-artifacts` |
| `TUIST_AZURE_BLOB_ENDPOINT` | Blobサービスのエンドポイント。省略すると`https://<account>.blob.core.windows.net`を使用します | いいえ | アカウント名から派生 | `https://tuiststorage.blob.core.windows.net` |
| `TUIST_AZURE_BLOB_SERVICE_VERSION` | 署名付きリクエストおよびSAS URLに使用されるAzure Blob REST APIバージョン | いいえ | `2020-12-06` | `2020-12-06` |

Helmチャートを使用する場合は、`server.storage.provider=azure_blob`を設定し、`server.azureBlob.*`を入力してください。チャートのトップレベル設定である`objectStorage`はS3互換のままです。これは、オプションのキャッシュおよびレジストリミラーのワークロードが引き続きS3互換ストレージを想定しているためです。これらのワークロードが無効でサーバーがAzure Blobを使用する場合は、`objectStorage.mode=external`を設定し、外部オブジェクトストレージのエンドポイントと資格情報を空にして、組み込みMinIOサービスのデプロイを回避してください。

#### アーティファクトの保持 {#artifact-retention}

セルフホストされたインスタンスでは、アーティファクトのクリーンアップはデフォルトで無効になっています。サポートされている各アーティファクトタイプには独自の環境変数があります。そのアーティファクトタイプのクリーンアップを有効にするには、変数を正の整数の日数に設定してください。変数を未設定または空白のままにすると、そのアーティファクトタイプのクリーンアップのみが無効になります。

```bash
TUIST_CACHE_ARTIFACT_RETENTION_DAYS=30
TUIST_APP_PREVIEW_RETENTION_DAYS=30
TUIST_BUILD_ARCHIVE_RETENTION_DAYS=60
TUIST_RUN_ARTIFACT_RETENTION_DAYS=30
TUIST_TEST_ATTACHMENT_RETENTION_DAYS=30
TUIST_SHARD_BUNDLE_RETENTION_DAYS=14
```

Helmチャートを使用する場合、同じウィンドウをマップとして構成します：

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

6つのキーはすべてオプションです。この例では、サポートされているすべてのアーティファクトタイプを独立した保持ウィンドウで有効にします。キーを省略するか、その値を空白のままにすると、そのアーティファクトタイプのクリーンアップは無効のままになります。セルフホストされた保持ウィンドウには30日の最大値はありません。正の整数ではない設定値の場合、サーバーは起動時に失敗します。

保持変数を変更した後、サーバーを再起動してください。キューに入れられたセルフホストのクリーンアップバッチはすべて、ファイルを削除する前に現在の構成を確認するため、変数の設定解除や空白化、またはウィンドウの増加は、再起動後の保留中のジョブからもファイルを保護します。

| 環境変数 | オブジェクトストレージから削除されるアーティファクトファイル |
| --- | --- |
| `TUIST_CACHE_ARTIFACT_RETENTION_DAYS` | Xcodeキャッシュ、レガシーコンテンツアドレサブルストレージキャッシュ、モジュールキャッシュ、およびGradleキャッシュファイル |
| `TUIST_APP_PREVIEW_RETENTION_DAYS` | アプリプレビューのビルドとアイコン |
| `TUIST_BUILD_ARCHIVE_RETENTION_DAYS` | 現在およびレガシーのビルドアーカイブ |
| `TUIST_RUN_ARTIFACT_RETENTION_DAYS` | 期限切れの実行のアーティファクトプレフィックスの下に保存されているすべてのオブジェクト（結果バンドル、呼び出しレコード、セッションアーカイブを含む） |
| `TUIST_TEST_ATTACHMENT_RETENTION_DAYS` | テスト実行の添付ファイル |
| `TUIST_SHARD_BUNDLE_RETENTION_DAYS` | テストシャードバンドル |

スケジュールされたクリーンアップはアーティファクトブロブのみを削除します。対応するPostgreSQLおよびClickHouseの行は保持されるため、ダウンロードの有効期限が切れた後でも、ビルド、テスト、実行、プレビュー、およびシャードのメタデータはダッシュボードで表示されたままになります。この構成はClickHouseテーブルの保持ルールを変更しません。

### メール構成 {#email-configuration}

Tuistは、ユーザー認証およびトランザクション通知（パスワードのリセット、アカウント通知など）のためにメール機能を必要とします。現在、メールプロバイダーとして**Mailgunのみがサポートされています**。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_MAILGUN_API_KEY` | Mailgunでの認証に使用するAPIキー | はい* | | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN` | メールの送信元となるドメイン | はい* | | `mg.tuist.io` |
| `TUIST_MAILING_FROM_ADDRESS` | 「From」フィールドに表示されるメールアドレス | はい* | | `noreply@tuist.io` |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | ユーザーからの返信用のオプションの返信先アドレス | いいえ | | `support@tuist.dev` |
| `TUIST_SKIP_EMAIL_CONFIRMATION` | 新規ユーザー登録時のメール確認をスキップします。有効にすると、ユーザーは自動的に確認され、登録後すぐにログインできます | いいえ | メールが構成されていない場合は`true`、メールが構成されている場合は`false` | `true`, `false`, `1`, `0` |

\* メール構成変数は、メールを送信する場合にのみ必要です。構成されていない場合、メール確認は自動的にスキップされます

> [!NOTE]
> **SMTPサポート**
>
> 一般的なSMTPサポートは現在利用できません。オンプレミス環境でのSMTPサポートが必要な場合は、要件について[contact@tuist.dev](mailto:contact@tuist.dev)までお問い合わせください。


> [!NOTE]
> **エアギャップ環境へのデプロイ**
>
> インターネットアクセスやメールプロバイダーの構成がないオンプレミス環境では、デフォルトでメール確認が自動的にスキップされます。ユーザーは登録後すぐにログインできます。メールを構成しているが確認をスキップしたい場合は、`TUIST_SKIP_EMAIL_CONFIRMATION=true`を設定してください。メールが構成されている場合にメール確認を必須にするには、`TUIST_SKIP_EMAIL_CONFIRMATION=false`を設定してください。

> [!NOTE]
> **メールのクォータとパスワードリセットリンク**
>
> メールが構成されている場合、招待メール（作成、一括送信、再送信）は、受信者ごとに5分間に1通まで、かつ組織および招待者ごとに時間あたり50通のバースト（毎時50通で補充）に制限されます。招待をキャンセルしても枠は回復せず、招待APIは枠が尽きた場合に`429`および`Retry-After`で応答します。複数のレプリカがある場合は、デプロイ全体でのクォータ管理のために共有Valkeyを構成してください。構成されているが利用できない場合、招待メールは拒否されます。パスワードリセットリンクは15分後に有効期限が切れます。


### Gitプラットフォーム構成 {#git-platform-configuration}

Tuistは<.localized_link href="/guides/server/authentication">Gitプラットフォームと統合</.localized_link>し、プルリクエストへのコメント自動投稿などの追加機能を提供できます。

#### GitHub {#platform-github}

セルフホスト型のTuistサーバーは、`https://tuist.dev`で動作するGitHub Appをインストールできません。GitHub Appは登録したサーバーに紐付けられるため、あなたのデプロイにはgithub.com上で独自のAppが必要です。

##### Appの登録 {#platform-github-registering-the-app}

GitHub組織が所有する[GitHub Appを作成](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)してください。OAuth Appを作成した場合を除き、認証用に作成したAppを再利用できます。次のように構成し、`YOUR_APP_URL`を`TUIST_APP_URL`の値に置き換えてください：

| 設定 | 値 |
| --- | --- |
| コールバックURL | `YOUR_APP_URL/users/auth/github/callback`および`YOUR_APP_URL/integrations/github/authorize` |
| セットアップURL | `YOUR_APP_URL/integrations/github/setup` |
| 更新時のリダイレクト | 有効 |
| Webhook URL | `YOUR_APP_URL/webhooks/github` |
| Webhookシークレット | 任意のランダムな文字列。`TUIST_GITHUB_APP_WEBHOOK_SECRET`として設定します |

以下のリポジトリ権限を付与してください：

| 権限 | アクセス |
| --- | --- |
| コンテンツ | 読み取り専用 |
| メタデータ | 読み取り専用 |
| Issues | 読み取りおよび書き込み |
| プルリクエスト | 読み取りおよび書き込み |
| Checks | 読み取りおよび書き込み |

また、**メンバー: 読み取り専用**の組織権限も付与してください。github.comでのセットアップ中に、Tuistは組織インストールを接続する人物がアクティブなGitHub組織所有者であることを確認し、単にリポジトリへのアクセス権を持つ人物ではないことを検証します。

Appを`Check run`、`Pull request`、および`Issue comment`イベントに登録してください。

GitHubがインストーラーをセットアップURLに送信できるように、**インストール中のユーザー承認（OAuth）をリクエスト**は無効のままにしてください。Tuistは、追加の`/integrations/github/authorize`コールバックを使用して別の承認ステップを開始し、インストールの所有権を検証します。GitHubでインストールが開始されると、インストーラーはTuist組織を選択します。GitHub組織でのインストールでは常にこの選択肢が表示され、Tuistで開始されたインストールはその組織を保持します。

##### サーバーの構成 {#platform-github-configuring-the-server}

以下の環境変数を設定し、サーバーを再起動してください：

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_NAME` | Appのスラグ。公開ページURL `https://github.com/apps/<slug>` の最後のパスコンポーネントです | はい | | `my-company-tuist` |
| `TUIST_GITHUB_APP_ID` | インストールの所有権を検証するために使用される数値のApp ID | はい | | `123456` |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHubアプリケーションのクライアントID | はい | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | アプリケーションのクライアントシークレット | はい | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHubアプリケーションのbase64エンコードされた秘密鍵。改行の扱いがプラットフォームに依存する `TUIST_GITHUB_APP_PRIVATE_KEY` よりも推奨されます | はい | | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |
| `TUIST_GITHUB_APP_WEBHOOK_SECRET` | GitHubアプリケーションで構成されたWebhookシークレット | いいえ | | `a4c1e0f2b8d6...` |

> [!IMPORTANT]
> **必要なAppの認証情報をすべて構成**
>
> 組織の統合ページにある **Install GitHub App** ボタンは、`TUIST_GITHUB_APP_NAME`、`TUIST_GITHUB_APP_CLIENT_ID`、`TUIST_GITHUB_APP_CLIENT_SECRET`、および秘密鍵がすべて設定されるまで無効のままです。インストールの所有権を検証するには、数値の `TUIST_GITHUB_APP_ID` も必要です。インストールURLにはAppのスラグが含まれるため、特に `TUIST_GITHUB_APP_NAME` が欠落していると、GitHubから404エラーが返されるリンクになります。

サーバーの再起動後、組織の管理者は <.localized_link href="/guides/integrations/gitforge/github">GitHub統合ガイド</.localized_link> に従ってAppをインストールし、リポジトリをプロジェクトに接続します。

##### OIDC認証はこれに依存します {#platform-github-oidc}

<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link> は、CIトークン内のリポジトリクレームをプロジェクトに接続されたリポジトリと照合します。接続はインストール済みのGitHub Appを通じてのみ作成できます。CIワークフローがOIDCで認証を行う前に、上記のセットアップを完了してください。

Tuistサーバーは、署名キーを取得するためにCIプロバイダーのOIDC発行元へのアウトバウンドアクセスも必要です：

| CIプロバイダー | ホスト |
| --- | --- |
| GitHub Actions | `token.actions.githubusercontent.com` |
| CircleCI | `oidc.circleci.com` |
| Bitrise | `token.builds.bitrise.io` |

##### GitHub Enterprise Server {#platform-github-enterprise-server}

上記の環境変数は、Tuistのgithub.com用Appのみを構成します。代わりにGitHub Enterprise Server（GHES）インスタンスとTuistを統合するには、組織の管理者が統合ページの **Enterprise server** タブに切り替え、GHESのベースURLを入力します。Tuistは、GHESインスタンスに新しいTuist Appを登録するためのGitHubの [Appマニフェストフロー](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) を案内します。新しいAppの認証情報はインストールごとに暗号化されて保存され、追加の `TUIST_GITHUB_APP_*` 環境変数は不要です。

#### Origin {#platform-origin}

セルフホスト型のTuistサーバーには、独自のOriginアプリが必要です。デプロイのURLと署名キーで構成してください。インストールと認証情報が独立した状態を保つため、Tuist環境ごとに個別のアプリを登録してください。

##### Appの登録 {#platform-origin-registering-the-app}

1. Ed25519をサポートするOpenSSLを使用して、Ed25519署名キーペアを生成します：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out origin-app-private.pem
   openssl pkey -in origin-app-private.pem -pubout -out origin-app-public.pem
   ```

2. [Originアプリの設定](https://cursor.com/codebase/settings/apps) でアプリを作成します。`origin-app-public.pem` の内容を公開署名キーとして登録します。`origin-app-private.pem` は秘密に保ち、Cursorにアップロードするのではなく、Tuistサーバーに提供してください。
3. 以下の設定を行い、`YOUR_APP_URL` をTuistデプロイのHTTPSベースURLに置き換えてください：

   | 設定 | 値 |
   | --- | --- |
   | ホームページURL | `YOUR_APP_URL` |
   | リダイレクトURI | `YOUR_APP_URL/integrations/origin/setup` |
   | Webhook URL | `YOUR_APP_URL/webhooks/origin` |

4. 登録されたApp ID（`app_`で始まる）をコピーします。

Tuistはインストール中に以下の権限を要求します：

| スコープ | 用途 |
| --- | --- |
| `repository:pull_requests:read` | プルリクエストとその現在のヘッドコミットを検索します。 |
| `repository:pull_requests:reviews:write` | レポートコメントの読み取り、投稿、更新を行います。Originには対応するレビュー読み取り権限が含まれています。 |
| `repository:metadata:read` | リポジトリを検出し、デフォルトブランチを読み取ります。Originによって自動的に付与されます。 |

オプションのリポジトリWebhookイベントは選択しないでください。インストールライフサイクルの通知で十分です。ソースコードへのアクセス、マージ権限、およびチェックラン権限は不要です。

##### サーバーの構成 {#platform-origin-configuring-the-server}

以下の環境変数を設定し、サーバーを再起動してください：

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_ORIGIN_APP_ID` | Originアプリの設定からコピーしたApp ID。 | はい | | `app_...` |
| `TUIST_ORIGIN_APP_PRIVATE_KEY` | `BEGIN PRIVATE KEY`と`END PRIVATE KEY`の行、およびすべての改行を含む`origin-app-private.pem`の完全な内容。 | はい | | `-----BEGIN PRIVATE KEY-----...` |

秘密鍵をデプロイのシークレットマネージャーに保存してください。複数行のPEM形式を維持してください。この設定はbase64エンコードされた代替を受け付けません。鍵をソース管理にコミットしたり、ログに公開したりしないでください。両方の変数は同じ登録済みAppに属している必要があります。

Tuistサーバーは`api.cursor.com`へのアウトバウンドHTTPSアクセスが必要です。CursorはWebhook URLにリクエストを配信できる必要があり、管理者はブラウザでリダイレクトURIに戻れる必要があります。登録された両方のURLは、デプロイのHTTPSベースURLと一致している必要があります。

##### Appのインストール {#platform-origin-installing-the-app}

サーバーが再起動したら、管理者は**Settings → Integrations**を開き、Originの下にある**Connect**を選択して、適切なOriginアカウントとリポジトリへのAppアクセスを承認します。このフロー全体でTuist組織は保持されます。代わりにOriginから直接開始されたインストールでは、管理者にログインを促し、接続するTuist組織を選択させます。その後、**Add new project connection**を選択して、Tuistプロジェクトをネイティブリポジトリにリンクします。

プロジェクト接続と結果アップロードの要件については、<.localized_link href="/guides/integrations/gitforge/origin">Origin統合ガイド</.localized_link>に従ってください。Appをインストールしてもビルドまたはテストワークフローは開始されません。それらのワークフローは引き続き結果をTuistサーバーに報告します。

#### Entire {#platform-entire}

セルフホスト型のTuistサーバーには、独自のEntireプラグインが必要です。デプロイのURLと署名キーで構成してください。Entireプラグインにはパートナー登録が必要なので、開始前にEntireに連絡してください。インストールと認証情報が独立した状態を保つため、Tuist環境ごとに個別のプラグイン、または少なくとも個別の署名キーを登録してください。

##### プラグインの登録 {#platform-entire-registering-the-plugin}

1. Ed25519をサポートするOpenSSLを使用して、Ed25519署名キーペアを生成します：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out entire-plugin-private.pem
   openssl pkey -in entire-plugin-private.pem -pubout -out entire-plugin-public.pem
   ```

2. Entireの[プラグイン登録ガイド](https://docs.entire.com/guides/api/plugins/register)に従ってプラグインを登録します。`entire-plugin-public.pem`の内容、またはそれを公開するJWKS URLをプラグインの署名キーとして共有します。`entire-plugin-private.pem`は秘密に保ち、EntireではなくTuistサーバーに提供してください。
3. 以下のURLを設定し、`YOUR_APP_URL`をTuistデプロイのHTTPSベースURLに置き換えてください：

   | 設定 | 値 |
   | --- | --- |
   | インストール後URL | `YOUR_APP_URL/integrations/entire/callback` |
   | Webhook URL | `YOUR_APP_URL/webhooks/entire` |

4. Entireが確認したプラグインスラグと、提供されたWebhook署名キーURLを記録してください。

以下の権限を要求してください：

| 権限 | 用途 |
| --- | --- |
| `contents:read` | Trailイベントを受信し、ヘッドコミットを含むオープンおよびドラフト状態のTrailを検索します。 |
| `checks:write` | Tuistゲートを公開します。 |
| `findings:write` | 失敗したテストおよびflakyなテストの調査結果を公開し、解決済みにします。 |
| `discussions:write` | サマリーコメントを投稿および更新します。この権限を付与していないインストールでも、ゲートと調査結果は受信されます。 |

リポジトリへの書き込みアクセスは不要です。既存の登録に権限を追加する場合は、Entireに更新を依頼し、インストールが新しい権限を付与していることを確認してください。Entireの[Checks](https://docs.entire.com/guides/api/plugins/report-checks)、[Findings](https://docs.entire.com/guides/api/plugins/trail-findings)、および[Trail comments](https://docs.entire.com/guides/api/plugins/trail-comments.md)の契約を参照してください。

##### サーバーの構成 {#platform-entire-configuring-the-server}

以下の環境変数を設定し、サーバーを再起動してください：

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | Entireによって確認されたプラグインスラグ。 | はい | | `tuist` |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | `entire-plugin-private.pem`の完全な内容。`BEGIN PRIVATE KEY`行と`END PRIVATE KEY`行、およびすべての改行を含みます。 | はい | | `-----BEGIN PRIVATE KEY-----...` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | 登録時にEntireから提供されたWebhook署名キーURL。 | はい | | |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | JWKSを通じて署名キーを登録した場合のキーID。 | いいえ | | |
| `TUIST_ENTIRE_CORE_URL` | インストールリクエストに使用されるEntire Core URL。 | いいえ | `https://eu.auth.entire.io` | |

秘密鍵をデプロイのシークレットマネージャーに保存し、複数行のPEM形式を保持してください。鍵をソース管理にコミットしたり、ログに露出させたりしないでください。Tuist Helmチャートを使用する場合、代わりにPEMを1Passwordボルトの`ENTIRE_PLUGIN/private_key`として保存し、`server.config.managedSecrets`とともに`server.config.entirePluginKey.enabled`を有効にできます。アイテム名とフィールド名は`server.config.entirePluginKey.item`および`.field`で構成可能です。このマッピングではスラグやWebhook署名キーURLは設定されません。

Tuistサーバーは、Entire Coreおよびリポジトリを提供するリージョン別のEntire APIホスト（すべて`entire.io`または`entire.com`ドメイン下）へのアウトバウンドHTTPSアクセスを必要とします。TuistはインストールレシートとWebhook署名を検証し、短期間有効なリポジトリスコープのトークンを発行しますが、レポートリンクにトークンを埋め込むことはありません。

##### 統合の有効化 {#platform-entire-enabling-the-integration}

アプリケーションを展開する前にサーバーマイグレーションを適用し、その後`entire_trails`機能フラグをグローバルに有効にして、すべてのアカウントまたは選択したアカウントに統合を提供します。フラグを有効にしても、Entireでプラグインをインストールできるユーザーは変わりません。プラグインを所有するEntireプロジェクトの外で提供するには、Entireの担当者にお問い合わせください。この統合はTuistのCI実行構成とは独立しています。

アプリケーションをロールバックする場合は、`entire_trail_reports`テーブルを保持してください。これにより、後のアップグレードで進行中の公開を復旧できます。

管理者はその後、<.localized_link href="/guides/integrations/gitforge/entire">Entire統合ガイド</.localized_link>に従ってプラグインをインストールし、リポジトリをプロジェクトに接続します。プラグインをインストールしてもビルドまたはテストワークフローは開始されません。それらのワークフローは引き続き結果をTuistサーバーに報告します。

## ローカルでのテスト {#testing-locally}

インフラストラクチャにデプロイする前に、ローカルマシンでTuistサーバーをテストするために必要なすべての依存関係を含む包括的なDocker Compose構成を提供します：

- PostgreSQL 15
- 分析用ClickHouse 26.5
- 調整用ClickHouse Keeper
- S3互換ストレージ用MinIO
- ローカルセルフホストキャッシュテスト用Kura
- データベース管理用pgweb

> [!CAUTION]
> **ライセンスが必要**
>
> Tuistサーバー（ローカル開発インスタンスを含む）を実行するには、法的に有効な`TUIST_LICENSE`環境変数が必要です。ライセンスが必要な場合は、[contact@tuist.dev](mailto:contact@tuist.dev)までお問い合わせください。


**クイックスタート：**

1. 設定ファイルをダウンロードします：
   ```bash
   curl -O https://tuist.dev/server/self-host/docker-compose.yml
   curl -O https://tuist.dev/server/self-host/clickhouse-config.xml
   curl -O https://tuist.dev/server/self-host/clickhouse-log-level.xml
   curl -O https://tuist.dev/server/self-host/clickhouse-log-ttl.xml
   curl -O https://tuist.dev/server/self-host/clickhouse-keeper-config.xml
   curl -O https://tuist.dev/server/self-host/.env.example
   ```

2. 環境変数を設定します：
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE, TUIST_SECRET_KEY_BASE, and authentication credentials
   ```

   バンドルされたClickHouseサービスは、以下のオプションの運用ログ制御を受け入れます：

   | 環境変数 | 説明 | デフォルト | 例 |
   | --- | --- | --- | --- |
   | `CLICKHOUSE_SYSTEM_LOG_TTL_DAYS` | ClickHouse `system.*`ログテーブル（`text_log`、`query_log`、`trace_log`、`metric_log`、`part_log`など）の保持期間（日数） | `14` | `7` |
   | `CLICKHOUSE_TEXT_LOG_LEVEL` | ClickHouseサーバーロガーおよび`system.text_log`レベル | `information` | `warning` |
   | `CLICKHOUSE_SUPERSEDED_LOG_TABLES` | ClickHouseがシステムログテーブルを更新する際に残す`<name>_N`テーブルの扱い。`ignore`は保持し、`delete`は削除します | `ignore` | `delete` |

3. すべてのサービスを開始します：
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

   Apple Siliconでは、Docker DesktopがTuistおよび依存関係イメージの`linux/arm64`バリアントを自動的にプルします。デバッグ用にamd64エミュレーションを強制するには、`DOCKER_DEFAULT_PLATFORM=linux/amd64`を指定してComposeを実行します。

   バンドルされたcomposeファイルは、永続データのために名前付きDockerボリュームを使用します。これをホストバインドマウントに置き換える場合は、まずホストディレクトリを作成し、特にClickHouseおよびClickHouse Keeperのデータディレクトリをコンテナユーザーが書き込めるようにしてください。

4. http://localhost:8080でサーバーにアクセスします

**サービスエンドポイント：**
- Tuist Server: http://localhost:8080
- Kuraキャッシュ（HTTP + REAPI gRPCを同一ポートで提供）: http://localhost:4000
- MinIO Console: http://localhost:9003 （認証情報: `tuist` / `tuist_dev_password`）
- MinIO API: http://localhost:9002
- pgweb (PostgreSQL UI): http://localhost:8081
- Prometheus Metrics: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**一般的なコマンド：**

サービスのステータスを確認します：
```bash
docker compose ps
# or: podman compose ps
```

ログを表示します：
```bash
docker compose logs -f tuist
```

サービスを停止します：
```bash
docker compose down
```

すべてをリセットします（すべてのデータを削除）：
```bash
docker compose down -v
```

**設定ファイル：**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - 完全なDocker Compose構成
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse設定
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml) - ClickHouse Keeper設定
- [.env.example](/server/self-host/.env.example) - 環境変数の例ファイル

## Helmを使用したKubernetes {#kubernetes-with-helm}

Tuistは、Kubernetesへのデプロイ用の公式Helmチャートを提供しています。このチャートには、Tuistサーバーとキャッシュサービス、および必要に応じて外部プロバイダーに置き換えられる埋め込みインフラストラクチャ依存関係が含まれています。

### チャートのインストール {#installing-the-chart}

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY"
```

特定のチャートバージョンを固定するには：

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY" \
  --version 0.1.0
```

### ライセンス {#helm-license}

`server.license.key`値は、標準のライセンスキーと、エアギャップ環境向けの場合はBase64エンコードされたライセンス証明書の両方を受け入れます。サーバーはどちらであるかを自動検出します。

`--set`を使用してライセンスを渡すことで、迅速なインストールが可能です。値をバージョン管理で維持する場合は、ライセンスをHelm外で管理するKubernetes Secret（Vault、Sealed Secrets、SOPSなどを使用）に保存し、チャートからそれを参照するように設定します：

```yaml
# values.yaml
server:
  license:
    existingSecret: tuist-license
    existingSecretKeys:
      key: TUIST_LICENSE
      certificateBase64: ""
```

`existingSecretKeys.key`のエントリは、ライセンス値（ライセンスキー、またはエアギャップ環境向けの場合はBase64エンコードされたライセンス証明書）を保持するSecret内のフィールド名を指定します。`existingSecretKeys`下の各エントリはチャートの独自のキー名にデフォルト設定されるため、Secretに含まれていないエントリは上記の`certificateBase64`のように空文字列に設定してください。そうしないと、ポッドが存在しないキーを参照して起動に失敗します。チャートをインストールまたはアップグレードする前に、リリースネームスペースにSecretを作成してください。

ライセンスは単一のソースを通じてのみ設定してください：`server.license.key`または`server.license.existingSecret`。どちらも設定されていない場合、またはソースが組み合わされている場合、チャートのレンダリングは失敗します。`server.extraEnv`経由で渡されたライセンスはソースとしてカウントされないため、代わりに`existingSecret`を使用してください。

### インフラストラクチャ依存関係 {#helm-infrastructure-dependencies}

このチャートは、`postgresql`、`clickhouse`、および`objectStorage`の3つのインフラストラクチャ依存関係を管理します。それぞれはデフォルトで**埋め込み**モードとなり、チャートがこれらをクラスター内にデプロイすることを意味します。代わりに独自の外部インスタンスを参照するには、依存関係の`mode`を`external`に設定し、`values.yaml`に接続詳細を入力してください。例えば、外部PostgreSQLデータベースを使用する場合：

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

PostgreSQLの認証情報をHelm外で管理している場合は、代わりに既存のKubernetes Secretをチャートから参照するように設定してください：

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

チャートはSecretからホスト、ユーザー名、パスワードを読み取り、Kubernetesの環境変数置換を通じて`DATABASE_URL`を構成するため、パスワードはHelmマニフェストに含まれません。Secretのパスワード値はデータベースURLに挿入されるため、URLセーフである必要があります。

同じパターンが`clickhouse`と`objectStorage`にも適用されます。設定可能なフィールドの完全なセットについては、チャートの`values.yaml`内の各セクションにある`external`ブロックを参照してください。

### 共有スケジューリングとラベル {#helm-shared-scheduling-and-labels}

チャートは`global`の下に少量の共有ポッド設定を公開しており、オペレーターはすべてのワークロードで同じ値を繰り返すことなく、デプロイメントをクラスターに適応させることができます：

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

以下の必要がある場合に、これらの設定を使用してください：

- すべてのポッドにクラスター固有のラベルを追加する
- プライベートレジストリからミラー化されたイメージをプルする
- 専用のノードプールをターゲットにする
- Tuistワークロード用に予約された汚染されたノードへのポッド配置を許可する

### ワークロードアイデンティティとサービスアカウント {#helm-workload-identity}

チャートはアプリケーションワークロードごとにサービスアカウントのスコープを設定するため、必要な場所でのみアイデンティティを付与できます：

- `server.serviceAccount`はTuistサーバーのデプロイメントと移行ジョブに適用されます
- `cache.serviceAccount`はキャッシュのデプロイメントに適用されます

例えば、キャッシュがEKS上の外部S3バケットを使用する場合、埋め込みデータベースに同じIAMロールをアタッチすることなく、キャッシュワークロードに対してIRSAを有効にできます：

```yaml
cache:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/tuist-cache
```

### 互換性オーバーライド {#helm-compatibility-overrides}

チャートはストレージおよびメッシュ固有の調整をオプトイン方式に保ち、デフォルトの移植性を維持します：

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

- `cache.podSecurityContext`はデフォルトで空です。ストレージクラスまたはCSIドライバーがマウントされたボリュームで共有グループ所有権を必要とする場合は、`fsGroup`を設定してください。
- `clickhouse.embedded.service.nativePort`はClickHouseの標準的な`9000`ネイティブサービスポートにデフォルト設定され、サービスメッシュまたはプラットフォームの予約がそのポートと競合する場合に変更できます。
- `clickhouse.embedded.systemLogs.ttlDays`はデフォルトで空であり、`system.text_log`、`system.query_log`、`system.trace_log`、`system.metric_log`、および`system.part_log`などの埋め込み内部ログテーブルに対するClickHouseの無制限の保持を残します。これを設定するとそれらのテーブルが一度上書きされるため、`supersededTables: delete`と一緒に採用してください — <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">運用ログの保持期間の上限設定</.localized_link>を参照。
- `clickhouse.embedded.systemLogs.level`は埋め込みClickHouseサーバーロガーおよび`system.text_log`に対してデフォルトで`information`になります。`ttlDays`とは異なり、これはどのテーブル定義の一部でもないため、変更してもテーブルを上書きすることはありません。
- `clickhouse.embedded.systemLogs.supersededTables`はデフォルトで`ignore`になり、システムログテーブルを上書きした際にClickHouseが残す`<name>_N`テーブルの扱いを決定します。各`helm upgrade`でそれらを削除するには、`delete`に設定してください。
- `ttlDays`と`level`への編集は、両方が`subPath`マウントであり、ConfigMapの変更時にチャートがStatefulSetをローリングしないため、ClickHouseポッドが次回再起動した際に反映されます。

### 観測可能性 {#helm-observability}

チャートにはオプションの観測可能性スタック（OpenTelemetry Collector、Prometheus、Grafana、Loki、Tempo）が含まれています。これはデフォルトで**無効**になっています。`values.yaml`で有効にするには：

```yaml
# values.yaml
observability:
  enabled: true
```

有効にすると、Grafanaはログ、トレース、メトリクスのドリルダウンが事前構成された状態で利用可能になります。外部の観測可能性を使用する場合は、これを無効にしたまま`server.extraEnv`経由でエンドポイントを構成してください：

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

設定可能な値の完全なリストについては、チャートの[`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)を参照してください。

## デプロイメント {#deployment}

公式のTuist Dockerイメージは以下で利用可能です：
```
ghcr.io/tuist/tuist
```

公開されているイメージには、`.xcactivitylog`アーカイブ用の埋め込みLinuxビルド処理が含まれているため、セルフホスト型デプロイメントは追加のサービスを実行せずにビルドを処理できます — `ProcessBuildWorker` Obanジョブは各サーバーポッド上でインプロセスで実行されます。ビルド処理を専用レプリカセットにオフロードしたい場合（例えば、Webティアとは独立して解析スループットをスケールさせるため）、Helmチャートで`processor.enabled: true`を設定してください：チャートはキュー専用コンシューマーとして同じイメージをデプロイします（`TUIST_PROCESSOR_MODE=true`）。設定項目の完全なセットについては、[`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)を参照してください。

> [!NOTE]
> `.xcresult`の解析はXcodeの`xcresulttool`に依存しているため、macOSでのみ実行できます。CLIはセルフホスト型デプロイメントに対してこれを透過的に処理します：`tuist test`は非`tuist.dev`サーバーに対してデフォルトで**ローカル**処理モードとなり、開発者マシン（ビルド自体のために既にXcodeを持っている）でxcresultを解析し、構造化された結果をアップロードします。テスト結果は追加のインフラストラクチャなしで取り込まれます。

### Dockerイメージのプル {#pulling-the-docker-image}

以下のコマンドを実行することでイメージを取得できます：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

イメージは`linux/amd64`と`linux/arm64`の両方に対して公開されているため、DockerはホストのネイティブLinuxアーキテクチャを自動的に選択します。

または、特定のバージョンをプルします：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Dockerイメージのデプロイ {#deploying-the-docker-image}

Dockerイメージのデプロイメントプロセスは、選択したクラウドプロバイダーと組織の継続的デプロイメントアプローチによって異なります。[Kubernetes](https://kubernetes.io/)などのほとんどのクラウドソリューションやツールはDockerイメージを基本単位として利用しているため、このセクションの例は既存のセットアップとよく適合するはずです。

> [!WARNING]
> デプロイメントパイプラインでサーバーが稼働中であることを検証する必要がある場合は、`/ready`に対して`GET` HTTPリクエストを送信し、レスポンスで`200`ステータスコードが返されることを確認できます。


#### Fly {#fly}

[Fly](https://fly.io/)でアプリをデプロイするには、`fly.toml`設定ファイルが必要です。継続的デプロイメント（CD）パイプライン内で動的に生成することを検討してください。以下は参考用の例です：

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

その後、`fly launch --local-only --no-deploy`を実行してアプリを起動できます。以降のデプロイでは、`fly launch --local-only`を実行する代わりに、`fly deploy --local-only`を実行する必要があります。Fly.ioはプライベートDockerイメージのプルを許可していないため、`--local-only`フラグを使用する必要があります。


## Prometheusメトリクス {#prometheus-metrics}

Tuistはセルフホスト型インスタンスの監視を支援するため、`/metrics`でPrometheusメトリクスを公開しています。これらのメトリクスには以下が含まれます：

### Finch HTTPクライアントメトリクス {#finch-metrics}

TuistはHTTPクライアントとして[Finch](https://github.com/sneako/finch)を使用しており、HTTPリクエストに関する詳細なメトリクスを公開しています：

#### リクエストメトリクス
- `tuist_prom_ex_finch_request_count_total` - Finchリクエストの総数（カウンター）
  - ラベル: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTPリクエストの期間（ヒストグラム）
  - ラベル: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
  - バケット: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s
- `tuist_prom_ex_finch_request_exception_count_total` - Finchリクエスト例外の総数（カウンター）
  - ラベル: `finch_name`, `method`, `scheme`, `host`, `port`, `kind`, `reason`

#### コネクションプールキューメトリクス
- `tuist_prom_ex_finch_queue_duration_milliseconds` - コネクションプールキューでの待機時間（ヒストグラム）
  - ラベル: `finch_name`, `scheme`, `host`, `port`, `pool`
  - バケット: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 使用される前の接続のアイドル時間（ヒストグラム）
  - ラベル: `finch_name`, `scheme`, `host`, `port`, `pool`
  - バケット: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 5s, 10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Finchキュー例外の総数（カウンター）
  - ラベル: `finch_name`, `scheme`, `host`, `port`, `kind`, `reason`

#### コネクションメトリクス
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 接続確立にかかった時間（ヒストグラム）
  - ラベル: `finch_name`, `scheme`, `host`, `port`, `error`
  - バケット: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s
- `tuist_prom_ex_finch_connect_count_total` - 接続試行の総数（カウンター）
  - ラベル: `finch_name`, `scheme`, `host`, `port`

#### 送信メトリクス
- `tuist_prom_ex_finch_send_duration_milliseconds` - リクエスト送信にかかった時間（ヒストグラム）
  - ラベル: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - バケット: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 送信前の接続のアイドル時間（ヒストグラム）
  - ラベル: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - バケット: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms

すべてのヒストグラムメトリクスは、詳細な分析のために`_bucket`、`_sum`、および`_count`のバリアントを提供します。

### その他のメトリクス

Finchメトリクスに加えて、Tuistは以下のメトリクスを公開しています：
- BEAM仮想マシンのパフォーマンス
- カスタムビジネスロジックのメトリクス（ストレージ、アカウント、プロジェクトなど）
- データベースのパフォーマンス（Tuistホスト型インフラストラクチャを使用する場合）

## 運用 {#operations}

Tuistは`/ops/`の下に、インスタンスの管理に使用できる一連のユーティリティを提供しています。

> [!WARNING]
> **認証**
>
> メールドメインが`TUIST_OPERATOR_EMAIL_DOMAIN`と一致するユーザーのみが`/ops/`エンドポイントにアクセスできます。変数が設定されていない場合、誰もアクセスできません。自分が管理するメールボックスを持つドメインに設定してください。
>
> ユーザーは、確認メールやパスワードリセットメールに従う、Google、GitHub、またはAppleでサインインする、ワンタイムコードを入力する、あるいはエージェントサインインの検証済みメールアドレスを提示することで、アドレスの所有権を証明する必要があります。メールプロバイダーがない場合にデフォルトとなる自動確認されたアカウントは、証明を行うまで対象外です。アカウント作成後、アドレスが`TUIST_OPERATOR_EMAIL_DOMAIN`に含まれている間のみ証明が記録されるため、変数を設定または変更した後、その下でアドレスを証明していないオペレーターは再度証明を行う必要があります。これらのプロバイダーのいずれかでサインインするか、エージェントサインインを通じて作成されたアカウントは、作成時に証明を保持します。メールプロバイダーがない場合、パスワードで登録されたアカウントはこれらのプロバイダーをリンクできないため、Google、GitHub、またはAppleでサインインしてオペレーターアカウントを作成するか、メールプロバイダーを設定してください。
>
> このチェックが存在する前に作成されたアカウントはまだその証明を記録していないため、既存のオペレーターはパスワードをリセットするか、これらのプロバイダーのいずれかで一度サインインすることでアクセスを回復します。
>
> 証明のないオペレータードメイン内のアカウントが初めてその方法でアドレスを証明すると、Tuistはそのパスワード、パスキー、組織のシングルサインオンプロバイダーへのリンクを削除し、ブラウザとCLIからサインアウトします。これは、アドレスを登録した人が所有者ではない可能性があるためです。そのようなアカウントでのパスワードリセットも、新しいパスワードを設定することを除いて同じ動作を行います。アカウントに設定された認証アプリは残ります。所有者のものでない場合は、代わりに削除してください。オペレータードメイン外の確認済みアカウントは資格情報を保持します。所有者はプロバイダーを使用してサインインし続けるか、リセットを通じて新しいパスワードを設定します。
>
> SCIMプロビジョニングによって作成または名前変更されたアカウントは、所有者が証明を提供するまで証明を持ちません。


- **エラー（`/ops/errors`）：** アプリケーションで発生した予期しないエラーを表示できます。これはデバッグや問題の原因を理解するのに役立ち、問題が発生している場合には、この情報を共有いただくようお願いすることがあります。
- **ダッシュボード（`/ops/dashboard`）：** アプリケーションのパフォーマンスと健全性（例：メモリ消費量、実行中のプロセス、リクエスト数）に関する洞察を提供するダッシュボードを表示できます。このダッシュボードは、使用しているハードウェアが負荷を処理するのに十分かどうかを理解するのに非常に役立ちます。
