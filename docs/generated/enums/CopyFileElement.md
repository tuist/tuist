**ENUM**

# `CopyFileElement`

```swift
public enum CopyFileElement: Codable, Equatable
```

A file element from a glob pattern or a folder reference which is conditionally applied to specific platforms.

## Cases
### `glob(pattern:condition:)`

```swift
case glob(pattern: Path, condition: PlatformCondition? = nil)
```

A file path (or glob pattern) to include with an optional PlatformCondition to control which platforms it applies to.

### `folderReference(path:condition:)`

```swift
case folderReference(path: Path, condition: PlatformCondition? = nil)
```

A directory path to include as a folder reference with an optional PlatformCondition to control which platforms it applies
to.
