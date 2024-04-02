**EXTENSION**

# `Destinations`
```swift
extension Destinations
```

## Properties
### `watchOS`

```swift
public static var watchOS: Destinations = [.appleWatch]
```

### `iOS`

```swift
public static var iOS: Destinations = [.iPhone, .iPad, .macWithiPadDesign]
```

Currently we omit `.visionOSwithiPadDesign` from our default because `visionOS` is unreleased.

### `macOS`

```swift
public static var macOS: Destinations = [.mac]
```

### `tvOS`

```swift
public static var tvOS: Destinations = [.appleTv]
```

### `visionOS`

```swift
public static var visionOS: Destinations = [.appleVision]
```

### `platforms`

```swift
public var platforms: Set<Platform>
```

Convience set of platforms that are supported by a set of destinations
