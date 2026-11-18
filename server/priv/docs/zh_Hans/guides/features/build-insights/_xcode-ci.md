## CI 中的构建洞察 {#continuous-integration}

要在 CI 中跟踪构建洞察，请确保 CI 已<.localized_link href="/guides/server/authentication#continuous-integration">通过身份验证</.localized_link>。

对于由 Xcodebuild 驱动的 CI，你需要：
- 在调用 `xcodebuild` 操作时使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>。
- 向你的 `xcodebuild` 命令添加 `-resultBundlePath`。

如果没有 `-resultBundlePath`，将不会生成所需的活动日志和结果包，`tuist inspect build` 也就无法分析构建。
