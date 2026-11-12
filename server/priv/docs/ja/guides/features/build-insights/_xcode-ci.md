## CI でのビルドインサイト {#continuous-integration}

CI でビルドインサイトを追跡するには、CI が<.localized_link href="/guides/server/authentication#continuous-integration">認証済み</.localized_link>であることを確認してください。

Xcodebuild を使用した CI では、次のことが必要です：
- `xcodebuild` アクションを呼び出す際は、<.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> を使用してください。
- `xcodebuild` コマンドに `-resultBundlePath` を追加してください。

`-resultBundlePath` がないと、必要なアクティビティログと結果バンドルが生成されず、`tuist inspect build` でビルドを分析できません。
