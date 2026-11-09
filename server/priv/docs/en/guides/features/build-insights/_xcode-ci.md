## Build insights in CI {#continuous-integration}

To track build insights on CI, make sure CI is <.localized_link href="/guides/server/authentication#continuous-integration">authenticated</.localized_link>.

For Xcodebuild-driven CI you need to:
- Use <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> when invoking `xcodebuild` actions.
- Add `-resultBundlePath` to your `xcodebuild` command.

Without `-resultBundlePath`, required activity logs and result bundles are not generated and `tuist inspect build` cannot analyze the build.
