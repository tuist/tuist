**ENUM**

# `LinkingStatus`

**Contents**

- [Cases](#cases)
  - `required`
  - `optional`
  - `none`

```swift
public enum LinkingStatus: String, Codable, Hashable, Sendable
```

Dependency status used by dependencies

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

### `none`

```swift
case none
```

Skip linking
