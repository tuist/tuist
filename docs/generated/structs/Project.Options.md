**STRUCT**

# `Project.Options`

```swift
public struct Options: Codable, Equatable
```

Options to configure a project.

## Properties
### `automaticSchemesOptions`

```swift
public var automaticSchemesOptions: AutomaticSchemesOptions
```

Configures automatic target schemes generation.

### `defaultKnownRegions`

```swift
public var defaultKnownRegions: [String]?
```

Configures the default known regions

### `developmentRegion`

```swift
public var developmentRegion: String?
```

Configures the development region.

### `disableBundleAccessors`

```swift
public var disableBundleAccessors: Bool
```

Disables generating Bundle accessors.

### `disableShowEnvironmentVarsInScriptPhases`

```swift
public var disableShowEnvironmentVarsInScriptPhases: Bool
```

Suppress logging of environment in Run Script build phases.

### `disableSynthesizedResourceAccessors`

```swift
public var disableSynthesizedResourceAccessors: Bool
```

Disable synthesized resource accessors.

### `textSettings`

```swift
public var textSettings: TextSettings
```

Configures text settings.

### `xcodeProjectName`

```swift
public var xcodeProjectName: String?
```

Configures the name of the generated .xcodeproj.

## Methods
### `options(automaticSchemesOptions:defaultKnownRegions:developmentRegion:disableBundleAccessors:disableShowEnvironmentVarsInScriptPhases:disableSynthesizedResourceAccessors:textSettings:xcodeProjectName:)`

```swift
public static func options(
    automaticSchemesOptions: AutomaticSchemesOptions = .enabled(),
    defaultKnownRegions: [String]? = nil,
    developmentRegion: String? = nil,
    disableBundleAccessors: Bool = false,
    disableShowEnvironmentVarsInScriptPhases: Bool = false,
    disableSynthesizedResourceAccessors: Bool = false,
    textSettings: TextSettings = .textSettings(),
    xcodeProjectName: String? = nil
) -> Self
```
