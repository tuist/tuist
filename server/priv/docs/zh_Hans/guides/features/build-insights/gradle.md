---
{
  "title": "Gradle Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Gradle task timings and cache behavior in the Tuist dashboard."
}
---
# Gradle 构建洞察 {#gradle-build-insights}

Tuist 的 Gradle 插件可以将构建分析数据发送到 Tuist，让你能够查看任务执行情况和构建性能。

## 配置上传行为 {#configure-upload-behavior}

默认情况下：
- 本地构建的构建分析数据会在后台上传。
- CI 运行的构建分析数据会在前台上传，以避免在短暂存在的代理上丢失遥测数据。

你可以使用 `tuist` 扩展中的 `uploadInBackground` 来控制此行为：

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

## 配置参考 {#configuration-reference}

`tuist` 扩展块（位于 `settings.gradle.kts` 中）提供了 `uploadInBackground` 选项：

| 选项 | 类型 | 默认值 | 描述 |
| --- | --- | --- | --- |
| `uploadInBackground` | `Boolean?` | `null`（本地后台，CI 前台） | 是否在本地构建时在后台上传构建洞察数据。 |

此设置不会影响 `buildCache` 块中的远程缓存设置。

## 报告参与者声明 {#report-actor-claim}

仅当你将 `TUIST_ACTOR_ID` 显式设置为组织范围的标签，或在设置中配置 `buildInsights.actorId` 时，构建和测试报告请求才会包含可选的 `x-tuist-actor-id` 标头。默认情况下不发送任何标签，且插件不会检测操作系统用户名。环境变量覆盖具有最高优先级。将任一覆盖设置为空字符串以省略报告的标识符；这不会删除由个人凭据建立的身份。无效的覆盖会省略声明，而不是回退。如果自定义代理拒绝不熟悉的标头，请使用 `TUIST_ACTOR_ID=""` 选择退出。

```kotlin
tuist {
    buildInsights {
        actorId = providers.environmentVariable("CORPORATE_ACTOR_ID").getOrElse("")
    }
}
```

参与者标识符是 1–128 字节的非空格可打印 ASCII 字符。任何可以查看项目报告的人（包括项目公开时的公众查看者）都可以看到这些标识符，并且它们会随报告一起导出。不要包含你不想发布的机密或个人信息。经验证的个人凭据在仪表板中具有最高优先级；否则，客户端发送的标识符会明确标记为 **未验证**。它们永远不会授予权限或自动链接到 Tuist 用户。旧服务器会忽略归属标头，而新服务器会继续接受不带该标头的旧客户端。没有标识符的新共享令牌报告会显示 **未知**，而不是发布组织；历史报告保留其先前的归属信息。构建和测试列表将已验证用户过滤器与未验证的报告标识符过滤器分开。

## 网络可信发布 {#network-trusted-publishing}

自托管部署可以明确允许来自其可信网络的 Gradle 构建和测试报告，无需开发者凭据。操作员必须先在实例上配置 `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING=true` 并重启。这适用于每个受支持的项目；仪表板中没有相关设置。请参阅 <.localized_link href="/guides/server/self-host/server#network-trusted-report-publishing">自托管指南</.localized_link>。

在仓库中一次性配置目标：

```kotlin
tuist {
    project = "organization/project"
    url = "https://tuist.internal.example"
    buildCache { enabled = false }
}
```

构建和测试报告不需要经过身份验证的缓存端点发现。缓存访问仍然需要凭据：如果开发者未配置令牌，请禁用缓存。未签名的测试报告会省略分片和现有构建引用，并且不会触发隔离或不稳定性自动化。当确实缺少凭据时，会跳过隔离查找；使用有效凭据时，会保留现有的身份验证行为。如果存在凭据，则会继续使用它们，无效凭据会导致失败，而不是回退到无凭据发布。当缺少凭据时，插件会自动发现自托管服务器是否允许无凭据报告。不需要客户端标志或 `buildInsights` 设置。在升级无凭据客户端之前，先将每个服务器副本升级到支持发现的版本。较旧的没有发现功能的服务器、禁用的实例以及发现错误仍然需要身份验证；身份验证发布保持兼容。显式为空的 `TUIST_TOKEN` 会导致失败关闭，而不是启用无凭据发布。对于没有密钥的 fork 或 Dependabot 作业，请移除该变量，而不是将其定义为空字符串。

服务器分配无凭据报告 ID。重复提交可能会创建第二个报告；此模式不保证幂等重试或与身份验证测试报告的相关性。此类报告无法触发 VCS 评论或自动故障代理事件。网络访问是发布信任边界，而不是所报告参与者身份的证明。

## 自定义元数据 {#custom-metadata}

将标签和键值数据附加到 Gradle 构建，以比较来自不同团队、硬件或工作流的运行。标签可用作仪表板过滤器，值会显示在每个构建的详细信息页面以及应用程序编程接口和模型上下文协议工具中。

使用环境变量设置元数据：

```sh
export TUIST_BUILD_TAGS="nightly,android"
export TUIST_BUILD_VALUE_TICKET="TUIST-123"
export TUIST_BUILD_VALUE_RUNNER="macos-14"
```

你也可以在 `settings.gradle.kts` 中配置元数据：

```kotlin
tuist {
    buildInsights {
        tag("nightly")
        tag("android")
        value("ticket", "TUIST-123")
        value("runner", "macos-14")
    }
}
```

当在两处配置相同的值时，`settings.gradle.kts` 中的值具有最高优先级。

标签只能包含字母、数字、连字符和下划线。一个构建最多可以有 50 个标签，每个标签最多可以包含 50 个字符。一个构建最多可以有 20 个键值条目，每个键最多可以包含 50 个字符，每个值最多可以包含 500 个字符。这与用于 Xcode 构建元数据的服务器端限制相同。插件在发送报告之前会跳过无效标签以及过大或空的元数据条目，因此无效配置不会阻止其余构建洞察报告的存储。对于不符合标签约束的值，请使用键值元数据。

项目成员可以在仪表板中以及通过应用程序编程接口和模型上下文协议工具查看自定义元数据。不要将其用于凭据、访问令牌或其他敏感数据。Tuist 会将 Gradle 构建数据（包括此元数据）保留 90 天。有关详细信息，请参阅 <.localized_link href="/guides/server/data-retention">数据保留政策</.localized_link>。
