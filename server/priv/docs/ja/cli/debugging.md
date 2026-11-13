---
{
  "title": "デバッグ",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "ログやネットワーク記録を使用してTuistの問題をデバッグする方法を学びます。"
}
---
# デバッグ {#debugging}

Tuist は、コマンドが期待通りに動作しない場合の問題診断を支援する複数のツールを提供します。

> [!WARNING]
> セッションデータには、ファイルパス、プロジェクト名、リクエスト/レスポンスボディなどの機密情報が含まれる場合があります。Authorization などの機密ヘッダーはマスクされますが、セッションデータを他者と共有する際は注意してください。


## セッションデータ {#session-data}

コマンドの実行が意図した結果をもたらさない場合は、セッションデータを検査することで問題を診断できます。CLI はログを [OSLog](https://developer.apple.com/documentation/os/oslog) とファイルシステムに転送します。

各実行時に、`$XDG_STATE_HOME/tuist/sessions/{uuid}/` にセッションディレクトリを作成します。`$XDG_STATE_HOME` は環境変数が設定されていない場合に `~/.local/state` の値をとります。`$TUIST_XDG_STATE_HOME` を使用して Tuist 専用のステートディレクトリを設定することもでき、これは `$XDG_STATE_HOME` より優先されます。

各セッションディレクトリには以下が含まれます：
- **`logs.txt`** - CLI セッションのテキストログ
- **`network.har`** - セッション中に発生したすべてのネットワークリクエストとレスポンスを含む [HTTP Archive (HAR)](https://w3c.github.io/web-performance/specs/HAR/Overview.html) ファイル

### HAR ファイルの可視化 {#visualizing-har-files}

HAR ファイルはセッション中に発生したすべての HTTP リクエストとレスポンスを記録するため、サーバー通信の問題をデバッグするのに役立ちます。HAR ファイルはいくつかのツールで開くことができます：

- **[Proxyman](https://proxyman.io/)**：HTTP トラフィックを表示・分析するための macOS ネイティブアプリ。[ファイル] > [インポート] から HAR ファイルをインポートします。
- **ブラウザの開発者ツール**：Chrome、Firefox、Safari はいずれも [ネットワーク] タブで HAR ファイルのインポートをサポートしています。
- **[HAR Viewer](http://www.softwareishard.com/har/viewer/)**：ウェブベースの HAR ファイルビューア。

> [!TIP]
> Tuist のディレクトリ構成とカスタムディレクトリの設定方法については、<.localized_link href="/cli/directories">ディレクトリのドキュメント</.localized_link>をご覧ください。


> [!TIP]
> **xcodebuild の未加工出力**
>
> `xcodebuild` を実行するコマンドは、その出力を xcbeautify でフォーマットします。フォーマットされていない出力を確認するには `--verbose` を渡してください。<.localized_link href="/guides/integrations/continuous-integration#xcodebuild-output-formatting">xcodebuild 出力のフォーマット</.localized_link>も参照してください。

デフォルトでは、CLI は実行が予期せず終了した場合にセッションパスを出力します。出力されない場合は、前述のパス（つまり、最新のセッションディレクトリ）でセッションデータを見つけることができます。

5日以上経過したセッションディレクトリは自動的にクリーンアップされます。Tuist はデフォルトで最大50個の非アクティブなセッションディレクトリを保持し、現在実行中の Tuist プロセスが所有するセッションは保護されます。同じステートディレクトリを使用して多くの Tuist コマンドを実行する CI 環境では、`TUIST_SESSION_MAX_SESSIONS` で非アクティブセッションの上限を引き上げることができます（例：`TUIST_SESSION_MAX_SESSIONS=200`）。無効な値、ゼロ、および負の値は無視され、Tuist はデフォルトの50に戻ります。

### 継続的インテグレーション {#diagnose-issues-using-logs-ci}

CI では環境が一時的であるため、Tuist のセッションデータをエクスポートするように CI パイプラインを設定したい場合があります。アーティファクトのエクスポートは CI サービス間で一般的な機能であり、設定は使用するサービスによって異なります。例えば、GitHub Actions では、`actions/upload-artifact` アクションを使用してセッションデータをアーティファクトとしてアップロードできます：

```yaml
name: Node CI

on: [push]

env:
  TUIST_XDG_STATE_HOME: /tmp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      # ... other steps
      - run: tuist generate
      # ... do something with the project
      - name: Export Tuist session data
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-sessions
          path: /tmp/tuist/sessions/
```

### Xcode キャッシュのデバッグ {#cache-daemon-debugging}

Xcode キャッシュの問題をデバッグするには、`tuist setup cache` の実行時とビルド時の両方で `TUIST_CAS_LOG` をファイルパスに設定します。Tuist はそのファイルにキャッシュ統計情報とエラーを追加します：

```bash
export TUIST_CAS_LOG=$HOME/.local/state/tuist/cas.log
tuist setup cache
xcodebuild build -scheme YourScheme
```

CI では、Tuist は設定なしでこのログを `~/.local/state/tuist/cas.log` に書き込みます。

## ネットワークタイムアウトとリトライの調整 {#tuning-network-timeouts}

サーバー呼び出し、レジストリ、プレビュー、キャッシュアーティファクトの転送を含む Tuist のすべての [Hypertext Transfer Protocol (HTTP)](https://developer.mozilla.org/en-US/docs/Web/HTTP) トラフィックは、妥当なデフォルト値を持つ共有の `URLSession` を経由します。遅延や混雑のあるネットワーク経路（例えば、企業プロキシを通じてオブジェクトストレージにアクセスするセルフホスト構成）では、個々のリクエストが停滞し、完了前にリソースタイムアウトに達することがあります。特にキャッシュダウンロードの場合、タイムアウトに達すると Tuist はモジュールをソースからビルドするフォールバックを行い、これはキャッシュされたバイナリをもう少し待つよりもはるかに高コストです。基礎となる設定は環境変数を通じて調整でき、未設定または無効な値が設定されている場合はデフォルトが適用されます：

```bash
# Maximum time (in seconds) a single resource transfer can take before it's cancelled
# (default: 90, or 600 for whole-file transfers such as test-product shard artifacts)
export TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE=600

# Maximum time (in seconds) to wait for new data on an existing request (default: 120)
export TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST=300

# Maximum number of simultaneous connections per host (default: 20)
export TUIST_HTTP_MAXIMUM_CONNECTIONS_PER_HOST=40

# Maximum retries after the initial attempt (default: 3, maximum: 10)
export TUIST_HTTP_MAXIMUM_RETRY_COUNT=1

# Initial exponential backoff delay in milliseconds (default: 100, maximum: 30000)
export TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS=250
```

リソースタイムアウトは転送全体の壁時計制限であり、ストール防止機構ではないため、移動する最大のアーティファクトに対応できる十分な大きさにする必要があります。シャードがダウンロードするテスト製品などのファイル全体転送は、そのため90秒ではなく10分がデフォルトとなり、新しいデータがないまま `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST` が経過すると停滞した転送は失敗します。これらの転送は `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE` を読み取って上限を引き上げることはありますが、10分未満に下限を下げることはないため、キャッシュリクエストを迅速に失敗させるために選択した値がシャードのテスト製品ダウンロードをキャンセルすることはありません。`TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE` を引き上げると、回復可能だが低速なダウンロードがタイムアウトせずに完了します。キャッシュダウンロードの場合、これはソースからのビルドへのフォールバックではなくキャッシュヒットを獲得することを意味するため、意図的に引き上げてください：低速なキャッシュダウンロードを維持するのと同じ値が、ソースからのビルドへのフォールバックも遅延させます。`TUIST_HTTP_MAXIMUM_RETRY_COUNT` を下げると、より長いタイムアウトが複数回の試行にわたって最悪の場合の待機時間を乗算することを防げます。リトライ遅延は失敗ごとに倍増し、最大で1回分のベース遅延のランダムジッターを含み、30秒を超えることはありません。

## カスタム CA 証明書の信頼 {#trusting-a-custom-ca-certificate}

デフォルトでは、Tuist はオペレーティングシステムのルートストアに対して TLS 証明書を検証します。プライベート認証局を使用するセルフホスト型の Tuist または Kura サーバーを実行する場合、Tuist もその CA を信頼する必要があります。システムキーチェーンにルートをインストールし（SSL に対して信頼済みとしてマーク）、これが標準的なアプローチですが、GUI セッションやモバイルデバイス管理（MDM）による信頼ビットの設定が存在しないヘッドレス CI ホストでは、しばしば実用的ではありません。

そのような場合、Tuist に直接 CA 証明書バンドルを指定できます。バンドルは PEM（連結された `-----BEGIN CERTIFICATE-----` ブロックが1つ以上）または単一の DER ファイルです。システムルートストアは引き続き信頼されるため、公開証明書は通常通り検証され、証明書評価がバイパスされることはありません。

```bash
# Path to a PEM/DER CA bundle to trust on top of the system root store (default: unset)
export TUIST_CA_CERTIFICATE=/etc/ssl/certs/self-hosted-ca.pem
```

また、<.localized_link href="/references/tuist-toml">設定ファイル</.localized_link>で宣言することもできます：

```toml
[network]
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

`TUIST_CA_CERTIFICATE` 環境変数は設定ファイルより優先されるため、コミットされたマニフェストを変更せずに CI シークレットとして提供するのが便利です。
