**STRUCT**

# `Tuist`

**Contents**

- [Properties](#properties)
  - `project`
  - `fullHandle`
  - `url`
- [Methods](#methods)
  - `init(compatibleXcodeVersions:cloud:fullHandle:url:swiftVersion:plugins:generationOptions:installOptions:)`
  - `init(fullHandle:url:project:)`

```swift
public struct Tuist: Codable, Equatable, Sendable
```

## Properties
### `project`

```swift
public let project: TuistProject
```

Configures the project Tuist will interact with.
When no project is provided, Tuist defaults to the workspace or project in the current directory.

### `fullHandle`

```swift
public let fullHandle: String?
```

The full project handle such as tuist-org/tuist.

### `url`

```swift
public let url: String
```

The base URL that points to the Tuist server.

## Methods
### `init(compatibleXcodeVersions:cloud:fullHandle:url:swiftVersion:plugins:generationOptions:installOptions:)`

```swift
public init(
    compatibleXcodeVersions: CompatibleXcodeVersions = .all,
    cloud: Cloud? = nil,
    fullHandle: String? = nil,
    url: String = "https://tuist.dev",
    swiftVersion: Version? = nil,
    plugins: [PluginLocation] = [],
    generationOptions: GenerationOptions = .options(),
    installOptions: InstallOptions = .options()
)
```

Creates a tuist configuration.

- Parameters:
  - compatibleXcodeVersions: List of Xcode versions the project is compatible with.
  - cloud: Cloud configuration.
  - swiftVersion: The version of Swift that will be used by Tuist.
  - plugins: A list of plugins to extend Tuist.
  - generationOptions: List of options to use when generating the project.
  - installOptions: List of options to use when running `tuist install`.

#### Parameters

| Name | Description |
| ---- | ----------- |
| compatibleXcodeVersions | List of Xcode versions the project is compatible with. |
| cloud | Cloud configuration. |
| swiftVersion | The version of Swift that will be used by Tuist. |
| plugins | A list of plugins to extend Tuist. |
| generationOptions | List of options to use when generating the project. |
| installOptions | List of options to use when running `tuist install`. |

### `init(fullHandle:url:project:)`

```swift
public init(
    fullHandle: String? = nil,
    url: String = "https://tuist.dev",
    project: TuistProject
)
```
