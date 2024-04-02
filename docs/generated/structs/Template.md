**STRUCT**

# `Template`

```swift
public struct Template: Codable, Equatable
```

A scaffold template model.

## Properties
### `description`

```swift
public let description: String
```

Description of template

### `attributes`

```swift
public let attributes: [Attribute]
```

Attributes to be passed to template

### `items`

```swift
public let items: [Item]
```

Items to generate

## Methods
### `init(description:attributes:items:)`

```swift
public init(
    description: String,
    attributes: [Attribute] = [],
    items: [Item] = []
)
```
