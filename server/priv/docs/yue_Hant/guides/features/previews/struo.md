---
{
  "title": "Struo 預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "透過 Struo 嘅原生 Tuist 提供者，發布 Android、Apple 模擬器同 macOS 應用程式預覽。"
}
---
# Struo 預覽 {#struo-previews}

<a id="once-previews"></a>

[Struo](https://struo.run/docs/guide/infrastructure/tuist#publish-application-previews) 可以將應用程式構件發布到 Tuist，讓團隊成員無需在本機重新構建即可試用構建版本。請使用 [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) 或更高版本，以及配備構件接收器的 Tuist 伺服器。

## 設定目的地

完成 <.localized_link href="/guides/get-started/struo-project">開始使用 Struo</.localized_link>，然後在工作區的 `struo.toml` 中加入構件綁定。如果提供者已為快取設定，請重複使用它：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.artifacts]
name = "tuist"
```

```bash
struo auth login --provider tuist
struo artifact publish MyApplication --track review
```

接收器會保留完整的集合、成員清單和負載，包括未知的介面。支援的原生介面會根據專案的預設可見性、存取權限和分發設定，非同步投影到預覽中。一般構件內容會保持私密，即使在公開專案中亦然。收據確認構件已儲存，而非預覽處理已完成；其 URL 會開啟專案的預覽列表。

## 符合資格的應用程式

Apple 投影接受 `dev.struo.apple-install.v2` 元數據，適用於在 macOS 上匯出的臨時簽署 macOS 和模擬器應用程式。實體裝置應用程式不符合資格。Android 投影接受帶有驗證簽章的 `dev.struo.android-install.v1` 元數據。Struo 僅批准自動發布除錯簽署且非檢測的 APK。未知介面仍可作為構件下載，但不會建立預覽。Android 安裝連結會保留 `.apk` 檔案名稱，即使負載是儲存在內容摘要之下。

## 選擇在構建後發布

```toml
[infrastructure]
publish_on_build = ["MyApplication"]
```

```bash
struo artifact publish MyApplication --allow-on-build
struo build MyApplication
```

所有請求的構建都必須成功。自動發布還需要生產者對整個閉包的批准，以及對本機、工作區、確切端點、目標和穩定的 Tuist 專案目的地的本地授權。如果沒有政策或授權，就不會發出構件發布網絡請求。普通的 Struo 構建不會產生隱式發布副作用。

重播相同的保留發布會驗證遠端收據並避免再次上傳。這與 `tuist share` 的重複構建行為不同。

## 保留

在託管 Tuist 上，構件發布會在 30 天後過期。自託管實例使用 `TUIST_APP_PREVIEW_RETENTION_DAYS`；如果不設定，則會停用此系列的過期功能。過期的記錄會作為墓碑保留，無法透過重播相同的意圖來重新啟用。現有的 `tuist share` 簽署、可見性和分發工作流程保持不變。

請參閱 <.localized_link href="/guides/features/previews#run-a-preview">執行預覽</.localized_link> 以了解如何執行已發布的構建、存取權限、追蹤和 README 徽章。

## Apple 預覽

對於符合資格的 Apple 模擬器和 macOS 預覽，請參閱 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS 配套應用程式說明</.localized_link>。實體裝置應用程式仍然不符合 Struo 發布資格。
