---
{
  "title": "tuist.toml",
  "titleTemplate": ":title · 參考資料 · Tuist",
  "description": "tuist.toml 設定檔案格式的參考資料。"
}
---

# tuist.toml {#tuist-toml}

`tuist.toml` 係一個唔依賴特定建構系統嘅設定檔，亦都係 `Tuist.swift` 嘅進化版本。同 `Tuist.swift` 唔同，佢唔需要 Swift，因此可以用喺任何平台同建構系統上面。佢好適合用喺冇 Swift 嘅環境，例如基於 Linux 嘅 CI runner，或者當你只需要設定伺服器相關選項而唔需要完整 `Tuist.swift` manifest 嗰陣。

Tuist 會由目前工作目錄開始向上遍歷目錄階層去搵 `tuist.toml`，搵到第一個符合嘅就停。即係話你可以將佢放喺專案根目錄，然後喺任何子目錄執行 Tuist 指令。

## 支援嘅鍵值 {#supported-keys}

| 鍵值 | 類型 | 必需 | 預設值 | 說明 |
| --- | --- | --- | --- | --- |
| `project` | `String` | 係 | — | 你專案嘅完整 handle（例如 `"tuist/tuist"`）。 |
| `url` | `String` | 否 | `https://tuist.dev` | Tuist 伺服器嘅 URL。 |

### 網絡 {#network}

`[network]` 表格設定 Tuist 點樣建立出站 HTTP 連線。

| 鍵值 | 類型 | 必需 | 預設值 | 說明 |
| --- | --- | --- | --- | --- |
| `proxy` | `Boolean` | 否 | `true` | 當 `true` 時，如果存在 `HTTPS_PROXY`/`HTTP_PROXY`，Tuist 就會使用佢哋定義嘅代理伺服器。請參閱 <.localized_link href="/guides/integrations/http-proxy">HTTP 代理伺服器指南</.localized_link>。 |
| `ca_certificate` | `String` | 否 | — | PEM 或 DER CA 憑證捆綁檔案嘅路徑，用於喺系統根憑證儲存區之上額外信任，例如用於使用私有 CA 嘅自託管伺服器。`TUIST_CA_CERTIFICATE` 環境變數具有更高優先級。請參閱 <.localized_link href="/cli/debugging#trusting-a-custom-ca-certificate">信任自訂 CA 憑證</.localized_link>。 |

## 範例 {#example}

```toml
project = "tuist/tuist"
url = "https://tuist.dev"

[network]
proxy = true
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

## 設定優先順序 {#configuration-precedence}

當同一個設定喺多個地方定義時，Tuist 會按照以下優先順序解析（由高到低）：

1. **CLI 旗標**
2. **環境變數**
3. **Tuist.swift**
4. **tuist.toml**
5. **預設值**
