---
{
  "title": "使用 CLI 运行预览",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "使用 Tuist CLI 运行移动应用、macOS 应用和命令行预览。"
}
---
# 使用 CLI 运行预览

安装 <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link>，然后运行共享的预览链接。你不需要用于生成该预览的构建系统：

```bash
tuist run {url}
```

Tuist 会为你的操作系统、CPU 架构和目标平台选择兼容的构建产物。私有预览需要身份验证和项目访问权限。

## 移动应用 {#mobile-applications}

选择已连接的设备或模拟器：

```bash
tuist run --device "My device" {url}
```

Android 设备和模拟器必须通过 ADB 连接。你也可以从预览页面下载 APK，并将其安装在允许从该来源安装的 Android 设备上。Apple 构建产物必须与目标平台匹配并满足其签名要求。对于 IPA，请在目标设备上打开预览链接以进行安装。

## 命令行预览 {#command-line-previews}

在 `--` 之后传递参数：

```bash
tuist run {url} -- --help
tuist run {url} -- build --configuration Release
```

`--` 之后的所有内容都会原样转发，包括 `--verbose`、`--quiet` 和 `--path`。子参数不会纳入 Tuist 命令分析。

预览会在你的工作目录、环境变量和终端输入/输出环境下运行，并返回可执行文件的退出状态。它不会替换已安装的 CLI，也不会将其添加到 `PATH`。CLI 分发包在执行后会保留在 Tuist 本地的 `previews` 缓存中，以便生成的项目可以继续引用它们；删除该缓存也会移除这些引用的目标。

桌面和 CLI 预览以当前用户身份运行，而非在沙盒中运行。仅运行你信任的作者和拉取请求中的构建产物。

## 选择版本 {#select-a-version}

`tuist run` 还支持使用 `latest` 的应用名称、分支名称或提交哈希：

```bash
tuist run App@latest # Latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Latest App preview associated with a branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Preview associated with a commit
```

这些选择器要求已发布相应的 Git 元数据。对于不包含 Git 元数据的工作流，请改用具体的预览 URL。

有关访问权限和组织方式，请参阅 <.localized_link href="/guides/features/previews#visibility">可见性和轨道</.localized_link>。
