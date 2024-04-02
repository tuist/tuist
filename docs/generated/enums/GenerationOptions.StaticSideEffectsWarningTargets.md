**ENUM**

# `GenerationOptions.StaticSideEffectsWarningTargets`

```swift
public enum StaticSideEffectsWarningTargets: Codable, Equatable
```

This enum represents the targets against which Tuist will run the check for potential side effects
caused by static transitive dependencies.

## Cases
### `all`

```swift
case all
```

### `none`

```swift
case none
```

### `excluding(_:)`

```swift
case excluding([String])
```
