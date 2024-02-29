# Config

Use the Config manifest file to configure Tuist's functionalities globally.

Tuist can be configured through a shared `Config.swift` manifest.
When Tuist is executed, it traverses up the directories to find a `Tuist` directory containing a `Config.swift` file.
Defining a configuration manifest is not required, but recommended to ensure a consistent behaviour across all the projects that are part of the repository.

The example below shows a project that has a global `Config.swift` file that will be used when Tuist is run from any of the subdirectories:

```bash
/Workspace.swift
/Tuist/Config.swift # Configuration manifest
/Framework/Project.swift
/App/Project.swift
```

That way, when executing Tuist in any of the subdirectories, it will use the shared configuration.

The snippet below shows an example configuration manifest:

```swift
import ProjectDescription

let config = Config(
    compatibleXcodeVersions: ["10.3"],
    swiftVersion: "5.4.0",
    generationOptions: .options(
        xcodeProjectName: "SomePrefix-\(.projectName)-SomeSuffix",
        organizationName: "Tuist",
        developmentRegion: "de"
    )
)
```

## Topics

### Related

- ``Cache``
- ``Cloud``
- ``CompatibleXcodeVersions``
- ``Plugin``
- ``PluginLocation``
- ``Version``
