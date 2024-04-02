**STRUCT**

# `Path`

**Contents**

- [Properties](#properties)
  - `type`
  - `pathString`
  - `callerPath`
- [Methods](#methods)
  - `path(_:)`
  - `relativeToCurrentFile(_:callerPath:)`
  - `relativeToManifest(_:)`
  - `relativeToRoot(_:)`
  - `init(stringLiteral:)`

```swift
public struct Path: ExpressibleByStringInterpolation, Codable, Hashable
```

A path represents to a file, directory, or a group of files represented by a glob expression.

Paths can be relative and absolute. We discourage using absolute paths because they create a dependency with the environment
where they are defined.

## Properties
### `type`

```swift
public var type: PathType
```

### `pathString`

```swift
public var pathString: String
```

### `callerPath`

```swift
public var callerPath: String?
```

## Methods
### `path(_:)`

```swift
public static func path(_ path: String) -> Self
```

Default PathType is `.relativeToManifest`

### `relativeToCurrentFile(_:callerPath:)`

```swift
public static func relativeToCurrentFile(_ pathString: String, callerPath: StaticString = #file) -> Path
```

Initialize a path that is relative to the file that defines the path.

### `relativeToManifest(_:)`

```swift
public static func relativeToManifest(_ pathString: String) -> Path
```

Initialize a path that is relative to the directory that contains the manifest file being loaded, for example the
directory that contains the Project.swift file.

### `relativeToRoot(_:)`

```swift
public static func relativeToRoot(_ pathString: String) -> Path
```

Initialize a path that is relative to the closest directory that contains a Tuist or a .git directory.

### `init(stringLiteral:)`

```swift
public init(stringLiteral: String)
```

Initializer uses `.relativeToRoot` if path starts with `//` otherwise it is `.relativeToManifest` by default
