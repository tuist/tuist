---
title: Command Line Tools
slug: '/examples/command-line-tools'
description: Learn how to use Tuist to define a CLI tools that might contain static dependencies.
---

Tuist supports defining CLI tools that might contain static dependencies. Below there's an example of how you'd define a project with a CLI target:

```swift
let project = Project(
    name: "CLITool",
    targets: [
        Target(
            name: "CLITool",
            platform: .macOS,
            product: .commandLineTool,
            bundleId: "io.tuist.App",
            infoPlist: .default,
            sources: ["Sources/**"],
            dependencies: [.target(name: "StaticLib")]
        ),
        Target(
            name: "StaticLib",
            platform: .macOS,
            product: .staticLibrary,
            bundleId: "io.tuist.StaticLib",
            infoPlist: .default,
            sources: ["StaticLib/Sources/**"]
        ),
    ]
)
```
