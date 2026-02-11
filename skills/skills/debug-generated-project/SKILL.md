---
name: debug-generated-project
description: Debugs issues users encounter with Tuist-generated projects by reproducing the scenario locally, building Tuist from source when needed, and triaging whether it is a bug, misconfiguration, or something that needs team input. Use when users report generation failures, build errors after generation, or unexpected project behavior.
---

# Debug Tuist Project Issue

## Quick Start

1. Ask the user to describe the issue and the project setup (targets, dependencies, configurations, platform).
2. Confirm the issue exists with the latest release by running `mise exec tuist@latest -- tuist generate` against a reproduction project.
3. If confirmed, clone the Tuist repository and build from source to test against main.
4. Triage: fix the bug and open a PR, advise on misconfiguration, or recommend the user files an issue with a reproduction.

## Step 1: Gather Context

Ask the user for:

- What command they ran (e.g. `tuist generate`)
- The error message or unexpected behavior
- **When the issue happens**: generation time, compile time, or runtime (app launch or later)
- Their project structure: targets, platforms, dependencies (SwiftPM, XCFrameworks, local packages)
- Their `Project.swift` and `Tuist.swift` content (or relevant excerpts)
- Their Tuist version (`tuist version`)

The answer to "when" determines the verification strategy:

- **Generation time**: the issue might be a Tuist bug or a project misconfiguration. Reproduce with `tuist generate`.
- **Compile time**: the generated project has incorrect build settings, missing sources, or wrong dependency wiring. Reproduce with `xcodebuild build` after generation.
- **Runtime**: the app builds but crashes or misbehaves on launch or during use. Reproduce by installing and launching on a simulator.

## Step 2: Reproduce with the latest release

Before investigating the source code, confirm the issue is not already fixed in the latest release.

### Set up a temporary reproduction project

```bash
REPRO_DIR=$(mktemp -d)
cd "$REPRO_DIR"
```

Create minimal `Tuist.swift`, `Project.swift`, and source files that reproduce the user's scenario. Keep it as small as possible while still triggering the issue.

### Run generation with the latest Tuist release

```bash
mise exec tuist@latest -- tuist generate --no-open --path "$REPRO_DIR"
```

If the issue involves dependencies, install them first:

```bash
mise exec tuist@latest -- tuist install --path "$REPRO_DIR"
```

### Check the result

- If generation succeeds and the issue is gone, tell the user to update to the latest version.
- If the issue persists, continue to Step 3.

## Step 3: Build Tuist from Source

Clone the repository and build the `tuist` executable and `ProjectDescription` library from source to test against the latest code on `main`.

```bash
TUIST_SRC=$(mktemp -d)
git clone --depth 1 https://github.com/tuist/tuist.git "$TUIST_SRC"
cd "$TUIST_SRC"
swift build --product tuist --product ProjectDescription --replace-scm-with-registry
```

The built binary will be at `.build/debug/tuist`. Use it to test the reproduction project:

```bash
"$TUIST_SRC/.build/debug/tuist" generate --no-open --path "$REPRO_DIR"
```

### If the issue is fixed on main

Tell the user the fix is already on `main`, and it hasn't been released, tell them it'll be in the nest release and point them to the relevant commit if you can identify it.

### If the issue persists on main

Continue to Step 4.

## Step 4: Triage the Issue

Investigate the Tuist source code to understand why the issue occurs.

### Outcome A: It is a bug

1. Identify the root cause in the source code.
2. Apply the fix.
3. Verify by rebuilding and running against the reproduction project:
   ```bash
   cd "$TUIST_SRC"
   swift build --product tuist --product ProjectDescription --replace-scm-with-registry
   "$TUIST_SRC/.build/debug/tuist" generate --no-open --path "$REPRO_DIR"
   ```
4. Zip the reproduction project and include it in the PR:
   ```bash
   cd "$REPRO_DIR" && cd ..
   zip -r reproduction.zip "$(basename "$REPRO_DIR")" -x '*.xcodeproj/*' -x '*.xcworkspace/*' -x 'Derived/*' -x '.build/*'
   ```
5. Open a PR on the Tuist repository with:
   - The fix
   - The zipped reproduction project attached or committed as a fixture
   - A clear description of the root cause and how to verify the fix

### Outcome B: It is a misconfiguration

Tell the user what is wrong and how to fix it. Common misconfigurations:

- Missing `tuist install` before `tuist generate` when using external dependencies
- Incorrect source or resource globs that exclude or double-include files
- Mismatched build configurations between the project and external dependencies
- Wrong product types for dependencies (static vs dynamic)
- Missing `-ObjC` linker flag for Objective-C dependencies
- Using `sources` and `resources` globs together with `buildableFolders`

Provide the corrected manifest snippet so the user can apply the fix directly.

### Outcome C: Unclear or needs team input

If you cannot determine whether it is a bug or misconfiguration, recommend the user:

1. Open a GitHub issue at https://github.com/tuist/tuist/issues with:
   - The reproduction project (zipped)
   - The error output
   - Their Tuist version and environment details

Provide a summary of what you investigated and what you ruled out, so the user does not have to repeat the triage.

## Build Verification

When testing a fix, always verify the full cycle:

```bash
# Build the patched tuist
cd "$TUIST_SRC"
swift build --product tuist --product ProjectDescription --replace-scm-with-registry

# Install dependencies if needed
"$TUIST_SRC/.build/debug/tuist" install --path "$REPRO_DIR"

# Generate the project
"$TUIST_SRC/.build/debug/tuist" generate --no-open --path "$REPRO_DIR"

# Build the generated project
xcodebuild build \
  -workspace "$REPRO_DIR"/*.xcworkspace \
  -scheme <scheme> \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro"
```

## Runtime Verification

When the user reports a runtime issue (crash on launch, missing resources at runtime, wrong bundle structure, or unexpected behavior), you must go beyond building and actually launch the app on a simulator.

### Launch and monitor for crashes

```bash
# Boot a simulator
xcrun simctl boot "iPhone 16 Pro" 2>/dev/null || true

# Build for the simulator
xcodebuild build \
  -workspace "$REPRO_DIR"/*.xcworkspace \
  -scheme <scheme> \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  -derivedDataPath "$REPRO_DIR/DerivedData"

# Install the app
xcrun simctl install booted "$REPRO_DIR/DerivedData/Build/Products/Debug-iphonesimulator/<AppName>.app"

# Launch and monitor — this will print crash info if the app terminates abnormally
xcrun simctl launch --console-pty booted <bundle-identifier>
```

The `--console-pty` flag streams the app's stdout/stderr so you can observe logs and crash output directly. Watch for:

- **Immediate crash on launch**: usually a missing framework, wrong bundle ID, missing entitlements, or stripped ObjC categories (`-ObjC` linker flag missing)
- **Crash after a few seconds**: often missing resources (images, storyboards, XIBs, asset catalogs) or a bundle structure mismatch
- **Runtime misbehavior without crash**: wrong resource paths, missing localization files, or incorrect Info.plist values

### Check crash logs

If the app crashes without useful console output, pull the crash log:

```bash
# List recent crash logs for the app
find ~/Library/Logs/DiagnosticReports -name "<AppName>*" -newer "$REPRO_DIR" -print
```

Read the crash log to identify the crashing thread and the faulting symbol.

## Done Checklist

- Gathered enough context from the user to reproduce the issue
- Determined whether the issue is at generation time, compile time, or runtime
- Confirmed whether the issue exists in the latest release
- Tested against Tuist built from source (main branch)
- If runtime issue: launched the app on a simulator and verified the crash or misbehavior
- Triaged the issue as a bug, misconfiguration, or unclear
- If bug: applied fix, verified it, and opened a PR with reproduction project
- If misconfiguration: provided corrected manifest to the user
- If unclear: gave the user a summary and recommended next steps
