**ENUM**

# `Destination`

**Contents**

- [Cases](#cases)
  - `iPhone`
  - `iPad`
  - `mac`
  - `macWithiPadDesign`
  - `macCatalyst`
  - `appleWatch`
  - `appleTv`
  - `appleVision`
  - `appleVisionWithiPadDesign`
- [Properties](#properties)
  - `platform`

```swift
public enum Destination: String, Codable, Equatable, CaseIterable
```

A supported deployment destination representation.

## Cases
### `iPhone`

```swift
case iPhone
```

iPhone support

### `iPad`

```swift
case iPad
```

iPad support

### `mac`

```swift
case mac
```

Native macOS support

### `macWithiPadDesign`

```swift
case macWithiPadDesign
```

macOS support using iPad design

### `macCatalyst`

```swift
case macCatalyst
```

mac Catalyst support

### `appleWatch`

```swift
case appleWatch
```

watchOS support

### `appleTv`

```swift
case appleTv
```

tvOS support

### `appleVision`

```swift
case appleVision
```

visionOS support

### `appleVisionWithiPadDesign`

```swift
case appleVisionWithiPadDesign
```

visionOS support useing iPad design

## Properties
### `platform`

```swift
public var platform: Platform
```

SDK Platform of a destination
