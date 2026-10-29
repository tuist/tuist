---
{
  "title": "Profiles",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Runner profiles are named machine shapes you reference from runs-on to choose a platform, size, and Xcode version for Tuist Runners."
}
---
# 設定檔 {#profiles}

**設定檔** 是一個以帳戶為範圍、具名的機器規格。你可以在工作流程的 `runs-on` 中引用它，Tuist 會將工作路由到相符的執行器。設定檔讓基礎設施選擇（平台、大小、Xcode 版本）集中在一處，而非散落在每個工作流程檔案中，並提供一個穩定的標籤供 CI 使用。

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

該標籤是設定檔名稱加上 `tuist-` 前綴。名為 `macos` 的設定檔對應 `runs-on: tuist-macos`；名為 `linux-large` 的設定檔對應 `runs-on: tuist-linux-large`。比對時不區分大小寫。

## 預設設定檔 {#default-profiles}

每個已啟用 Runners 的帳戶都會從兩個設定檔開始，讓你無需任何設定即可使用執行器群組：

{{runner_default_profiles_table}}

兩者都指向其平台的預設 <.localized_link href="/guides/features/runners/profiles#machine-shapes">規格</.localized_link>。它們受 **保護**，因此無法刪除，且你的工作流程所依賴的標籤始終能正確解析。你仍然可以變更其規格或 Xcode 版本，並可以為其他大小或 Xcode 版本建立額外的設定檔。

## 機器規格 {#machine-shapes}

執行器可在 macOS（Apple silicon，在 Mac 群組上虛擬化）和 Linux 上使用。每個設定檔會固定來自下方目錄的一個機器規格，即一組 `(vCPUs, memory)`。

### Linux {#linux}

{{runner_linux_shapes_table}}

每個 Linux 設定檔都透過 `/dev/kvm` 支援 <.localized_link href="/guides/features/runners#android-emulators">硬體加速的 Android 模擬器</.localized_link>。不需要單獨的 KVM 設定檔。

### macOS {#macos}

{{runner_macos_shapes_table}}

較大的 macOS 規格在群組中可用的機器較少，因此請求該規格的工作可能比在較小規格上運行的相同工作等待更長時間才能啟動。當工作受 CPU 限制時，請選擇較大的規格，其他情況則保持預設規格。如果不確定，請在兩種規格上運行工作並在儀表板中比較持續時間。

macOS 設定檔也會固定一個 **Xcode 版本**。該版本會選擇預裝了該 Xcode 的執行器映像，因此工作開始時工具鏈已就緒。目前支援的版本：

{{runner_macos_xcode_versions}}

> [!NOTE]
> 隨著我們新增硬體和 Xcode 發布版本，目錄會不斷演進。儀表板中的 **新設定檔** 表單和 `tuist runner profile catalog` 始終顯示你的帳戶當前可用的規格和 Xcode 版本，因此請將它們視為事實來源。

macOS 執行器的名稱顯示其運行的 macOS 版本、設定檔的 Xcode 版本及其規格，例如 `tuist-macos-26.6-xcode-27.0-6vcpu-14gb-1a2b3c4d5e6f`。該名稱出現在 GitHub 上工作的 **設定工作** 步驟以及 Tuist 儀表板中的工作詳細資訊中。

## 建立設定檔 {#creating-a-profile}

1. 開啟帳戶儀表板的 **Runners → Profiles** 部分。
2. 選擇 **新設定檔**。
3. 為其命名，選擇平台，並選擇規格。對於 macOS，還需選擇 Xcode 版本。
4. 儲存，然後在工作流程中使用 `runs-on: tuist-<name>` 引用它。

你也可以從命令列管理設定檔。建立、變更和刪除設定檔需要帳戶管理權限（如同在儀表板中），或具有 `account:runners:write` 範圍的帳戶令牌：

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

Agents 可以透過 <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link> 執行相同操作。

例如，名為 `linux-large` 的設定檔使用 8 vCPU / 32 GB 規格：

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

或者，名為 `xcode-26-4` 的 macOS 設定檔固定為 Xcode `26.4.1`，這樣工作可以在較舊的工具鏈上運行，而你的預設 `macos` 設定檔則追蹤最新版本：

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
