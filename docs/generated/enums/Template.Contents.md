**ENUM**

# `Template.Contents`

**Contents**

- [Cases](#cases)
  - `string(_:)`
  - `file(_:)`
  - `directory(_:)`

```swift
public enum Contents: Codable, Equatable
```

Enum containing information about how to generate item

## Cases
### `string(_:)`

```swift
case string(String)
```

String Contents is defined in `name_of_template.swift` and contains a simple `String`
Can not contain any additional logic apart from plain `String` from `arguments`

### `file(_:)`

```swift
case file(Path)
```

File content is defined in a different file from `name_of_template.swift`
Can contain additional logic and anything that is defined in `ProjectDescriptionHelpers`

### `directory(_:)`

```swift
case directory(Path)
```

Directory content is defined in a path
It is just for copying files without modifications and logic inside
