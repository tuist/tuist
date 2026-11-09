## CI 中的構建洞察 {#continuous-integration}

要追蹤 CI 上的構建洞察，請確保 CI 已<.localized_link href="/guides/server/authentication#continuous-integration">通過驗證</.localized_link>。

對於由 Xcodebuild 驅動的 CI，你需要：
- 在調用 `xcodebuild` 操作時使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>。
- 將 `-resultBundlePath` 添加到你的 `xcodebuild` 命令中。

如果沒有 `-resultBundlePath`，則不會生成所需的活動日誌和結果包，`tuist inspect build` 也無法分析構建。
