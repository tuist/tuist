---
{
  "title": "tuist.toml",
  "titleTemplate": ":title · 參考資料 · Tuist",
  "description": "tuist.toml 設定檔案格式的參考資料。"
}
---

# tuist.toml {#tuist-toml}

`tuist.toml` 係一個唔依賴特定構建系統嘅設定檔，亦係 `Tuist.swift` 嘅進化版本。同 `Tuist.swift` 唔同，佢唔需要 Swift，因此可以喺任何平台同構建系統中使用。對於 Swift 不可用嘅環境（例如基於 Linux 嘅 CI 執行器），或者當你只需要設定伺服器相關選項而唔需要完整 `Tuist.swift` 清單時，呢個檔案非常理想。

Tuist 會由當前工作目錄向上遍歷目錄結構來尋找 `tuist.toml`，並喺找到第一個匹配項時停止。這意味著你可以將它放喺項目根目錄，然後從任何子目錄運行 Tuist 命令。

## 支援嘅鍵 {#supported-keys}

| 鍵 | 類型 | 必需 | 預設值 | 描述 |
| --- | --- | --- | --- | --- |
| `project` | `String` | 是 | — | 你項目嘅完整句柄（例如 `"tuist/tuist"`）。 |
| `url` | `String` | 否 | `https://tuist.dev` | Tuist 伺服器嘅 URL。 |

### 網絡 {#network}

`[network]` 表格設定 Tuist 如何建立出站 HTTP 連線。

| 鍵 | 類型 | 必需 | 預設值 | 描述 |
| --- | --- | --- | --- | --- |
| `proxy` | `Boolean` | 否 | `true` | 當為 `true` 時，如果存在 `HTTPS_PROXY`/`HTTP_PROXY`，Tuist 會使用由其定義嘅代理。請參閱 <.localized_link href="/guides/integrations/http-proxy">HTTP 代理指南</.localized_link>。 |
| `ca_certificate` | `String` | 否 | — | 指向 PEM 或 DER CA 證書束嘅路徑，用於喺系統根證書庫之上添加信任，例如用於使用私有 CA 嘅自託管伺服器。`TUIST_CA_CERTIFICATE` 環境變量具有更高優先級。請參閱 <.localized_link href="/cli/debugging#trusting-a-custom-ca-certificate">信任自定義 CA 證書</.localized_link>。 |

## 示例 {#example}

```toml
project = "tuist/tuist"
url = "https://tuist.dev"

[network]
proxy = true
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

## 設定優先級 {#configuration-precedence}

當同一個設定喺多個地方定義時，Tuist 會按照以下優先級順序（從高到低）進行解析：

1. **CLI 標誌**
2. **環境變量**
3. **Tuist.swift**
4. **tuist.toml**
5. **預設值**
