---
{
  "title": "Releases",
  "titleTemplate": ":title | Contributors | Tuist",
  "description": "Learn how Tuist's continuous release process works"
}
---
# Releases

Tuist uses a continuous release system that automatically publishes new versions whenever meaningful changes are merged to the main branch. This approach ensures that improvements reach users quickly without manual intervention from maintainers.

## Overview

We continuously release three main components:
- **Tuist CLI** - The command-line tool
- **Tuist Server** - The backend services
- **Tuist App** - The macOS and iOS apps (iOS app is only continuously deployed to TestFlight, see more [here](#app-store-release)

Each component has its own release pipeline that runs automatically on every push to the main branch.

## How it works

### 1. Commit conventions

We use [Conventional Commits](https://www.conventionalcommits.org/) to structure our commit messages. This allows our tooling to understand the nature of changes, determine version bumps, and generate appropriate changelogs.

Format: `type(scope): description`

#### Commit types and their impact

| Type | Description | Version Impact | Example |
|------|-------------|----------------|---------|
| `feat` | New feature or capability | Minor version bump (x.Y.z) | `feat(cli): add support for Swift 6` |
| `fix` | Bug fix | Patch version bump (x.y.Z) | `fix(app): resolve crash when opening projects` |
| `docs` | Documentation changes | No release | `docs: update installation guide` |
| `style` | Code style changes | No release | `style: format code with swiftformat` |
| `refactor` | Code refactoring | No release | `refactor(server): simplify auth logic` |
| `perf` | Performance improvements | Patch version bump | `perf(cli): optimize dependency resolution` |
| `test` | Test additions/changes | No release | `test: add unit tests for cache` |
| `chore` | Maintenance tasks | No release | `chore: update dependencies` |
| `ci` | CI/CD changes | No release | `ci: add workflow for releases` |

#### Breaking changes

Breaking changes trigger a major version bump (X.0.0) and should be indicated in the commit body:

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. Change detection

Each component uses [git cliff](https://git-cliff.org/) to:
- Analyze commits since the last release
- Filter commits by scope (cli, app, server)
- Determine if there are releasable changes
- Generate changelogs automatically

### 3. Release pipeline

When releasable changes are detected:

1. **Version calculation**: The pipeline determines the next version number
2. **Changelog generation**: git cliff creates a changelog from commit messages
3. **Build process**: The component is built and tested
4. **Release creation**: A GitHub release is created with artifacts
5. **Distribution**: Updates are pushed to package managers (e.g., Homebrew for CLI)

### 4. Scope filtering

Each component only releases when it has relevant changes:

- **CLI**: Commits with `(cli)` scope or no scope
- **App**: Commits with `(app)` scope
- **Server**: Commits with `(server)` scope

## Writing good commit messages

Since commit messages directly influence release notes, it's important to write clear, descriptive messages:

### Do:
- Use present tense: "add feature" not "added feature"
- Be concise but descriptive
- Include the scope when changes are component-specific
- Reference issues when applicable: `fix(cli): resolve build cache issue (#1234)`

### Don't:
- Use vague messages like "fix bug" or "update code"
- Mix multiple unrelated changes in one commit
- Forget to include breaking change information

### Breaking changes

For breaking changes, include `BREAKING CHANGE:` in the commit body:

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## Release workflows

The release workflows are defined in:
- `.github/workflows/cli-release.yml` - CLI releases
- `.github/workflows/app-release.yml` - App releases
- `.github/workflows/server-release.yml` - Server releases

Each workflow:
- Runs on pushes to main
- Can be triggered manually
- Uses git cliff for change detection
- Handles the entire release process

## Monitoring releases

You can monitor releases through:
- [GitHub Releases page](https://github.com/tuist/tuist/releases)
- GitHub Actions tab for workflow runs
- Changelog files in each component directory

## Benefits

This continuous release approach provides:

- **Fast delivery**: Changes reach users immediately after merging
- **Reduced bottlenecks**: No waiting for manual releases
- **Clear communication**: Automated changelogs from commit messages
- **Consistent process**: Same release flow for all components
- **Quality assurance**: Only tested changes are released

## Troubleshooting

If a release fails:

1. Check the GitHub Actions logs for the failed workflow
2. Ensure your commit messages follow the conventional format
3. Verify that all tests pass
4. Check that the component builds successfully

For urgent fixes that need immediate release:
1. Ensure your commit has a clear scope
2. After merging, monitor the release workflow
3. If needed, trigger a manual release

## App Store release

While the CLI and Server follow the continuous release process described above, the **iOS app** is an exception due to Apple's App Store review process:

- **Manual releases**: iOS app releases require manual submission to the App Store
- **Review delays**: Each release must go through Apple's review process, which can take 1-7 days
- **Batched changes**: Multiple changes are typically bundled together in each iOS release
- **TestFlight**: Beta versions may be distributed via TestFlight before App Store release
- **Release notes**: Must be written specifically for App Store guidelines

The iOS app still follows the same commit conventions and uses git cliff for changelog generation, but the actual release to users happens on a less frequent, manual schedule.
