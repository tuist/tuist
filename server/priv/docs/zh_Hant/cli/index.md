---
{
  "title": "CLI",
  "titleTemplate": ":title · Tuist",
  "description": "Tuist CLI、其指令，以及如何針對你的工作流程進行設定。"
}
---
# CLI {#cli}

Tuist CLI 是與 Tuist 互動的介面之一；若你使用 <.localized_link href="/guides/features/projects">產生的專案</.localized_link>，這也是最常見的介面。它提供產生專案、快取二進位檔、執行測試、分享預覽等指令。

## 開始使用 {#getting-started}

若尚未安裝 Tuist，請參閱 <.localized_link href="/guides/install-tuist">安裝指南</.localized_link> 以開始使用。

安裝完成後，你可以在終端機中執行 `tuist` 來查看可用指令清單：

```bash
tuist --help
```

## 設定 {#configuration}

你可以透過 `tuist.toml` 檔案設定 CLI 行為。請參閱 <.localized_link href="/references/tuist-toml">tuist.toml 參考文件</.localized_link> 以了解所有可用選項。

## 疑難排解 {#troubleshooting}

若遇到問題，請參閱 <.localized_link href="/cli/debugging">除錯指南</.localized_link>，其中包含診斷問題的工具，例如工作階段記錄與網路封包記錄。
