**STRUCT**

# `Settings`

**Contents**

- [Properties](#properties)
  - `base`
  - `configurations`
  - `defaultSettings`
- [Methods](#methods)
  - `settings(base:debug:release:defaultSettings:)`
  - `settings(base:configurations:defaultSettings:)`

```swift
public struct Settings: Equatable, Codable
```

A group of settings configuration.

## Properties
### `base`

```swift
public var base: SettingsDictionary
```

A dictionary with build settings that are inherited from all the configurations.

### `configurations`

```swift
public var configurations: [Configuration]
```

### `defaultSettings`

```swift
public var defaultSettings: DefaultSettings
```

## Methods
### `settings(base:debug:release:defaultSettings:)`

```swift
public static func settings(
    base: SettingsDictionary = [:],
    debug: SettingsDictionary = [:],
    release: SettingsDictionary = [:],
    defaultSettings: DefaultSettings = .recommended
) -> Settings
```

Creates settings with default.configurations `Debug` and `Release`

- Parameters:
  - base: A dictionary with build settings that are inherited from all the configurations.
  - debug: The debug configuration settings.
  - release: The release configuration settings.
  - defaultSettings: An enum specifying the set of default settings.

- Note: To specify custom configurations (e.g. `Debug`, `Beta` & `Release`) or to specify xcconfigs, you can use the
alternate static method
        `.settings(base:configurations:defaultSettings:)`

- seealso: Configuration
- seealso: DefaultSettings

#### Parameters

| Name | Description |
| ---- | ----------- |
| base | A dictionary with build settings that are inherited from all the configurations. |
| debug | The debug configuration settings. |
| release | The release configuration settings. |
| defaultSettings | An enum specifying the set of default settings. |

### `settings(base:configurations:defaultSettings:)`

```swift
public static func settings(
    base: SettingsDictionary = [:],
    configurations: [Configuration],
    defaultSettings: DefaultSettings = .recommended
) -> Settings
```

Creates settings with any number of configurations.

- Parameters:
  - base: A dictionary with build settings that are inherited from all the configurations.
  - configurations: A list of configurations.
  - defaultSettings: An enum specifying the set of default settings.

- Note: Configurations shouldn't be empty, please use the alternate static method
        `.settings(base:debug:release:defaultSettings:)` to leverage the default configurations
         if you don't have any custom configurations.

- seealso: Configuration
- seealso: DefaultSettings

#### Parameters

| Name | Description |
| ---- | ----------- |
| base | A dictionary with build settings that are inherited from all the configurations. |
| configurations | A list of configurations. |
| defaultSettings | An enum specifying the set of default settings. |