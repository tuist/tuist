---
{
  "title": "tuist.toml",
  "titleTemplate": ":title · 參考資料 · Tuist",
  "description": "tuist.toml 設定檔格式的參考說明。"
}
---

# tuist.toml {#tuist-toml}

`tuist.toml` 是不依賴建置系統的設定檔，也是 `Tuist.swift` 的演進版本。與 `Tuist.swift` 不同，它不需要 Swift，因此可在任何平台與建置系統中使用。在無法使用 Swift 的環境（例如基於 Linux 的 CI 執行器），或只需設定伺服器相關選項而無需完整 `Tuist.swift` 資訊清單時，它特別適合。

Tuist 會從目前工作目錄向上遍歷目錄結構來尋找 `tuist.toml`，並在找到第一個符合項時停止。這表示你可以將它放在專案根目錄，並從任何子目錄執行 Tuist 指令。

## 支援的鍵 {#supported-keys}

| 鍵 | 類型 | 必填 | 預設值 | 說明 |
| --- | --- | --- | --- | --- |
| `project` | `String` | 是 | — | 你專案的完整代號（例如 `"tuist/tuist"`）。 |
| `url` | `String` | 否 | `https://tuist.dev` | Tuist 伺服器的 URL。 |

### 網路 {#network}

`[network]` 資料表設定 Tuist 如何建立外向 HTTP 連線。

| 鍵 | 類型 | 必填 | 預設值 | 說明 |
| --- | --- | --- | --- | --- |
| `proxy` | `Boolean` | 否 | `true` | 當 `true` 時，若存在 `HTTPS_PROXY`/`HTTP_PROXY`，Tuist 會使用其所定義的代理伺服器。請參閱 <.localized_link href="/guides/integrations/http-proxy">HTTP 代理伺服器指南</.localized_link>。 |
| `ca_certificate` | `String` | 否 | — | PEM 或 DER 格式的 CA 憑證套件路徑，用於在系統根憑證存放區之上額外信任，例如使用私有 CA 的自架伺服器。`TUIST_CA_CERTIFICATE` 環境變數具有較高優先順序。請參閱 <.localized_link href="/cli/debugging#trusting-a-custom-ca-certificate">信任自訂 CA 憑證</.localized_link>。 |

## 範例 {#example}

```toml
project = "tuist/tuist"
url = "https://tuist.dev"

[network]
proxy = true
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

## 設定優先順序 {#configuration-precedence}

當同一項設定在多處定義時，Tuist 會依下列優先順序解析（由高到低）：

1. **CLI 旗標**
2. **環境變數**
3. **Tuist.swift**
4. **tuist.toml**
5. **預設值**
