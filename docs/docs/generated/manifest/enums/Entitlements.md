**ENUM**

# `Entitlements`

**Contents**

- [Cases](#cases)
  - `file(path:)`
  - `dictionary(_:)`
  - `variable(_:)`
- [Properties](#properties)
  - `path`

```swift
public enum Entitlements: Codable, Equatable, Sendable
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

### `variable(_:)`

```swift
case variable(String)
```

 A user defined xcconfig variable map to .entitlements file.

 This should be used when the project has different entitlements files per config (aka: debug,release,staging,etc)

  ````
 .target(
     ...
     entitlements: .variable("$(ENTITLEMENT_FILE_VARIABLE)"),
 )
  ````

 Or as literal string
 ````
.target(
    ...
    entitlements: $(ENTITLEMENT_FILE_VARIABLE),
)
 ````

## Properties
### `path`

```swift
public var path: Path?
```
