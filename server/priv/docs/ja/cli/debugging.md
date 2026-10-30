---
{
  "title": "デバッグ",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "ログやネットワーク記録を使用してTuistの問題をデバッグする方法を学びます。"
}
---
# デバッグ {#debugging}

Tuistは、コマンドが期待通りに動作しない場合の問題診断を支援するいくつかのツールを提供します。

> [!WARNING]
> セッションデータには、ファイルパス、プロジェクト名、リクエスト/レスポンスボディなどの機密情報が含まれる可能性があります。機密性の高いヘッダー（Authorizationなど）はマスクされますが、セッションデータを他人と共有する際は注意してください。


## セッションデータ {#session-data}

コマンドの実行が意図した結果をもたらさない場合、セッションデータを検査することで問題を診断できます。CLIはログを[OSLog](https://developer.apple.com/documentation/os/oslog)およびファイルシステムに転送します。

各実行時に、`$XDG_STATE_HOME/tuist/sessions/{uuid}/`にセッションディレクトリを作成します。`$XDG_STATE_HOME`は環境変数が設定されていない場合、`~/.local/state`の値を取ります。また、`$TUIST_XDG_STATE_HOME`を使用してTuist固有のステートディレクトリを設定することもでき、これは`$XDG_STATE_HOME`よりも優先されます。

各セッションディレクトリには以下が含まれます：
- **`logs.txt`** - CLIセッションからのテキストログ
- **`network.har`** - セッション中に発生したすべてのネットワークリクエストとレスポンスを含む[HTTP Archive (HAR)](https://w3c.github.io/web-performance/specs/HAR/Overview.html)ファイル

### HARファイルの可視化 {#visualizing-har-files}

HARファイルはセッション中に発生したすべてのHTTPリクエストとレスポンスを記録しており、サーバー通信の問題をデバッグするのに役立ちます。HARファイルはいくつかのツールで開くことができます：

- **[Proxyman](https://proxyman.io/)**：HTTPトラフィックの表示と分析を行うネイティブmacOSアプリ。ファイル > インポートからHARファイルをインポートします。
- **ブラウザの開発者ツール**：Chrome、Firefox、SafariはいずれもネットワークタブでHARファイルのインポートをサポートしています。
- **[HAR Viewer](http://www.softwareishard.com/har/viewer/)**：WebベースのHARファイルビューア。

> [!TIP]
> Tuistのディレクトリ構成とカスタムディレクトリの設定方法については、<.localized_link href="/cli/directories">ディレクトリのドキュメント</.localized_link>をご覧ください。


デフォルトでは、CLIは実行が予期せず終了した際にセッションパスを出力します。出力されない場合は、前述のパス（つまり、最新のセッションディレクトリ）でセッションデータを見つけることができます。

5日以上経過したセッションディレクトリは自動的にクリーンアップされます。Tuistはデフォルトで最大50個の非アクティブなセッションディレクトリを保持し、現在実行中のTuistプロセスが所有するセッションは保護されます。同じステートディレクトリを使用して多くのTuistコマンドを実行するCI環境では、`TUIST_SESSION_MAX_SESSIONS`を使用して非アクティブセッションの上限を引き上げることができます。例えば`TUIST_SESSION_MAX_SESSIONS=200`です。無効な値、ゼロ、負の値は無視され、Tuistはデフォルトの50に戻ります。

### 継続的インテグレーション {#diagnose-issues-using-logs-ci}

使い捨て可能な環境であるCIでは、TuistセッションデータをエクスポートするようにCIパイプラインを設定したい場合があります。アーティファクトのエクスポートはCIサービス間で一般的な機能であり、設定は使用するサービスによって異なります。例えば、GitHub Actionsでは、`actions/upload-artifact`アクションを使用してセッションデータをアーティファクトとしてアップロードできます：

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

Xcodeキャッシュの問題をデバッグするには、`tuist setup cache`の実行時とビルド時の両方で`TUIST_CAS_LOG`をファイルパスに設定します。Tuistはそのファイルにキャッシュ統計情報とエラーを追記します：

```bash
export TUIST_CAS_LOG=$HOME/.local/state/tuist/cas.log
tuist setup cache
xcodebuild build -scheme YourScheme
```

CIでは、Tuistはこのログを設定なしで`~/.local/state/tuist/cas.log`に書き込みます。

## ネットワークタイムアウトとリトライの調整 {#tuning-network-timeouts}

サーバー呼び出し、レジストリ、プレビュー、キャッシュアーティファクトの転送を含むTuistのすべての[Hyptertext Transfer Protocol (HTTP)](https://developer.mozilla.org/en-US/docs/Web/HTTP)トラフィックは、妥当なデフォルト値を持つ共有の`URLSession`を経由します。遅延や混雑のあるネットワーク経路（例えば、企業プロキシ経由でオブジェクトストレージに到達するセルフホスト構成）では、個別のリクエストがスタベーション状態になり、完了前にリソースタイムアウトに達することがあります。特にキャッシュダウンロードの場合、タイムアウトに達するとTuistはモジュールをソースからビルドするフォールバックを行い、これはキャッシュされたバイナリをもう少し待つよりもはるかにコストがかかります。基礎となる設定は環境変数を通じて調整でき、未設定または無効な値が設定されている場合はデフォルトが適用されます：

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

リソースタイムアウトは転送全体の壁時計による上限であり、ストール検出ではないため、移動する最大のアーティファクトに対応できる十分な大きさにする必要があります。シャードがダウンロードするテスト製品などのファイル全体転送は、したがって90秒ではなく10分がデフォルトとなり、新しいデータがないまま`TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST`を経過するとストールした転送は失敗します。これらの転送は`TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE`を読み取って上限を引き上げることはあっても、10分未満に下限を下げることはないため、キャッシュリクエストを速やかに失敗させるために選択した値が、シャードのテスト製品のダウンロードまでキャンセルすることはありません。`TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE`を引き上げると、回復可能だが遅いダウンロードがタイムアウトせずに完了します。キャッシュダウンロードの場合、これはソースからのビルドへのフォールバックではなくキャッシュヒットを得ることを意味するため、意図的に引き上げてください：遅いキャッシュダウンロードを維持するのと同じ値は、ソースからのビルドへのフォールバックも遅延させます。`TUIST_HTTP_MAXIMUM_RETRY_COUNT`を下げると、より長いタイムアウトが複数回の試行にわたって最悪の場合の待ち時間を乗算することを防げます。リトライ間の遅延は失敗ごとに倍増し、最大で1回分の基本遅延に相当するランダムジッターを含み、30秒を超えることはありません。

## カスタムCA証明書の信頼 {#trusting-a-custom-ca-certificate}

デフォルトでは、Tuistはオペレーティングシステムのルートストアに対してTLS証明書を検証します。プライベート認証局を使用するセルフホスト型のTuistまたはKuraサーバーを実行する場合、TuistはそのCAも信頼する必要があります。システムキーチェーンにルートをインストールし（SSL用に信頼マークを付ける）のが標準的なアプローチですが、GUIセッションやモバイルデバイス管理（MDM）による信頼ビットの設定がないヘッドレスCIホストでは、現実的でないことが多いです。

そのような場合、Tuistを直接CA証明書バンドルに向けることができます。バンドルはPEM（連結された`-----BEGIN CERTIFICATE-----`ブロックが1つ以上）または単一のDERファイルです。システムルートストアはそれ alongside で信頼されたままになるため、公開証明書は通常通り検証され、証明書評価がバイパスされることはありません。

```bash
# Path to a PEM/DER CA bundle to trust on top of the system root store (default: unset)
export TUIST_CA_CERTIFICATE=/etc/ssl/certs/self-hosted-ca.pem
```

また、<.localized_link href="/references/tuist-toml">設定ファイル</.localized_link>で宣言することもできます：

```toml
[network]
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

`TUIST_CA_CERTIFICATE`環境変数は設定ファイルよりも優先されるため、コミットされたマニフェストを変更せずにCIシークレットとして提供するのに便利です。
