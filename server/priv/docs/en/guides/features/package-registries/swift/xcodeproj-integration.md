---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "Use the Tuist Registry with XcodeProj-based package integration in generated projects."
}
---
# Generated project with the XcodeProj-based package integration {#generated-project-with-xcodeproj-based-integration}

When using the <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj-based integration</.localized_link>, you can use the `--replace-scm-with-registry` flag to resolve dependencies from the registry if they are available. Add it to the `installOptions` in your `Tuist.swift` file:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

If you want to ensure that the registry is used every time you resolve dependencies, you will need to update `dependencies` in your `Tuist/Package.swift` file to use the registry identifier instead of a URL.

<!-- @snippet: ./_registry-identifier -->
