**ENUM**

# `Cloud.Option`

**Contents**

- [Cases](#cases)
  - `optional`

```swift
public enum Option: String, Codable, Equatable, Sendable
```

Options for cloud configuration.

## Cases
### `optional`

```swift
case optional
```

Marks whether the Tuist server authentication is optional.
If present, the interaction with the Tuist server will be skipped (instead of failing) if a user is not authenticated.
