---
{
  "title": "Bitrise",
  "titleTemplate": ":title · CI 供應商 · Runners · 功能 · 指南 · Tuist",
  "description": "喺 Tuist Runners 上執行你嘅 Bitrise 構建：連接你嘅工作區，將自託管嘅 runner 池同 Tuist 設定檔配對，然後喺你嘅工作流程中選擇該池。"
}
---
# Bitrise {#bitrise}

> [!WARNING]
> **只限私人儲存庫**
>
> Tuist 信任每個 Bitrise 建構：建構會共用你帳戶的快取，並可寫入其中。切勿將工作流程會建構來自公開儲存庫分支的拉取請求的集區配對。

Tuist 會為你的 Bitrise 工作區提供自託管執行器集區。選擇其中一個集區的建構，會在與該集區配對的 <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link> 所對應的 Tuist 機器上執行。你的工作流程、觸發條件和日誌仍保留在 Bitrise；只有機器會改變。

1. **連接你的工作區。** 在 Bitrise 中，開啟 **Workspace settings → Security → Workspace API tokens**，並建立一個具備 **Viewer** 工作區角色及所有專案的 **Tester/QA** Bitrise CI 存取權的令牌。在你的 Tuist 儀表板中，前往 **Settings → Integrations**，在 Bitrise 卡片上選擇 **Connect**，然後貼上令牌。Tuist 會從令牌讀取工作區資訊，以加密方式儲存令牌，且不會再次顯示。
2. **建立執行器集區。** 在 Bitrise 中，開啟 **Workspace settings → Infrastructure**，選擇 **Add Runner pool**，並以它所代表的機器命名，例如 `tuist-macos`。複製集區令牌：Bitrise 只會顯示一次。
3. **將集區與 Tuist 設定檔配對。** 在 Tuist 的 Bitrise 卡片上，於 **Runner pools** 下方，選擇集區、其建構應執行的 Tuist 設定檔，貼上集區令牌，然後選擇 **Add pool**。每個已啟用的帳戶都會預設兩個設定檔：`tuist-linux` 和 `tuist-macos`。為你想要使用的每個設定檔新增一個集區。
4. **在工作流程中選擇集區。** 在 Bitrise 的 Workflow Editor 中，開啟 **Stacks & Machines** 並選擇 **Self-Hosted Runner: tuist-macos**。在 `bitrise.yml` 中，設定集區的 stack，Tuist 會在集區名稱下方顯示：

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

5. **執行建構。** 幾秒內，一台 Tuist 機器會連接到集區、接收建構，並在完成後斷開連線。該建構會出現在你 Tuist 儀表板的 **Runners** 區段，當中包含其機器指標以及返回 Bitrise 的連結，其日誌會保留在 Bitrise。

## 專用集區 {#dedicated-pools}

僅將你與 Tuist 配對的集區用於 Tuist。如果你自己的其中一部機器也連接到已配對的集區，它會與 Tuist 競爭該集區的建構任務。

## 執行器限制 {#runner-limit}

每台 Tuist 機器在執行建構期間會計為一個 Bitrise 執行器，並在斷開連線時停止計數。因此，你的 Bitrise 方案的執行器限制會限制同時在 Tuist 上運行的建構數量，這與你的 Tuist 並行限制一同生效。

## 斷開連線 {#disconnecting}

從 Bitrise 卡片移除集區會阻止 Tuist 接收該集區的建構。已經運行的建構不受影響。

在 Bitrise 卡片上選擇 **Disconnect** 會移除工作區及其所有集區。
