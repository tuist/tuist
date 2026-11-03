---
{
  "title": "一次性發佈構件",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "將不可變的 Once 應用程式構件發佈到現有的 Tuist 專案，並需明確授權目標位置。"
}
---
# Once 構件發布

[Once](https://buildonce.dev/docs/guide/infrastructure/tuist#publish-application-previews) 可以使用現有的 Tuist 認證來發布不可變的構件。這需要 Once 0.74.0+ 版本，以及配備構件接收器的 Tuist 伺服器。Once 0.73.x 則使用舊版的單一負載配接器。

## 設定目的地

在工作區的 `once.toml` 中：

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

接收器會保留完整的集合、成員清單和負載，包括未知的介面。支援的原生介面會根據專案的預設可見性、存取權限和分發設定，以非同步方式投射到預覽中。一般構件內容保持私密，即使在公開專案中亦然。收據確認構件已儲存，而非預覽處理已完成；其 URL 會開啟專案的預覽列表。

## 符合資格的應用程式

Apple 投射接受 `dev.once.apple-install.v2` 元數據，用於在 macOS 上匯出的臨時簽署 macOS 和模擬器應用程式。實體裝置應用程式不符合資格。Android 投射接受帶有已驗證簽章的 `dev.once.android-install.v1` 元數據。Once 僅批准自動發布經除錯簽署且非檢測的 APK。未知介面仍可作為構件下載，但不會建立預覽。Android 安裝連結會保留 `.apk` 檔案名稱，即使負載是儲存在內容摘要之下。

## 選擇在建置後發布

```toml
[infrastructure]
publish_on_build = ["MyApplication"]
```

```bash
once artifact publish MyApplication --allow-on-build
once build MyApplication
```

所有請求的建置都必須成功。自動發布還需要生產者批准整個閉包，以及對此機器、工作區、確切端點、目標和穩定的 Tuist 專案目的地的本機授權。如果沒有政策或授權，就不會發出構件發布的網絡請求。普通的 Once 建置不會產生隱含的發布副作用。

重放相同的保留發布會驗證遠端收據並避免再次上傳。這與 `tuist share` 的重複建置行為不同。

## 保留期

在託管的 Tuist 上，構件發布會在 30 天後過期。自託管實例使用 `TUIST_APP_PREVIEW_RETENTION_DAYS`；如果不設定，則會為此系列停用過期功能。過期的記錄會保留為墓碑，無法透過重放相同的意圖來重新啟用。現有的 `tuist share` 簽署、可見性和分發工作流程保持不變。

請參閱 <.localized_link href="/guides/features/previews#run-a-preview">執行預覽</.localized_link>，以了解如何執行已發布的建置、存取權限、追蹤軌道和 README 徽章。

## Apple 預覽

對於符合資格的 Apple 模擬器和 macOS 預覽，請參閱 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS 輔助應用程式說明</.localized_link>。實體裝置應用程式仍然不符合 Once 發布的資格。
