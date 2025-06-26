# Code style
- Do not add one-line comments unless you think they are really useful.

# Workflow
- The Xcode project is generated with Tuist running `tuist generate --no-open`
- When compiling Swift changes, use `xcodebuild build -workspace Tuist.xcworkspace -scheme Tuist-Workspace` instead of `swift build`
- When testing Swift changes, use `xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace -only-testing MyTests/SuiteTests` instead of `swift test`.
- Prefer running test suites or individual test cases, and not the whole test target, for performance

# Testing
- Use Swift Testing framework with custom traits for tests that need temporary directories
- For tests requiring temporary directories, use `@Test(.inTemporaryDirectory)` and access the directory via `FileSystem.temporaryTestDirectory`
- Import `FileSystemTesting` when using the `.inTemporaryDirectory` trait
- Example pattern:
  ```swift
  import FileSystemTesting
  import Testing
  
  @Test(.inTemporaryDirectory) func test_example() async throws {
      let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
      // Test implementation
  }
  ```
