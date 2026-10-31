---
{
  "title": "設定檔",
  "titleTemplate": ":title · 執行器 · 功能 · 指南 · Tuist",
  "description": "執行器設定檔是有名稱的機器規格，你可從 runs-on 參考它們，為 Tuist 執行器選擇平台、大小與 Xcode 版本。"
}
---
# 設定檔 {#profiles}

**設定檔**是以帳號為範圍、具名稱的機器規格。你可以在工作流程的 `runs-on` 中引用它，Tuist 會將工作路由至相符的執行器。設定檔將基礎設施選擇（平台、大小、Xcode 版本）集中管理，而非分散在每個工作流程檔案中，並提供穩定的標籤供 CI 指向。

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

該標籤是設定檔名稱加上 `tuist-` 前綴。名為 `macos` 的設定檔對應 `runs-on: tuist-macos`；名為 `linux-large` 的設定檔對應 `runs-on: tuist-linux-large`。比對時不區分大小寫。

## 預設設定檔 {#default-profiles}

每個已啟用 Runners 的帳號都會從兩個設定檔開始，讓你無需任何設定即可使用執行器群組：

{{runner_default_profiles_table}}

兩者皆指向各自平台的預設<.localized_link href="/guides/features/runners/profiles#machine-shapes">機器規格</.localized_link>。它們受**保護**，因此無法刪除，確保工作流程所依賴的標籤始終能正確解析。你仍可變更其機器規格或 Xcode 版本，並可為其他規格或 Xcode 版本建立額外的設定檔。

## 機器規格 {#machine-shapes}

Runners 可在 macOS（Apple silicon，於 Mac 群組上虛擬化）與 Linux 上使用。每個設定檔會固定來自下方目錄的一個機器規格，即一組 `(vCPUs, memory)` 配對。

### Linux {#linux}

{{runner_linux_shapes_table}}

每個 Linux 設定檔都透過 `/dev/kvm` 支援 <.localized_link href="/guides/features/runners#android-emulators">硬體加速的 Android 模擬器</.localized_link>。無需獨立的 KVM 設定檔。

### macOS {#macos}

{{runner_macos_shapes_table}}

較大的 macOS 規格在群組中可用的機器較少，因此要求該規格的工作可能比在較小規格上執行的相同工作等待更久才啟動。當工作受 CPU 限制時，請選擇較大的規格；其他情況則保留預設規格。若不確定，可在兩種規格上執行工作，並在儀表板中比較持續時間。

macOS 設定檔也會固定一個**Xcode 版本**。該版本會選擇已預裝該 Xcode 的執行器映像，讓工作在開始時就已備妥工具鏈。目前支援的版本：

{{runner_macos_xcode_versions}}

> [!NOTE]
> 隨著我們新增硬體與 Xcode 發行版，目錄會持續演進。儀表板中的**新增設定檔**表單與 `tuist runner profile catalog` 始終顯示你帳號目前可用的規格與 Xcode 版本，請以它們為準。

macOS 執行器的名稱會顯示其執行的 macOS 版本、設定檔的 Xcode 版本及其規格，例如 `tuist-macos-26.6-xcode-27.0-6vcpu-14gb-1a2b3c4d5e6f`。該名稱會出現在 GitHub 上工作的 **設定工作** 步驟，以及 Tuist 儀表板中的工作詳細資訊。

## 建立設定檔 {#creating-a-profile}

1. 開啟帳號儀表板的 **Runners → Profiles** 區段。
2. 選擇 **新增設定檔**。
3. 為其命名、選擇平台，並選取規格。若是 macOS，還需選擇 Xcode 版本。
4. 儲存後，在工作流程中使用 `runs-on: tuist-<name>` 引用它。

你也可以從命令列管理設定檔。建立、變更與刪除設定檔需要帳號管理權限（如同在儀表板中），或具備 `account:runners:write` 範圍的帳號權杖：

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

Agents 可以透過 <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link> 執行相同操作。

例如，名為 `linux-large` 的設定檔，使用 8 vCPU / 32 GB 規格：

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

或是名為 `xcode-26-4` 的 macOS 設定檔，固定於 Xcode `26.4.1`，讓工作可以在較舊的工具鏈上執行，而你的預設 `macos` 設定檔則追蹤最新版本：

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
