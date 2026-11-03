---
{
  "title": "Gradle 預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "使用 Tuist Previews 從 Gradle 專案建構並分享 Android 應用程式及原生命令列工具。"
}
---
# Gradle 預覽

直接從 Gradle 構建並分享 Android 應用程式和原生命令列工具。請先參閱<.localized_link href="/guides/get-started/gradle-project">Gradle 專案指南</.localized_link>以連接專案並進行身份驗證。

## Android 應用程式

```bash
./gradlew :app:tuistShareDebug
```

`dev.tuist`設定外掛程式會為 Android Gradle Plugin（8.8.2 或更高版本）中的每個應用程式變體註冊一個`tuistShare<Variant>`任務。將`app`和`Debug`替換為你的應用程式模組和變體，例如產品風味可使用`:app:tuistShareDemoDebug`。該任務在發布前會透過 Gradle 聲明的構件依賴關係來構建 APK。即使構建輸出已是最新狀態或從構建快取中恢復，此任務也能正常運作。

僅支援單一、已簽署的通用應用程式 APK。Android 的 debug 變體通常使用 debug 簽名金鑰；release 變體則需要你自己的簽名配置。該任務會在身份驗證或上傳前驗證 APK 簽名。未簽署、無效、instrumentation 以及 split APK 都會被拒絕。函式庫模組、測試 APK 和 Android App Bundles (`.aab`) 並非發布目標。

## 原生命令列工具

使用 Gradle 的`cpp-application`或`swift-application`外掛程式的專案，會為每個原生二進制檔案獲得一個分享任務：

```bash
./gradlew :app:tuistShareMainDebug
```

該任務會構建並打包已安裝的分發套件，包括其啟動器和執行時函式庫。對於 release 二進制檔案，請使用`tuistShareMainRelease`。針對多部機器的專案會為每個二進制檔案提供一個任務；執行`./gradlew :app:tasks --all`以查找它們的名稱。

支援 arm64 或 x86_64 的原生 macOS 和 Linux 可執行檔。請在使用 Gradle 外掛程式所需的工具鏈下，於目標平台上進行構建。此整合不支援 JVM 應用程式及其產生的啟動器腳本。

## 發布行為

分享任務會使用外掛程式現有的 Tuist 憑證進行發布，無需呼叫 Tuist CLI。普通的`assemble`、`build`和測試任務絕不會發布預覽。

分享後，請在專案中開啟**預覽**以複製連結。重複分享相同的構建和軌道會重用其發布內容，包括在快取命中後。上傳失敗或未確認的上傳會導致分享任務失敗；它們不會被報告為成功的預覽。

## CI 與軌道

使用與外掛程式其他需要身份驗證的功能相同的憑證來配置<.localized_link href="/guides/integrations/continuous-integration">CI 身份驗證</.localized_link>，然後明確請求發布：

```bash
./gradlew :app:tuistShareDebug --track nightly
```

以同樣方式將`--track nightly`添加到原生分享任務中。任務會使用已配置的 Tuist 專案、伺服器 URL 和代理設定。預覽發布始終需要身份驗證。這些任務不會附加 Git 修訂元數據、發行說明或自動 Pull Request 評論。

在託管版 Tuist 上，構件發布會在 30 天後過期。自託管實例使用`TUIST_APP_PREVIEW_RETENTION_DAYS`；若不設定則會為此類別禁用過期功能。已過期的發布無法透過重複相同操作來恢復。

## 分享現有 APK

對於在此工作流程之外構建的 APK，或要在舊版上傳流程中包含發行說明，CLI 仍然可用：

```bash
tuist share app/build/outputs/apk/debug/app-debug.apk \
  --track nightly --release-notes "Improve checkout"
```

請參閱<.localized_link href="/guides/features/previews#run-a-preview">執行預覽</.localized_link>以了解如何執行已發布的構建、存取權限、軌道以及 README 徽章。

<!-- @snippet: ./_tuist-share -->
