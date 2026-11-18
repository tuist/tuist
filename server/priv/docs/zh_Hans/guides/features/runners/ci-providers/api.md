---
{
  "title": "API",
  "titleTemplate": ":title · CI 提供商 · Runners · 功能 · 指南 · Tuist",
  "description": "从你自己的 Git 平台或编排器在 Tuist Runners 上运行作业：通过一次 API 请求创建作业，并通过 Webhook 跟踪其状态。"
}
---
# API {#api}

<!-- @snippet: ./_invite-only -->

没有自有 Runner 协议的 Git Forge、合并队列和代理编排器可以直接在 Tuist Runners 上运行作业。你只需发起一个请求即可创建作业，所选<.localized_link href="/guides/features/runners/profiles">配置文件</.localized_link>对应的 Tuist 机器会检出提交并运行你的脚本，然后 Tuist 将结果报告给你的 Webhook 端点。

## 运行作业 {#run-a-job}

1. **创建账户令牌**，并赋予 `account:runners:write` 作用域：

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **创建作业。** 典型调用方会在其推送钩子中执行此操作，并使用一个短期有效的令牌，使机器能够克隆仓库：

   ```bash
   curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs \
     -H "Authorization: Bearer $TUIST_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "profile": "tuist-macos",
       "repository_url": "https://git.example.com/acme/app.git",
       "clone_token": "<short-lived token>",
       "commit_sha": "4f1c2d0e9b8a7c6d5e4f3a2b1c0d9e8f7a6b5c4d",
       "ref": "refs/heads/main",
       "name": "test",
       "script": "mise install\nmise run test",
       "secrets": { "SIGNING_KEY": "..." },
       "timeout_minutes": 30,
       "idempotency_key": "acme/app:4f1c2d0e:test"
     }'
   ```

   响应即为该作业，其中包含其 `workflow_job_id`。它会立即出现在 Tuist 仪表板的**Runners**部分，并在所选配置文件的机器空闲时立即启动。预热中的机器通常会在几秒内启动作业。

3. **跟踪作业。** 为 <.localized_link href="/guides/integrations/webhooks">Webhook 端点</.localized_link>订阅 `runner_job.started` 和 `runner_job.completed`。完成事件会携带作业的 `conclusion`：`success`、`failure` 或 `cancelled`。你也可以轮询 `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}`，并从 `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs` 读取日志。

## 集成 Git Forge {#integrate-a-git-forge}

没有 Runner 协议的 Forge 通过一个小型桥接服务连接，该桥接可以是 Forge 自身的服务，也可以是其钩子调用的函数：

1. **在推送时**，Forge 的推送钩子会到达桥接服务。桥接服务验证钩子，决定该提交需要哪些检查，并为仓库生成一个只读克隆令牌，该令牌会在作业超时后过期。
2. **对于每项检查**，桥接服务会创建一个作业，并将 `idempotency_key` 设置为 `<repository>:<commit>:<check>`，这样重新交付的钩子不会创建新作业。它会保存返回的 `workflow_job_id`，并可以在 Forge 中将检查标记为待处理。
3. **在收到 `runner_job.started` 和 `runner_job.completed`** 时，桥接服务使用端点的密钥验证 `Tuist-Signature` 标头，通过 `workflow_job_id` 或 `idempotency_key` 找到对应的检查，并用 `conclusion` 更新 Forge 中的提交状态。它还可以将状态链接到 Tuist 仪表板中的作业页面。
4. **当一次推送取代某个提交时**，桥接服务会取消它为旧提交创建的作业。

## 作业如何运行 {#how-the-job-runs}

机器通过 HTTPS 从 `repository_url` 获取 `commit_sha`。如果服务器不按 SHA 提供提交，它会改为获取 `ref`，该引用必须包含该提交。`clone_token`（如果你提供了）仅作为 `Authorization: Bearer <token>` 发送给仓库主机。它永远不会出现在你的脚本或作业日志中。

你的脚本在登录 shell 中使用 Bash 运行，并启用 `set -eo pipefail`，从检出目录的根目录开始执行。当脚本以非零状态退出或运行超过 `timeout_minutes`（默认为 60，最多可达 360）时，作业失败。除了你的 `env` 和 `secrets`，脚本还可以看到 `CI=true`、`TUIST_JOB_ID`、`TUIST_JOB_NAME`、`TUIST_JOB_REPOSITORY_URL`、`TUIST_JOB_REF` 和 `TUIST_JOB_COMMIT_SHA`。`secrets` 的值在作业日志中会被掩码处理。

## 重试与幂等性 {#idempotency}

为每个作业提供一个 `idempotency_key`，用于标识其用途，例如 `<repository>:<commit>:<check>`。如果请求使用的键在你的账户中已被使用，则会返回现有作业，状态码为 200 而非 201，且不会创建新作业。这样，你的推送钩子可以将请求交给重试队列，而无需担心重复创建作业。

Webhook 投递会不断重试，直到你的端点返回 2xx 状态码，因此事件可能会多次到达。使用信封的 `id`，或结合事件类型使用作业的 `workflow_job_id` 来进行去重。

## 取消作业 {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

尚未被任何机器启动的作业会立即取消。正在运行的作业会在几秒内停止，其完成事件会报告 `cancelled`。24 小时内没有任何机器启动的作业会自动取消。

## 缓存与信任 {#trust}

任何能向仓库推送的人都可以更改作业运行的内容，因此 API 作业被视为不可信：它们无法使用你账户共享的<.localized_link href="/guides/features/runners/cache-volumes">缓存卷</.localized_link>，也无法获得缓存签名授权。作业的机密信息、脚本和克隆令牌会以加密方式存储，并在作业完成后删除。
