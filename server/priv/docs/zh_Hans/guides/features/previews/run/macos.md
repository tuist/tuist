---
{
  "title": "使用 macOS 应用运行预览",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "使用 Tuist macOS 菜单栏应用在设备和模拟器上运行兼容的 Apple 预览。"
}
---
# 使用 macOS 应用运行预览

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download Tuist for macOS</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

对于 Apple 预览，Tuist macOS 菜单栏应用是 CLI 的替代方案，无论构建来自 Xcode、Bazel 还是 Once。发布工作流的签名和资格要求仍然适用。

## 安装 {#install}

[下载应用](https://tuist.dev/download)或使用 `brew install --cask tuist/tuist/tuist` 进行安装。

## 运行构建 {#run-a-build}

在菜单栏应用中选择兼容的设备或模拟器，然后在预览页面点击**运行**。

macOS 应用首先请求每个应用的最新兼容预览。在较旧的服务器上，如果它们在应用平台过滤器之前选择不同的应用，则会回退到分页历史记录，而不会设置可能隐藏可用构建的截止点。

有关访问和组织方式，请参阅<.localized_link href="/guides/features/previews#visibility">可见性和轨道</.localized_link>。
