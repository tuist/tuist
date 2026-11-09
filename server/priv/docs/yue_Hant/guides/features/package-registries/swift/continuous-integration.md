---
{
  "title": "持續整合",
  "titleTemplate": ":title · Swift · Package Registries · 功能 · 指南 · Tuist",
  "description": "了解如何在持續整合中使用 Tuist Registry。"
}
---
# 持續整合 (CI) {#continuous-integration-ci}

Registry 喺 CI 環境入面開箱即用，唔使再做額外嘅認證設定。預設情況下，每個 IP 地址嘅未認證請求會被限制為每分鐘 **1,000 次請求**。

如果你需要更高嘅速率限制（每分鐘 **20,000 次請求**），可以執行 `tuist registry login` 進行認證。這需要設置 `TUIST_TOKEN` 環境變量。你可以按照<.localized_link href="/guides/server/authentication#account-tokens">認證指南</.localized_link>建立帳戶令牌。

> [!NOTE]
> 下面嘅 Keychain 設定只係喺你需要使用 `tuist registry login` 嚟取得更高速率限制時才需要。喺大多數情況下，預設嘅未認證速率限制已經足夠，你可以完全跳過呢一步。
>
> 另外，只有當你使用 Xcode 嘅套件整合功能時，先至需要建立一個新嘅預先解鎖 Keychain。


由於 `tuist registry login` 會將憑證儲存喺 Keychain 入面，你需要確保喺 CI 環境中可以訪問該 Keychain。請注意，部分 CI 供應商或自動化工具（例如 [Fastlane](https://fastlane.tools/)）已經會建立臨時 Keychain，或者提供內置方法嚟建立。不過，你亦都可以透過以下代碼自訂步驟嚟建立：
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

請確保你嘅預設 Keychain 喺執行 `tuist registry login` _之前_ 已經建立並解鎖。

## 跨環境增量解析 {#incremental-resolution-across-environments}

使用我哋嘅 Registry 時，乾淨／冷啟動解析會稍快一啲；如果你喺多次 CI 建構之間持久化已解析嘅依賴項，仲可以獲得更大嘅改善。請注意，得益於 Registry，你需要儲存同恢復嘅目錄大小比不使用 Registry 時細好多，節省大量時間。要喺使用預設 Xcode 套件整合時快取依賴項，最佳做法係透過 `xcodebuild` 解析依賴項時指定自訂嘅 `clonedSourcePackagesDirPath`。你可以將以下內容加入到你嘅 `Tuist.swift` 檔案中：

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

另外，你需要搵到 `Package.resolved` 嘅路徑。你可以執行 `ls **/Package.resolved` 來獲取路徑。路徑應該類似 `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`。

對於 Swift 套件同基於 XcodeProj 嘅整合，我哋可以使用位於專案根目錄或 `Tuist` 目錄中嘅預設 `.build` 目錄。請確保喺設置 pipeline 時路徑正確。

以下係使用預設 Xcode 套件整合時，喺 GitHub Actions 中解析同快取依賴項嘅工作流程示例：
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
