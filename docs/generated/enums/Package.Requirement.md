**ENUM**

# `Package.Requirement`

**Contents**

- [Cases](#cases)
  - `upToNextMajor(from:)`
  - `upToNextMinor(from:)`
  - `range(from:to:)`
  - `exact(_:)`
  - `branch(_:)`
  - `revision(_:)`

```swift
public enum Requirement: Codable, Equatable
```

## Cases
### `upToNextMajor(from:)`

```swift
case upToNextMajor(from: Version)
```

### `upToNextMinor(from:)`

```swift
case upToNextMinor(from: Version)
```

### `range(from:to:)`

```swift
case range(from: Version, to: Version)
```

### `exact(_:)`

```swift
case exact(Version)
```

### `branch(_:)`

```swift
case branch(String)
```

### `revision(_:)`

```swift
case revision(String)
```
