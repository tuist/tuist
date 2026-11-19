---
{
  "title": "Bitrise",
  "titleTemplate": ":title · CI 供應商 · Runners · 功能 · 指南 · Tuist",
  "description": "喺 Tuist Runners 上執行你嘅 Bitrise 建構：連接你嘅工作區，將自託管嘅 runner 池配對到 Tuist 設定檔，然後喺你嘅工作流程中選擇該池。"
}
---
# Bitrise {#bitrise}

<!-- @snippet: ./_invite-only -->

> [!WARNING]
> **只限私人儲存庫**
>
> Tuist 信任每一個 Bitrise 建置：建置會共用你帳戶的快取，並可以寫入。不要配對一個其工作流程會建置來自公開儲存庫分支的拉取請求的池。

Tuist 為你 Bitrise 工作區的自託管執行器池提供服務。選擇其中一個池的建置會在與該池配對的<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>所對應的 Tuist 機器上運行。你的工作流程、觸發條件和日誌仍保留在 Bitrise；只有機器會改變。

1. **連接你的工作區。** 在 Bitrise 中，開啟**Workspace settings → Security → Workspace API tokens**，並建立一個具有**Viewer**工作區角色及對所有專案具有**Tester/QA** Bitrise CI 存取權限的令牌。在你的 Tuist 儀表板中，前往**Settings → Integrations**，在 Bitrise 卡片上選擇**Connect**，並貼上令牌。Tuist 會從令牌讀取工作區資訊，將令牌加密儲存，並且不再顯示。
2. **建立執行器池。** 在 Bitrise 中，開啟**Workspace settings → Infrastructure**，選擇**Add Runner pool**，並以它所代表的機器命名，例如`tuist-macos`。複製池令牌：Bitrise 只會顯示一次。
3. **將池與 Tuist 設定檔配對。** 在 Tuist 的 Bitrise 卡片上，於**Runner pools**下方，選擇池、其建置應運行的 Tuist 設定檔，貼上池令牌，然後選擇**Add pool**。每個已啟用的帳戶都會預設兩個設定檔：`tuist-linux`和`tuist-macos`。為每個你想使用的設定檔新增一個池。
4. **在你的工作流程中選擇池。** 在 Bitrise 的 Workflow Editor 中，開啟**Stacks & Machines**並選擇**Self-Hosted Runner: tuist-macos**。在`bitrise.yml`中，設定池的堆疊，Tuist 會在池名稱下方顯示：

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

5. **運行建置。** 幾秒鐘內，一台 Tuist 機器會連接到池，接收建置，並在完成後斷開連接。該建置會出現在你 Tuist 儀表板的**Runners**部分，包含其機器指標以及返回 Bitrise 的連結，其日誌仍保留在 Bitrise。

## 專用池 {#dedicated-pools}

僅將你與 Tuist 配對的池用於 Tuist。如果你自己的其中一台機器也連接到已配對的池，它會與 Tuist 競爭該池的建置。

## 執行器限制 {#runner-limit}

每台 Tuist 機器在運行建置時計為一個 Bitrise 執行器，並在斷開連接時停止計數。因此，你的 Bitrise 方案的執行器限制會限制同時在 Tuist 上運行的建置數量，這與你的 Tuist 並發限制一起生效。

## 斷開連接 {#disconnecting}

從 Bitrise 卡片移除池會阻止 Tuist 接收該池的建置。已經運行的建置不受影響。

在 Bitrise 卡片上選擇**Disconnect**會移除工作區及其所有池。
