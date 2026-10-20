---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect an existing Xcode project to Tuist for the Xcode compilation cache, build and test insights, bundle-size tracking, and preview links, without adopting project generation."
}
---
# Xcode project {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

Follow this path when you want to keep your `.xcodeproj` or `.xcworkspace` exactly as it is and pull in Tuist's capabilities without adopting project generation. Every section below opens with what's missing today and then walks you through the feature that fills the gap.

## Prerequisites

- macOS with **Xcode 26 or later** (the compilation cache and modern insights depend on it).
- The <.localized_link href="/guides/install-tuist">Tuist command-line interface</.localized_link>.

## Connect the project

Run `tuist init` at the repository root. Choose **Integrate `<YourApp>`** when Tuist detects your workspace, then authenticate in the browser and pick the account that should own the project. Tuist writes a `Tuist.swift` at the root that pins the project handle so your teammates and CI share the same connection. Commit it.

If you're driving this from a coding agent or a script, run `tuist auth login` first (the browser flow waits for you to press Enter), then use the non-interactive form:

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

Everything below is optional and independent.

## Xcode compilation cache

Xcode 26 ships with a per-file compilation cache, but its store lives inside a machine's `DerivedData`. A clean build populates it locally; teammates and CI runners rebuild from scratch because they don't see that store.

`tuist setup cache` points Xcode's compilation cache at the shared Tuist cache network. A hit on any developer machine or CI run then benefits every other machine building the same revision.

```bash
tuist setup cache
```

Build in Xcode. Wipe Derived Data, build again on a second machine or a CI runner. The second build finishes in a fraction of the time and Xcode's build report shows the compilation cache hits.

## Build insights

Xcode records per-target build durations in the log and in the build report. Neither is aggregated across runs or across machines. A build-time regression that lands in one PR usually surfaces only as a slower CI overall, with no obvious signal about which target caused it or when.

Build insights records every build's duration and phase timings so the trend is visible on the dashboard. It's a one-line post-action on your scheme:

1. In Xcode: **Product → Scheme → Edit Scheme…**
2. Expand **Build → Post-actions**, click **+**, choose **New Run Script Action**.
3. Under **Provide build settings from**, pick your app target.
4. Paste the line that matches how you installed Tuist:
   ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcode's scheme scripts don't inherit your shell's `PATH`, so mise's shim isn't found on its own. The Mise line above calls mise by its absolute path and asks it to load config from `$SRCROOT` so it picks the version pinned in your project.
5. Build once. The build appears on the dashboard's **Builds** tab within seconds.

## Test insights

Xcode's test log lists per-test results one run at a time. It doesn't aggregate the cross-run signal you actually need: how often a test fails, how much slower it got last week, whether it fails only on certain simulators. A test drifting from reliable to flaky over ten CI runs looks the same as a single unlucky run.

Test insights records every test's outcome and duration and correlates results across runs. Slow tests, failures, and flakes surface on the dashboard's **Tests** tab.

1. **Product → Scheme → Edit Scheme…**
2. **Test → Post-actions → +** → **New Run Script Action**.
3. **Provide build settings from** your app target.
4. Paste:
   ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
   ```
   ```bash [Homebrew]
   tuist inspect test
   ```
   <!-- -->
   :::
5. Run the test action once. Results appear on the dashboard's **Tests** tab.

## Bundle insights

An IPA's install and download size shift with every asset added and every symbol linked in. Xcode reports the sizes on demand in **Product → Show Archive**, not as a series. A PR that adds a large asset is indistinguishable from any other PR in the merge queue.

Bundle insights records install and download sizes for every analyzed build and can fail a PR check when a per-branch threshold is breached. Add this to your CI right after your build step:

```bash
tuist inspect bundle App.ipa
```

Open **Bundle insights** on the dashboard to see the trend and configure thresholds.

## Previews

TestFlight adds a build-and-review round trip on every share. Sending a signed `.ipa` directly requires the recipient's UDID in the provisioning profile. Neither is convenient for a designer or QA who just wants to try the current branch.

Previews turns a build into a shareable link that runs on a simulator or device with one command:

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

Send the link. Recipients run it with `tuist run <url>` or the Tuist macOS app.

## Bring the team along

The cache and insights compound with the number of people connected to the project. Invite your teammates to the organization from the account settings on the dashboard, and set up <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> (Google, Okta, Microsoft) so onboarding is a click rather than a per-person `tuist auth login`.

## Where to go next

If you outgrow this path, the biggest step is Tuist-generated projects. That's a real change (targets described in Swift manifests instead of an `.xcodeproj`), but it's what unlocks the module cache and selective testing. Covered end-to-end in the <.localized_link href="/guides/get-started/generated-xcode-project">Generated Xcode project</.localized_link> guide.
