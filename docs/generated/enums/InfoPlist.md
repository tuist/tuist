**ENUM**

# `InfoPlist`

```swift
public enum InfoPlist: Codable, Equatable
```

A info plist from a file, a custom dictonary or a extended defaults.

## Cases
### `file(path:)`

```swift
case file(path: Path)
```

The path to an existing Info.plist file.

### `dictionary(_:)`

```swift
case dictionary([String: Plist.Value])
```

A dictionary with the Info.plist content. Tuist generates the Info.plist file at the generation time.

### `extendingDefault(with:)`

```swift
case extendingDefault(with: [String: Plist.Value])
```

Generate an Info.plist file with the default content for the target product extended with the values in the given
dictionary.

## Properties
### `default`

```swift
public static var `default`: InfoPlist
```

Generate the default content for the target the InfoPlist belongs to.

### `path`

```swift
public var path: Path?
```
