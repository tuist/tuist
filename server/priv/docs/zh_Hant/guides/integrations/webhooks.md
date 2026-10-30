---
{
  "title": "Webhooks",
  "titleTemplate": ":title | 整合 | 指南 | Tuist",
  "description": "訂閱 HTTPS 端點以接收 Tuist 事件，透過簽章載荷驗證交付，並從儀表板檢查每次嘗試。"
}
---
# Webhook {#webhooks}

Webhook 讓你的系統在 Tuist 內發生變更時立即做出反應。每當相關事件發生——例如觀察到新的測試案例、預覽完成上傳，或不穩定測試獲得修復——Tuist 會對你已訂閱該事件類型的每個端點發出 HTTP POST 請求。請求主體是一個 JSON 封裝，每次傳送都會攜帶簽章標頭，你可以使用端點的簽署密鑰進行驗證。

你註冊目標 URL、選擇想要的事件，Tuist 會處理簽署、重試與傳送稽核記錄。

## 接收 Webhook 的步驟 {#steps}

你可以透過以下步驟開始在應用程式中接收事件通知：

1. [識別應用程式想要接收的事件](#event-types)。
2. 在本機伺服器上建立一個 HTTP 端點（URL），作為 [Webhook 端點](#create-an-endpoint)。
3. 透過 [解析負載](#payload) 並回傳 [2xx 狀態碼](#responding) 來處理來自 Tuist 的請求，讓 Tuist 將此次傳送標記為成功。
4. [驗證每個請求的簽章](#verify-signature)，以證明其來自 Tuist。
5. 使用 Tuist 儀表板中的 [事件記錄](#inspect-deliveries)，在建置期間進行除錯。

## 事件類型 {#event-types}

Tuist 會依照事件所描述的資源對事件進行分組。封裝中的 `type` 欄位使用點號表示法（`{resource}.{action}`），與你在儀表板中訂閱的值相同。

{{webhook_events_table}}

未來將支援更多事件類型。若你需要我們尚未發出的事件類型，請告訴我們，我們會將其加入目錄。

## 建立端點 {#create-an-endpoint}

端點以帳號為單位進行設定。從帳號設定開啟 **Webhooks**，點擊 **新增端點**，並提供以下資訊：

- **名稱** — 端點在列表中顯示的名稱。
- **端點 URL** — 必須使用 `https://`。
- **要監聽的事件** — 選擇特定事件，或在群組層級使用 **全選**。只有當已訂閱的事件觸發時，Tuist 才會向端點發出 POST 請求。

![端點列表，顯示兩個 Webhook 端點各自訂閱了兩個事件](/images/guides/integrations/webhooks/endpoints.png)

儲存時，Tuist 會產生一組全新的簽署密鑰並僅顯示一次。請立即將其複製到應用程式的設定中——你無法再從儀表板取回該密鑰。若遺失密鑰，請在端點的動作選單中使用 **輪替密鑰** 來發行新密鑰。

<img src="/images/guides/integrations/webhooks/create-endpoint.png" alt="Webhook 端點建立對話框，包含名稱、URL 與依群組分類的事件類型核取方塊" style="max-width: 500px;" />

## 負載 {#payload}

每次傳送都是一個單一 JSON 物件。封裝將特定事件的資源快照包裹在中繼資料中，你可藉此進行去重複、路由與稽核傳送：

| 欄位     | 說明                                                              |
| --------- | ------------------------------------------------------------------------ |
| `id`      | 此傳送專屬的 UUID。當重試觸發時，可使用它進行去重複。 |
| `type`    | 點號表示的事件類型，例如 `test_case.updated`。                         |
| `created` | Tuist 將傳送加入佇列時的 Unix 時間戳記（秒）。           |
| `object`  | 資源快照。結構取決於事件類型。              |

每種事件類型的精確負載結構記載於 [Tuist API 參考文件](https://tuist.dev/api/docs#section/Webhook-events) 的 **Webhook 事件** 章節——每個事件在 `components.schemas` 下都有對應的 `WebhookXxxEvent` 結構，你可以從程式碼產生器中使用 `$ref` 引用。

例如，`test_case.updated` 負載也攜帶一個 `events` 陣列，列出導致寫入的標準轉換（`marked_flaky`、`muted`、`unskipped`…），以及 `actor_id` 與 `alert_id`，讓接收端能夠區分手動編輯與自動化驅動的變更。

每個請求也攜帶以下 HTTP 標頭：

| 標頭              | 說明                                                                                   |
| ------------------- | --------------------------------------------------------------------------------------------- |
| `Content-Type`      | 一律為 `application/json`。                                                                    |
| `User-Agent`        | `Tuist-Webhooks/1.0`.                                                                         |
| `Tuist-Event-Id`    | 與主體中的 `id` 相同的 UUID——若你在解析負載前先記錄標頭，會很方便。     |
| `Tuist-Event-Type`  | 與主體中的 `type` 相同的字串。                                                            |
| `Tuist-Signature`   | HMAC-SHA256 簽章，格式為 `t={timestamp},v1={hex_digest}`——詳見下方。          |

## 回應 Webhook {#responding}

若要確認收到傳送，你的端點應回傳任何 `2xx` 狀態碼。任何不在 `2xx` 範圍內的回應——以及連線失敗與逾時——都會被視為傳送失敗並進行重試。Tuist 不會追蹤 `3xx` 回應，因此請直接在標準 URL 上回應，而非重新導向。

保持處理常式 **快速**：Tuist 最多等待 **10 秒** 以取得回應。若有繁重工作要執行（呼叫其他 API、更新資料庫、傳送通知），請先接受請求並異步處理。提早回傳也能讓你對下游服務的暫時性緩慢更具韌性。

## 驗證簽章 {#verify-signature}

任何得知你端點 URL 的人都可以向其發送 POST 請求。簽署密鑰讓你的伺服器能夠拒絕任何非來自 Tuist 的請求。

對於每個請求，Tuist 會計算：

```
signed_payload = "{timestamp}.{raw_request_body}"
signature      = HMAC-SHA256(signing_secret, signed_payload)
header         = "t={timestamp},v1={hex(signature)}"
```

要在你的側進行驗證：

1. 讀取 `Tuist-Signature` 標頭，並將其拆分為 `t=`（時間戳記）和 `v1=`（十六進位摘要）部分。
2. 若時間戳記與伺服器當前時間相差超過 **5 分鐘**，則拒絕該請求。這會 *限制* 重放視窗，但不會完全關閉它——請搭配下方的冪等性使用。
3. 重新計算 `HMAC-SHA256(signing_secret, "{timestamp}.{raw_body}")` 並以 **恆定時間** 比較摘要。
4. 根據負載 `id` 對傳送進行去重複（也顯示為 `Tuist-Event-Id` 標頭）。它在重試中保持穩定，因此持久化你已處理的 ID 可以防止被攔截的請求在容差視窗內重放，並保護你在重試時不會重複處理。

> [!IMPORTANT] USE THE RAW BODY
> 簽章是根據 Tuist 發送的位元組計算的。若你的 Web 框架在驗證前重新解析並重新序列化 JSON，摘要將無法匹配。捕捉原始主體（例如 Rack 中的 `request.body.read`，Express 中的原始 `Buffer`）並將其傳遞給驗證器。

Node.js 中的參考驗證器——將相同的四個步驟（解析標頭、檢查時間戳記偏移、重新計算 HMAC、以恆定時間比較）轉換為你接收器所使用的語言：

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

Tuist 會重試任何回傳非 `2xx` 狀態、逾時或連線失敗的傳送。排程是固定的：

| 嘗試次數 | 發送前的等待時間 |
| ------- | ------------------- |
| 1       | （立即）         |
| 2       | 1 分鐘            |
| 3       | 5 分鐘           |
| 4       | 30 分鐘          |
| 5       | 2 小時             |
| 6       | 8 小時             |
| 7       | 24 小時            |

第七次嘗試失敗後，該傳送將被永久標記為失敗。由於每次嘗試都使用發送時的時間戳記進行簽章，你的重放保護視窗在重試時仍然適用——你無需擴大它。

## 檢查傳送 {#inspect-deliveries}

從 **Webhooks** 頁面開啟端點以查看其傳送歷史記錄。詳細頁面顯示：

- 一個 **摘要卡片**，包含目的地 URL、遮罩後的簽署密鑰、訂閱的事件以及建立日期。
- 一個 **傳送圖表**，顯示累計總數和失敗次數，範圍限定於選定的時間視窗。
- 一個 **事件表格**，你可以依狀態、事件類型或事件 ID 進行篩選。

![Webhook 端點詳細頁面，顯示摘要卡片和事件傳送圖表](/images/guides/integrations/webhooks/endpoint-detail.png)

點擊事件以查看該次嘗試的完整請求和回應——Tuist 發送的精確負載、標頭、上游狀態碼以及回應主體。這與你的伺服器看到的數據相同，使其成為除錯簽章驗證不匹配或上游 5xx 錯誤的最快方法。

![Webhook 事件詳細頁面，顯示摘要、請求標頭和主體，以及上游回應](/images/guides/integrations/webhooks/event-detail.png)

傳送記錄會無限期保留，以便你在除錯整合時回顧。若你的下游系統需要持久副本（例如為了合規性），請在傳送到達時將其捕获到你的基礎設施中。

## 輪替或刪除端點 {#rotate-or-delete}

這兩個動作都位於端點列的 kebab 選單以及端點的詳細頁面中：

- **輪替密鑰** — 產生新的簽署密鑰並僅顯示一次。現有消費者在更新之前驗證會失敗，因此請將輪替與部署一起規劃。
- **刪除端點** — 移除端點並停止傳送。已記錄的傳送嘗試會保留至標準保留視窗過期。

## 安全性注意事項 {#security}

- 端點 URL 必須使用 HTTPS。Tuist 拒絕向明文目的地傳送。
- Tuist 在每次傳送前解析目的地主機名稱，並拒絕迴環、RFC1918、鏈路本地、ULA 和雲端中繼資料地址（`169.254.169.254`、`fd00::/8`…）。這可防止設定錯誤的 Webhook 被用於掃描或攻擊運行 Tuist 伺服器的主機。
- 端點 URL 和簽署密鑰在靜態時加密。它們作為 bearer 憑證，不包含在 GDPR/CCPA 數據匯出中。
- 簽署密鑰僅顯示一次。請將其視為密碼：儲存在你的密鑰管理器中，而非程式碼倉庫裡。
