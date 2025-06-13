# Code style
- Do not add one-line comments unless you think they are really useful.

# Workflow
- When compiling Swift changes, use `xcodebuild build -workspace Tuist.xcworkspace -scheme Tuist-Workspace` instead of `swift build`
- When testing Swift changes, use `xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace -only-testing MyTests/SuiteTests` instead of `swift test`.
- Prefer running test suites or individual test cases, and not the whole test target, for performance
