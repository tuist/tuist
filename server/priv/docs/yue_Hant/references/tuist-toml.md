---
{
  "title": "tuist.toml",
  "titleTemplate": ":title · 參考資料 · Tuist",
  "description": "tuist.toml 設定檔案格式的參考資料。"
}
---

# tuist.toml {#tuist-toml}

`tuist.toml` 係一個唔依賴特定構建系統嘅設定檔，亦係 `Tuist.swift` 嘅進化版本。同 `Tuist.swift` 唔同，佢唔需要 Swift，所以可以喺任何平台同構建系統使用。如果環境入面無 Swift（例如基於 Linux 嘅 CI runner），或者你只需要設定伺服器相關選項而唔需要完整嘅 `Tuist.swift` manifest，呢個檔案就非常適合。

Tuist 會由目前工作目錄向上遍歷目錄階層來尋找 `tuist.toml`，直到搵到第一個匹配項為止。這意味著你可以將佢放喺項目根目錄，然後從任何子目錄執行 Tuist 命令。

## 支援嘅鍵值 {#supported-keys}

| 鍵值 | 類型 | 必填 | 預設值 | 說明 |
| --- | --- | --- | --- | --- |
| `project` | `String` | 是 | — | 你項目嘅完整句柄（例如 `"tuist/tuist"`）。 |
| `url` | `String` | 否 | `https://tuist.dev` | Tuist 伺服器嘅 URL。 |

### 網絡 {#network}

`[network]` 表格設定 Tuist 點樣建立出站 HTTP 連線。

| 鍵值 | 類型 | 必填 | 預設值 | 說明 |
| --- | --- | --- | --- | --- |
| `proxy` | `Boolean` | 否 | `true` | 當設為 `true` 時，如果存在 `HTTPS_PROXY`/`HTTP_PROXY`，Tuist 就會使用佢哋定義嘅代理伺服器。請參閱 <.localized_link href="/guides/integrations/http-proxy">HTTP 代理伺服器指南</.localized_link>。 |
| `ca_certificate` | `String` | 否 | — | PEM 或 DER 格式嘅 CA 憑證捆綁包路徑，用於喺系統根憑證儲存區之上額外信任嘅憑證，例如用於使用私有 CA 嘅自託管伺服器。`TUIST_CA_CERTIFICATE` 環境變量具有更高優先級。請參閱 <.localized_link href="/cli/debugging#trusting-a-custom-ca-certificate">信任自訂 CA 憑證</.localized_link>。 |

## 範例 {#example}

```toml
project = "tuist/tuist"
url = "https://tuist.dev"

[network]
proxy = true
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

## 設定優先級 {#configuration-precedence}

如果同一個設定喺多個地方定義，Tuist 會按照以下優先級順序（由高到低）進行解析：

1. **CLI 標誌**
2. **環境變量**
3. **Tuist.swift**
4. **tuist.toml**
5. **預設值**
