**ENUM**

# `ResourceFileElement`

**Contents**

- [Cases](#cases)
  - `glob(pattern:excluding:tags:inclusionCondition:)`
  - `folderReference(path:tags:inclusionCondition:)`

```swift
public enum ResourceFileElement: Codable, Equatable
```

A resource file element from a glob pattern or a folder reference.

- glob: a glob pattern for files to include
- folderReference: a single path to a directory

Note: For convenience, an element can be represented as a string literal
      `"some/pattern/**"` is the equivalent of `ResourceFileElement.glob(pattern: "some/pattern/**")`

## Cases
### `glob(pattern:excluding:tags:inclusionCondition:)`

```swift
case glob(pattern: Path, excluding: [Path] = [], tags: [String] = [], inclusionCondition: PlatformCondition? = nil)
```

A glob pattern of files to include and ODR tags

### `folderReference(path:tags:inclusionCondition:)`

```swift
case folderReference(path: Path, tags: [String] = [], inclusionCondition: PlatformCondition? = nil)
```

Relative path to a directory to include as a folder reference and ODR tags
