**STRUCT**

# `RunActionOptions.SimulatedLocation`

```swift
public struct SimulatedLocation: Codable, Equatable
```

Simulated location represents a GPS location that is used when running an app on the simulator.

## Properties
### `identifier`

```swift
public var identifier: String?
```

The identifier of the location (e.g. London, England)

### `gpxFile`

```swift
public var gpxFile: Path?
```

Path to a .gpx file that indicates the location

### `london`

```swift
public static var london: SimulatedLocation
```

### `johannesburg`

```swift
public static var johannesburg: SimulatedLocation
```

### `moscow`

```swift
public static var moscow: SimulatedLocation
```

### `mumbai`

```swift
public static var mumbai: SimulatedLocation
```

### `tokyo`

```swift
public static var tokyo: SimulatedLocation
```

### `sydney`

```swift
public static var sydney: SimulatedLocation
```

### `hongKong`

```swift
public static var hongKong: SimulatedLocation
```

### `honolulu`

```swift
public static var honolulu: SimulatedLocation
```

### `sanFrancisco`

```swift
public static var sanFrancisco: SimulatedLocation
```

### `mexicoCity`

```swift
public static var mexicoCity: SimulatedLocation
```

### `newYork`

```swift
public static var newYork: SimulatedLocation
```

### `rioDeJaneiro`

```swift
public static var rioDeJaneiro: SimulatedLocation
```

## Methods
### `custom(gpxFile:)`

```swift
public static func custom(gpxFile: Path) -> SimulatedLocation
```
