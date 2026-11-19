---
{
  "title": "Bitrise",
  "titleTemplate": ":title · CI 服務供應商 · 執行器 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 執行器上執行你的 Bitrise 建置：連接你的工作區，將自託管執行器集區與 Tuist 設定檔配對，並在工作流程中選取該集區。"
}
---
# Bitrise {#bitrise}

<!-- @snippet: ./_invite-only -->

> [!WARNING]
> **僅限私人儲存庫**
>
> Tuist 信任所有 Bitrise 建置：這些建置會共用你帳戶的快取並可寫入其中。請勿將工作流程會建置來自公開儲存庫分支之拉取請求的集區進行配對。

Tuist 為你的 Bitrise 工作區提供自託管執行器集區。選擇其中一個集區的建置，會在與該集區配對的<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>所對應的 Tuist 機器上執行。你的工作流程、觸發條件和日誌仍保留在 Bitrise；只有執行機器會改變。

1. **連接你的工作區。** 在 Bitrise 中，開啟**工作區設定 → 安全性 → 工作區 API 權杖**，並建立一個具備**檢視者**工作區角色以及對所有專案具有 Bitrise CI **測試人員/QA**存取權的權杖。在你的 Tuist 儀表板中，前往**設定 → 整合**，在 Bitrise 卡片上選擇**連接**，並貼上權杖。Tuist 會從權杖讀取工作區資訊，以加密方式儲存權杖，且之後不再顯示。
2. **建立執行器集區。** 在 Bitrise 中，開啟**工作區設定 → 基礎設施**，選擇**新增執行器集區**，並以它所代表的機器命名，例如 `tuist-macos`。複製集區權杖：Bitrise 僅顯示一次。
3. **將集區與 Tuist 設定檔配對。** 在 Tuist 的 Bitrise 卡片上，於**執行器集區**下方，選擇集區、其建置應執行的 Tuist 設定檔，貼上集區權杖，然後選擇**新增集區**。每個啟用的帳戶都會預設包含兩個設定檔：`tuist-linux` 和 `tuist-macos`。為你想要使用的每個設定檔新增一個集區。
4. **在你的工作流程中選擇集區。** 在 Bitrise 的工作流程編輯器中，開啟**堆疊與機器**，並選擇**自託管執行器：tuist-macos**。在 `bitrise.yml` 中，設定集區的堆疊，Tuist 會在集區名稱下方顯示該堆疊：

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

5. **執行建置。** 幾秒內，一台 Tuist 機器會連接到集區、接收建置，並在完成後斷開連線。該建置會出現在你 Tuist 儀表板的**執行器**區段中，並顯示其機器指標以及返回 Bitrise 的連結，其日誌仍保留在 Bitrise。

## 專用集區 {#dedicated-pools}

僅將與 Tuist 配對的集區用於 Tuist。若你自己的其中一台機器也連接到已配對的集區，它將與 Tuist 競爭該集區的建置任務。

## 執行器限制 {#runner-limit}

每台 Tuist 機器在執行建置期間會計為一個 Bitrise 執行器，並在斷開連線時停止計數。因此，你的 Bitrise 方案中的執行器限制會與你的 Tuist 並行限制一起，限制同時在 Tuist 上執行的建置數量。

## 斷開連線 {#disconnecting}

從 Bitrise 卡片移除集區會阻止 Tuist 接收該集區的建置。已在執行的建置不受影響。

在 Bitrise 卡片上選擇**斷開連線**會移除工作區及其所有集區。
