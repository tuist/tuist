---
{
  "title": "Bazel 預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "從 Bazel 發布 Android 應用程式、Apple 應用程式和命令列工具作為預覽。"
}
---
# Bazel 預覽

從現有的 Bazel 目標發布 Android APK、Apple 模擬器與 macOS 應用程式，以及命令列工具。為你想要分享的每個輸出新增預覽目標；你的一般建置流程保持不變。

## 設定

將 Tuist 儲存庫中的 [`rules_tuist`](https://github.com/tuist/tuist/tree/main/bazel) 加入 `MODULE.bazel`，並固定你要使用的提交：

```starlark
bazel_dep(name = "rules_tuist")

git_override(
    module_name = "rules_tuist",
    remote = "https://github.com/tuist/tuist.git",
    commit = "FULL_COMMIT_SHA",
    strip_prefix = "bazel",
)
```

保留現有的應用程式目標、原生 SDK 與簽署設定。Bazel 會提供發布工具。

直接從 Bazel 登入：

```bash
bazel run @rules_tuist//:login
```

這會與 Tuist CLI 和 Gradle 外掛程式共用憑證；若已登入也可沿用。在 CI 上，使用 `TUIST_TOKEN` 或透過 Tuist 的 <.localized_link href="/guides/integrations/continuous-integration">OIDC 驗證</.localized_link> 執行登入目標。切勿將憑證放入 BUILD 檔案或規則屬性中。傳入 `-- --url https://tuist.example.com` 以登入自託管實例。

僅在你的 `BUILD.bazel` 中載入所需的介面卡：

```starlark
load("@rules_tuist//:android.bzl", "android_preview")

android_preview(name = "preview_android", app = ":android_app")
```

針對 Apple 應用程式：

```starlark
load("@rules_tuist//:apple.bzl", "apple_preview")

apple_preview(name = "preview_ios", app = ":ios_app")
apple_preview(name = "preview_macos", app = ":macos_app")
```

針對可執行目標（例如 `cc_binary`）：

```starlark
load("@rules_tuist//:executable.bzl", "executable_preview")

executable_preview(name = "preview_cli", binary = ":my_tool")
```

可執行預覽包含目標宣告的執行階段檔案。在你的 Bazel 目標中宣告工具所需的程式庫與資源，並使用在建置目錄之外也能運作的路徑。

## 建置與發布

```bash
bazel run //:preview_android -- \
  --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- \
  --publish --project acme/app --track review
bazel run //:preview_macos -- --publish --project acme/app --track review
bazel run //:preview_cli -- --publish --project acme/app --track review
```

將應用程式與模擬器平台標籤替換為你自己的標籤。為自託管的 Tuist 來源傳入 `--url`，並傳入 `--revision` 以關聯 Git 提交。

傳入 `--publish --project account/project` 以分享成功的建置。若未使用 `--publish`，或使用 `--no-publish`，則不會上傳任何內容，也無需登入。一般的 `bazel build` 絕不會發布，即使在快取命中時亦然。`tuist bazel setup` 會啟用快取與洞察功能，但不會進行發布。

## 支援的輸出

- **Android：** 已簽署的應用程式 APK，包括偵錯建置。安裝 Android SDK 的 build-tools 與命令列工具，並設定 `ANDROID_HOME` 或 `ANDROID_SDK_ROOT`。不支援測試 APK 與 Android App Bundles。
- **Apple：** 以 ad-hoc 方式簽署的模擬器與 macOS 應用程式，需在 macOS 上建置與驗證。不支援實體裝置建置、框架、擴充套件與測試。請使用封存輸出，而非實驗性的樹狀封存。
- **命令列工具：** 適用於 arm64 或 x86\_64 的 macOS 或 Linux 可執行檔，包括通用 macOS 二進位檔。腳本需要在接收端系統上具備 shebang 與直譯器。在你的目標中宣告執行階段相依性；Tuist 不會安裝缺少的程式庫或語言執行環境。

## 快取重放、失敗與保留

重複相同的發布會重用現有預覽，不會再次上傳，即使 Bazel 從快取還原建置亦然。變更輸出、軌道或修訂版本會建立新的發布。上傳失敗會導致命令失敗；你可以重新執行以確認發布是否已完成，再嘗試一次。

該命令會連結至你專案的預覽，處理可能需要一點時間。預覽會使用專案的預設可見性。

在託管的 Tuist 上，構件發布會在 30 天後過期。自託管實例使用 `TUIST_APP_PREVIEW_RETENTION_DAYS`；若不設定則對此系列停用過期。已過期的發布記錄無法透過重放相同意圖來恢復。

參閱 <.localized_link href="/guides/features/previews#run-a-preview">執行預覽</.localized_link> 以了解如何執行已發布的建置、存取權限、軌道與 README 徽章。

## Apple 預覽

針對 Apple 模擬器與 macOS 預覽，請參閱 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS 輔助應用程式說明</.localized_link>。這些不會改變 Bazel 的應用程式資格或簽署要求。

## 相關工作流程 {#publish-from-once}

現有的 Struo 整合有獨立的 <.localized_link href="/guides/features/previews/struo">構件發布指南</.localized_link>。這兩種工作流程都將發布與快取的圖形執行分開。
