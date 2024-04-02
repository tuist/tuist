**ENUM**

# `SDKStatus`

**Contents**

- [Cases](#cases)
  - `required`
  - `optional`

```swift
public enum SDKStatus: String, Codable, Hashable
```

Dependency status used by `.sdk` target dependencies

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
