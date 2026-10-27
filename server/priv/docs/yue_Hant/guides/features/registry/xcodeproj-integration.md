---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# Generated project with the XcodeProj-based package integration {#generated-project-with-xcodeproj-based-integration}

When using the
<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj-based integration</LocalizedLink>, you can use the ``--replace-scm-with-registry``
flag to resolve dependencies from the registry if they are available. Add it to
the `installOptions` in your `Tuist.swift` file:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

If you want to ensure that the registry is used every time you resolve
dependencies, you will need to update `dependencies` in your
`Tuist/Package.swift` file to use the registry identifier instead of a URL. The
registry identifier is always in the form of `{organization}.{repository}`. For
example, to use the registry for the `swift-composable-architecture` package, do
the following:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
