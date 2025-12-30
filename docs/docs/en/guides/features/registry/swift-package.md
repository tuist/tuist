---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# Swift package {#swift-package}

If you are working on a Swift package, you can use the `--replace-scm-with-registry` flag to resolve dependencies from the registry if they are available:

```bash
swift package --replace-scm-with-registry resolve
```

If you want to ensure that the registry is used every time you resolve dependencies, you will need to update `dependencies` in your `Package.swift` file to use the registry identifier instead of a URL. The registry identifier is always in the form of `{organization}.{repository}`. For example, to use the registry for the `swift-composable-architecture` package, do the following:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
