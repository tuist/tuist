---
{
  "title": "設定檔",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "Runner 設定檔係有名稱嘅機器規格，你可以喺 runs-on 入面引用佢哋，為 Tuist Runners 選擇平台、大小、Ubuntu 版本或者 Xcode 版本。"
}
---
# 設定檔 {#profiles}

**設定檔** 係一個帳戶範圍內、有名稱嘅機器規格。你可以喺工作流嘅 `runs-on` 入面引用佢，Tuist 就會將工作派發到符合條件嘅執行器。設定檔將基礎設施選擇（平台、大小、Ubuntu 版本或 Xcode 版本）集中管理，而唔使分散喺每個工作流檔案中，亦提供一個穩定嘅標籤俾 CI 使用。

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

標籤係設定檔名稱加上 `tuist-` 前綴。名為 `macos` 嘅設定檔對應 `runs-on: tuist-macos`；名為 `linux-large` 嘅設定檔對應 `runs-on: tuist-linux-large`。配對時不區分大小寫。

## 預設設定檔 {#default-profiles}

每個啟用咗 Runners 嘅帳戶都會預先配備兩個設定檔，令你無需任何配置即可使用執行器集群：

{{runner_default_profiles_table}}

兩者都指向各自平台嘅預設 <.localized_link href="/guides/features/runners/profiles#machine-shapes">規格</.localized_link>。佢哋係 **受保護** 嘅，所以無法刪除，確保你工作流依賴嘅標籤始終有效。你仍然可以更改佢哋嘅規格或 Xcode 版本，亦可以創建額外嘅設定檔以支援其他大小或 Xcode 版本。

## 機器規格 {#machine-shapes}

執行器支援 macOS（Apple silicon，喺 Mac 集群上虛擬化）同 Linux。每個設定檔會固定目錄中嘅一種機器規格，即一對 `(vCPUs, memory)`。

### Linux {#linux}

{{runner_linux_shapes_table}}

Linux 設定檔亦會選擇一個 **Ubuntu 版本**，就好似 macOS 設定檔選擇 Xcode 版本咁：

- **Ubuntu 24.04**（`ubuntu-24.04`），新設定檔嘅預設選項。
- **Ubuntu 22.04**（`ubuntu-22.04`），供仍需使用該版本嘅工作流。GitHub 已棄用其 22.04 託管映像，並將於 2027 年 4 月 17 日移除；請計劃在此之前遷移。

設定檔會保持喺你所選嘅版本，直到你主動更改，因此較新嘅預設值不會自動將你嘅工作遷移到另一個作業系統。喺 24.04 上構建嘅二進制文件需要較新嘅 glibc (2.39)，可能無法喺較舊系統上運行，而且其系統 Python 會拒絕喺虛擬環境之外執行 `pip install`（PEP 668）。執行器會設置 `ImageOS`（`ubuntu24` 或 `ubuntu22`），如同 GitHub 託管執行器所做嘅咁，以便設置動作選擇正確版本嘅構建。

每個 Linux 設定檔都透過 `/dev/kvm` 支援 <.localized_link href="/guides/features/runners#android-emulators">硬件加速嘅 Android 模擬器</.localized_link>。無需單獨嘅 KVM 設定檔。

### macOS {#macos}

{{runner_macos_shapes_table}}

較大嘅 macOS 規格喺集群中可用嘅機器較少，因此請求該規格嘅工作可能比使用較小規格嘅相同工作需要更長嘅啟動時間。當工作受 CPU 限制時，請選擇較大嘅規格，其他情況則保持預設規格。如果你不確定，可以喺兩種規格上運行工作並喺儀表板中比較持續時間。

macOS 設定檔亦會固定一個 **Xcode 版本**。該版本會選擇預裝咗該 Xcode 嘅執行器映像，因此工作開始時工具鏈已經就位。目前支援嘅版本：

{{runner_macos_xcode_versions}}

> [!NOTE]
> 隨著我哋添加新硬件同 Xcode 版本，目錄會不斷更新。儀表板中嘅 **新增設定檔** 表單同 `tuist runner profile catalog` 始終顯示你帳戶當前可用嘅規格、Xcode 版本同 Ubuntu 版本，請以佢哋為準。

macOS 執行器嘅名稱顯示其運行嘅 macOS 版本、設定檔嘅 Xcode 版本及其規格，例如 `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-1a2b3c4d5e6f`。該名稱會出現喺 GitHub 上工作嘅 **設置工作** 步驟中，以及 Tuist 儀表板中工作嘅詳細信息裡。

## 創建設定檔 {#creating-a-profile}

1. 打開帳戶儀表板中嘅 **Runners → Profiles** 部分。
2. 選擇 **新增設定檔**。
3. 為其命名，選擇平台，並選擇規格。對於 Linux，亦需選擇 Ubuntu 版本；對於 macOS，則選擇 Xcode 版本。
4. 保存，然後喺工作流中使用 `runs-on: tuist-<name>` 引用佢。

你亦可以從命令行管理設定檔。創建、更改同刪除設定檔需要帳戶管理權限（如同喺儀表板中），或者擁有帶有 `account:runners:write` 範圍嘅帳戶令牌：

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

或者一個名為 `xcode-26-4` 嘅 macOS 設定檔，固定於 Xcode `26.4.1`，這樣工作就可以喺較舊嘅工具鏈上運行，而你嘅預設 `macos` 設定檔則追蹤最新版本：

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
