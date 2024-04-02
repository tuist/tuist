**EXTENSION**

# `Version`
```swift
extension Version: Comparable
```

## Properties
### `description`

```swift
public var description: String
```

## Methods
### `<(_:_:)`

```swift
public static func < (lhs: Version, rhs: Version) -> Bool
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| lhs | A value to compare. |
| rhs | Another value to compare. |

### `init(string:)`

```swift
public init?(string: String)
```

Create a version object from string.

- Parameters:
  - string: The string to parse.

#### Parameters

| Name | Description |
| ---- | ----------- |
| string | The string to parse. |

### `init(stringLiteral:)`

```swift
public init(stringLiteral value: String)
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| value | The value of the new instance. |