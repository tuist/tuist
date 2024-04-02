**ENUM**

# `Parser.Option`

```swift
public enum Option: Equatable, Codable
```

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

### `double(_:)`

```swift
case double(Double)
```

It represents a floating value.

### `boolean(_:)`

```swift
case boolean(Bool)
```

It represents a boolean value.

### `dictionary(_:)`

```swift
case dictionary([String: Option])
```

It represents a dictionary value.

### `array(_:)`

```swift
case array([Option])
```

It represents an array value.
