---
{
  "title": "tuist.toml",
  "titleTemplate": ":title · リファレンス · Tuist",
  "description": "tuist.toml設定ファイル形式のリファレンス。"
}
---

# tuist.toml {#tuist-toml}

`tuist.toml` はビルドシステムに依存しない設定ファイルであり、`Tuist.swift` の進化形です。`Tuist.swift` とは異なり Swift を必要としないため、あらゆるプラットフォームやビルドシステムで利用できます。Linux ベースの CI ランナーなど Swift が利用できない環境や、完全な `Tuist.swift` マニフェストなしでサーバー関連の設定のみを行いたい場合に最適です。

Tuist は現在の作業ディレクトリから上位のディレクトリ階層をたどって `tuist.toml` を検索し、最初に一致した場所で停止します。つまり、プロジェクトのルートに配置すれば、どのサブディレクトリからでも Tuist コマンドを実行できます。

## サポートされているキー {#supported-keys}

| キー | 型 | 必須 | デフォルト | 説明 |
| --- | --- | --- | --- | --- |
| `project` | `String` | はい | — | プロジェクトの完全なハンドル（例: `"tuist/tuist"`）。 |
| `url` | `String` | いいえ | `https://tuist.dev` | Tuist サーバーの URL。 |

### ネットワーク {#network}

`[network]` テーブルは、Tuist が外部への HTTP 接続を行う方法を構成します。

| キー | 型 | 必須 | デフォルト | 説明 |
| --- | --- | --- | --- | --- |
| `proxy` | `Boolean` | いいえ | `true` | `true` の場合、存在すれば `HTTPS_PROXY`/`HTTP_PROXY` で定義されたプロキシを使用します。<.localized_link href="/guides/integrations/http-proxy">HTTP プロキシガイド</.localized_link>を参照してください。 |
| `ca_certificate` | `String` | いいえ | — | システムのルート証明書ストアに加えて信頼する PEM または DER 形式の CA 証明書バンドルへのパス。例えば、プライベート CA を使用するセルフホスト型サーバーの場合などに使用します。`TUIST_CA_CERTIFICATE` 環境変数が優先されます。<.localized_link href="/cli/debugging#trusting-a-custom-ca-certificate">カスタム CA 証明書の信頼</.localized_link>を参照してください。 |

## 例 {#example}

```toml
project = "tuist/tuist"
url = "https://tuist.dev"

[network]
proxy = true
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

## 設定の優先順位 {#configuration-precedence}

同じ設定が複数の場所で定義されている場合、Tuist は以下の優先順位（高い順）で解決します。

1. **CLI フラグ**
2. **環境変数**
3. **Tuist.swift**
4. **tuist.toml**
5. **デフォルト**
