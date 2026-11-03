---
{
  "title": "一次性構件發布",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "將不可變的 Once 應用程式構件發布至現有的 Tuist 專案，並透過明確的目標授權進行管理。"
}
---
# Once 構件發布

[Once](https://buildonce.dev/docs/guide/infrastructure/tuist#publish-application-previews) 可以使用現有的 Tuist 驗證來發布不可變的構件。這需要 Once 0.74.0+ 以及配備構件接收器的 Tuist 伺服器。Once 0.73.x 則使用舊版的單一負載配接器。

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

接收器會保留完整的集合、成員清單與負載，包括未知的介面。支援的原生介面會依據專案預設的可見性、存取權限與分發設定，非同步投影至預覽。通用構件內容仍保持私密，即使在公開專案中亦然。收據僅確認構件已儲存，而非預覽處理已完成；其網址會開啟專案的預覽清單。

## 符合資格的應用程式

Apple 投影接受 `dev.once.apple-install.v2` 中繼資料，適用於在 macOS 上匯出的隨選簽署 macOS 與模擬器應用程式。實體裝置應用程式不符合資格。Android 投影接受帶有已驗證簽章的 `dev.once.android-install.v1` 中繼資料。Once 僅核准自動發布偵錯簽署且不含插樁的 APK。未知介面仍可作為構件下載，但不會建立預覽。Android 安裝連結會保留 `.apk` 檔名，即使負載是依內容摘要儲存。

## 選擇在建置後發布

```toml
[infrastructure]
publish_on_build = ["MyApplication"]
```

```bash
once artifact publish MyApplication --allow-on-build
once build MyApplication
```

所有請求的建置都必須成功。自動發布還需要生產者對整個閉包的核准，以及本機對此機器、工作區、確切端點、目標與穩定 Tuist 專案目的地的授權。若無政策或授權，就不會發出構件發布的網路請求。一般的 Once 建置不會產生隱含的發布副作用。

重放相同的已保留發布會驗證遠端收據，並避免再次上傳。這與 `tuist share` 的重複建置行為不同。

## 保留期限

在託管的 Tuist 上，構件發布會在 30 天後過期。自託管實例使用 `TUIST_APP_PREVIEW_RETENTION_DAYS`；若不設定，則對此系列停用過期。過期的記錄會保留為墓碑，且無法透過重放相同意圖來重新啟用。現有的 `tuist share` 簽署、可見性與分發工作流程維持不變。

請參閱 <.localized_link href="/guides/features/previews#run-a-preview">執行預覽</.localized_link>，以了解如何執行已發布的建置、存取權限、軌道與 README 徽章。

## Apple 預覽

對於符合資格的 Apple 模擬器與 macOS 預覽，請參閱 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS 輔助應用程式說明</.localized_link>。實體裝置應用程式仍不符合 Once 發布資格。
