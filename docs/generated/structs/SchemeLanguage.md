**STRUCT**

# `SchemeLanguage`

```swift
public struct SchemeLanguage: Codable, Equatable, ExpressibleByStringLiteral
```

A language to use for run and test actions.

## Properties
### `identifier`

```swift
public let identifier: String
```

## Methods
### `init(identifier:)`

```swift
public init(identifier: String)
```

Creates a new scheme language.
- Parameter identifier: A valid language code or a pre-defined pseudo language.

#### Parameters

| Name | Description |
| ---- | ----------- |
| identifier | A valid language code or a pre-defined pseudo language. |

### `init(stringLiteral:)`

```swift
public init(stringLiteral: String)
```

Creates a new scheme language.
- Parameter stringLiteral: A valid language code or a pre-defined pseudo language.

#### Parameters

| Name | Description |
| ---- | ----------- |
| stringLiteral | A valid language code or a pre-defined pseudo language. |