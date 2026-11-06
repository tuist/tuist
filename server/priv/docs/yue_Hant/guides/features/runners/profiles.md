---
{
  "title": "設定檔",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "Runner 設定檔係有名稱嘅機器規格，你可以喺 runs-on 入面引用佢哋，為 Tuist Runners 選擇平台、大小同 Xcode 版本。"
}
---
# 設定檔 {#profiles}

**設定檔**係一個以帳戶為範圍、有名稱嘅機器規格。你可以喺工作流程嘅 `runs-on` 入面引用佢，Tuist 就會將工作分派到符合條件嘅執行器。設定檔將基礎設施選擇（平台、大小、Xcode 版本）集中管理，唔使分散喺每個工作流程檔案度，亦提供一個穩定嘅標籤畀 CI 使用。

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

標籤就係設定檔名稱加上 `tuist-` 前綴。名為 `macos` 嘅設定檔對應 `runs-on: tuist-macos`；名為 `linux-large` 嘅設定檔對應 `runs-on: tuist-linux-large`。配對時不區分大小寫。

## 預設設定檔 {#default-profiles}

每個啟用咗 Runners 功能嘅帳戶都會預設兩個設定檔，令你唔使做任何設定就可以直接使用執行器群組：

{{runner_default_profiles_table}}

兩者都指向各自平台嘅預設 <.localized_link href="/guides/features/runners/profiles#machine-shapes">規格</.localized_link>。佢哋係 **受保護** 嘅，所以唔可以被刪除，而你工作流程所依賴嘅標籤亦會一直有效。你仍然可以更改佢哋嘅規格或 Xcode 版本，亦可以建立額外嘅設定檔嚟支援其他大小或 Xcode 版本。

## 機器規格 {#machine-shapes}

執行器支援 macOS（Apple silicon，喺 Mac 群組上虛擬化運行）同 Linux。每個設定檔都會固定一種機器規格，即係下面目錄中嘅 `(vCPUs, memory)` 組合。

### Linux {#linux}

{{runner_linux_shapes_table}}

每個 Linux 設定檔都透過 `/dev/kvm` 支援 <.localized_link href="/guides/features/runners#android-emulators">硬件加速嘅 Android 模擬器</.localized_link>。唔需要額外嘅 KVM 設定檔。

### macOS {#macos}

{{runner_macos_shapes_table}}

較大嘅 macOS 規格喺群組中可用嘅機器較少，所以要求呢類規格嘅工作可能要比使用較小規格嘅同樣工作等待更長時間先至開始。當工作受 CPU 限制時，先考慮使用較大規格，其他情況則保留預設規格。如果你唔確定，可以分別用兩種規格運行工作，然後喺儀表板比較耗時。

macOS 設定檔亦會固定一個 **Xcode 版本**。該版本會選擇已預裝相應 Xcode 嘅執行器映像，令工作開始時工具鏈已經準備就緒。目前支援嘅版本：

{{runner_macos_xcode_versions}}

> [!NOTE]
> 隨著我哋加入新硬件同 Xcode 版本，目錄會不斷更新。儀表板中嘅 **新增設定檔** 表單同 `tuist runner profile catalog` 始終顯示你帳戶當前可用嘅規格同 Xcode 版本，請以佢哋為準。

macOS 執行器嘅名稱會顯示其所運行嘅 macOS 版本、設定檔嘅 Xcode 版本及其規格，例如 `tuist-macos-26.6-xcode-27.0-6vcpu-14gb-1a2b3c4d5e6f`。呢個名稱會出現喺 GitHub 上工作嘅 **設置工作** 步驟中，以及 Tuist 儀表板嘅工作詳情入面。

## 建立設定檔 {#creating-a-profile}

1. 打開你帳戶儀表板嘅 **Runners → Profiles** 部分。
2. 選擇 **新增設定檔**。
3. 為佢起個名，選擇平台，然後揀選規格。對於 macOS，仲要選擇一個 Xcode 版本。
4. 儲存，然後喺工作流程中使用 `runs-on: tuist-<name>` 引用佢。

你亦可以從命令列管理設定檔。建立、更改同刪除設定檔需要帳戶管理權限（如同喺儀表板中一樣），或者擁有帶有 `account:runners:write` 權限範圍嘅帳戶令牌：

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

Agent 可以透過 <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link> 執行相同操作。

例如，一個名為 `linux-large` 嘅設定檔，使用 8 vCPU / 32 GB 規格：

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

或者一個名為 `xcode-26-4` 嘅 macOS 設定檔，固定於 Xcode `26.4.1`，令工作可以使用較舊嘅工具鏈運行，而你嘅預設 `macos` 設定檔則追蹤最新版本：

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
