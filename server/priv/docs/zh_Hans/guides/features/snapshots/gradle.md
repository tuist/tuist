---
{
  "title": "Gradle",
  "titleTemplate": ":title · Snapshots · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Gradle 插件，为每个 Compose 预览生成快照，或上传 Paparazzi 和 Roborazzi 录制的内容。"
}
---
# Gradle 快照 {#gradle-snapshots}

> [!IMPORTANT]
> **要求**
>
> - 你的账户已启用快照功能。目前仅限受邀用户：请[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中留言以申请访问权限。
> - <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle 插件</.localized_link>。
> - 在你进行快照的模块中使用[Paparazzi](https://github.com/cashapp/paparazzi)或[Roborazzi](https://github.com/takahirom/roborazzi)。

Tuist Gradle 插件会上传 Paparazzi 和 Roborazzi 记录的图像，Tuist 会将它们与<.localized_link href="/guides/features/snapshots#how-it-works">基线</.localized_link>进行比较。在应用了 Paparazzi 的模块中，该插件还会生成一个测试来渲染每个 Compose `@Preview`，因此你无需手动编写快照测试。

## 设置 {#set-up}

在你的 `settings.gradle.kts` 中启用快照：

```kotlin
tuist {
    snapshots {
        enabled = true
        set = "android-phone" // Defaults to the Gradle project's path.
    }
}
```

## 运行 {#run}

在 CI 中，`./gradlew test` 会渲染预览并上传它们，当预览发生变化且无人批准时，构建将失败。本地运行不会上传任何内容，因为它们会上传未提交的更改。传递 `-Ptuist.snapshots=false` 可在 CI 中关闭上传功能。

Paparazzi 和 Roborazzi 的记录任务（例如 `recordPaparazziDebug`）在启用快照时始终会上传。

## 选项 {#options}

`snapshots` 块接受以下选项：

- `enabled`：是否上传快照。默认为 `false`。
- `set`：构建比较所在的集合。默认为 Gradle 项目的路径。
- `directory`：包含要上传图像的目录，相对于 Gradle 项目。默认为生成的预览测试或快照库写入的位置。
- `failOnChanges`：当存在无人批准的更改时，构建是否失败。默认为 `true`。
- `diffThreshold`：在图像被视为已更改之前，允许不同的像素比例，范围为 0 到 1。默认为 `0`。
- `previews { generateTests }`：是否生成 Compose 预览测试。默认为 `true`。
- `previews { packageTrees }`：扫描预览的软件包。默认为 Android 命名空间。
- `previews { includePrivatePreviews }`：是否也渲染私有 `@Preview` 函数。默认为 `false`。
- `previews { theme }`：渲染 Android 主题预览所使用的主题。默认为 Paparazzi 的主题。
