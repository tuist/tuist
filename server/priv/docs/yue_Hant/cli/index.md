---
{
  "title": "CLI",
  "titleTemplate": ":title · Tuist",
  "description": "Tuist CLI、其指令，以及如何為你的工作流程進行設定。"
}
---
# CLI {#cli}

Tuist CLI 係同 Tuist 互動嘅其中一個介面；如果你使用 <.localized_link href="/guides/features/projects">generated projects</.localized_link>，佢就係最常用嘅。佢提供生成專案、快取二進制檔案、執行測試、分享預覽等指令。

## 開始使用 {#getting-started}

如果你仲未安裝 Tuist，請跟隨 <.localized_link href="/guides/install-tuist">安裝指南</.localized_link> 開始。

安裝之後，你可以喺終端機執行 `tuist` 來查看可用指令列表：

```bash
tuist --help
```

## 設定 {#configuration}

可以透過 `tuist.toml` 檔案設定 CLI 行為。請參閱 <.localized_link href="/references/tuist-toml">tuist.toml 參考資料</.localized_link> 以了解所有可用選項。

## 疑難排解 {#troubleshooting}

如果遇到問題，請查閱 <.localized_link href="/cli/debugging">除錯指南</.localized_link>，入面有診斷問題嘅工具，包括工作階段記錄同網絡錄製。
