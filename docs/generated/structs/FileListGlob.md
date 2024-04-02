**STRUCT**

# `FileListGlob`

```swift
public struct FileListGlob: Codable, Equatable
```

A glob pattern that refers to files.

## Properties
### `glob`

```swift
public var glob: Path
```

The path with a glob pattern.

### `excluding`

```swift
public var excluding: [Path]
```

The excluding paths.

## Methods
### `glob(_:excluding:)`

```swift
public static func glob(
    _ glob: Path,
    excluding: [Path] = []
) -> FileListGlob
```

Returns a generic file list glob.
- Parameters:
  - glob: The path with a glob pattern.
  - excluding: The excluding paths.

#### Parameters

| Name | Description |
| ---- | ----------- |
| glob | The path with a glob pattern. |
| excluding | The excluding paths. |

### `glob(_:excluding:)`

```swift
public static func glob(
    _ glob: Path,
    excluding: Path?
) -> FileListGlob
```

Returns a file list glob with an optional excluding path.
