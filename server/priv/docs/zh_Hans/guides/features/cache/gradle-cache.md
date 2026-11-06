---
{
  "title": "Gradle 缓存",
  "titleTemplate": ":title · 缓存 · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 在团队和 CI 之间共享 Gradle 构建缓存产物。"
}
---
# Gradle 缓存 {#gradle-cache}

Tuist 提供了一个 Gradle 插件，可与 [Gradle 内置的构建缓存](https://docs.gradle.org/current/userguide/build_cache.html) 集成，以远程共享构建产物。当任务的输出已缓存时，Gradle 会跳过执行并从 Tuist 的远程缓存中拉取结果，从而为团队和 CI 环境节省构建时间。

安装 <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle 插件</.localized_link> 后，你还需要在 `gradle.properties` 文件中启用 Gradle 的构建缓存：

```properties
org.gradle.caching=true
```

若不进行此配置，即使已配置远程缓存，Gradle 也不会激活其构建缓存子系统，所有任务都将执行而不会命中或填充缓存。启用后，Gradle 会将 Tuist 用作远程构建缓存，在缓存命中时下载缓存的任务输出，并在任务执行后上传它们。

## 缓存上传策略 {#cache-upload-policy}

默认情况下，该插件既从远程缓存下载工件，也向其上传工件。你可以通过 `buildCache` 块中的 `push` 选项来控制上传：

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

一种常见模式是仅从 CI 推送工件（因为那里的构建是可复现的），同时保持本地环境为只读：

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

通过这种设置，本地构建可以从缓存的工件中受益而无需上传，而 CI 构建则会为团队的其他成员填充缓存。

## 持续集成 {#continuous-integration}

对于 CI 环境，请使用 <.localized_link href="/guides/server/authentication#continuous-integration">身份验证指南</.localized_link> 中的一种方法进行身份验证。有关特定提供商的 CI 示例，请参阅 <.localized_link href="/guides/integrations/continuous-integration">持续集成指南</.localized_link>。

### 禁用本地构建缓存 {#disabling-the-local-build-cache}

Gradle 同时维护本地和远程构建缓存。本地构建缓存将任务输出存储在磁盘上的 `~/.gradle/caches/build-cache-1` 目录下。

当 Tuist 被配置为远程构建缓存时，建议在 CI 上禁用本地构建缓存。这可以避免在 CI 运行器上存储冗余的工件，并确保构建始终用新的条目填充远程缓存，供团队其他成员使用。

在你的 `settings.gradle.kts` 中禁用 CI 上的 Gradle 本地构建缓存：

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

这使得本地构建缓存在本地开发中可用，同时在 CI 上禁用它，由 Tuist 的远程缓存处理工件共享。

## 配置参考 {#configuration-reference}

`buildCache` 块支持以下选项：

| 选项 | 类型 | 默认值 | 描述 |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | 是否启用远程构建缓存。 |
| `push` | `Boolean` | `true` | 是否将任务输出上传到远程缓存。 |
| `allowInsecureProtocol` | `Boolean` | `false` | 是否允许不安全的 HTTP 连接。 |
