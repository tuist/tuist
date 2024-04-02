**ENUM**

# `TargetScript.Order`

**Contents**

- [Cases](#cases)
  - `pre`
  - `post`

```swift
public enum Order: String, Codable, Equatable
```

Order when the script gets executed.

- pre: Before the sources and resources build phase.
- post: After the sources and resources build phase.

## Cases
### `pre`

```swift
case pre
```

### `post`

```swift
case post
```
