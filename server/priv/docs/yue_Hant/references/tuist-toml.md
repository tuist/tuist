---
{
  "title": "tuist.toml",
  "titleTemplate": ":title · 參考資料 · Tuist",
  "description": "tuist.toml 設定檔案格式的參考資料。"
}
---

# tuist.toml {#tuist-toml}

`tuist.toml` 係一個唔依賴特定構建系統嘅設定檔，亦都係 `Tuist.swift` 嘅進化版本。同 `Tuist.swift` 唔同，佢唔需要 Swift，所以可以喺任何平台同構建系統使用。對於冇 Swift 嘅環境（例如基於 Linux 嘅 CI runner），或者你只需要設定伺服器相關選項而唔需要完整 `Tuist.swift` 清單檔案嘅情況，呢個格式就特別適合。

Tuist 會由目前工作目錄開始向上遍歷目錄結構去搵 `tuist.toml`，搵到第一個符合嘅檔案就會停止。即係話，你可以將佢放喺專案根目錄，然後從任何子目錄執行 Tuist 指令。

## 支援嘅設定鍵 {#supported-keys}

| 設定鍵 | 類型 | 必填 | 預設值 | 說明 |
| --- | --- | --- | --- | --- |
| `project` | `String` | 係 | — | 你專案嘅完整識別名稱（例如 `"tuist/tuist"`）。 |
| `url` | `String` | 否 | `https://tuist.dev` | Tuist 伺服器嘅 URL。 |

### 網絡 {#network}

`[network]` 表格設定 Tuist 點樣建立向外嘅 HTTP 連線。

| 設定鍵 | 類型 | 必填 | 預設值 | 說明 |
| --- | --- | --- | --- | --- |
| `proxy` | `Boolean` | 否 | `true` | 當設為 `true` 時，如果環境中有定義 `HTTPS_PROXY`/`HTTP_PROXY`，Tuist 就會使用該代理伺服器。請參閱 <.localized_link href="/guides/integrations/http-proxy">HTTP 代理伺服器指南</.localized_link>。 |
| `ca_certificate` | `String` | 否 | — | 指向 PEM 或 DER 格式嘅 CA 憑證束檔案路徑，用於喺系統根憑證儲存區之上額外信任該憑證，例如用於使用私有 CA 嘅自託管伺服器。`TUIST_CA_CERTIFICATE` 環境變數具有更高優先級。請參閱 <.localized_link href="/cli/debugging#trusting-a-custom-ca-certificate">信任自訂 CA 憑證</.localized_link>。 |

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
