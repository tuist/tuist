**ENUM**

# `Template.Attribute`

```swift
public enum Attribute: Codable, Equatable
```

Attribute to be passed to `tuist scaffold` for generating with `Template`

## Cases
### `required(_:)`

```swift
case required(String)
```

Required attribute with a given name

### `optional(_:default:)`

```swift
case optional(String, default: Value)
```

Optional attribute with a given name and a default value used when attribute not provided by user
