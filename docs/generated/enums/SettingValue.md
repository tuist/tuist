**ENUM**

# `SettingValue`

```swift
public enum SettingValue: ExpressibleByStringInterpolation, ExpressibleByArrayLiteral, ExpressibleByBooleanLiteral, Equatable,
    Codable
```

A value or a collection of values used for settings configuration.

## Cases
### `string(_:)`

```swift
case string(String)
```

### `array(_:)`

```swift
case array([String])
```

## Methods
### `init(stringLiteral:)`

```swift
public init(stringLiteral value: String)
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| value | The value of the new instance. |

### `init(arrayLiteral:)`

```swift
public init(arrayLiteral elements: String...)
```

### `init(booleanLiteral:)`

```swift
public init(booleanLiteral value: Bool)
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| value | The value of the new instance. |

### `init(_:)`

```swift
public init<T>(_ stringRawRepresentable: T) where T: RawRepresentable, T.RawValue == String
```
