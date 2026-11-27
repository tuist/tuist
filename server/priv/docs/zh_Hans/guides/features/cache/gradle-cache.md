---
{
  "title": "Gradle 构建缓存：为 CI 和团队设置远程缓存",
  "titleTemplate": ":title · Tuist",
  "description": "通过 Tuist 插件和 org.gradle.caching=true 设置 Gradle 远程构建缓存，让 CI 和开发者复用任务输出，而非重新运行任务。"
}
---
# Gradle 构建缓存 {#gradle-cache}

Tuist 是一个 Gradle 远程构建缓存：其 Gradle 插件将 [Gradle 内置的构建缓存](https://docs.gradle.org/current/userguide/build_cache.html) 连接到共享服务器，因此 CI 和每台开发者机器都能复用任务输出，而无需重新运行任务。当任务的输出已被缓存时，Gradle 会跳过执行并从 Tuist 拉取结果，从而为团队和 CI 环境节省构建时间。如需了解 Tuist 还为 Gradle 构建添加了哪些功能（例如构建洞察和测试洞察），请参阅 [使用 Tuist 进行 Gradle 构建](https://tuist.dev/build-systems/gradle)；如果你正在将其与 Develocity 进行比较，请参阅 [Develocity 与 Tuist 对比](https://tuist.dev/compare/develocity)。如需了解 Gradle 的本地和远程构建缓存与最新状态检查及配置缓存的区别，请参阅 <.localized_link href="/references/concepts/build-cache#gradle">什么是构建缓存？</.localized_link>。若要找出缓存在缓慢构建中消除了哪一部分耗时，以及应优先修复项目中的哪些问题，请参阅 [缓慢构建](https://tuist.dev/solutions/slow-builds)。

安装 <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle 插件</.localized_link> 后，你还需要在 `gradle.properties` 文件中启用 Gradle 的构建缓存：

```properties
org.gradle.caching=true
```

如果没有此设置，Gradle 不会激活其构建缓存子系统——即使已配置远程缓存——所有任务都将执行，但不会命中或填充缓存。启用后，Gradle 会将 Tuist 用作远程构建缓存，在缓存命中时下载缓存的任务输出，并在任务执行后上传它们。

## 缓存上传策略 {#cache-upload-policy}

默认情况下，插件既会从远程缓存下载工件，也会向其上传工件。你可以通过 `buildCache` 块中的 `push` 选项来控制上传行为：

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

一种常见的模式是仅从 CI 推送工件（因为那里的构建是可复现的），同时保持本地环境为只读：

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

通过此设置，本地构建可以从缓存的工件中受益而无需上传，而 CI 构建则会为团队其他成员填充缓存。

## 持续集成 {#continuous-integration}

对于 CI 环境，请使用 <.localized_link href="/guides/server/authentication#continuous-integration">身份验证指南</.localized_link> 中的一种方法进行身份验证。有关特定提供商的 CI 示例，请参阅 <.localized_link href="/guides/integrations/continuous-integration">持续集成指南</.localized_link>。

### 禁用本地构建缓存 {#disabling-the-local-build-cache}

Gradle 同时维护本地和远程构建缓存。本地构建缓存将任务输出存储在磁盘上的 `~/.gradle/caches/build-cache-1` 目录下。

当 Tuist 被配置为远程构建缓存时，建议在 CI 上禁用本地构建缓存。这可以避免在 CI 运行器上存储冗余工件，并确保构建始终用新条目填充远程缓存，供团队其他成员使用。

在 `settings.gradle.kts` 中禁用 CI 上的 Gradle 本地构建缓存：

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

这使得本地构建缓存可用于本地开发，同时在 CI 上禁用它，由 Tuist 的远程缓存处理工件共享。

## 配置参考 {#configuration-reference}

`buildCache` 块支持以下选项：

| 选项 | 类型 | 默认值 | 描述 |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | 是否启用远程构建缓存。 |
| `push` | `Boolean` | `true` | 是否将任务输出上传到远程缓存。 |
| `allowInsecureProtocol` | `Boolean` | `false` | 是否允许不安全的 HTTP 连接。 |
