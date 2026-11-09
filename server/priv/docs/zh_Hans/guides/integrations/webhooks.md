---
{
  "title": "Webhooks",
  "titleTemplate": ":title | 集成 | 指南 | Tuist",
  "description": "将 HTTPS 端点订阅到 Tuist 事件，使用签名载荷验证交付，并从仪表板检查每次尝试。"
}
---
# Webhook {#webhooks}

Webhook 让你的系统能够在 Tuist 内部发生变化时立即做出反应。每当发生相关事件——例如观察到新的测试用例、预览完成上传、或不稳定测试得到修复——Tuist 都会向你订阅了该事件类型的每个端点发送 HTTP POST 请求。请求体是一个 JSON 信封，每次交付都携带一个签名头，你可以使用端点的签名密钥进行验证。

你注册目标 URL，选择想要的事件，Tuist 会负责签名、重试和交付审计日志。

## 接收 Webhook 的步骤 {#steps}

你可以通过以下步骤开始在应用中接收事件通知：

1. [确定你的应用想要接收的事件](#event-types)。
2. 在本地服务器上[创建 Webhook 端点](#create-an-endpoint)作为 HTTP 端点（URL）。
3. 通过[解析负载](#payload)并返回[2xx 状态码](#responding)来处理来自 Tuist 的请求，以便 Tuist 将交付标记为成功。
4. [验证每个请求的签名](#verify-signature)以证明其来自 Tuist。
5. 使用 Tuist 仪表板中的[事件日志](#inspect-deliveries)在构建过程中进行调试。

## 事件类型 {#event-types}

Tuist 按事件描述的资源对事件进行分组。信封中的 `type` 字段使用点号表示法（`{resource}.{action}`）——与你在仪表板中订阅的值相同。

{{webhook_events_table}}

更多事件类型将陆续推出。如果你需要尚未提供的事件类型，请告知我们，我们会将其添加到目录中。

## 创建端点 {#create-an-endpoint}

端点按账户配置。从账户设置中打开**Webhook**，点击**添加端点**，并提供：

- **名称** —— 端点在列表中的显示方式。
- **端点 URL** —— 必须使用 `https://`。
- **监听的事件** —— 选择特定事件，或在组级别使用**全选**。只有当订阅的事件触发时，Tuist 才会向端点发送 POST 请求。

![端点列表，显示两个 Webhook 端点，每个端点订阅了两个事件](/images/guides/integrations/webhooks/endpoints.png)

保存时，Tuist 会生成一个新的签名密钥并仅显示一次。请立即将其复制到应用的配置中——你将无法从仪表板再次检索它。如果丢失，请使用端点操作菜单中的**轮换密钥**来生成新密钥。

<img src="/images/guides/integrations/webhooks/create-endpoint.png" alt="Webhook 端点创建模态框，包含名称、URL 和分组的事件类型复选框" style="max-width: 500px;" />

## 负载 {#payload}

每次交付都是一个单独的 JSON 对象。信封将特定事件的资源快照包裹在元数据中，你可以使用这些元数据进行去重、路由和审计交付：

| 字段     | 描述                                                              |
| --------- | ------------------------------------------------------------------------ |
| `id`      | 此交付唯一的 UUID。在重试时使用它进行去重。 |
| `type`    | 点号表示的事件类型，例如 `test_case.updated`。                         |
| `created` | Tuist 将交付加入队列时的 Unix 时间戳（秒）。           |
| `object`  | 资源快照。结构取决于事件类型。              |

每种事件类型的精确负载架构记录在[Tuist API 参考](https://tuist.dev/api/docs#section/Webhook-events)的**Webhook 事件**部分——每个事件在 `components.schemas` 下都有一个匹配的 `WebhookXxxEvent` 架构，你可以从代码生成器中 `$ref`。

例如，`test_case.updated` 负载还携带一个 `events` 数组，列出导致写入的标准转换（`marked_flaky`、`muted`、`unskipped`、…），以及 `actor_id` 和 `alert_id`，以便接收者区分手动编辑和自动化驱动的变化。

每个请求还携带以下 HTTP 头：

| 头              | 描述                                                                                   |
| ------------------- | --------------------------------------------------------------------------------------------- |
| `Content-Type`      | 始终为 `application/json`。                                                                    |
| `User-Agent`        | `Tuist-Webhooks/1.0`.                                                                         |
| `Tuist-Event-Id`    | 与正文中的 `id` 相同的 UUID——如果你在解析负载之前记录头信息，这会很方便。     |
| `Tuist-Event-Type`  | 与正文中的 `type` 相同的字符串。                                                            |
| `Tuist-Signature`   | HMAC-SHA256 签名，格式为 `t={timestamp},v1={hex_digest}`——见下文。          |

## 响应 Webhook {#responding}

要确认交付，你的端点应返回任何 `2xx` 状态码。`2xx` 范围之外的任何内容——以及连接失败和超时——都被视为交付失败并重试。Tuist 不跟随 `3xx` 响应，因此直接在规范 URL 上响应，而不是重定向。

确保你的处理程序**快速**：Tuist 等待响应的时间最长为**10 秒**。如果你有繁重的工作要做（调用其他 API、更新数据库、发送通知），请接受请求并异步处理。尽早返回还能让你对下游服务的暂时性缓慢具有弹性。

## 验证签名 {#verify-signature}

任何知道你的端点 URL 的人都可以向其发送 POST 请求。签名密钥允许你的服务器拒绝任何非来自 Tuist 的请求。

对于每个请求，Tuist 会计算：

```
signed_payload = "{timestamp}.{raw_request_body}"
signature      = HMAC-SHA256(signing_secret, signed_payload)
header         = "t={timestamp},v1={hex(signature)}"
```

要在你的侧进行验证：

1. 读取 `Tuist-Signature` 头并将其拆分为 `t=`（时间戳）和 `v1=`（十六进制摘要）部分。
2. 如果时间戳与服务器当前时间相差超过 **5 分钟**，则拒绝该请求。这*限制*了重放窗口，但并未关闭它——请与下面的幂等性配合使用。
3. 重新计算 `HMAC-SHA256(signing_secret, "{timestamp}.{raw_body}")` 并在**恒定时间**内将其与摘要进行比较。
4. 根据负载 `id` 对交付进行去重（也作为 `Tuist-Event-Id` 头显示）。它在重试之间是稳定的，因此持久化你已处理的 ID 可以防止捕获的请求在容差窗口内被重放，并保护你在重试时免受双重处理。

> [!IMPORTANT] USE THE RAW BODY
> 签名是根据 Tuist 发送的字节计算的。如果你的 Web 框架在验证之前重新解析并重新序列化 JSON，则摘要将不匹配。捕获原始正文（例如 Rack 中的 `request.body.read`，Express 中的原始 `Buffer`）并将其传递给验证器。

Node.js 中的参考验证器——将相同的四个步骤（解析头、检查时间戳漂移、重新计算 HMAC、恒定时间比较）翻译为你的接收器所使用的任何语言：

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

## 重试 {#retries}

Tuist 会重试任何返回非 `2xx` 状态、超时或连接失败的交付。计划是固定的：

| 尝试次数 | 发送前等待 |
| ------- | ------------------- |
| 1       | （立即）         |
| 2       | 1 分钟            |
| 3       | 5 分钟           |
| 4       | 30 分钟          |
| 5       | 2 小时             |
| 6       | 8 小时             |
| 7       | 24 小时            |

第七次尝试失败后，交付将被永久标记为失败。因为每次尝试都使用发送时的时间戳进行签名，所以你的重放保护窗口仍然适用于重试——你无需扩大它。

## 检查交付 {#inspect-deliveries}

从 **Webhooks** 页面打开一个端点以查看其交付历史。详细信息页面显示：

- 一个**摘要卡片**，包含目标 URL、掩码签名密钥、订阅的事件和创建日期。
- 一个**交付图表**，显示运行总数和失败计数，范围限定为所选时间窗口。
- 一个**事件表**，你可以按状态、事件类型或事件 ID 进行过滤。

![Webhook 端点详细信息页面，显示摘要卡片和事件交付图表](/images/guides/integrations/webhooks/endpoint-detail.png)

点击一个事件以查看该尝试的完整请求和响应——Tuist 发送的确切负载、头、上游状态代码和响应正文。这与你的服务器看到的数据相同，这使得它成为调试签名验证不匹配或上游 5xx 错误的最快方法。

![Webhook 事件详细信息页面，显示摘要、请求头和正文以及上游响应](/images/guides/integrations/webhooks/event-detail.png)

交付记录将无限期保留，以便你在调试集成时可以回溯。如果你的下游系统需要持久副本（例如为了合规性），请在交付到达时在你的基础设施上捕获它们。

## 轮换或删除端点 {#rotate-or-delete}

这两个操作都位于端点行和端点详细信息页面上的三点菜单中：

- **轮换密钥** — 生成一个新的签名密钥并仅显示一次。现有消费者在更新之前验证会失败，因此请计划在部署期间进行轮换。
- **删除端点** — 删除端点并停止交付。已记录的交付尝试将保留到标准保留窗口过期。

## 安全说明 {#security}

- 端点 URL 必须是 HTTPS。Tuist 拒绝向明文目标交付。
- Tuist 在每次交付之前解析目标主机名，并拒绝环回、RFC1918、链路本地、ULA 和云元数据地址（`169.254.169.254`、`fd00::/8`、…）。这可以防止配置错误的 Webhook 被用于扫描或攻击运行你的 Tuist 服务器的主机。
- 端点 URL 和签名密钥在静态时加密。它们作为持有者凭据被排除在 GDPR/CCPA 数据导出之外。
- 签名密钥仅显示一次。请像对待密码一样对待它：将其存储在密钥管理器中，而不是代码仓库里。
