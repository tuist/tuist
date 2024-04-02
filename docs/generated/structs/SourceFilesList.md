**STRUCT**

# `SourceFilesList`

```swift
public struct SourceFilesList: Codable, Equatable
```

A collection of source file globs.

## Properties
### `globs`

```swift
public var globs: [SourceFileGlob]
```

List glob patterns.

## Methods
### `sourceFilesList(globs:)`

```swift
public static func sourceFilesList(globs: [SourceFileGlob]) -> Self
```

Creates the source files list with the glob patterns.

- Parameter globs: Glob patterns.

#### Parameters

| Name | Description |
| ---- | ----------- |
| globs | Glob patterns. |

### `sourceFilesList(globs:)`

```swift
public static func sourceFilesList(globs: [String]) -> Self
```

Creates the source files list with the glob patterns as strings.

- Parameter globs: Glob patterns.

#### Parameters

| Name | Description |
| ---- | ----------- |
| globs | Glob patterns. |

### `paths(_:)`

```swift
public static func paths(_ paths: [Path]) -> SourceFilesList
```

Returns a sources list from a list of paths.
- Parameter paths: Source paths.

#### Parameters

| Name | Description |
| ---- | ----------- |
| paths | Source paths. |