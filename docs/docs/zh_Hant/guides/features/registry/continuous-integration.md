---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# 持續整合 (CI){#continuous-integration-ci}

若要在 CI 上使用註冊表，您需要在工作流程中執行`tuist registry login` ，以確保已登入註冊表。

::: info ONLY XCODE INTEGRATION
<!-- -->
只有當您使用 Xcode 整合套件時，才需要建立新的預先解鎖鑰匙鏈。
<!-- -->
:::

由於註冊表憑證儲存在鑰匙鏈中，因此您需要確保在 CI 環境中可以存取鑰匙鏈。請注意，有些 CI 提供者或自動化工具（例如
[Fastlane](https://fastlane.tools/)）已經建立臨時的 keychain，或提供內建的方式來建立
keychain。不過，您也可以使用下列程式碼建立自訂步驟，以建立臨時keychain：
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`tuist 註冊登入` 會將憑證儲存於預設的 keychain 中。在執行_ `tuist 註冊登入` 之前，請確保已建立預設的 keychain
並解除鎖定_。

此外，您需要確保`TUIST_TOKEN` 環境變數已設定。您可以按照說明文件
<LocalizedLink href="/guides/server/authentication#as-a-project"> 這裡 </LocalizedLink> 建立一個。

GitHub Actions 的示例工作流程如下：
```yaml
name: Build

jobs:
  build:
    steps:
      - # Your set up steps...
      - name: Create keychain
        run: |
        TMP_DIRECTORY=$(mktemp -d)
        KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
        KEYCHAIN_PASSWORD=$(uuidgen)
        security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
        security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
        security default-keychain -s $KEYCHAIN_PATH
        security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
      - name: Log in to the Tuist Registry
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
        run: tuist registry login
      - # Your build steps
```

### 跨環境的遞增解析度{#incremental-resolution-across-environments}

使用我們的註冊表進行清潔/冷卻解析會稍微快一點，如果您在 CI
建置中持續使用已解析的相依性，您可以體驗到更大的改進。請注意，由於註冊表的存在，您需要儲存與還原的目錄大小比沒有使用註冊表時小得多，所花費的時間也顯著減少。`使用預設的
Xcode 套件整合時，若要快取相依性，最好的方法是在透過`xcodebuild
解析相依性時，指定自訂的`clonedSourcePackagesDirPath` 。這可以透過在您的`Config.swift` 檔案中加入下列內容來完成：

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

此外，您還需要找到`Package.resolved` 的路徑。您可以執行`ls **/Package.resolved`
來取得路徑。路徑應該看起來像`App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
。

對於 Swift 套件和基於 XcodeProj 的整合，我們可以使用位於專案根目錄或`Tuist` 目錄中的預設`.build`
目錄。設定管道時，請確定路徑正確。

以下是使用預設 Xcode 套件整合時，GitHub Actions 解析和快取相依性的工作流程範例：
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
