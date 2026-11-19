---
{
  "title": "Once 預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "透過 Once 的原生 Tuist 提供者，發布 Android、Apple 模擬器與 macOS 應用程式預覽。"
}
---
# Once 預覽 {#once-previews}

[Once](https://buildonce.dev/docs/guide/infrastructure/tuist#publish-application-previews) 可將應用程式構件發布至 Tuist，讓團隊成員無需在本機重新建置即可試用該版本。此功能需要 Once 0.74.0+ 以及具備構件接收器的 Tuist 伺服器。Once 0.73.x 則改用舊版的單一負載配接器。

## 設定目的地

完成<.localized_link href="/guides/get-started/once-project">開始使用 Once</.localized_link>，然後在工作區的 `once.toml` 中加入構件綁定。若提供者已設定用於快取，請直接复用：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.artifacts]
name = "tuist"
```

```bash
once auth login --provider tuist
once artifact publish MyApplication --track review
```

接收器會保留完整集合、成員清單與負載，包括未知的介面。支援的原生介面會依據專案的預設可見性、存取權限與分發設定，以非同步方式投影為預覽。一般構件內容仍維持私密，即使在公開專案中亦然。收據僅確認構件已儲存，不代表預覽處理已完成；其 URL 會開啟專案的預覽清單。

## 符合資格的應用程式

Apple 投影接受 `dev.once.apple-install.v2` 中繼資料，適用於在 macOS 上匯出的臨時簽署 macOS 與模擬器應用程式。實體裝置應用程式不符合資格。Android 投影接受帶有已驗證簽章的 `dev.once.android-install.v1` 中繼資料。Once 僅核准自動發布除錯簽署且非檢測用的 APK。未知介面仍可作為構件下載，但不會建立預覽。Android 安裝連結會保留 `.apk` 檔名，即使負載是儲存在內容摘要之下。

## 選擇在建置後發布

```toml
[infrastructure]
publish_on_build = ["MyApplication"]
```

```bash
once artifact publish MyApplication --allow-on-build
once build MyApplication
```

所有請求的建置都必須成功。自動發布還需要生產者對整個閉包進行核准，以及針對本機、工作區、確切端點、目標和穩定的 Tuist 專案目的地進行本機授權。若無政策或授權，就不會發出構件發布的網路請求。一般的 Once 建置不會產生隱含的發布副作用。

重播相同的已保留發布會驗證遠端收據，並避免再次上傳。這與 `tuist share` 的重複建置行為不同。

## 保留期限

在託管式 Tuist 上，構件發布會在 30 天後過期。自託管實例使用 `TUIST_APP_PREVIEW_RETENTION_DAYS`；若不設定此值，則對此系列停用過期。過期的記錄會保留為墓碑記錄，無法透過重播相同意圖來重新啟用。現有的 `tuist share` 簽署、可見性與分發工作流程維持不變。

請參閱<.localized_link href="/guides/features/previews#run-a-preview">執行預覽</.localized_link>，了解如何執行已發布的建置、存取權限、追蹤軌跡以及 README 徽章。

## Apple 預覽

對於符合資格的 Apple 模擬器與 macOS 預覽，請參閱<.localized_link href="/guides/features/previews/run/macos">Tuist macOS  companion app 說明</.localized_link>。實體裝置應用程式仍不符合 Once 發布資格。
