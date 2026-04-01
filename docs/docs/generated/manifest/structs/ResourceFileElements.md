**STRUCT**

# `ResourceFileElements`

**Contents**

- [Properties](#properties)
  - `resources`
  - `privacyManifest`
- [Methods](#methods)
  - `resources(_:privacyManifest:)`

```swift
public struct ResourceFileElements: Codable, Equatable, Sendable
```

A collection of resource file.

## Properties
### `resources`

```swift
public var resources: [ResourceFileElement]
```

List of resource file elements

### `privacyManifest`

```swift
public var privacyManifest: PrivacyManifest?
```

Define your apps privacy manifest

## Methods
### `resources(_:privacyManifest:)`

```swift
public static func resources(_ resources: [ResourceFileElement], privacyManifest: PrivacyManifest? = nil) -> Self
```
