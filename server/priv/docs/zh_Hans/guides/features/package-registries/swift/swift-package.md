---
{
  "title": "Swift 软件包",
  "titleTemplate": ":title · Swift · 软件包注册表 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Swift 软件包中使用 Tuist Registry。"
}
---
# Swift 包 {#swift-package}

如果你正在开发 Swift 包，可以使用 `--replace-scm-with-registry` 标志从注册表中解析依赖（如果可用）：

```bash
swift package --replace-scm-with-registry resolve
```

如果你希望每次解析依赖时都使用注册表，需要更新 `Package.swift` 文件中的 `dependencies`，用注册表标识符替换 URL。

<!-- @snippet: ./_registry-identifier -->
