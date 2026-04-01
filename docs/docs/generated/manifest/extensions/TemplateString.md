**EXTENSION**

# `TemplateString`
```swift
extension TemplateString: ExpressibleByStringLiteral
```

## Properties
### `description`

```swift
public var description: String
```

## Methods
### `init(stringLiteral:)`

```swift
public init(stringLiteral: String)
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| value | The value of the new instance. |

### `init(stringInterpolation:)`

```swift
public init(stringInterpolation: StringInterpolation)
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| stringInterpolation | An instance of `StringInterpolation` which has had each segment of the string literal appended to it. |