---
{
  "title": "Swift 包",
  "titleTemplate": ":title · Swift · 包注册表 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Swift 包中使用 Tuist 注册表。"
}
---
# Swift 包 {#swift-package}

如果你正在开发 Swift 包，可以使用 `--replace-scm-with-registry` 标志从注册表中解析依赖项（如果可用）：

```bash
swift package --replace-scm-with-registry resolve
```

如果你希望每次解析依赖项时都使用注册表，需要更新 `Package.swift` 文件中的 `dependencies`，将 URL 替换为注册表标识符。

<!-- @snippet: ./_registry-identifier -->
