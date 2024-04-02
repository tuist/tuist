**STRUCT**

# `CoreDataModel`

```swift
public struct CoreDataModel: Codable, Equatable
```

A Core Data model.

## Properties
### `path`

```swift
public var path: Path
```

Relative path to the model.

### `currentVersion`

```swift
public var currentVersion: String?
```

Optional Current version (with or without extension)

## Methods
### `coreDataModel(_:currentVersion:)`

```swift
public static func coreDataModel(
    _ path: Path,
    currentVersion: String? = nil
) -> Self
```

Creates a Core Data model from a path.

- Parameters:
  - path: relative path to the Core Data model.
  - currentVersion: optional current version name (with or without the extension)
  By providing nil, it will try to read it from the .xccurrentversion file.

#### Parameters

| Name | Description |
| ---- | ----------- |
| path | relative path to the Core Data model. |
| currentVersion | optional current version name (with or without the extension) By providing nil, it will try to read it from the .xccurrentversion file. |