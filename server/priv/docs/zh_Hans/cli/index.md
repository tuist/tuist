---
{
  "title": "CLI",
  "titleTemplate": ":title · Tuist",
  "description": "Tuist CLI、其命令以及如何为你的工作流进行配置。"
}
---
# 命令行界面 {#cli}

Tuist 命令行界面是与 Tuist 交互的接口之一，如果你使用<.localized_link href="/guides/features/projects">生成的项目</.localized_link>，它是最常用的接口。它提供了用于生成项目、缓存二进制文件、运行测试、共享预览等命令。

## 入门指南 {#getting-started}

如果你尚未安装 Tuist，请按照<.localized_link href="/guides/install-tuist">安装指南</.localized_link>开始使用。

安装完成后，你可以在终端中运行 `tuist` 以查看可用命令列表：

```bash
tuist --help
```

## 配置 {#configuration}

可以通过 `tuist.toml` 文件配置命令行界面的行为。请参阅<.localized_link href="/references/tuist-toml">tuist.toml 参考文档</.localized_link>了解所有可用选项。

## 故障排除 {#troubleshooting}

如果遇到问题，请查看<.localized_link href="/cli/debugging">调试指南</.localized_link>，其中提供了诊断问题的工具，包括会话日志和网络记录。
