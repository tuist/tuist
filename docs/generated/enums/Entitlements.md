**ENUM**

# `Entitlements`

```swift
public enum Entitlements: Codable, Equatable
```

## Cases
### `file(path:)`

```swift
case file(path: Path)
```

The path to an existing .entitlements file.

### `dictionary(_:)`

```swift
case dictionary([String: Plist.Value])
```

A dictionary with the entitlements content. Tuist generates the .entitlements file at the generation time.

## Properties
### `path`

```swift
public var path: Path?
```
