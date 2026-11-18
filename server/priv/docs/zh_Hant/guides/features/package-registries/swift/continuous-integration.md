---
{
  "title": "持續整合",
  "titleTemplate": ":title · Swift · Package Registries · 功能 · 指南 · Tuist",
  "description": "了解如何在持續整合中使用 Tuist Registry。"
}
---
# 持續整合 (CI) {#continuous-integration-ci}

登錄庫在 CI 上開箱即用，無需任何額外的驗證設定。預設情況下，未經驗證的請求每個 IP 位址的速率限制為**每分鐘 1,000 次請求**。

若您需要更高的速率限制（**每分鐘 20,000 次請求**），可以執行 `tuist registry login` 進行驗證。這需要設定 `TUIST_TOKEN` 環境變數。您可以依照<.localized_link href="/guides/server/authentication#account-tokens">驗證指南</.localized_link>建立帳戶權杖。

> [!NOTE]
> 下方的鑰匙圈設定僅在您使用 `tuist registry login` 以取得更高速率限制時才需要。在大多數情況下，預設的未經驗證速率限制已足夠，您可以完全略過此步驟。
>
> 此外，僅在使用套件的 Xcode 整合時，才需要建立新的預先解鎖鑰匙圈。


由於 `tuist registry login` 會將憑證儲存在鑰匙圈中，您需要確保在 CI 環境中可以存取該鑰匙圈。請注意，某些 CI 供應商或自動化工具（例如 [Fastlane](https://fastlane.tools/)）已經會建立暫存鑰匙圈，或提供內建方式來建立鑰匙圈。不過，您也可以透過以下程式碼建立自訂步驟來建立：
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

請確保您的預設鑰匙圈已在執行 `tuist registry login` _之前_ 建立並解鎖。

## 跨環境的增量解析 {#incremental-resolution-across-environments}

使用我們的登錄庫時，乾淨/冷啟動解析的速度會稍快一些；若您能在 CI 建置之間保留已解析的相依性，還能獲得更大的改進。請注意，得益於登錄庫，您需要儲存和還原的目錄大小比不使用登錄庫時小得多，所需時間也顯著減少。若要在預設 Xcode 套件整合中快取相依性，最佳做法是在透過 `xcodebuild` 解析相依性時指定自訂的 `clonedSourcePackagesDirPath`。您可以將以下內容加入 `Tuist.swift` 檔案中來完成：

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
        )
    )
)
```

此外，您還需要找到 `Package.resolved` 的路徑。您可以執行 `ls **/Package.resolved` 來取得路徑。路徑看起來應類似 `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`。

對於 Swift 套件和基於 XcodeProj 的整合，我們可以使用位於專案根目錄或 `Tuist` 目錄中的預設 `.build` 目錄。在設定管線時，請確保路徑正確無誤。

以下是使用預設 Xcode 套件整合時，用於解析和快取相依性的 GitHub Actions 工作流程範例：
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
