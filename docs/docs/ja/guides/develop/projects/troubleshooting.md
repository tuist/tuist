---
title: Troubleshooting
titleTemplate: ":title | Projects | Tuist"
description: Troubleshoot common issues when working with Tuist projects.
---

# Troubleshooting

This page lists common issues that you might encounter when working with Tuist projects and provides solutions to help you resolve them.

## Couldn’t be copied to “Signatures” because an item with the same name already exists

When linking pre-compiled XCFrameworks, either through Tuist's integration of Swift Packages, or manually, you might come across the error `Couldn’t be copied to “Signatures” because an item with the same name already exists` when archiving the app.
This seems to be [a bug in Xcode](https://github.com/CocoaPods/CocoaPods/issues/12022) ([radar](https://feedbackassistant.apple.com/feedback/15554623)), which internally constructs a build graph with duplicated tasks for the same XCFrameworks, causing the error. Until the error gets fixed, or we find a graph setup that doesn't trigger it, you can work around it by adding a `Run Script` phase to the target that archives the app, with the following content:

```swift
let target = Target(
  // Other props
  scripts: [
  .post(
      script: """
      find "$BUILT_PRODUCTS_DIR" -name "*.signature" -type f | xargs -r rm
      """,
      name: "Strip signatures from pre-compiled XCFrameworks",
      runForInstallBuildsOnly: true
    )
  ]
)
```
