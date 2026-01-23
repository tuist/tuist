---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# 持续集成（CI）{#continuous-integration-ci}

要在CI环境中使用注册表，需确保通过运行`tuist registry login` 完成注册表登录，将其纳入工作流流程。

::: info ONLY XCODE INTEGRATION
<!-- -->
仅当使用Xcode的包集成时，才需要创建新的预解锁钥匙串。
<!-- -->
:::

由于注册表凭据存储在钥匙串中，您需要确保CI环境中可访问该钥匙串。请注意，某些CI提供商或自动化工具（如[Fastlane](https://fastlane.tools/)）已创建临时钥匙串或提供内置创建方式。但您也可通过创建自定义步骤并使用以下代码来创建钥匙串：
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`tuist registry login` 将把凭据存储在默认钥匙串中。在运行_ `tuist registry login`
之前，请确保已创建并解锁默认钥匙串_。

此外，需确保环境变量`TUIST_TOKEN`
已设置。可参照文档<LocalizedLink href="/guides/server/authentication#as-a-project">此处</LocalizedLink>进行创建。

GitHub Actions 的示例工作流如下所示：
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

### 跨环境的增量解析{#incremental-resolution-across-environments}

使用我们的注册表可略微提升干净/冷解析速度，若在持续集成构建中持久化解析后的依赖项，性能提升更为显著。需注意：注册表使存储和恢复所需的目录体积大幅缩减，耗时显著降低。
使用默认Xcode包集成时，缓存依赖项的最佳方式是在通过`xcodebuild` 解析依赖项时，通过`clonedSourcePackagesDirPath`
指定自定义路径。可在`Config.swift` 文件中添加以下配置实现：

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

`此外，您需要获取`的Package.resolved路径。可通过运行`ls **/Package.resolved`
获取路径。该路径应类似于`App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
。

对于Swift包及基于XcodeProj的集成，可使用默认路径`.build` 目录（位于项目根目录或`Tuist` 目录内）。设置管道时请确保路径正确。

以下是使用默认Xcode包集成时，通过GitHub Actions解决并缓存依赖项的示例工作流：
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
