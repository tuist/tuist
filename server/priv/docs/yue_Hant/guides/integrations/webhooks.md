---
{
  "title": "Webhooks",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "訂閱 HTTPS 端點以接收 Tuist 事件，透過簽署的 payload 驗證傳送，並從儀表板檢查每次嘗試。"
}
---
# Webhook {#webhooks}

Webhook 令你嘅系統可以喺 Tuist 內部發生變化時即時作出反應。每當有相關事件發生——例如偵測到新測試案例、預覽完成上傳，或者不穩定測試得到修復——Tuist 會向你已訂閱該事件類型嘅每個端點發出 HTTP POST 請求。請求主體係一個 JSON 信封，每次傳送都帶有簽名標頭，你可以使用端點嘅簽名密鑰進行驗證。

你註冊目標 URL，揀選你想要嘅事件，Tuist 就會處理簽名、重試同傳送審計日誌。

## 接收 Webhook 嘅步驟 {#steps}

你可以透過以下步驟開始喺你嘅應用程式中接收事件通知：

1. [識別](#event-types)你嘅應用程式想要接收嘅事件。
2. 喺你嘅本地伺服器上建立一個 HTTP 端點（URL），作為 [Webhook 端點](#create-an-endpoint)。
3. 透過 [解析負載](#payload) 並返回 [2xx 狀態碼](#responding) 來處理來自 Tuist 嘅請求，令 Tuist 將傳送標記為成功。
4. [驗證每個請求嘅簽名](#verify-signature)，以證明佢來自 Tuist。
5. 使用 Tuist 儀表板中嘅 [事件日誌](#inspect-deliveries) 喺開發期間進行除錯。

## 事件類型 {#event-types}

Tuist 按照事件所描述嘅資源對事件進行分組。信封中嘅 `type` 欄位使用點號表示法（`{resource}.{action}`）——同你喺儀表板中訂閱嘅值一樣。

{{webhook_events_table}}

未來會有更多事件類型。如果你需要我哋尚未發出嘅類型，請告訴我哋，我哋會將其加入目錄。

## 建立端點 {#create-an-endpoint}

端點係按帳戶配置嘅。從你嘅帳戶設定中打開 **Webhook**，點擊 **新增端點**，然後提供：

- **名稱** —— 端點喺列表中顯示嘅方式。
- **端點 URL** —— 必須使用 `https://`。
- **要監聽嘅事件** —— 揀選特定事件，或者喺群組層級使用 **全選**。只有當訂閱嘅其中一個事件觸發時，Tuist 才會向端點發出 POST 請求。

![端點列表，顯示兩個 Webhook 端點，每個端點訂閱咗兩個事件](/images/guides/integrations/webhooks/endpoints.png)

當你儲存時，Tuist 會生成一個新嘅簽名密鑰並只顯示一次。立即將其複製到你嘅應用程式配置中——你無法再從儀表板中檢索它。如果你遺失咗，請使用端點操作選單中嘅 **輪換密鑰** 來頒發一個新嘅。

<img src="/images/guides/integrations/webhooks/create-endpoint.png" alt="Webhook 端點建立對話框，包含名稱、URL 同分組嘅事件類型複選框" style="max-width: 500px;" />

## 負載 {#payload}

每次傳送都係單一 JSON 物件。信封將特定事件嘅資源快照包裹喺元數據中，你可以用嚟去重、路由同審計傳送：

| 欄位     | 描述                                                              |
| --------- | ------------------------------------------------------------------------ |
| `id`      | 此傳送獨有嘅 UUID。當重試觸發時，用佢嚟去重。 |
| `type`    | 點號分隔嘅事件類型，例如 `test_case.updated`。                         |
| `created` | Tuist 將傳送加入佇列時嘅 Unix 時間戳（秒）。           |
| `object`  | 資源快照。結構取決於事件類型。              |

每個事件類型嘅確切負載架構記錄喺 [Tuist API 參考文件](https://tuist.dev/api/docs#section/Webhook-events) 嘅 **Webhook 事件** 部分——每個事件都有一個對應嘅 `WebhookXxxEvent` 架構，位於 `components.schemas` 之下，你可以從代碼生成器中 `$ref`。

例如，`test_case.updated` 負載亦都帶有一個 `events` 陣列，列出導致寫入嘅規範轉換（`marked_flaky`、`muted`、`unskipped`……），以及 `actor_id` 同 `alert_id`，以便接收者區分手動編輯同自動化驅動嘅更改。

每個請求亦都帶有呢啲 HTTP 標頭：

| 標頭              | 描述                                                                                   |
| ------------------- | --------------------------------------------------------------------------------------------- |
| `Content-Type`      | 永遠係 `application/json`。                                                                    |
| `User-Agent`        | `Tuist-Webhooks/1.0`.                                                                         |
| `Tuist-Event-Id`    | 同主體中嘅 `id` 相同嘅 UUID——如果你喺解析負載之前記錄標頭，會好方便。     |
| `Tuist-Event-Type`  | 同主體中嘅 `type` 相同嘅字符串。                                                            |
| `Tuist-Signature`   | HMAC-SHA256 簽名，格式為 `t={timestamp},v1={hex_digest}`——見下文。          |

## 回應 Webhook {#responding}

為確認收到傳送，你嘅端點應該返回任何 `2xx` 狀態碼。任何超出 `2xx` 範圍嘅內容——連同連接失敗同超時——都會被視為傳送失敗並重試。Tuist 不會跟隨 `3xx` 響應，所以請直接喺規範 URL 處響應，而唔好重定向。

保持你嘅處理程序 **快速**：Tuist 會等待最多 **10 秒** 以獲取響應。如果你有繁重嘅工作要做（調用另一個 API、更新數據庫、發送通知），請接受請求並異步處理。及早返回亦都令你更能抵禦下游服務中嘅暫時性緩慢。

## 驗證簽名 {#verify-signature}

任何知道你端點 URL 嘅人都可以向其發送 POST 請求。簽名密鑰讓你嘅服務器拒絕任何非來自 Tuist 嘅內容。

對於每個請求，Tuist 會計算：

```
signed_payload = "{timestamp}.{raw_request_body}"
signature      = HMAC-SHA256(signing_secret, signed_payload)
header         = "t={timestamp},v1={hex(signature)}"
```

喺你嗰邊進行驗證：

1. 讀取 `Tuist-Signature` 標頭並將其拆分為 `t=`（時間戳）同 `v1=`（十六進制摘要）部分。
2. 如果時間戳與你服務器當前時間相差超過 **5 分鐘**，則拒絕該請求。這 *限制* 咗重放窗口但並未關閉它——請與下面嘅冪等性配合使用。
3. 重新計算 `HMAC-SHA256(signing_secret, "{timestamp}.{raw_body}")` 並以 **恆定時間** 將其與摘要進行比較。
4. 根據負載 `id` 對傳送進行去重（亦顯示為 `Tuist-Event-Id` 標頭）。佢喺重試期間保持穩定，所以持久化你已經處理過嘅 ID 可以防止被捕獲嘅請求喺容忍窗口內被重放，並保護你免受重試時嘅重複處理。

> [!IMPORTANT] USE THE RAW BODY
> 簽名係基於 Tuist 發送嘅字節計算嘅。如果你嘅 Web 框架喺你驗證之前重新解析並重新序列化 JSON，摘要將不匹配。捕獲原始主體（例如 Rack 中嘅 `request.body.read`，Express 中嘅原始 `Buffer`）並將其傳遞給你嘅驗證器。

Node.js 中嘅參考驗證器——將相同嘅四個步驟（解析標頭、檢查時間戳偏移、重新計算 HMAC、以恆定時間比較）翻譯成你接收器所用嘅任何語言：

```javascript
import crypto from "node:crypto";

function verifyTuistSignature(rawBody, header, secret, toleranceSeconds = 300) {
  const parts = Object.fromEntries(
    header.split(",").map((kv) => kv.split("=", 2))
  );
  const timestamp = Number(parts.t);
  const signature = parts.v1;
  if (!timestamp || !signature) return false;

  const drift = Math.abs(Math.floor(Date.now() / 1000) - timestamp);
  if (drift > toleranceSeconds) return false;

  const expected = crypto
    .createHmac("sha256", secret)
    .update(`${timestamp}.${rawBody}`)
    .digest("hex");

  const a = Buffer.from(expected, "hex");
  const b = Buffer.from(signature, "hex");
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
```

## 重試 {#retries}

Tuist 會重試任何返回非 `2xx` 狀態、超時或連接失敗嘅傳送。計劃係固定嘅：

| 嘗試次數 | 發送前等待 |
| ------- | ------------------- |
| 1       | （立即）         |
| 2       | 1 分鐘            |
| 3       | 5 分鐘           |
| 4       | 30 分鐘          |
| 5       | 2 小時             |
| 6       | 8 小時             |
| 7       | 24 小時            |

第七次嘗試失敗後，傳送將被永久標記為失敗。由於每次嘗試都使用發送時嘅時間戳進行簽名，你嘅重放保護窗口仍然適用於重試——你無需擴大它。

## 檢查傳送 {#inspect-deliveries}

從 **Webhooks** 頁面打開一個端點以查看其傳送歷史記錄。詳細頁面顯示：

- 一張 **摘要卡片**，包含目標 URL、遮罩嘅簽名密鑰、訂閱嘅事件同創建日期。
- 一張 **傳送圖表**，顯示累計總數同失敗次數，範圍限定於所選時間窗口。
- 一個 **事件表格**，你可以按狀態、事件類型或事件 ID 進行過濾。

![Webhook 端點詳細頁面，顯示摘要卡片同事件傳送圖表](/images/guides/integrations/webhooks/endpoint-detail.png)

點擊一個事件以查看該次嘗試嘅完整請求同響應——Tuist 發送嘅確切負載、標頭、上游狀態碼同響應主體。這與你服務器看到嘅數據相同，使其成為調試簽名驗證不匹配或上游 5xx 錯誤嘅最快方法。

![Webhook 事件詳細頁面，顯示摘要、請求標頭同主體，以及上游響應](/images/guides/integrations/webhooks/event-detail.png)

傳送記錄會無限期保留，以便你喺調試集成時回顧。如果你嘅下游系統需要持久副本（例如用於合規性），請喺傳送到達時喺你自己嘅基礎設施上捕獲它們。

## 輪換或删除端點 {#rotate-or-delete}

這兩個操作都位於端點行嘅三點菜單同端點詳細頁面上：

- **輪換密鑰** — 生成一個新嘅簽名密鑰並只顯示一次。現有消費者喺你更新他們之前會驗證失敗，所以請將輪換與部署一起規劃。
- **删除端點** — 移除端點並停止傳送。已記錄嘅傳送嘗試會保留到標準保留窗口過期。

## 安全注意事項 {#security}

- 端點 URL 必須係 HTTPS。Tuist 拒絕向明文目標傳送。
- Tuist 喺每次傳送之前解析目標主機名，並拒絕環回、RFC1918、鏈路本地、ULA 同雲元數據地址（`169.254.169.254`、`fd00::/8`……）。這可以防止配置錯誤嘅 webhook 被用來掃描或攻擊運行你 Tuist 服務器嘅主機。
- 端點 URL 同簽名密鑰喺靜態時加密。作為 bearer 憑證，它們被排除喺 GDPR/CCPA 數據導出之外。
- 簽名密鑰只會顯示一次。請將其視為密碼：儲存喺你嘅密鑰管理器中，而唔係放喺代碼庫。
