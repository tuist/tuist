**STRUCT**

# `Configuration`

```swift
public struct Configuration: Equatable, Codable
```

A the build settings and the .xcconfig file of a project or target. It is initialized with either the `.debug` or `.release`
static method.

## Properties
### `name`

```swift
public var name: ConfigurationName
```

### `variant`

```swift
public var variant: Variant
```

### `settings`

```swift
public var settings: SettingsDictionary
```

### `xcconfig`

```swift
public var xcconfig: Path?
```

## Methods
### `debug(name:settings:xcconfig:)`

```swift
public static func debug(
    name: ConfigurationName,
    settings: SettingsDictionary = [:],
    xcconfig: Path? = nil
) -> Configuration
```

Returns a debug configuration.

- Parameters:
  - name: The name of the configuration to use
  - settings: The base build settings to apply
  - xcconfig: The xcconfig file to associate with this configuration
- Returns: A debug `CustomConfiguration`

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | The name of the configuration to use |
| settings | The base build settings to apply |
| xcconfig | The xcconfig file to associate with this configuration |

### `release(name:settings:xcconfig:)`

```swift
public static func release(
    name: ConfigurationName,
    settings: SettingsDictionary = [:],
    xcconfig: Path? = nil
) -> Configuration
```

Creates a release configuration

- Parameters:
  - name: The name of the configuration to use
  - settings: The base build settings to apply
  - xcconfig: The xcconfig file to associate with this configuration
- Returns: A release `CustomConfiguration`

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | The name of the configuration to use |
| settings | The base build settings to apply |
| xcconfig | The xcconfig file to associate with this configuration |