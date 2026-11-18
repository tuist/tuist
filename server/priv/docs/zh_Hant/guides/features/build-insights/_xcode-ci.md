## CI 中的建置洞察 {#continuous-integration}

若要在 CI 上追蹤建置洞察，請確認 CI 已<.localized_link href="/guides/server/authentication#continuous-integration">通過驗證</.localized_link>。

對於由 Xcodebuild 驅動的 CI，你需要：
- 在呼叫 `xcodebuild` 動作時使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>。
- 將 `-resultBundlePath` 加入你的 `xcodebuild` 指令。

若缺少 `-resultBundlePath`，系統不會產生必要的活動記錄與結果套件，導致 `tuist inspect build` 無法分析該次建置。
