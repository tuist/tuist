**STRUCT**

# `FileList`

```swift
public struct FileList: Codable, Equatable
```

A collection of file globs.

The list of files can be initialized with a string that represents the glob pattern, or an array of strings, which represents
a list of glob patterns.

## Properties
### `globs`

```swift
public let globs: [FileListGlob]
```

Glob pattern to the files.

## Methods
### `list(_:)`

```swift
public static func list(_ globs: [FileListGlob]) -> FileList
```

Creates a file list from a collection of glob patterns.

  - glob: Relative glob pattern.
  - excluding: Relative glob patterns for excluded files.
