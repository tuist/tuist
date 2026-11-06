---
{
  "title": "一次性构件发布",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "将不可变的一次性应用构件发布到现有 Tuist 项目中，并需显式授权目标地址。"
}
---
# Once 构件发布

[Once](https://buildonce.dev/docs/guide/infrastructure/tuist#publish-application-previews) 可以使用现有的 Tuist 身份认证发布不可变构件。这需要 Once 0.74.0+ 以及配置了构件接收器的 Tuist 服务器。Once 0.73.x 则使用旧版的单载荷适配器。

## 配置目标地址

在工作区的 `once.toml` 中：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.artifacts]
name = "tuist"
```

```bash
once auth login --provider tuist
once artifact publish MyApplication --track review
```

接收器会保留完整的集合、成员清单和载荷，包括未知接口。受支持的原生接口会根据项目的默认可见性、访问权限和分发设置，异步投影为预览。通用构件内容保持私密，即使在公开项目中也是如此。回执仅确认构件已存储，并不代表预览处理已完成；其 URL 会打开项目的预览列表。

## 符合条件的应用

Apple 投影接受 `dev.once.apple-install.v2` 元数据，适用于在 macOS 上导出的临时签名 macOS 应用和模拟器应用。真机应用不符合条件。Android 投影接受带有已验证签名的 `dev.once.android-install.v1` 元数据。Once 仅批准自动发布调试签名且非插桩的 APK。未知接口仍可作为构件下载，但不会创建预览。Android 安装链接会保留 `.apk` 文件名，尽管载荷是按内容摘要存储的。

## 选择在构建后发布

```toml
[infrastructure]
publish_on_build = ["MyApplication"]
```

```bash
once artifact publish MyApplication --allow-on-build
once build MyApplication
```

所有请求的构建都必须成功。自动发布还需要生产者对整个闭包的批准，以及针对此机器、工作区、确切端点、目标和稳定 Tuist 项目目标的本地授权。如果没有策略或授权，就不会发起构件发布的网络请求。普通的 Once 构建不会产生隐式发布的副作用。

重放相同的保留发布会验证远程回执并避免再次上传。这与 `tuist share` 的重复构建行为不同。

## 保留期

在托管的 Tuist 上，构件发布会在 30 天后过期。自托管实例使用 `TUIST_APP_PREVIEW_RETENTION_DAYS`；如果不设置该变量，则对此类发布禁用过期。过期的记录会保留为墓碑记录，无法通过重放相同的意图重新激活。现有的 `tuist share` 签名、可见性和分发工作流保持不变。

请参阅 <.localized_link href="/guides/features/previews#run-a-preview">运行预览</.localized_link>，了解如何运行已发布的构建、管理访问权限、跟踪分支以及添加 README 徽章。

## Apple 预览

对于符合条件的 Apple 模拟器和 macOS 预览，请参阅 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS 配套应用说明</.localized_link>。真机应用仍然不符合 Once 发布条件。
