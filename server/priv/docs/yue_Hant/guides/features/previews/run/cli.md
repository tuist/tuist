---
{
  "title": "使用 CLI 執行預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "使用 Tuist CLI 執行流動應用程式、macOS 應用程式和命令列預覽。"
}
---
# 使用 CLI 執行預覽

安裝 <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link>，然後執行共享的預覽連結。你不需要產生該預覽的構建系統：

```bash
tuist run {url}
```

Tuist 會為你的作業系統、CPU 架構和目標裝置選擇相容的構建版本。私人預覽需要通過身份驗證並擁有專案存取權限。

## 流動應用程式 {#mobile-applications}

選擇已連接的裝置或模擬器：

```bash
tuist run --device "My device" {url}
```

Android 裝置和模擬器必須透過 ADB 連接。你也可以從預覽頁面下載 APK，並將其安裝在允許從該來源安裝的 Android 裝置上。Apple 構建版本必須符合目標平台的要求並滿足其簽署條件。對於 IPA，請在目標裝置上開啟預覽連結以進行安裝。

## 命令列預覽 {#command-line-previews}

在 `--` 之後傳遞參數：

```bash
tuist run {url} -- --help
tuist run {url} -- build --configuration Release
```

`--` 之後的所有內容都會原樣轉發，包括 `--verbose`、`--quiet` 和 `--path`。子參數不會被納入 Tuist 命令分析中。

預覽會在你的工作目錄、環境變數和終端機輸入/輸出下執行，並返回可執行檔的退出狀態碼。它不會取代已安裝的 CLI，也不會將其加入 `PATH`。CLI 分發檔案在執行後仍會保留在 Tuist 的本地 `previews` 快取中，以便產生的專案可以繼續引用它們；刪除該快取也會移除這些引用的目標。

桌面和 CLI 預覽以當前使用者身份執行，而非在沙盒中。只應執行你信任的作者和拉取請求中的構建版本。

## 選擇版本 {#select-a-version}

`tuist run` 也接受帶有 `latest` 的應用程式名稱、分支名稱或提交雜湊值：

```bash
tuist run App@latest # Latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Latest App preview associated with a branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Preview associated with a commit
```

這些選擇器要求相應的 Git 元數據已發布。對於省略 Git 元數據的工作流程，請改用特定的預覽 URL。

有關存取權限和組織方式，請參閱 <.localized_link href="/guides/features/previews#visibility">可見性和追蹤</.localized_link>。
