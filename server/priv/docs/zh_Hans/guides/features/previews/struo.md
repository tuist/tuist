---
{
  "title": "Struo 预览",
  "titleTemplate": ":title · 预览 · Tuist",
  "description": "通过 Struo 的原生 Tuist 提供程序发布 Android、Apple 模拟器和 macOS 应用程序预览。"
}
---
# Struo 预览 {#struo-previews}

<a id="once-previews"></a>

[Struo](https://struo.run/docs/guide/infrastructure/tuist#publish-application-previews) 可以将应用构件发布到 Tuist，让团队成员无需在本地重新构建即可试用某个构建版本。请使用 [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) 或更高版本，以及配备了构件接收器的 Tuist 服务器。

## 配置目标地址

完成<.localized_link href="/guides/get-started/struo-project">Struo 入门指南</.localized_link>，然后在工作区的 `struo.toml` 中添加构件绑定。如果该提供者已为缓存配置，则可复用：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.artifacts]
name = "tuist"
```

```bash
struo auth login --provider tuist
struo artifact publish MyApplication --track review
```

接收器会保留完整的集合、成员清单和载荷，包括未知接口。受支持的原生接口会根据项目的默认可见性、访问权限和分发设置，异步投影到预览中。通用构件内容保持私密，即使在公开项目中也是如此。收据仅确认构件已存储，并不表示预览处理已完成；其 URL 会打开项目的预览列表。

## 符合条件的应用

Apple 投影接受用于在 macOS 上导出的临时签名 macOS 应用和模拟器应用的 `dev.struo.apple-install.v2` 元数据。真机应用不符合条件。Android 投影接受带有已验证签名的 `dev.struo.android-install.v1` 元数据。Struo 仅批准自动发布经过调试签名且非插桩的 APK。未知接口仍可作为构件下载，但不会创建预览。Android 安装链接会保留 `.apk` 文件名，尽管载荷是按内容摘要存储的。

## 选择在构建后发布

```toml
[infrastructure]
publish_on_build = ["MyApplication"]
```

```bash
struo artifact publish MyApplication --allow-on-build
struo build MyApplication
```

所有请求的构建都必须成功。自动发布还需要生产者对整个闭包的批准，以及针对此机器、工作区、确切端点、目标和稳定 Tuist 项目目标的本地授权。如果没有策略或授权，就不会发出构件发布的网络请求。常规 Struo 构建不会产生隐式发布的副作用。

重放相同的保留发布会验证远程收据并避免再次上传。这与 `tuist share` 的重复构建行为不同。

## 保留期

在托管的 Tuist 上，构件发布会在 30 天后过期。自托管实例使用 `TUIST_APP_PREVIEW_RETENTION_DAYS`；不设置该变量将为此类发布禁用过期。过期记录会保留为墓碑状态，无法通过重放相同意图来重新激活。现有的 `tuist share` 签名、可见性和分发工作流程保持不变。

请参阅<.localized_link href="/guides/features/previews#run-a-preview">运行预览</.localized_link>，了解如何运行已发布的构建、管理访问权限、跟踪渠道以及添加 README 徽章。

## Apple 预览

对于符合条件的 Apple 模拟器和 macOS 预览，请参阅<.localized_link href="/guides/features/previews/run/macos">Tuist macOS 配套应用说明</.localized_link>。真机应用仍然不符合 Struo 发布条件。
