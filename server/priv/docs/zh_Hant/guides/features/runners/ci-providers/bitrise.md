---
{
  "title": "Bitrise",
  "titleTemplate": ":title · CI 供應商 · 執行器 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 執行器上執行你的 Bitrise 建置：連接你的工作區，將自託管執行器集區與 Tuist 設定檔配對，並在你的工作流程中選取該集區。"
}
---
# Bitrise {#bitrise}

> [!WARNING]
> **僅限私有儲存庫**
>
> Tuist 信任所有 Bitrise 建置：這些建置會共用你帳戶的快取，並可寫入其中。請勿將工作流程會建置來自公開儲存庫分支之拉取請求的集區進行配對。

Tuist 會為你 Bitrise 工作區的自託管執行器集區提供服務。選擇其中一個集區的建置，會在與該集區配對的<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>所對應的 Tuist 機器上執行。你的工作流程、觸發條件和日誌仍保留在 Bitrise；只有執行機器會改變。

1. **連接你的工作區。** 在 Bitrise 中，開啟**Workspace settings → Security → Workspace API tokens**，並建立一個具備**Viewer**工作區角色以及對所有專案的 Bitrise CI 擁有**Tester/QA**存取權的權杖。在你的 Tuist 儀表板中，前往**Settings → Integrations**，在 Bitrise 卡片上選擇**Connect**，然後貼上權杖。Tuist 會從權杖讀取工作區資訊，以加密方式儲存權杖，且不會再次顯示。
2. **建立執行器集區。** 在 Bitrise 中，開啟**Workspace settings → Infrastructure**，選擇**Add Runner pool**，並以它所代表的機器命名，例如`tuist-macos`。複製集區權杖：Bitrise 僅顯示一次。
3. **將集區與 Tuist 設定檔配對。** 在 Tuist 的 Bitrise 卡片上，於**Runner pools**下方，選擇集區、該集區建置應執行的 Tuist 設定檔，貼上集區權杖，然後選擇**Add pool**。每個啟用的帳戶一開始都會有兩個設定檔：`tuist-linux`和`tuist-macos`。為每個你想使用的設定檔新增一個集區。
4. **在工作流程中選擇集區。** 在 Bitrise 的 Workflow Editor 中，開啟**Stacks & Machines**並選擇**Self-Hosted Runner: tuist-macos**。在`bitrise.yml`中，設定集區的 stack，Tuist 會在集區名稱下方顯示該值：

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

5. **執行建置。** 幾秒內，一台 Tuist 機器會連接到集區、接手建置，並在完成後斷開連線。該建置會出現在你 Tuist 儀表板的**Runners**區段中，包含其機器指標以及指向 Bitrise 的連結（日誌仍保留在該處）。

## 專用集區{#dedicated-pools}

僅將與 Tuist 配對的集區用於 Tuist。若你自己的其中一台機器也連接到已配對的集區，它將與 Tuist 競爭該集區的建置任務。

## 執行器數量上限{#runner-limit}

每台 Tuist 機器在執行建置期間會計為一個 Bitrise 執行器，並在斷開連線時停止計數。因此，你的 Bitrise 方案中的執行器數量上限，會限制同時在 Tuist 上執行的建置數量，這與你的 Tuist 並行上限共同作用。

## 斷開連線{#disconnecting}

從 Bitrise 卡片移除集區後，Tuist 將不再接手該集區的建置。已在執行的建置不受影響。

在 Bitrise 卡片上選擇**Disconnect**會移除工作區及其所有集區。
