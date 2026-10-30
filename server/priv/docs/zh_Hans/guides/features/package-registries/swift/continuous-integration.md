---
{
  "title": "持续集成",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "了解如何在持续集成中使用 Tuist Registry。"
}
---
# 持续集成 (CI) {#continuous-integration-ci}

注册表在 CI 环境中开箱即用，无需额外的身份验证设置。默认情况下，未身份验证的请求按 IP 地址进行速率限制，上限为**每分钟 1,000 次请求**。

如果你需要更高的速率限制（**每分钟 20,000 次请求**），可以通过运行 `tuist registry login` 进行身份验证。这需要设置 `TUIST_TOKEN` 环境变量。你可以按照文档<.localized_link href="/guides/server/authentication#as-a-project">此处</.localized_link>的说明创建项目令牌。

> [!NOTE]
> 仅在使用 `tuist registry login` 获取更高速率限制时，才需要以下钥匙串设置。在大多数情况下，默认的未身份验证速率限制已足够，你可以完全跳过此步骤。
>
> 此外，仅在使用 Xcode 包集成时，才需要创建一个新的预解锁钥匙串。


由于 `tuist registry login` 将凭据存储在钥匙串中，你需要确保在 CI 环境中可以访问该钥匙串。请注意，某些 CI 提供商或自动化工具（如 [Fastlane](https://fastlane.tools/)）已经会创建临时钥匙串或提供内置的创建方法。不过，你也可以通过创建一个包含以下代码的自定义步骤来创建钥匙串：
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

确保在运行 `tuist registry login` _之前_ 创建并解锁你的默认钥匙串。

### 跨环境的增量解析 {#incremental-resolution-across-environments}

使用我们的注册表时，清理/冷解析的速度会稍快一些，如果你在 CI 构建之间持久化已解析的依赖项，还能获得更大的性能提升。请注意，得益于注册表，你需要存储和恢复的目录大小比不使用注册表时小得多，从而显著节省时间。在使用默认 Xcode 包集成时缓存依赖项的最佳方法是在通过 `xcodebuild` 解析依赖项时指定自定义的 `clonedSourcePackagesDirPath`。这可以通过在 `Config.swift` 文件中添加以下内容来实现：

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

此外，你还需要找到 `Package.resolved` 的路径。你可以通过运行 `ls **/Package.resolved` 来获取路径。该路径应该类似于 `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`。

对于 Swift 包和基于 XcodeProj 的集成，我们可以使用默认的 `.build` 目录，该目录位于项目根目录或 `Tuist` 目录中。在设置流水线时，请确保路径正确。

以下是使用默认 Xcode 包集成时，用于解析和缓存依赖项的 GitHub Actions 工作流示例：
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
