---
{
  "title": "Gradle 預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "使用 Tuist Previews 從 Gradle 專案構建並分享 Android 應用程式及原生命令列工具。"
}
---
# Gradle 預覽

直接從 Gradle 建置並分享 Android 應用程式和原生命令列工具。請先參閱 <.localized_link href="/guides/get-started/gradle-project">Gradle 專案指南</.localized_link> 以連接專案並進行驗證。

## Android 應用程式

```bash
./gradlew :app:tuistShareDebug
```

`dev.tuist` 設定外掛程式會為 Android Gradle Plugin（8.8.2 或更高版本）中的每個應用程式變體註冊一個 `tuistShare<Variant>` 任務。將 `app` 和 `Debug` 替換為你的應用程式模組和變體，例如產品風味可使用 `:app:tuistShareDemoDebug`。該任務會在發布 APK 之前，透過 Gradle 宣告的構件依賴關係來建置它。當建置輸出已是最新狀態或從建置快取還原時，此任務同樣有效。

僅支援單一、已簽署的通用應用程式 APK。Android 的 debug 變體通常使用 debug 簽署金鑰；release 變體則需要你自己的簽署設定。該任務會在驗證或上傳前檢查 APK 簽章。未簽署、無效、instrumentation 以及分割 APK 會被拒絕。函式庫模組、測試 APK 和 Android App Bundles (`.aab`) 並非發布目標。

## 原生命令列工具

使用 Gradle 的 `cpp-application` 或 `swift-application` 外掛程式的專案，會為每個原生二進制檔獲得一個分享任務：

```bash
./gradlew :app:tuistShareMainDebug
```

該任務會建置並封裝已安裝的發行版，包括其啟動器和執行時期函式庫。對於 release 二進制檔，請使用 `tuistShareMainRelease`。針對多部機器的專案，每個二進制檔都有一個對應任務；執行 `./gradlew :app:tasks --all` 以查找它們的名稱。

支援 arm64 或 x86_64 的原生 macOS 和 Linux 可執行檔。請在目標平台上，使用 Gradle 外掛程式所需的工具鏈進行建置。JVM 應用程式及其產生的啟動器腳本不受此整合支援。

## 發布行為

分享任務會使用外掛程式現有的 Tuist 憑證進行發布，無需呼叫 Tuist CLI。一般的 `assemble`、`build` 和測試任務絕不會發布預覽。

分享後，請在專案中開啟 **預覽** 以複製連結。重複分享相同的建置和軌道會重用其發布內容，包括在建置快取命中之後。上傳失敗或未確認的上傳會導致分享任務失敗；它們不會被報告為成功的預覽。

## CI 和軌道

使用與外掛程式其他需驗證功能相同的憑證來設定 <.localized_link href="/guides/integrations/continuous-integration">CI 驗證</.localized_link>，然後明確請求發布：

```bash
./gradlew :app:tuistShareDebug --track nightly
```

以相同方式將 `--track nightly` 加入原生分享任務。任務會使用已設定的 Tuist 專案、伺服器 URL 和代理設定。預覽發布始終需要驗證。Git 修訂元數據、發行說明和自動拉取請求評論不會由這些任務附加。

在託管的 Tuist 上，構件發布會在 30 天後過期。自託管實例使用 `TUIST_APP_PREVIEW_RETENTION_DAYS`；若不設定則會停用此類別的過期機制。已過期的發布無法透過重複相同意圖來恢復。

## 分享現有 APK

對於在此工作流程之外建置的 APK，或要在舊版上傳流程中包含發行說明，CLI 仍然可用：

```bash
tuist share app/build/outputs/apk/debug/app-debug.apk \
  --track nightly --release-notes "Improve checkout"
```

請參閱 <.localized_link href="/guides/features/previews#run-a-preview">執行預覽</.localized_link> 以了解如何執行已發布的建置、存取權限、軌道和 README 徽章。

<!-- @snippet: ./_tuist-share -->
