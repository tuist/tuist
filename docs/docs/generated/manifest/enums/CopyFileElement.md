**ENUM**

# `CopyFileElement`

**Contents**

- [Cases](#cases)
  - `glob(pattern:condition:codeSignOnCopy:)`
  - `folderReference(path:condition:codeSignOnCopy:)`

```swift
public enum CopyFileElement: Codable, Equatable, Sendable
```

A file element from a glob pattern or a folder reference which is conditionally applied to specific platforms with an optional
"Code Sign On Copy" flag.

## Cases
### `glob(pattern:condition:codeSignOnCopy:)`

```swift
case glob(pattern: Path, condition: PlatformCondition? = nil, codeSignOnCopy: Bool = false)
```

A file path (or glob pattern) to include with an optional PlatformCondition to control which platforms it applies.
"Code Sign on Copy" can be optionally enabled for the glob.

### `folderReference(path:condition:codeSignOnCopy:)`

```swift
case folderReference(path: Path, condition: PlatformCondition? = nil, codeSignOnCopy: Bool = false)
```

A directory path to include as a folder reference with an optional PlatformCondition to control which platforms it applies
to. "Code Sign on Copy" can be optionally enabled for the folder reference.
