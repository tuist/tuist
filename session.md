# Session Log: Mastodon iOS migration to Tuist generated projects

Date: 2026-02-02
Location:
- /Users/pepicrft/src/github.com/mastodon/mastodon-ios
- /Users/pepicrft/src/github.com/tuist/tuist

## Objective

Migrate the Mastodon iOS client to Tuist generated projects, validate build and runtime, warm cache and benchmark clean builds, and capture the process in a reusable skill and a long form blog post.

## Constraints and requirements captured from the conversation

- Use `tuist generate --no-open`.
- Integrate external dependencies through `.external` where possible.
- For cached generation, use a profile that maximizes binary use.
- Perform clean builds for both baseline and cached benchmarks.
- Cache warm with `tuist cache` and keep Xcode module cache in the cached runs.
- Use hyperfine for benchmarks: https://github.com/sharkdp/hyperfine.
- Ensure the app builds and runs, not just compiles.
- Keep migration close to the original project structure.
- Prefer extracting build settings into `.xcconfig` files.
- Blog post should be long form, story driven, no em dashes, and explicitly mention the agent doing work.
- Skill should be generic and avoid caching guidance.
- Use markdown links in the blog post.

## Chronological log (actions and outcomes)

Note: commands below reflect what was executed during the migration. Where an exact flag or destination was not recorded in a local shell history, the command is listed as used in the run with the arguments that were applied.

1) Baseline verification
- Built the original Xcode project with a clean build to establish a baseline for compilation time.
- Launched the app on a simulator to confirm runtime behavior before any migration work.

2) Build settings extraction
- Extracted build settings from the Xcode project into `.xcconfig` files under `xcconfigs/`.
- Wired the configs back into target definitions in `Project.swift`.
- Goal: preserve settings hierarchy, keep configs aligned across targets, and keep the manifest readable.

3) Initial Tuist manifests
- Created `Tuist.swift` to define project configuration.
- Created `Project.swift` to describe targets, resources, and dependencies.
- Created `Tuist/Package.swift` for Swift Package dependencies.
- Integrated external dependencies through `.external` where possible.

4) First generated build
- Ran `tuist generate --no-open`.
- Built the generated workspace with `xcodebuild` to validate the initial migration.

5) Source inclusion fix
- Error: missing `TimelineListViewController` referenced by `DiscoveryViewModel`.
- Root cause: a folder called "In Progress New Layout and Datamodel" was excluded too broadly.
- Fix: mirrored the pbx exception set, included the folder, and excluded only the explicit file.
- Result: compilation progressed after regenerating.

6) Resource and source classification fixes
- Errors: `.intentdefinition` treated as resources, `.xcstrings` shadowed by `.strings`, settings bundles treated as files not folders.
- Fix: adjusted resources and sources in `Project.swift`.
- Regenerated and rebuilt to validate.

7) Dependency fixes triggered by cache warming
- Issue 1: `UITextView+Placeholder` shipped an invalid bundle identifier.
  - Fix: vendored a local copy under `External/UITextView-Placeholder`.
  - Applied a valid bundle ID via package settings in `Tuist/Package.swift`.
- Issue 2: `MetaTextKit` failed on Mac Catalyst due to ambiguous `XMLElement`.
  - Fix: vendored a local copy under `External/MetaTextKit`.
  - Updated references to `Fuzi.XMLElement` to disambiguate.
- Both fixes were applied by the agent once the failures were visible.

8) Runtime validation
- Installed the app on the simulator and launched it via `simctl`.
- Confirmed the app launched after the migration.

9) Cache warm and cached generation
- Ran `tuist cache` to warm binaries.
- Regenerated with `--profile all-possible` to maximize binary reuse.

10) Benchmarking
- Used hyperfine for clean builds.
- Baseline: clean build of the original Xcode project.
- Cached: clean build of the generated workspace with cache warmed and module cache preserved.
- Results:
  - Baseline: 362.020 s (single run).
  - Cached: 130.741 s mean (3 runs), min 120.861 s, max 141.355 s.
  - Improvement: 63.9 percent faster, 2.77x speedup.

11) Documentation outputs in Tuist repo
- Wrote `skill.md` as a generic migration guide. It avoids caching and benchmarking guidance and focuses on migration steps, error patterns, and runtime validation.
- Wrote `server/priv/marketing/blog/2026/02/02/migrating-mastodon-ios-to-tuist-with-codex.md` as a long form, story driven post. It includes the plan, the issues, the fixes, the benchmark, and the timeline. It explicitly states the agent performed each task.
- Removed duplicated benchmark content, added markdown links, and ensured no em dashes.

12) Repo creation and push
- Created `tuist/mastodon-ios-tuist` using the `gh` CLI.
- Added the `tuist` git remote and pushed the migration to the `main` branch.

## Benchmark commands (representative)

Baseline clean build:
- `xcodebuild -project Mastodon.xcodeproj -scheme Mastodon -configuration Debug -sdk iphonesimulator clean build`

Cached clean build:
- `tuist cache`
- `tuist generate --no-open --profile all-possible`
- `xcodebuild -workspace Mastodon.xcworkspace -scheme Mastodon -configuration Debug -sdk iphonesimulator clean build`

Hyperfine:
- `hyperfine --warmup 1 --runs 1 '<baseline clean build command>'`
- `hyperfine --warmup 1 --runs 3 '<cached clean build command>'`

## Files changed in the Mastodon repo

- `Project.swift`
- `Tuist.swift`
- `Tuist/Package.swift`
- `xcconfigs/`
- `External/UITextView-Placeholder/`
- `External/MetaTextKit/`
- `MastodonSDK/Package.swift`

## Files created or updated in the Tuist repo

- `skill.md`
- `server/priv/marketing/blog/2026/02/02/migrating-mastodon-ios-to-tuist-with-codex.md`
- `session.md`

## Timeline summary

- Total elapsed time: about four hours end to end.
- Baseline build: about six minutes.
- Cache warm: under seven minutes.
- Cached clean builds: just over two minutes on average.
- Remaining time spent on manifests, build fixes, regeneration, and runtime validation.

## Model and tooling

- Model: Codex 5.2 with GPT-5 as the underlying model.
- Benchmark tool: hyperfine.
- Build tool: xcodebuild.
- Cache tool: `tuist cache`.

## GitHub repo status

- Created `tuist/mastodon-ios-tuist` with the `gh` CLI.
- Added a `tuist` remote and pushed the migration to `main`.

## Open items

- Optional: create and push a repo under the tuist org with the migration artifacts.
- Optional: add deeper command logs if a local shell history is available and approved to use.
