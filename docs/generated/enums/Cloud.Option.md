**ENUM**

# `Cloud.Option`

```swift
public enum Option: String, Codable, Equatable
```

Options for cloud configuration.

## Cases
### `optional`

```swift
case optional
```

Marks whether Tuist Cloud authentication is optional.
If present, the interaction with Tuist Cloud will be skipped (instead of failing) if a user is not authenticated.
