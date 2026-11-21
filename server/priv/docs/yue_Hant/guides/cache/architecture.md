---
{
  "title": "架構",
  "titleTemplate": ":title | Cache | Guides | Tuist",
  "description": "了解 Tuist 快取服務的架構。"
}
---

# 快取架構 {#cache-architecture}

> [!NOTE]
> 本頁提供 Tuist 快取服務架構的技術概覽。主要對象為需要理解服務內部運作的**自行託管使用者**同**貢獻者**。只想使用快取的一般使用者無需閱讀此內容。


Tuist 快取服務係一項獨立服務，為構建產物提供內容定址儲存（CAS），並為快取元數據提供鍵值儲存。

## 概覽 {#overview}

服務採用兩層儲存架構，加上本地 SQLite 元數據：

- **本地磁碟**：低延遲快取命中的主要儲存
- **S3**：持久儲存，可保留產物並於驅逐後恢復
- **SQLite**：本地元數據，用於追蹤產物存取、清理孤立檔案、執行背景工作，以及儲存鍵值快取數據

```mermaid
flowchart LR
    CLI[Tuist CLI] --> NGINX[Nginx]
    NGINX --> APP[Cache service]
    NGINX -->|X-Accel-Redirect| DISK[(Local Disk)]
    APP --> S3[(S3)]
    APP -->|auth| SERVER[Tuist Server]
```

## 元件 {#components}

### Nginx {#nginx}

Nginx 作為入口點，並使用 `X-Accel-Redirect` 高效交付檔案：

- **下載**：快取服務驗證身份驗證後，返回 `X-Accel-Redirect` 標頭。Nginx 直接從磁碟提供檔案，或從 S3 代理。
- **上傳**：Nginx 將請求代理至快取服務，後者將數據流式寫入磁碟。

### 內容定址儲存 {#cas}

產物以分片目錄結構儲存在本地磁碟：

- **路徑**：`{account}/{project}/cas/{shard1}/{shard2}/{artifact_id}`
- **分片**：產物 ID 的前四個字符建立兩級分片（例如 `ABCD1234` → `AB/CD/ABCD1234`）

### SQLite 元數據 {#sqlite}

快取服務使用兩個 SQLite 數據庫：

- **主要元數據數據庫**：儲存 `cache_artifacts`、孤立掃描游標、Oban 工作及其他服務元數據。
- **鍵值數據庫**：在專用 SQLite 檔案中儲存 `key_value_entries` 同 `key_value_entry_hashes`。

鍵值儲存拆分到獨立數據庫，以便使用 SQLite 增量自動清理，而不影響產物元數據同孤立清理狀態。

### S3 整合 {#s3}

S3 提供持久儲存：

- **背景上傳**：寫入磁碟後，產物會透過每分鐘運行的背景工作排隊上傳至 S3
- **按需載入**：當本地缺少產物時，請求會即時透過預簽名 S3 URL 提供，同時將產物排隊於背景下載到本地磁碟

### 磁碟驅逐 {#eviction}

服務使用多個背景進程管理磁碟空間：

- **CAS 磁碟驅逐** 使用由 `cache_artifacts` 支援的 LRU 語義
- 當磁碟使用量超過 85% 時，會刪除最舊的產物，直至使用量降至 70%
- 本地驅逐後，產物仍保留於 S3
- **KV 驅逐** 按保留策略移除舊的鍵值條目，並可在專用 KV 數據庫超過設定的大小預算時縮小其體積

### 孤立清理 {#orphan-cleanup}

服務亦運行孤立清理工作以處理磁碟產物：

- 它掃描儲存樹，尋找存在於磁碟但沒有對應 `cache_artifacts` 記錄的檔案。
- 如果檔案已寫入磁碟，但元數據寫入在 SQLite 緩衝區刷新完成前丟失，就會出現這種情況。
- 比安全窗口更新的檔案會被忽略，以避免與進行中的上傳發生競爭。
- 如果孤立檔案被刪除後再次被請求，下一次快取未命中會導致其重新上傳，從而使系統自我修復。

### 身份驗證 {#authentication}

快取透過呼叫 `/api/projects` 端點並將結果快取（成功 10 分鐘，失敗 3 秒），將身份驗證委派給 Tuist 伺服器。

## 請求流程 {#request-flows}

### 下載 {#download-flow}

```mermaid
sequenceDiagram
    participant CLI as Tuist CLI
    participant N as Nginx
    participant A as Cache service
    participant D as Disk
    participant S as S3

    CLI->>N: GET /api/cache/cas/:id
    N->>A: Proxy for auth
    A-->>N: X-Accel-Redirect
    alt On disk
        N->>D: Serve file
    else Not on disk
        N->>S: Proxy from S3
    end
    N-->>CLI: File bytes
```

### 上傳 {#upload-flow}

```mermaid
sequenceDiagram
    participant CLI as Tuist CLI
    participant N as Nginx
    participant A as Cache service
    participant D as Disk
    participant S as S3

    CLI->>N: POST /api/cache/cas/:id
    N->>A: Proxy upload
    A->>D: Stream to disk
    A-->>CLI: 201 Created
    A->>S: Background upload
```

## API 端點 {#api-endpoints}

| 端點 | 方法 | 描述 |
|----------|--------|-------------|
| `/up` | GET | 健康檢查 |
| `/metrics` | GET | Prometheus 指標 |
| `/api/cache/cas/:id` | GET | 下載 CAS 產物 |
| `/api/cache/cas/:id` | POST | 上傳 CAS 產物 |
| `/api/cache/keyvalue/:cas_id` | GET | 取得鍵值條目 |
| `/api/cache/keyvalue` | PUT | 儲存鍵值條目 |
| `/api/cache/module/:id` | HEAD | 檢查模組產物是否存在 |
| `/api/cache/module/:id` | GET | 下載模組產物 |
| `/api/cache/module/start` | POST | 開始多部分上傳 |
| `/api/cache/module/part` | POST | 上傳部分 |
| `/api/cache/module/complete` | POST | 完成多部分上傳 |
