---
{
  "title": "持續整合",
  "titleTemplate": ":title · Swift · Package Registries · 功能 · 指南 · Tuist",
  "description": "了解如何在持續整合中使用 Tuist Registry。"
}
---
# 持續整合 (CI) {#continuous-integration-ci}

註冊中心喺 CI 環境入面开箱即用，唔需要額外設定認證。預設情況下，每個 IP 地址嘅未認證請求會被限制為每分鐘 **1,000 次請求**。

如果你需要更高嘅速率限制（每分鐘 **20,000 次請求**），可以執行 `tuist registry login` 進行認證。這需要設定 `TUIST_TOKEN` 環境變量。你可以按照文檔 <.localized_link href="/guides/server/authentication#as-a-project">此處</.localized_link> 建立專案令牌。

> [!NOTE]
> 下面嘅鑰匙圈設定只係喺你使用 `tuist registry login` 獲取更高速率限制時才需要。大多數情況下，預設嘅未認證速率限制已經足夠，你可以完全跳過此步驟。
>
> 此外，只有當使用 Xcode 套件整合時，才需要建立一個新嘅預先解鎖鑰匙圈。


由於 `tuist registry login` 會將憑證儲存喺鑰匙圈中，你需要確保喺 CI 環境中可以訪問該鑰匙圈。請注意，某些 CI 供應商或自動化工具（例如 [Fastlane](https://fastlane.tools/)）已經會建立臨時鑰匙圈或提供內建方法來建立。不過，你也可以通過以下代碼建立自定義步驟來建立：
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

請確保喺執行 `tuist registry login` 之前，你嘅默認鑰匙圈已經建立並解鎖 _之前_。

### 跨環境嘅增量解析 {#incremental-resolution-across-environments}

使用我哋嘅註冊中心時，乾淨/冷啟動解析會稍快一些，如果你喺 CI 構建之間持久化已解析嘅依賴項，體驗到更大嘅改進。請注意，得益於註冊中心，你需要儲存和恢復嘅目錄大小比不使用註冊中心時小得多，所需時間亦顯著減少。當使用默認 Xcode 套件整合時，緩存依賴項嘅最佳方法係喺通過 `xcodebuild` 解析依賴項時指定自定義嘅 `clonedSourcePackagesDirPath`。你可以通過將以下內容添加到 `Config.swift` 文件中來實現：

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

此外，你需要找到 `Package.resolved` 嘅路徑。你可以通過執行 `ls **/Package.resolved` 來獲取路徑。路徑應該類似於 `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`。

對於 Swift 套件和基於 XcodeProj 嘅整合，我哋可以使用位於專案根目錄或 `Tuist` 目錄中嘅默認 `.build` 目錄。設置流水線時，請確保路徑正確。

以下係使用默認 Xcode 套件整合時，GitHub Actions 解析和緩存依賴項嘅工作流程示例：
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
