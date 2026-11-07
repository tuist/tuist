---
{
  "title": "Gradle 預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "使用 Tuist Previews 從 Gradle 專案建置並分享 Android 應用程式與原生命令列工具。"
}
---
# Gradle 預覽

直接從 Gradle 建置並分享 Android 應用程式與原生命令列工具。請先參閱 <.localized_link href="/guides/get-started/gradle-project">Gradle 專案指南</.localized_link>，以連線專案並完成驗證。

## Android 應用程式

```bash
./gradlew :app:tuistShareDebug
```

`dev.tuist` 設定外掛程式會為 Android Gradle Plugin（8.8.2 或更新版本）中的每個應用程式變體註冊一個 `tuistShare<Variant>` 工作。將 `app` 與 `Debug` 替換為你的應用程式模組與變體，例如產品風味可使用 `:app:tuistShareDemoDebug`。此工作會在發布前透過 Gradle 宣告的構件相依性來建置 APK。當建置輸出已是最新狀態或從建置快取還原時，此工作也能正常運作。

僅支援單一、已簽署的通用應用程式 APK。Android 的除錯變體通常使用除錯簽署金鑰；發布變體則需要你自己的簽署設定。此工作會在驗證或上傳前檢查 APK 簽章。未簽署、無效、檢測儀器以及分割 APK 都會被拒絕。程式庫模組、測試 APK 與 Android App Bundle（`.aab`）並非發布目標。

## 原生命令列工具

使用 Gradle 的 `cpp-application` 或 `swift-application` 外掛程式的專案，會為每個原生二進位檔取得一個分享工作：

```bash
./gradlew :app:tuistShareMainDebug
```

此工作會建置並封裝已安裝的發行版，包含其啟動器與執行時期函式庫。發布二進位檔請使用 `tuistShareMainRelease`。針對多部機器的專案，每個二進位檔都有一個對應工作；執行 `./gradlew :app:tasks --all` 即可查詢其名稱。

支援 arm64 或 x86_64 的原生 macOS 與 Linux 可執行檔。請在目標平台上，使用 Gradle 外掛程式所需的工具鏈進行建置。JVM 應用程式及其產生的啟動器指令碼不受此整合支援。

## 發布行為

分享工作會使用外掛程式現有的 Tuist 憑證進行發布，無需叫用 Tuist CLI。一般的 `assemble`、`build` 與測試工作永遠不會發布預覽。

分享後，請在專案中開啟 **預覽** 以複製連結。重複分享相同的建置與軌道會複用其發布內容，包含在建置快取命中後亦然。上傳失敗或未確認的上傳會導致分享工作失敗；這些情況不會被回報為成功的預覽。

## CI 與軌道

使用與外掛程式其他需要驗證之功能相同的憑證來設定 <.localized_link href="/guides/integrations/continuous-integration">CI 驗證</.localized_link>，然後明確請求發布：

```bash
./gradlew :app:tuistShareDebug --track nightly
```

以相同方式將 `--track nightly` 加到原生分享工作。工作會使用已設定的 Tuist 專案、伺服器 URL 與代理設定。預覽發布一律需要驗證。這些工作不會附加 Git 修訂元資料、發布說明或自動拉取請求留言。

在託管式 Tuist 上，構件發布會在 30 天後過期。自行託管的實體使用 `TUIST_APP_PREVIEW_RETENTION_DAYS`；若未設定，則為此系列停用過期。已過期的發布無法透過重複相同意圖來恢復。

## 分享現有 APK

若 APK 是在此工作流程之外建置，或要在舊版上傳流程中加入發布說明，仍可使用 CLI：

```bash
tuist share app/build/outputs/apk/debug/app-debug.apk \
  --track nightly --release-notes "Improve checkout"
```

請參閱 <.localized_link href="/guides/features/previews#run-a-preview">執行預覽</.localized_link>，了解如何執行已發布的建置、存取權限、軌道與 README 徽章。

<!-- @snippet: ./_tuist-share -->
