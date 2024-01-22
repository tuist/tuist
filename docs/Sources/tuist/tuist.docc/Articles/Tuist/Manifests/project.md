# Project

Projects are defined in `Project.swift` files, which we refer to as manifest files.

The snippet below shows an example project manifest:

```swift
import ProjectDescription

let project = Project(
    name: "MyProject",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            sources: ["Sources/**"]
        )
    ]
)
```

## Topics

### Configuring targets

- ``Target``

### Configuring custom schemes

- ``Scheme``

### Others

- ``Options-swift.struct``
- ``TestingOptions``
- ``FileHeaderTemplate``
- ``ResourceSynthesizer``
