---
{
  "title": "Xcode previews",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Share application previews from existing Xcode projects and Tuist-generated projects."
}
---
# Xcode previews

Build your application, then use `tuist share` to publish it to your Tuist project. Connect your project first using the <.localized_link href="/guides/get-started/existing-xcode-project">existing Xcode project</.localized_link> or <.localized_link href="/guides/get-started/generated-xcode-project">generated project</.localized_link> guide.

## Build and share

For a Tuist-generated project:

```bash
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace \
  -configuration Debug -sdk iphonesimulator
tuist share App
```

For an existing Xcode project:

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -sdk iphonesimulator
tuist share App --configuration Debug --platforms iOS
```

Replace the scheme, project, and workspace names with your own. To share a Release build, use `-configuration Release` when building and `--configuration Release` when sharing.

## Physical devices

You are responsible for signing device builds with a provisioning profile that allows installation on the recipient's device. Build with a device destination instead of the simulator SDK:

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -destination 'generic/platform=iOS'
tuist share App --configuration Debug --platforms iOS
```

You can also share an already exported IPA:

```bash
tuist share App.ipa
```

Recipients can open an IPA preview link on their mobile device to install the application. Authentication and the project's preview visibility still apply.

## CI and build numbers

Use your existing <.localized_link href="/guides/integrations/continuous-integration">CI authentication</.localized_link> and make `CFBundleVersion` unique for each new build. For example, use GitHub Actions' <code v-pre>${{ github.run_number }}</code>. Uploading the same binary and build number again through `tuist share` fails rather than creating a duplicate.

```bash
tuist share App --track beta --release-notes "Fix sign-in"
```

See the <.localized_link href="/guides/features/previews">Previews overview</.localized_link> for running previews, tracks, release notes, visibility, and the companion apps.
