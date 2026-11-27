## CI 中的構建洞察 {#continuous-integration}

要追蹤 CI 中的構建洞察，請確保 CI 已<.localized_link href="/guides/server/authentication#continuous-integration">驗證</.localized_link>。

對於由 Xcodebuild 驅動的 CI，你需要：
- 在調用 `xcodebuild` 操作時使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>。
- 將 `-resultBundlePath` 加入你的 `xcodebuild` 指令。

如果沒有 `-resultBundlePath`，就不會生成所需的活動日誌和結果包，而 `tuist inspect build` 也無法分析構建。
