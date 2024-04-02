**ENUM**

# `FileElement`

**Contents**

- [Cases](#cases)
  - `glob(pattern:)`
  - `folderReference(path:)`

```swift
public enum FileElement: Codable, Equatable
```

A file element from a glob pattern or a folder reference.

- glob: a glob pattern for files to include
- folderReference: a single path to a directory

Note: For convenience, an element can be represented as a string literal
      `"some/pattern/**"` is the equivalent of `FileElement.glob(pattern: "some/pattern/**")`

## Cases
### `glob(pattern:)`

```swift
case glob(pattern: Path)
```

A file path (or glob pattern) to include. For convenience, a string literal can be used as an alternate way to specify
this option.

### `folderReference(path:)`

```swift
case folderReference(path: Path)
```

A directory path to include as a folder reference.
