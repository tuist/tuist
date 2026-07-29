---
{
  "title": "Releases",
  "titleTemplate": ":title | Contributors | Tuist",
  "description": "Learn how Tuist's continuous release process works"
}
---
# Releases

Tuist publishes new versions automatically as changes are merged to the main branch. The server and app are released continuously, so improvements reach users immediately. The CLI builds on the same tooling but ships through release channels (canary, release candidate, stable) so the recommended install stays stable and slow-moving; cutting a release candidate and promoting it to stable are deliberate, maintainer-triggered steps.

## Overview

We release these main components:
- **Tuist CLI** - The command-line tool, shipped through canary, release candidate, and stable [channels](#cli-release-channels)
- **Tuist Server** - The backend services, released continuously
- **Tuist App** - The macOS and iOS apps, released continuously (iOS app is only continuously deployed to TestFlight, see more [here](#app-store-release))

The server and app publish automatically on every push to the main branch. The CLI publishes a canary prerelease on every push, but reaches a stable release only when a maintainer cuts and promotes it (see [CLI release channels](#cli-release-channels)).

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

For the CLI, these bumps determine the canary version and the changelog grouping. Stable CLI versions are minor lines (`X.Y.0`) cut by hand, and stable patches (`X.Y.Z`) come only from backports, so a `feat` or `fix` reaches CLI users through the channel flow below rather than as an immediate stable release.

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
4. **Artifact generation**: Release-specific assets are produced, such as the CLI bundles, checksums, and the `tuist.spec.json` CLI specification generated from `tuist --experimental-dump-help`
5. **Release creation**: A GitHub release is created with artifacts
6. **Distribution**: Updates are pushed to package managers (e.g., Homebrew for CLI)

For the server and app this produces a stable release. For the CLI this same automatic pipeline produces a **canary** prerelease only; release candidates and stable releases are cut manually (see [CLI release channels](#cli-release-channels)).

### 4. Scope filtering

Each component only releases when it has relevant changes:

- **CLI**: Commits with `(cli)` scope or no scope
- **App**: Commits with `(app)` scope
- **Server**: Commits with `(server)` scope

## CLI release channels

Unlike the server and app, the CLI is not promoted to a stable release on every push to `main`. It ships through three channels so the recommended install stays stable and slow-moving while early adopters keep per-commit builds. The <.localized_link href="/cli/release-channels">Release channels</.localized_link> page documents this from a user's perspective; this section is the maintainer runbook.

| Channel | Version | Cut by |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | Automatically, on every CLI-touching push to `main` (`cli-release.yml`) |
| Release candidate | `X.Y.0-rc.N` | Manually, on a `releases/<major>.<minor>.x` branch (`cli-rc.yml`) |
| Stable | `X.Y.Z` | Manually, by promoting a soaked RC (`cli-promote.yml`); patches via `cli-backport.yml` |

Canary and RC builds are published as GitHub prereleases (never marked "Latest", never pushed to Homebrew), so package managers only resolve them on explicit opt-in. Canary always targets the next unreleased minor: once an RC line is cut, `main`'s canary advances to the following minor.

You never hand-pick version numbers. Every channel's next version is derived from the existing git tags by `mise/tasks/cli/release/channel-version.sh`, which the workflows below invoke.

### Cutting a release candidate

When the next minor is ready to soak, cut a new line:

1. Run the **CLI Release Candidate** workflow (`cli-rc.yml`) with an empty `branch` input.
2. It publishes `X.Y.0-rc.1` and, after that succeeds, creates the protected `releases/X.Y.x` branch at the built commit.

To pull a critical fix or regression into a soaking line, cherry-pick it onto the release branch through a PR (the same flow as backports; CI never cherry-picks), then iterate the RC:

1. Branch off `releases/X.Y.x`, cherry-pick the fix, open a PR back into the release branch, resolve any conflicts there, and merge.
2. Run **CLI Release Candidate** again with `branch=releases/X.Y.x`. It publishes `X.Y.0-rc.(N+1)` from the branch HEAD.

A soaking line is feature-frozen: only critical fixes and regressions go onto it.

### Promoting to stable

After the RC has soaked cleanly (about a week):

1. Run the **CLI Promote to Stable** workflow (`cli-promote.yml`) with `branch=releases/X.Y.x`.
2. It publishes the bare `X.Y.0` tag with `make_latest=true` and updates the Homebrew formula.

Promotion refuses to run unless the branch HEAD is exactly the commit the latest RC points at. So if any fix merged onto the line after the last RC, you must cut a new RC and let it soak before it can ship as stable.

### Backporting fixes to a stable line

Once a line is stable, ship patches with the **CLI Backport Release** workflow (`cli-backport.yml`): cherry-pick the fix onto `releases/X.Y.x` through a PR, then run the workflow with that branch to cut `X.Y.(Z+1)`. Backports never move the "Latest" pointer or the Homebrew formula. Two lines are maintained at a time: the current line takes regressions and security fixes, the previous line takes critical and security fixes only. Other bug fixes are not backported and ship with the next minor.

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

The server, app, cache, Gradle plugin, skills, Noora, and infrastructure components release through `.github/workflows/release.yml`. It runs on pushes to main, uses git cliff for change detection, and handles the full process including artifacts and GitHub releases.

The CLI has its own set of workflows (it is excluded from `release.yml`):

- `cli-release.yml` - publishes a canary on every CLI-touching push to main
- `cli-rc.yml` - manually cuts or iterates a release candidate
- `cli-promote.yml` - manually promotes a soaked RC to stable
- `cli-backport.yml` - manually cuts a patch on a stable line
- `cli-build-publish.yml` - the shared build and publish pipeline the four above call

The CLI build (`cli-build-publish.yml`) also produces and publishes a `tuist.spec.json` artifact (generated from `tuist --experimental-dump-help`) so downstream tooling can consume the command interface. All CLI workflows serialize through one `cli-publish` concurrency group so version resolution and tagging never race.

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
3. For the server or app, the fix ships on the next push; if needed, trigger a manual release
4. For the CLI, the fix lands on canary automatically. To get it to stable users, backport it to the maintained stable line(s) (see [Backporting fixes to a stable line](#backporting-fixes-to-a-stable-line))

## App Store release

While the CLI and Server follow the continuous release process described above, the **iOS app** is an exception due to Apple's App Store review process:

- **Manual releases**: iOS app releases require manual submission to the App Store
- **Review delays**: Each release must go through Apple's review process, which can take 1-7 days
- **Batched changes**: Multiple changes are typically bundled together in each iOS release
- **TestFlight**: Beta versions may be distributed via TestFlight before App Store release
- **Release notes**: Must be written specifically for App Store guidelines

The iOS app still follows the same commit conventions and uses git cliff for changelog generation, but the actual release to users happens on a less frequent, manual schedule.
