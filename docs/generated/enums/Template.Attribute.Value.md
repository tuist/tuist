**ENUM**

# `Template.Attribute.Value`

```swift
public indirect enum Value: Codable, Equatable
```

This represents the default value type of Attribute

## Cases
### `string(_:)`

```swift
case string(String)
```

It represents a string value.

### `integer(_:)`

```swift
case integer(Int)
```

It represents an integer value.

### `real(_:)`

```swift
case real(Double)
```

It represents a floating value.

### `boolean(_:)`

```swift
case boolean(Bool)
```

It represents a boolean value.

### `dictionary(_:)`

```swift
case dictionary([String: Value])
```

It represents a dictionary value.

### `array(_:)`

```swift
case array([Value])
```

It represents an array value.
