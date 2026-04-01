**EXTENSION**

# `Destinations`
```swift
extension Destinations
```

## Properties
### `watchOS`

```swift
public static let watchOS: Destinations = [.appleWatch]
```

### `iOS`

```swift
public static let iOS: Destinations = [.iPhone, .iPad, .macWithiPadDesign]
```

Currently we omit `.visionOSwithiPadDesign` from our default because `visionOS` is unreleased.

### `macOS`

```swift
public static let macOS: Destinations = [.mac]
```

### `tvOS`

```swift
public static let tvOS: Destinations = [.appleTv]
```

### `visionOS`

```swift
public static let visionOS: Destinations = [.appleVision]
```

### `platforms`

```swift
public var platforms: Set<Platform>
```

Convenience set of platforms that are supported by a set of destinations
