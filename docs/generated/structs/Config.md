**STRUCT**

# `Config`

```swift
public struct Config: Codable, Equatable
```

The configuration of your environment.

Tuist can be configured through a shared `Config.swift` manifest.
When Tuist is executed, it traverses up the directories to find a `Tuist` directory containing a `Config.swift` file.
Defining a configuration manifest is not required, but recommended to ensure a consistent behaviour across all the projects
that are part of the repository.

The example below shows a project that has a global `Config.swift` file that will be used when Tuist is run from any of the
subdirectories:

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
    compatibleXcodeVersions: ["14.2"],
    swiftVersion: "5.9.0"
)
```

## Properties
### `generationOptions`

```swift
public let generationOptions: GenerationOptions
```

Generation options.

### `compatibleXcodeVersions`

```swift
public let compatibleXcodeVersions: CompatibleXcodeVersions
```

Set the versions of Xcode that the project is compatible with.

### `plugins`

```swift
public let plugins: [PluginLocation]
```

List of `Plugin`s used to extend Tuist.

### `cloud`

```swift
public let cloud: Cloud?
```

Cloud configuration.

### `swiftVersion`

```swift
public let swiftVersion: Version?
```

The Swift tools versions that will be used by Tuist to fetch external dependencies.
If `nil` is passed then Tuist will use the environment’s version.
- Note: This **does not** control the `SWIFT_VERSION` build setting in regular generated projects, for this please use
`Project.settings`
or `Target.settings` as needed.

## Methods
### `init(compatibleXcodeVersions:cloud:swiftVersion:plugins:generationOptions:)`

```swift
public init(
    compatibleXcodeVersions: CompatibleXcodeVersions = .all,
    cloud: Cloud? = nil,
    swiftVersion: Version? = nil,
    plugins: [PluginLocation] = [],
    generationOptions: GenerationOptions = .options()
)
```

Creates a tuist configuration.

- Parameters:
  - compatibleXcodeVersions: List of Xcode versions the project is compatible with.
  - cloud: Cloud configuration.
  - swiftVersion: The version of Swift that will be used by Tuist.
  - plugins: A list of plugins to extend Tuist.
  - generationOptions: List of options to use when generating the project.

#### Parameters

| Name | Description |
| ---- | ----------- |
| compatibleXcodeVersions | List of Xcode versions the project is compatible with. |
| cloud | Cloud configuration. |
| swiftVersion | The version of Swift that will be used by Tuist. |
| plugins | A list of plugins to extend Tuist. |
| generationOptions | List of options to use when generating the project. |