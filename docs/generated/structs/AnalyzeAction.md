**STRUCT**

# `AnalyzeAction`

```swift
public struct AnalyzeAction: Equatable, Codable
```

An action that analyzes the built products.

It's initialized with the `.analyzeAction` static method

## Properties
### `configuration`

```swift
public var configuration: ConfigurationName
```

Indicates the build configuration the product should be analyzed with.

## Methods
### `analyzeAction(configuration:)`

```swift
public static func analyzeAction(configuration: ConfigurationName) -> AnalyzeAction
```

Returns an analyze action.
- Parameter configuration: Indicates the build configuration the product should be analyzed with.
- Returns: Analyze action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| configuration | Indicates the build configuration the product should be analyzed with. |