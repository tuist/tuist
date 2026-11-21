---
{
  "title": "Bazel 預覽",
  "titleTemplate": ":title · 預覽 · Tuist",
  "description": "從 Bazel 將 Android 應用程式、Apple 應用程式和命令列工具發佈為預覽。"
}
---
# Bazel 預覽

從你現有的 Bazel target 發布 Android APK、Apple 模擬器及 macOS 應用程式，以及命令列工具。為每個你想分享的輸出新增一個預覽 target；你的一般建構流程保持不變。

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

保留你現有的應用程式 target、原生 SDK 及簽署設定。Bazel 會提供發布工具。

直接從 Bazel 登入：

```bash
bazel run @rules_tuist//:login
```

這會與 Tuist CLI 及 Gradle plugin 共用憑證；已有的登入狀態亦有效。在 CI 上，使用 `TUIST_TOKEN` 或執行登入 target 並搭配 Tuist 的 <.localized_link href="/guides/integrations/continuous-integration">OIDC 驗證</.localized_link>。切勿將憑證放入 BUILD 檔案或 rule 屬性中。傳遞 `-- --url https://tuist.example.com` 以登入自託管實例。

只在你需要的 `BUILD.bazel` 中載入對應的 adapter：

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

可執行預覽包含 target 所宣告的執行階段檔案。在你的 Bazel target 中宣告工具所需的程式庫及資源，並使用在建構目錄之外也能運作的路徑。

## 建構與發布

```bash
bazel run //:preview_android -- \
  --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- \
  --publish --project acme/app --track review
bazel run //:preview_macos -- --publish --project acme/app --track review
bazel run //:preview_cli -- --publish --project acme/app --track review
```

將應用程式及模擬器平台標籤替換为你自己的。傳遞 `--url` 以指定自託管 Tuist 來源，並傳遞 `--revision` 以關聯 Git commit。

傳遞 `--publish --project account/project` 以分享成功的建構。若沒有 `--publish`，或使用 `--no-publish`，則不會上傳任何內容，亦無需登入。一般的 `bazel build` 永遠不會發布，包括快取命中時。`tuist bazel setup` 只會啟用快取與洞察功能，並非發布。

## 支援的輸出

- **Android：** 已簽署的應用程式 APK，包括除錯版本。安裝 Android SDK build-tools 及命令列工具，並設定 `ANDROID_HOME` 或 `ANDROID_SDK_ROOT`。不支援測試 APK 及 Android App Bundles。
- **Apple：** 採用 ad-hoc 簽署的模擬器及 macOS 應用程式，需在 macOS 上建構並驗證。不支援實體裝置建構、frameworks、extensions 及測試。請使用 archive 輸出，而非實驗性的 tree archives。
- **命令列工具：** 適用於 arm64 或 x86\_64 的 macOS 或 Linux 可執行檔，包括通用 macOS 二進位檔。腳本需要在接收者的系統上具備 shebang 及直譯器。在你的 target 中宣告執行階段依賴項；Tuist 不會安裝缺少的程式庫或語言執行環境。

## 快取重放、失敗與保留

重複相同的發布會重用現有的預覽，而不會再次上傳，即使 Bazel 從快取還原建構亦然。更改輸出、track 或 revision 會建立新的發布。上傳失敗會導致命令失敗；你可以重新執行以檢查發布是否已完成，然後再試一次。

該命令會連結到你專案的預覽，處理可能需要一點時間。預覽使用專案的預設可見性。

在託管的 Tuist 上，artifact 發布會在 30 天後過期。自託管實例使用 `TUIST_APP_PREVIEW_RETENTION_DAYS`；若不設定此值，則對此系列禁用過期。已過期的發布記錄無法透過重放相同的意圖來恢復。

參閱 <.localized_link href="/guides/features/previews#run-a-preview">執行預覽</.localized_link> 以了解如何執行已發布的建構、存取權限、tracks 及 README badges。

## Apple 預覽

關於 Apple 模擬器及 macOS 預覽，請參閱 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS  companion app 說明</.localized_link>。這些不會改變 Bazel 的應用程式資格或簽署要求。

## 相關工作流程 {#publish-from-once}

現有的 Struo 整合有獨立的 <.localized_link href="/guides/features/previews/struo">artifact 發布指南</.localized_link>。兩種工作流程都將發布與快取的圖形執行分開。
