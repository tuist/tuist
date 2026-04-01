**ENUM**

# `SDKType`

**Contents**

- [Cases](#cases)
  - `library`
  - `swiftLibrary`
  - `framework`

```swift
public enum SDKType: String, Codable, Hashable, Sendable
```

Dependency type used by `.sdk` target dependencies

## Cases
### `library`

```swift
case library
```

Library SDK dependency
Libraries are located in:
`{path-to-xcode}.app/Contents/Developer/Platforms/{platform}.platform/Developer/SDKs/{runtime}.sdk/usr/lib`

### `swiftLibrary`

```swift
case swiftLibrary
```

Swift library SDK dependency
Swift libraries are located in:
`{path-to-xcode}.app/Contents/Developer/Platforms/{platform}.platform/Developer/SDKs/{runtime}.sdk/usr/lib/swift`

### `framework`

```swift
case framework
```

Framework SDK dependency
