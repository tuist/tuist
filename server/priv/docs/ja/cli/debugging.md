---
{
  "title": "デバッグ",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "ログとネットワーク記録を使用して、Tuist の問題をデバッグする方法を学びます。"
}
---
# デバッグ {#debugging}

Tuistは、コマンドが期待通りに動作しない場合の問題診断を支援する複数のツールを提供します。

> [!WARNING]
> セッションデータには、ファイルパス、プロジェクト名、リクエスト/レスポンスボディなどの機密情報が含まれる可能性があります。機密性の高いヘッダー（Authorizationなど）はマスキングされますが、セッションデータを他者と共有する際は注意してください。


## セッションデータ {#session-data}

コマンドの実行結果が意図したものでない場合、セッションデータを検査することで問題を診断できます。CLIはログを[OSLog](https://developer.apple.com/documentation/os/oslog)とファイルシステムに転送します。

各実行時に、`$XDG_STATE_HOME/tuist/sessions/{uuid}/` にセッションディレクトリを作成します。`$XDG_STATE_HOME` は環境変数が設定されていない場合に `~/.local/state` の値を取ります。また、`$TUIST_XDG_STATE_HOME` を使用してTuist固有のステートディレクトリを設定することもでき、これは `$XDG_STATE_HOME` より優先されます。

各セッションディレクトリには以下が含まれます：
- **`logs.txt`** - CLIセッションからのテキストログ
- **`network.har`** - セッション中に発生したすべてのネットワークリクエストとレスポンスを含む [HTTP Archive (HAR)](https://w3c.github.io/web-performance/specs/HAR/Overview.html) ファイル

### HARファイルの可視化 {#visualizing-har-files}

HARファイルはセッション中に発生したすべてのHTTPリクエストとレスポンスを記録しており、サーバー通信の問題をデバッグする際に役立ちます。HARファイルはいくつかのツールで開くことができます：

- **[Proxyman](https://proxyman.io/)**: HTTPトラフィックの表示と分析を行うmacOSネイティブアプリです。ファイル > インポートからHARファイルをインポートします。
- **ブラウザの開発者ツール**: Chrome、Firefox、SafariはいずれもネットワークタブでHARファイルのインポートをサポートしています。
- **[HAR Viewer](http://www.softwareishard.com/har/viewer/)**: WebベースのHARファイルビューアーです。

> [!TIP]
> Tuistのディレクトリ構成とカスタムディレクトリの設定方法については、<.localized_link href="/cli/directories">ディレクトリのドキュメント</.localized_link>をご覧ください。


デフォルトでは、CLIは実行が予期せず終了した際にセッションパスを出力します。出力されない場合は、前述のパス（つまり最新のセッションディレクトリ）でセッションデータを見つけることができます。

5日以上経過したセッションディレクトリは自動的にクリーンアップされます。Tuistはデフォルトで最大50個の非アクティブなセッションディレクトリを保持し、現在実行中のTuistプロセスが所有するセッションは保護されます。同じステートディレクトリを使用して多数のTuistコマンドを実行するCI環境では、`TUIST_SESSION_MAX_SESSIONS` で非アクティブセッションの上限を引き上げることができます。例えば `TUIST_SESSION_MAX_SESSIONS=200` のように設定します。無効な値、ゼロ、負の値は無視され、Tuistはデフォルトの50に戻ります。

### 継続的インテグレーション {#diagnose-issues-using-logs-ci}

環境を使い捨てできるCIでは、TuistセッションデータをエクスポートするようにCIパイプラインを設定するとよいでしょう。アーティファクトのエクスポートはCIサービス間で一般的な機能であり、設定は使用するサービスによって異なります。例えばGitHub Actionsでは、`actions/upload-artifact` アクションを使用してセッションデータをアーティファクトとしてアップロードできます：

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

### Xcodeキャッシュのデバッグ {#cache-daemon-debugging}

Xcodeキャッシュの問題をデバッグするには、`tuist setup cache` の実行時とビルド時の両方で `TUIST_CAS_LOG` をファイルパスに設定します。Tuistはそのファイルにキャッシュ統計情報とエラーを追記します：

```bash
export TUIST_CAS_LOG=$HOME/.local/state/tuist/cas.log
tuist setup cache
xcodebuild build -scheme YourScheme
```

CI環境では、Tuistは設定なしでこのログを `~/.local/state/tuist/cas.log` に書き込みます。

## ネットワークタイムアウトとリトライの調整 {#tuning-network-timeouts}

サーバー呼び出し、レジストリ、プレビュー、キャッシュアーティファクト転送を含むTuistのすべての [Hypertext Transfer Protocol (HTTP)](https://developer.mozilla.org/en-US/docs/Web/HTTP) トラフィックは、適切なデフォルト値を持つ共有の `URLSession` を経由します。遅延や混雑のあるネットワーク経路（例えば、企業プロキシ経由でオブジェクトストレージにアクセスするセルフホスト構成）では、個別のリクエストが停滞し、完了前にリソースタイムアウトに達することがあります。特にキャッシュダウンロードの場合、タイムアウトに達するとTuistはモジュールのソースからのビルドにフォールバックしますが、これはキャッシュされたバイナリをもう少し待つよりもはるかにコストがかかります。環境変数を通じて基盤となる設定を調整でき、未設定または無効な値が設定されている場合はデフォルトが適用されます：

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

リソースタイムアウトは転送全体の壁時計による上限であり、ストール検出ではないため、移動する最大のアーティファクトに対応できる十分な大きさにする必要があります。シャードがダウンロードするテスト製品などのファイル全体転送は、そのため90秒ではなく10分がデフォルトとなり、新しいデータがない状態で `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST` 経過すると停滞した転送は依然として失敗します。これらの転送は `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE` を読み取って上限を引き上げるだけで、10分未満に下げることは never ありません。したがって、キャッシュリクエストを速やかに失敗させるために選択した値が、シャードのテスト製品のダウンロードもキャンセルすることはありません。`TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE` を引き上げると、回復可能だが低速なダウンロードがタイムアウトせずに完了します。キャッシュダウンロードの場合、これはソースからのビルドへのフォールバックではなくキャッシュヒットを得られることを意味するため、意図的に引き上げてください：低速なキャッシュダウンロードを維持するのと同じ値は、ソースからのビルドへのフォールバックも遅延させます。`TUIST_HTTP_MAXIMUM_RETRY_COUNT` を下げると、より長いタイムアウトが複数回の試行にわたって最悪の場合の待機時間を増幅することを防げます。リトライ遅延は失敗ごとに倍増し、最大1回分の基本遅延にランダムジッターを含み、30秒を超えることはありません。

## カスタムCA証明書の信頼 {#trusting-a-custom-ca-certificate}

デフォルトでは、Tuistはオペレーティングシステムのルートストアに対してTLS証明書を検証します。プライベート認証局を使用するセルフホスト型のTuistまたはKuraサーバーを実行する場合、TuistはそのCAも信頼する必要があります。システムキーチェーンにルートをインストールし（SSL用に信頼済みとしてマーク）、これが標準的なアプローチですが、GUIセッションやモバイルデバイス管理（MDM）が存在しないヘッドレスCIホストでは、信頼ビットを設定するのが現実的でないことがよくあります。

そのような場合、Tuistを直接CA証明書バンドルに向けることができます。バンドルはPEM（1つ以上の連結された `-----BEGIN CERTIFICATE-----` ブロック）または単一のDERファイルです。システムルートストアは引き続き信頼されるため、公開証明書は通常通り検証され、証明書評価がバイパスされることはありません。

```bash
# Path to a PEM/DER CA bundle to trust on top of the system root store (default: unset)
export TUIST_CA_CERTIFICATE=/etc/ssl/certs/self-hosted-ca.pem
```

また、<.localized_link href="/references/tuist-toml">設定ファイル</.localized_link>で宣言することもできます：

```toml
[network]
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

`TUIST_CA_CERTIFICATE` 環境変数は設定ファイルより優先されるため、コミットされたマニフェストを変更せずにCIシークレットとして提供するのに便利です。
