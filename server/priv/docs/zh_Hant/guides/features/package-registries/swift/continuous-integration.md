---
{
  "title": "持續整合",
  "titleTemplate": ":title · Swift · Package Registries · 功能 · 指南 · Tuist",
  "description": "了解如何在持續整合中使用 Tuist Registry。"
}
---
# 持續整合 (CI) {#continuous-integration-ci}

註冊表在 CI 上開箱即用，無需任何額外的驗證設定。預設情況下，未經驗證的請求會受到速率限制，每個 IP 地址每分鐘最多 **1,000 次請求**。

如果你需要更高的速率限制（**每分鐘 20,000 次請求**），可以透過執行 `tuist registry login` 進行驗證。這需要設定 `TUIST_TOKEN` 環境變數。你可以依照文件說明<.localized_link href="/guides/server/authentication#as-a-project">這裡</.localized_link>建立專案權杖。

> [!NOTE]
> 下方的金鑰圈設定僅在你使用 `tuist registry login` 以取得更高速率限制時才需要。在大多數情況下，預設的未驗證速率限制已足夠，你可以完全略過此步驟。
>
> 此外，只有在使用套件的 Xcode 整合功能時，才需要建立新的預先解鎖金鑰圈。


由於 `tuist registry login` 會將憑證儲存在金鑰圈中，你需要確保在 CI 環境中可以存取該金鑰圈。請注意，某些 CI 供應商或自動化工具（例如 [Fastlane](https://fastlane.tools/)）已經會建立臨時金鑰圈，或提供內建方式來建立金鑰圈。不過，你也可以透過以下程式碼建立自訂步驟來建立金鑰圈：
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

請確保在執行 `tuist registry login` _之前_，已建立並解鎖你的預設金鑰圈。

### 跨環境的增量解析 {#incremental-resolution-across-environments}

使用我們的註冊表時，乾淨/冷啟動解析的速度會稍快一些；如果你在 CI 建置之間持久化已解析的相依性，還能獲得更大的效能提升。請注意，得益於註冊表，你需要儲存和還原的目錄大小比不使用註冊表時小得多，所需時間也顯著減少。若要在預設的 Xcode 套件整合中快取相依性，最佳做法是在透過 `xcodebuild` 解析相依性時指定自訂的 `clonedSourcePackagesDirPath`。你可以將以下內容加入 `Config.swift` 檔案來完成此設定：

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

此外，你还需要找到 `Package.resolved` 的路徑。你可以執行 `ls **/Package.resolved` 來取得路徑。路徑看起來應該類似 `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`。

對於 Swift 套件和基於 XcodeProj 的整合，我們可以使用位於專案根目錄或 `Tuist` 目錄中的預設 `.build` 目錄。在設定你的管線時，請確保路徑正確。

以下是一個 GitHub Actions 工作流程範例，用於在使用預設 Xcode 套件整合時解析並快取相依性：
```yaml
- name: Restore cache
  id: cache-restore
  uses: actions/cache/restore@v4
  with:
    path: .build
    key: ${{ runner.os }}-${{ hashFiles('App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
- name: Resolve dependencies
  if: steps.cache-restore.outputs.cache-hit != 'true'
  run: xcodebuild -resolvePackageDependencies -clonedSourcePackagesDirPath .build
- name: Save cache
  id: cache-save
  uses: actions/cache/save@v4
  with:
    path: .build
    key: ${{ steps.cache-restore.outputs.cache-primary-key }}
```
