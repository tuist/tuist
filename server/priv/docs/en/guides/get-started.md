---
{
  "title": "Get started",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Pick the Tuist path that matches how your app is built today: Xcode, generated Xcode projects, Gradle, or Bazel."
}
---
# Get started {#get-started}

Pick the path that matches how your app is built today. Each one walks through what to install, how to enable caching, insights, and testing features, and how to verify the setup end-to-end. You can adopt them independently, or combine them if you ship on more than one platform.

## Xcode project {#existing-xcode-project}

Keep your existing Xcode project or workspace and add Tuist capabilities one at a time. No project generation required.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## Generated Xcode project {#generated-xcode-project}

Let Tuist define and generate your Xcode project from Swift manifests. Generated projects compress the complexity of modular Xcode projects into a concise, declarative description of the graph, and are a strict requirement for the <.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link> and <.localized_link href="/guides/features/selective-testing/generated-xcode-project">selective testing</.localized_link>.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle project {#gradle-project}

Connect a Gradle project to Tuist's remote cache, build insights, and test insights through the `dev.tuist` Gradle plugin.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Bazel project {#bazel-project}

Point a Bazel workspace at Tuist's Remote Execution API cache and Build Event Service to share cache hits and insights across your team and CI.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

Before any of these, <.localized_link href="/guides/install-tuist">install the Tuist command-line interface</.localized_link>.
