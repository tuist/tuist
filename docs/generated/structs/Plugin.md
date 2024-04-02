**STRUCT**

# `Plugin`

```swift
public struct Plugin: Codable, Equatable
```

A plugin representation.

Supported plugins include:
- ProjectDescriptionHelpers
    - These are plugins designed to be usable by any other manifest excluding `Config` and `Plugin`.
    - The source files for these helpers must live under a ProjectDescriptionHelpers directory in the location where `Plugin`
manifest lives.

## Properties
### `name`

```swift
public let name: String
```

The name of the `Plugin`.

## Methods
### `init(name:)`

```swift
public init(name: String)
```

Creates a new plugin.
- Parameters:
    - name: The name of the plugin.

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | The name of the plugin. |