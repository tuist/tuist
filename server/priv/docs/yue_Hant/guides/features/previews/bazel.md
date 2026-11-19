---
{
  "title": "Bazel 預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "透過 Bazel 將 Android 應用程式、Apple 應用程式及命令列工具發布為預覽。"
}
---
# Bazel 預覽

從現有 Bazel target 發佈 Android APK、Apple 模擬器與 macOS app，以及命令列工具。為你想要分享的每個輸出新增一個 preview target；你的一般建置保持不變。

## 設定

將 [`rules_tuist`（來自 Tuist 儲存庫）](https://github.com/tuist/tuist/tree/main/bazel) 加入 `MODULE.bazel`，並鎖定你要使用的 commit：

```starlark
bazel_dep(name = "rules_tuist")

git_override(
    module_name = "rules_tuist",
    remote = "https://github.com/tuist/tuist.git",
    commit = "FULL_COMMIT_SHA",
    strip_prefix = "bazel",
)
```

保留你現有的 application target、原生 SDK 與簽署設定。Bazel 會提供發佈工具。

直接從 Bazel 登入：

```bash
bazel run @rules_tuist//:login
```

這會與 Tuist CLI 和 Gradle plugin 共用憑證；已有的登入狀態也可用。在 CI 上，使用 `TUIST_TOKEN` 或執行 login target 並搭配 Tuist 的 <.localized_link href="/guides/integrations/continuous-integration">OIDC 驗證</.localized_link>。切勿將憑證放入 BUILD 檔案或 rule 屬性中。傳遞 `-- --url https://tuist.example.com` 以登入自託管實例。

只在你的 `BUILD.bazel` 中載入你需要的 adapter：

```starlark
load("@rules_tuist//:android.bzl", "android_preview")

android_preview(name = "preview_android", app = ":android_app")
```

對於 Apple 應用程式：

```starlark
load("@rules_tuist//:apple.bzl", "apple_preview")

apple_preview(name = "preview_ios", app = ":ios_app")
apple_preview(name = "preview_macos", app = ":macos_app")
```

對於可執行 target（例如 `cc_binary`）：

```starlark
load("@rules_tuist//:executable.bzl", "executable_preview")

executable_preview(name = "preview_cli", binary = ":my_tool")
```

可執行預覽會包含 target 所宣告的執行階段檔案。在你的 Bazel target 中宣告工具所需的函式庫與資源，並使用在建置目錄之外也能運作的路徑。

## 建置與發佈

```bash
bazel run //:preview_android -- \
  --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- \
  --publish --project acme/app --track review
bazel run //:preview_macos -- --publish --project acme/app --track review
bazel run //:preview_cli -- --publish --project acme/app --track review
```

將應用程式與模擬器平台標籤替換為你自己的。為自託管 Tuist 來源傳遞 `--url`，並傳遞 `--revision` 以關聯 Git commit。

傳遞 `--publish --project account/project` 以分享成功的建置。若沒有 `--publish`，或使用 `--no-publish`，則不會上傳任何內容，也無需登入。一般的 `bazel build` 永遠不會發佈，即使在快取命中時亦然。`tuist bazel setup` 會啟用快取與洞察，但不會進行發佈。

## 支援的輸出

- **Android：** 已簽署的應用程式 APK，包括偵錯建置。安裝 Android SDK build-tools 與命令列工具，並設定 `ANDROID_HOME` 或 `ANDROID_SDK_ROOT`。不支援測試 APK 與 Android App Bundle。
- **Apple：** 以 ad-hoc 簽署的模擬器與 macOS 應用程式，需在 macOS 上建置與驗證。不支援實體裝置建置、framework、extension 與測試。請使用 archive 輸出，而非實驗性的 tree archive。
- **命令列工具：** 適用於 arm64 或 x86\_64 的 macOS 或 Linux 可執行檔，包括通用 macOS 二進位檔。腳本需要在接收端系統上有 shebang 與直譯器。在你的 target 中宣告執行階段相依性；Tuist 不會安裝缺少的函式庫或語言執行環境。

## 快取重放、失敗與保留

重複相同的發佈會重用現有的預覽而不會再次上傳，即使 Bazel 從快取還原建置亦然。變更輸出、track 或 revision 會建立新的發佈。上傳失敗會使命令失敗；你可以重新執行以檢查發佈是否已完成，然後再試一次。

該命令會連結到你專案的預覽，處理可能需要一點時間。預覽會使用專案的預設可見性。

在託管的 Tuist 上，artifact 發佈會在 30 天後過期。自託管實例使用 `TUIST_APP_PREVIEW_RETENTION_DAYS`；若不設定則會為此系列停用過期。已過期的發佈記錄無法透過重放相同意圖來恢復。

參閱 <.localized_link href="/guides/features/previews#run-a-preview">執行預覽</.localized_link> 以了解如何執行已發佈的建置、存取權限、track 與 README 徽章。

## Apple 預覽

對於 Apple 模擬器與 macOS 預覽，請參閱 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS  companion app 說明</.localized_link>。這些不會改變 Bazel 的應用程式資格或簽署要求。

## 相關工作流程 {#publish-from-once}

現有的 Struo 整合有獨立的 <.localized_link href="/guides/features/previews/struo">artifact 發佈指南</.localized_link>。兩種工作流程都讓發佈與快取的圖執行分開。
