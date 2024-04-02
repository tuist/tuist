**STRUCT**

# `TemplateString.StringInterpolation`

**Contents**

- [Methods](#methods)
  - `init(literalCapacity:interpolationCount:)`
  - `appendLiteral(_:)`
  - `appendInterpolation(_:)`

```swift
public struct StringInterpolation: StringInterpolationProtocol
```

## Methods
### `init(literalCapacity:interpolationCount:)`

```swift
public init(literalCapacity _: Int, interpolationCount _: Int)
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| literalCapacity | The approximate size of all literal segments combined. This is meant to be passed to `String.reserveCapacity(_:)`; it may be slightly larger or smaller than the sum of the counts of each literal segment. |
| interpolationCount | The number of interpolations which will be appended. Use this value to estimate how much additional capacity will be needed for the interpolated segments. |

### `appendLiteral(_:)`

```swift
public mutating func appendLiteral(_ literal: String)
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| literal | A string literal containing the characters that appear next in the string literal. |

### `appendInterpolation(_:)`

```swift
public mutating func appendInterpolation(_ token: TemplateString.Token)
```
