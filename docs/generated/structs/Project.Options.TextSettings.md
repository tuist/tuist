**STRUCT**

# `Project.Options.TextSettings`

**Contents**

- [Properties](#properties)
  - `usesTabs`
  - `indentWidth`
  - `tabWidth`
  - `wrapsLines`
- [Methods](#methods)
  - `textSettings(usesTabs:indentWidth:tabWidth:wrapsLines:)`

```swift
public struct TextSettings: Codable, Equatable
```

The text settings options

## Properties
### `usesTabs`

```swift
public var usesTabs: Bool?
```

Whether tabs should be used instead of spaces

### `indentWidth`

```swift
public var indentWidth: UInt?
```

The width of space indent

### `tabWidth`

```swift
public var tabWidth: UInt?
```

The width of tab indent

### `wrapsLines`

```swift
public var wrapsLines: Bool?
```

Whether lines should be wrapped or not

## Methods
### `textSettings(usesTabs:indentWidth:tabWidth:wrapsLines:)`

```swift
public static func textSettings(
    usesTabs: Bool? = nil,
    indentWidth: UInt? = nil,
    tabWidth: UInt? = nil,
    wrapsLines: Bool? = nil
) -> Self
```
