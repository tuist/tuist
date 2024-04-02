**ENUM**

# `FrameworkStatus`

**Contents**

- [Cases](#cases)
  - `required`
  - `optional`

```swift
public enum FrameworkStatus: String, Codable, Hashable
```

Dependency status used by `.framework` and `.xcframework` target
dependencies

## Cases
### `required`

```swift
case required
```

Required dependency

### `optional`

```swift
case optional
```

Optional dependency (weakly linked)
