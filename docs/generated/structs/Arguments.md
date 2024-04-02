**STRUCT**

# `Arguments`

**Contents**

- [Properties](#properties)
  - `environmentVariables`
  - `launchArguments`
- [Methods](#methods)
  - `arguments(environmentVariables:launchArguments:)`

```swift
public struct Arguments: Equatable, Codable
```

A collection of arguments and environment variables.

## Properties
### `environmentVariables`

```swift
public var environmentVariables: [String: EnvironmentVariable]
```

### `launchArguments`

```swift
public var launchArguments: [LaunchArgument]
```

## Methods
### `arguments(environmentVariables:launchArguments:)`

```swift
public static func arguments(
    environmentVariables: [String: EnvironmentVariable] = [:],
    launchArguments: [LaunchArgument] = []
) -> Self
```
