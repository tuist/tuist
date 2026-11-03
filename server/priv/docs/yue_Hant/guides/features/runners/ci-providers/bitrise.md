---
{
  "title": "Bitrise",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "喺 Tuist Runners 上執行你嘅 Bitrise 構建：連接你嘅工作區，將自託管運行器池與 Tuist 設定檔配對，然後喺你嘅工作流程中選擇該池。"
}
---
# Bitrise {#bitrise}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前僅限邀請。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯絡我們，為你的帳戶申請存取權限。

> [!WARNING]
> **僅限私人儲存庫**
>
> Tuist 信任每個 Bitrise 建構：建構會共用你帳戶的快取並可寫入其中。切勿將工作流程會從公開儲存庫的分叉建構拉取請求的集區進行配對。

Tuist 為你 Bitrise 工作區的自託管 Runner 集區提供服務。選擇其中一個集區的建構，會在與該集區配對的<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>所對應的 Tuist 機器上執行。你的工作流程、觸發條件和日誌仍保留在 Bitrise；只有機器會改變。

1. **申請存取權限。** 測試期間，Runners 僅限邀請。[聯絡我們](mailto:contact@tuist.dev)並提供你想啟用的帳戶。
2. **連接你的工作區。** 在 Bitrise 中，開啟**工作區設定 → 安全性 → 工作區 API 權杖**，並建立一個具有**檢視者**工作區角色及對所有專案的 Bitrise CI 具備**測試人員/QA**存取權限的權杖。在你的 Tuist 儀表板中，前往**設定 → 整合**，在 Bitrise 卡片上選擇**連接**，然後貼上權杖。Tuist 會從權杖讀取工作區資訊，將權杖加密儲存，且不會再次顯示。
3. **建立 Runner 集區。** 在 Bitrise 中，開啟**工作區設定 → 基礎設施**，選擇**新增 Runner 集區**，並以它所代表的機器命名，例如`tuist-macos`。複製集區權杖：Bitrise 只會顯示一次。
4. **將集區與 Tuist 設定檔配對。** 在 Tuist 的 Bitrise 卡片上，於**Runner 集區**下方，選擇集區、其建構應執行的 Tuist 設定檔，貼上集區權杖，然後選擇**新增集區**。每個已啟用的帳戶預設都有兩個設定檔：`tuist-linux`和`tuist-macos`。為你想要使用的每個設定檔新增一個集區。
5. **在你的工作流程中選擇集區。** 在 Bitrise 的工作流程編輯器中，開啟**堆疊與機器**並選擇**Self-Hosted Runner: tuist-macos**。在`bitrise.yml`中，設定集區的堆疊，Tuist 會在集區名稱下方顯示：

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

6. **執行建構。** 幾秒內，一台 Tuist 機器會連接到集區、接收建構，並在完成後斷開連線。該建構會出現在你 Tuist 儀表板的**Runners**區段，包含其機器指標以及返回 Bitrise 的連結，日誌仍保留在 Bitrise。

## 專用集區{#dedicated-pools}

僅將與 Tuist 配對的集區用於 Tuist。如果你自己的其中一台機器也連接到已配對的集區，它會與 Tuist 競爭該集區的建構。

## Runner 數量上限{#runner-limit}

每台 Tuist 機器在執行建構時會計為一個 Bitrise runner，並在斷開連線時停止計數。因此，你的 Bitrise 方案的 runner 數量上限會限制同時在 Tuist 上執行的建構數量，這與你的 Tuist 並行限制同時生效。

## 斷開連線{#disconnecting}

從 Bitrise 卡片移除集區會阻止 Tuist 接收該集區的建構。已經執行中的建構不受影響。

在 Bitrise 卡片上選擇**斷開連線**會移除工作區及其所有集區。
