---
{
  "title": "設定檔",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "Runner 設定檔係具名嘅機器規格，你可以喺 runs-on 入面引用佢哋，為 Tuist Runners 揀選平台、大小、Ubuntu 版本或 Xcode 版本。"
}
---
# 設定檔 {#profiles}

**設定檔**係一個以帳戶為範圍、有名稱嘅機器規格。你可以喺工作流程嘅 `runs-on` 入面引用佢，Tuist 就會將工作派發到符合規格嘅 runner。設定檔將基礎設施選擇（平台、大小、Ubuntu 版本或 Xcode 版本）集中管理，唔使分散喺每個工作流程檔案入面，亦提供一個穩定標籤俾 CI 使用。

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

標籤就係設定檔名稱加上 `tuist-` 前綴。名為 `macos` 嘅設定檔對應 `runs-on: tuist-macos`；名為 `linux-large` 嘅設定檔對應 `runs-on: tuist-linux-large`。配對時唔區分大小寫。

## 預設設定檔 {#default-profiles}

每個啟用 Runners 功能嘅帳戶都會預設兩個設定檔，等你唔使額外設定就可以直接使用資源池：

{{runner_default_profiles_table}}

兩者都指向各自平台嘅預設 <.localized_link href="/guides/features/runners/profiles#machine-shapes">規格</.localized_link>。佢哋係 **受保護** 嘅，所以唔可以刪除，確保你工作流程依賴嘅標籤永遠有效。你仍然可以更改佢哋嘅規格或 Xcode 版本，亦可以建立額外設定檔嚟支援其他大小或 Xcode 版本。

## 機器規格 {#machine-shapes}

Runner 支援 macOS（Apple 晶片，喺 Mac 資源池上虛擬化）同 Linux。每個設定檔會固定選用目錄中其中一種機器規格，即係一對 `(vCPUs, memory)`。

### Linux {#linux}

{{runner_linux_shapes_table}}

Linux 設定檔亦會揀選一個 **Ubuntu 版本**，就好似 macOS 設定檔揀選 Xcode 版本咁：

- **Ubuntu 24.04**（`ubuntu-24.04`），新設定檔嘅預設選項。
- **Ubuntu 22.04**（`ubuntu-22.04`），供仍需要此版本嘅工作流程使用。GitHub 已棄用其 22.04 託管映像，並將於 2027 年 4 月 17 日移除；請計劃在此之前遷移。

設定檔會保留你選擇嘅版本，直到你主動更改，所以較新嘅預設值唔會自動將你嘅工作移到另一個作業系統。喺 24.04 上編譯嘅二進制檔案需要較新嘅 glibc (2.39)，可能無法喺較舊系統上運行；而且其系統 Python 會拒絕喺虛擬環境之外執行 `pip install`（PEP 668）。Runner 會好似 GitHub 託管 runner 咁設定 `ImageOS`（`ubuntu24` 或 `ubuntu22`），讓設定動作揀選正確版本嘅構建。

每個 Linux 設定檔都透過 `/dev/kvm` 支援 <.localized_link href="/guides/features/runners#android-emulators">硬體加速 Android 模擬器</.localized_link>。唔需要額外嘅 KVM 設定檔。

### macOS {#macos}

{{runner_macos_shapes_table}}

較大嘅 macOS 規格喺資源池中可用嘅機器較少，所以請求該規格嘅工作可能比使用較小規格等待更長時間先開始。當工作受 CPU 限制時，先選用較大規格；其他情況保持使用預設規格。如果你唔確定，可以喺兩種規格上都運行工作，然後喺儀表板比較持續時間。

macOS 設定檔亦會固定一個 **Xcode 版本**。該版本會選擇已預裝該 Xcode 嘅 runner 映像，讓工作開始時工具鏈已經就位。關於每個映像包含嘅其他內容，請參閱 <.localized_link href="/guides/features/runners/images">映像</.localized_link>。目前支援嘅版本：

{{runner_macos_xcode_versions}}

> [!NOTE]
> 隨著我哋新增硬體同 Xcode 版本，目錄會不斷更新。儀表板中嘅 **新設定檔** 表單同 `tuist runner profile catalog` 永遠顯示你帳戶當前可用嘅規格、Xcode 版本同 Ubuntu 版本，所以請以佢哋為準。

macOS runner 嘅名稱會顯示佢運行嘅 macOS 版本、設定檔嘅 Xcode 版本及其規格，例如 `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-1a2b3c4d5e6f`。呢個名稱會出現喺 GitHub 工作嘅 **設定工作** 步驟同 Tuist 儀表板嘅工作詳情中。

## 建立設定檔 {#creating-a-profile}

1. 開啟你帳戶儀表板嘅 **Runners → Profiles** 部分。
2. 選擇 **新設定檔**。
3. 為佢命名，選擇平台，然後揀選規格。對於 Linux，仲要選擇 Ubuntu 版本；對於 macOS，則選擇 Xcode 版本。
4. 儲存，然後喺工作流程中使用 `runs-on: tuist-<name>` 引用佢。

你亦可以從命令列管理設定檔。建立、更改同刪除設定檔需要帳戶管理權限（好似儀表板咁），或者擁有帶有 `account:runners:write` 範圍嘅帳戶令牌：

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

Agents 可以透過 <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link> 執行相同操作。

例如，一個名為 `linux-large`、使用 8 vCPU / 32 GB 規格嘅設定檔：

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

或者一個名為 `xcode-26-4`、固定於 Xcode `26.4.1` 嘅 macOS 設定檔，讓工作可以喺較舊工具鏈上運行，而你嘅預設 `macos` 設定檔則追蹤最新版本：

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
