---
{
  "title": "Bazel 预览",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "从 Bazel 发布 Android 应用、Apple 应用和命令行工具作为预览。"
}
---
# Bazel 预览

从现有的 Bazel 目标发布 Android APK、Apple 模拟器和 macOS 应用，以及命令行工具。为你想要分享的每个输出添加一个预览目标；你的常规构建保持不变。

## 设置

将 [`rules_tuist`（来自 Tuist 仓库）](https://github.com/tuist/tuist/tree/main/bazel) 添加到 `MODULE.bazel`，并固定你要使用的提交：

```starlark
bazel_dep(name = "rules_tuist")

git_override(
    module_name = "rules_tuist",
    remote = "https://github.com/tuist/tuist.git",
    commit = "FULL_COMMIT_SHA",
    strip_prefix = "bazel",
)
```

保留你现有的应用目标、原生 SDK 和签名配置。Bazel 提供发布工具。

直接从 Bazel 登录：

```bash
bazel run @rules_tuist//:login
```

这会将凭据与 Tuist CLI 和 Gradle 插件共享；已有的登录状态同样有效。在 CI 中，使用 `TUIST_TOKEN` 或通过 Tuist 的 <.localized_link href="/guides/integrations/continuous-integration">OIDC 认证</.localized_link> 运行登录目标。切勿将凭据放入 BUILD 文件或规则属性中。传递 `-- --url https://tuist.example.com` 以登录到自托管实例。

仅在 `BUILD.bazel` 中加载你需要的适配器：

```starlark
load("@rules_tuist//:android.bzl", "android_preview")

android_preview(name = "preview_android", app = ":android_app")
```

对于 Apple 应用：

```starlark
load("@rules_tuist//:apple.bzl", "apple_preview")

apple_preview(name = "preview_ios", app = ":ios_app")
apple_preview(name = "preview_macos", app = ":macos_app")
```

对于可执行目标（例如 `cc_binary`）：

```starlark
load("@rules_tuist//:executable.bzl", "executable_preview")

executable_preview(name = "preview_cli", binary = ":my_tool")
```

可执行预览包含目标声明的运行时文件。在你的 Bazel 目标中声明工具所需的库和资源，并使用在构建目录之外也能正常工作的路径。

## 构建并发布

```bash
bazel run //:preview_android -- \
  --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- \
  --publish --project acme/app --track review
bazel run //:preview_macos -- --publish --project acme/app --track review
bazel run //:preview_cli -- --publish --project acme/app --track review
```

将应用和模拟器平台标签替换为你自己的标签。为自托管的 Tuist 源传递 `--url`，并通过 `--revision` 关联 Git 提交。

传递 `--publish --project account/project` 以分享成功的构建。如果不带 `--publish`，或使用 `--no-publish`，则不会上传任何内容，也无需登录。常规的 `bazel build` 永远不会发布，即使在缓存命中时也是如此。`tuist bazel setup` 启用缓存和洞察功能，而非发布功能。

## 支持的输出

- **Android：** 已签名的应用 APK，包括调试构建。安装 Android SDK 构建工具和命令行工具，并设置 `ANDROID_HOME` 或 `ANDROID_SDK_ROOT`。不支持测试 APK 和 Android App Bundle。
- **Apple：** 采用 ad-hoc 签名的模拟器和 macOS 应用，需在 macOS 上构建和验证。不支持真机构建、框架、扩展和测试。请使用归档输出，而非实验性的树状归档。
- **命令行工具：** 适用于 arm64 或 x86\_64 的 macOS 或 Linux 可执行文件，包括通用 macOS 二进制文件。脚本需要在接收方系统上具备 shebang 和解释器。请在你的目标中声明运行时依赖项；Tuist 不会安装缺失的库或语言运行时。

## 缓存重放、失败和保留

重复相同的发布会重用现有预览，而不会再次上传，即使 Bazel 从缓存恢复构建也是如此。更改输出、轨道或修订版本会创建新的发布。上传失败会导致命令失败；你可以重新运行它以检查发布是否已完成，然后再试一次。

该命令会链接到你项目的预览，处理可能需要一点时间。预览使用项目的默认可见性设置。

在托管的 Tuist 上，构件发布会在 30 天后过期。自托管实例使用 `TUIST_APP_PREVIEW_RETENTION_DAYS`；不设置该项将禁用此类发布的过期机制。已过期的发布记录无法通过重放相同意图来恢复。

请参阅 <.localized_link href="/guides/features/previews#run-a-preview">运行预览</.localized_link>，了解如何运行已发布的构建、访问权限、轨道以及 README 徽章。

## Apple 预览

对于 Apple 模拟器和 macOS 预览，请参阅 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS 配套应用说明</.localized_link>。这些不会改变 Bazel 的应用资格或签名要求。

## 相关工作流 {#publish-from-once}

现有的 Once 集成有单独的 <.localized_link href="/guides/features/previews/once">构件发布指南</.localized_link>。这两种工作流都将发布与缓存图执行分开。
