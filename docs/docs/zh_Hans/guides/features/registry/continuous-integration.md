---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# 持续集成 (CI){#continuous-integration-ci}

要在 CI 上使用注册表，需要在工作流程中运行`tuist registry login` ，确保已登录注册表。

::: info ONLY XCODE INTEGRATION
<!-- -->
只有在使用 Xcode 集成软件包时，才需要创建新的预解锁钥匙串。
<!-- -->
:::

由于注册表凭据存储在钥匙串中，因此需要确保在 CI 环境中可以访问钥匙串。请注意，一些 CI 提供商或自动化工具（如
[Fastlane](https://fastlane.tools/)
）已经创建了临时钥匙串，或提供了创建钥匙串的内置方法。不过，您也可以通过使用以下代码创建自定义步骤来创建一个：
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`tuist 注册表登录` 会将凭证存储在默认钥匙串中。在运行_ `tuist registry login` 之前，确保已创建并解锁默认钥匙串_。

此外，您还需要确保`TUIST_TOKEN` 环境变量已设置。您可以根据此处的文档
<LocalizedLink href="/guides/server/authentication#as-a-project"></LocalizedLink>
创建一个环境变量。

GitHub 操作的工作流程示例如下：
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

### 跨环境递增分辨率{#incremental-resolution-across-environments}

使用我们的注册表，清洁/冷解析的速度会稍快一些，如果在 CI
构建过程中持续保持已解析的依赖关系，效果会更好。请注意，由于有了注册表，您需要存储和还原的目录大小比没有注册表时要小得多，所需的时间也大大减少。要在使用默认的
Xcode 软件包集成时缓存依赖关系，最好的办法是在通过`xcodebuild`
解析依赖关系时指定一个自定义的`clonedSourcePackagesDirPath` 。这可以通过在`Config.swift` 文件中添加以下内容来实现：

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

此外，您还需要找到`Package.resolved` 的路径。您可以运行`ls **/Package.resolved`
获取路径。路径应类似于`App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
。

对于 Swift 包和基于 XcodeProj 的集成，我们可以使用位于项目根目录或`Tuist` 目录中的默认`.build`
目录。请在设置管道时确保路径正确。

下面是一个 GitHub Actions 工作流程示例，用于在使用默认 Xcode 软件包集成时解析和缓存依赖关系：
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
