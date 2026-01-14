# Tuist CLI (Swift)

This node covers the Tuist CLI workspace under `cli/`. Follow downlinks for subsystem boundaries.

## Key Boundaries
- Entry point lives in `cli/Sources/tuist`.
- Core domain models and shared abstractions live in `cli/Sources/TuistCore`.
- Common utilities and infra (logging, file system helpers, etc.) live in `cli/Sources/TuistSupport`.
- Tuist Server client: `cli/Sources/TuistServer`
- Cache client: `cli/Sources/TuistCache`
- Dependencies tooling: `cli/Sources/TuistDependencies`
- Manifest loading: `cli/Sources/TuistLoader`

## Legacy Modules (avoid adding new code)
- `cli/Sources/TuistKit` - Monolithic command wiring; new commands should be added to feature-specific modules.
- `cli/Sources/TuistGenerator` - Monolithic generation pipeline; new generation logic should be added to smaller, focused modules.

## Code Style
- Do not add one-line comments unless they are truly useful.

## Testing
- Use Swift Testing framework with custom traits for tests that need temporary directories.
- For temporary directories, use `@Test(.inTemporaryDirectory)` and access it via `FileSystem.temporaryTestDirectory`.
- Import `FileSystemTesting` when using `.inTemporaryDirectory`.
- Example:
  ```swift
  import FileSystemTesting
  import Testing

  @Test(.inTemporaryDirectory) func test_example() async throws {
      let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
      // Test implementation
  }
  ```

## Linting
- Check: `mise run lint`
- Auto-fix: `mise run lint --fix`

## Related Context (Downlinks)
- CLI entry point: `cli/Sources/tuist/AGENTS.md`
- Command definitions and wiring: `cli/Sources/TuistKit/AGENTS.md`
- Core domain models: `cli/Sources/TuistCore/AGENTS.md`
- Shared utilities: `cli/Sources/TuistSupport/AGENTS.md`
- Project generation: `cli/Sources/TuistGenerator/AGENTS.md`
- Dependency management: `cli/Sources/TuistDependencies/AGENTS.md`
- Manifest loading: `cli/Sources/TuistLoader/AGENTS.md`
- Server integration: `cli/Sources/TuistServer/AGENTS.md`
- Cache integration: `cli/Sources/TuistCache/AGENTS.md`
- Project description models: `cli/Sources/ProjectDescription/AGENTS.md`
- Project automation: `cli/Sources/ProjectAutomation/AGENTS.md`
- Tuist automation: `cli/Sources/TuistAutomation/AGENTS.md`
- Acceptance testing support: `cli/Sources/TuistAcceptanceTesting/AGENTS.md`
- CAS support: `cli/Sources/TuistCAS/AGENTS.md`
- CAS analytics: `cli/Sources/TuistCASAnalytics/AGENTS.md`
- CI integration: `cli/Sources/TuistCI/AGENTS.md`
- Environment management: `cli/Sources/TuistEnvKit/AGENTS.md`
- Git integration: `cli/Sources/TuistGit/AGENTS.md`
- HTTP client: `cli/Sources/TuistHTTP/AGENTS.md`
- Hashing utilities: `cli/Sources/TuistHasher/AGENTS.md`
- Launchd integration: `cli/Sources/TuistLaunchctl/AGENTS.md`
- Migration utilities: `cli/Sources/TuistMigration/AGENTS.md`
- OIDC integration: `cli/Sources/TuistOIDC/AGENTS.md`
- Plugin system: `cli/Sources/TuistPlugin/AGENTS.md`
- Process execution: `cli/Sources/TuistProcess/AGENTS.md`
- Root directory resolution: `cli/Sources/TuistRootDirectoryLocator/AGENTS.md`
- Scaffold generation: `cli/Sources/TuistScaffold/AGENTS.md`
- Simulator integration: `cli/Sources/TuistSimulator/AGENTS.md`
- Test helpers: `cli/Sources/TuistTesting/AGENTS.md`
- XCActivityLog parsing: `cli/Sources/TuistXCActivityLog/AGENTS.md`
- XCResult handling: `cli/Sources/TuistXCResultService/AGENTS.md`
- Xcode project/workspace path resolution: `cli/Sources/TuistXcodeProjectOrWorkspacePathLocator/AGENTS.md`
- Benchmark tooling: `cli/Sources/tuistbenchmark/AGENTS.md`
- Fixture generation tooling: `cli/Sources/tuistfixturegenerator/AGENTS.md`

Note: `cli/TuistCacheEE` is a git submodule; keep any intent nodes for that package within the submodule itself.
