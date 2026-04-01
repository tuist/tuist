**ENUM**

# `TargetDependency.PackageType`

**Contents**

- [Cases](#cases)
  - `runtime`
  - `runtimeEmbedded`
  - `plugin`
  - `macro`

```swift
public enum PackageType: Codable, Hashable, Sendable
```

## Cases
### `runtime`

```swift
case runtime
```

A runtime package type represents a standard package whose sources are linked at runtime.
For example importing the framework and consuming from dependent targets.

### `runtimeEmbedded`

```swift
case runtimeEmbedded
```

A runtime embedded package type represents a package that's embedded in the product at runtime.

### `plugin`

```swift
case plugin
```

A plugin package represents a package that's loaded by the build system at compile-time to
extend the compilation process.

### `macro`

```swift
case macro
```

A macro package represents a package that contains a Swift Macro.
