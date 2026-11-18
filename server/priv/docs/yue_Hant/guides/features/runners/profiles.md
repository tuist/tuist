---
{
  "title": "設定檔",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "Runner 設定檔係具名嘅機器規格，你可以喺 runs-on 入面引用佢哋，為 Tuist Runners 選擇平台、大小、Ubuntu 版本或者 Xcode 版本。"
}
---
# 設定檔 {#profiles}

**設定檔**是以帳戶為範圍、具名稱的機器規格。你可以在工作流程的 `runs-on` 中引用它，Tuist 會將工作路由至相符的執行器。設定檔將基礎架構選擇（平台、大小、Ubuntu 版本或 Xcode 版本）集中在一處，而非散落在每個工作流程檔案中，並提供穩定的標籤供 CI 指向。

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

該標籤是設定檔名稱加上 `tuist-` 前綴。名為 `macos` 的設定檔對應 `runs-on: tuist-macos`；名為 `linux-large` 的設定檔對應 `runs-on: tuist-linux-large`。比對時不區分大小寫。

## 預設設定檔 {#default-profiles}

每個已啟用 Runners 的帳戶都會從兩個設定檔開始，讓你可以直接使用叢集而無需任何設定：

{{runner_default_profiles_table}}

兩者都指向各自平台的預設 <.localized_link href="/guides/features/runners/profiles#machine-shapes">規格</.localized_link>。它們受 **保護**，因此無法刪除，確保你的工作流程所依賴的標籤始終能解析。你仍可變更其規格或 Xcode 版本，並可建立其他大小或 Xcode 版本的額外設定檔。

## 機器規格 {#machine-shapes}

執行器可在 macOS（Apple Silicon，在 Mac 叢集上虛擬化）和 Linux 上使用。每個設定檔會固定下方目錄中的一種機器規格，即一組 `(vCPUs, memory)`。

### Linux {#linux}

{{runner_linux_shapes_table}}

Linux 設定檔也會選擇一個 **Ubuntu 版本**，就像 macOS 設定檔選擇 Xcode 版本一樣：

- **Ubuntu 24.04**（`ubuntu-24.04`），新設定檔的預設值。
- **Ubuntu 22.04**（`ubuntu-22.04`），適用於仍需要此版本的工作流程。GitHub 已棄用其 22.04 託管映像，並將於 2027 年 4 月 17 日移除；請計劃在此之前遷移。

設定檔會保留在你選擇的版本上，直到你主動變更為止，因此較新的預設值不會自動將你的工作移至另一個作業系統。在 24.04 上建構的二進制檔需要其較新的 glibc (2.39)，可能無法在較舊的系統上執行，且其系統 Python 會在虛擬環境之外拒絕 `pip install`（PEP 668）。執行器會像 GitHub 託管的執行器一樣設定 `ImageOS`（`ubuntu24` 或 `ubuntu22`），以便設定動作選取正確版本的建構。

每個 Linux 設定檔都透過 `/dev/kvm` 支援 <.localized_link href="/guides/features/runners#android-emulators">硬體加速的 Android 模擬器</.localized_link>。不需要單獨的 KVM 設定檔。

### macOS {#macos}

{{runner_macos_shapes_table}}

較大的 macOS 規格在叢集中可用的機器較少，因此請求該規格的工作可能比在較小規格上運行的相同工作等待更長時間才能啟動。當工作受 CPU 限制時，請選用較大的規格；其他情況則保留預設規格。如果不確定，可以在兩種規格上運行工作並在儀表板中比較持續時間。

macOS 設定檔也會固定一個 **Xcode 版本**。該版本會選取預先安裝該 Xcode 的執行器映像，因此工作開始時工具鏈已就緒。請參閱 <.localized_link href="/guides/features/runners/images">映像</.localized_link> 以了解每個映像包含的其他內容。目前支援的版本：

{{runner_macos_xcode_versions}}

> [!NOTE]
> 隨著我們新增硬體和 Xcode 版本，目錄會不斷演進。儀表板中的 **新增設定檔** 表單和 `tuist runner profile catalog` 始終顯示你帳戶當前可用的規格、Xcode 版本和 Ubuntu 版本，因此請將它們視為事實來源。

macOS 執行器的名稱會顯示其運行的 macOS 版本、設定檔的 Xcode 版本及其規格，例如 `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-1a2b3c4d5e6f`。該名稱會出現在 GitHub 上工作的 **設定工作** 步驟中，以及 Tuist 儀表板的工作詳細資訊中。

## 建立設定檔 {#creating-a-profile}

1. 開啟帳戶儀表板的 **Runners → Profiles** 部分。
2. 選擇 **新增設定檔**。
3. 為其命名，選擇平台，並選取規格。對於 Linux，還需選擇 Ubuntu 版本；對於 macOS，則選擇 Xcode 版本。
4. 儲存，然後在工作流程中使用 `runs-on: tuist-<name>` 引用它。

你也可以從命令列管理設定檔。建立、變更和刪除設定檔需要帳戶管理權限（如同在儀表板中），或具有 `account:runners:write` 範圍的帳戶令牌：

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

Agent 可以透過 <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link> 執行相同操作。

例如，在 8 vCPU / 32 GB 規格上名為 `linux-large` 的設定檔：

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

或者，名為 `xcode-26-4` 的 macOS 設定檔固定於 Xcode `26.4.1`，這樣工作就可以在較舊的工具鏈上運行，而你的預設 `macos` 設定檔則追蹤最新版本：

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
