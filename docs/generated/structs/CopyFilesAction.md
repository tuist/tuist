**STRUCT**

# `CopyFilesAction`

```swift
public struct CopyFilesAction: Codable, Equatable
```

A build phase action used to copy files.

Copy files actions, represented as target copy files build phases, are useful to associate project files
and products of other targets with the target and copies them to a specified destination, typically a
subfolder within a product. This action may be used multiple times per target.

## Properties
### `name`

```swift
public var name: String
```

Name of the build phase when the project gets generated.

### `destination`

```swift
public var destination: Destination
```

Destination to copy files to.

### `subpath`

```swift
public var subpath: String?
```

Path to a folder inside the destination.

### `files`

```swift
public var files: [CopyFileElement]
```

Relative paths to the files to be copied.

## Methods
### `productsDirectory(name:subpath:files:)`

```swift
public static func productsDirectory(
    name: String,
    subpath: String? = nil,
    files: [CopyFileElement]
) -> CopyFilesAction
```

A copy files action for the products directory.
- Parameters:
  - name: Name of the build phase when the project gets generated.
  - subpath: Path to a folder inside the destination.
  - files: Relative paths to the files to be copied.
- Returns: Copy files action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | Name of the build phase when the project gets generated. |
| subpath | Path to a folder inside the destination. |
| files | Relative paths to the files to be copied. |

### `wrapper(name:subpath:files:)`

```swift
public static func wrapper(
    name: String,
    subpath: String? = nil,
    files: [CopyFileElement]
) -> CopyFilesAction
```

A copy files action for the wrapper directory.
- Parameters:
  - name: Name of the build phase when the project gets generated.
  - subpath: Path to a folder inside the destination.
  - files: Relative paths to the files to be copied.
- Returns: Copy files action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | Name of the build phase when the project gets generated. |
| subpath | Path to a folder inside the destination. |
| files | Relative paths to the files to be copied. |

### `executables(name:subpath:files:)`

```swift
public static func executables(
    name: String,
    subpath: String? = nil,
    files: [CopyFileElement]
) -> CopyFilesAction
```

A copy files action for the executables directory.
- Parameters:
  - name: Name of the build phase when the project gets generated.
  - subpath: Path to a folder inside the destination.
  - files: Relative paths to the files to be copied.
- Returns: Copy files action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | Name of the build phase when the project gets generated. |
| subpath | Path to a folder inside the destination. |
| files | Relative paths to the files to be copied. |

### `resources(name:subpath:files:)`

```swift
public static func resources(
    name: String,
    subpath: String? = nil,
    files: [CopyFileElement]
) -> CopyFilesAction
```

A copy files action for the resources directory.
- Parameters:
  - name: Name of the build phase when the project gets generated.
  - subpath: Path to a folder inside the destination.
  - files: Relative paths to the files to be copied.
- Returns: Copy files action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | Name of the build phase when the project gets generated. |
| subpath | Path to a folder inside the destination. |
| files | Relative paths to the files to be copied. |

### `javaResources(name:subpath:files:)`

```swift
public static func javaResources(
    name: String,
    subpath: String? = nil,
    files: [CopyFileElement]
) -> CopyFilesAction
```

A copy files action for the java resources directory.
- Parameters:
  - name: Name of the build phase when the project gets generated.
  - subpath: Path to a folder inside the destination.
  - files: Relative paths to the files to be copied.
- Returns: Copy files action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | Name of the build phase when the project gets generated. |
| subpath | Path to a folder inside the destination. |
| files | Relative paths to the files to be copied. |

### `frameworks(name:subpath:files:)`

```swift
public static func frameworks(
    name: String,
    subpath: String? = nil,
    files: [CopyFileElement]
) -> CopyFilesAction
```

A copy files action for the frameworks directory.
- Parameters:
  - name: Name of the build phase when the project gets generated.
  - subpath: Path to a folder inside the destination.
  - files: Relative paths to the files to be copied.
- Returns: Copy files action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | Name of the build phase when the project gets generated. |
| subpath | Path to a folder inside the destination. |
| files | Relative paths to the files to be copied. |

### `sharedFrameworks(name:subpath:files:)`

```swift
public static func sharedFrameworks(
    name: String,
    subpath: String? = nil,
    files: [CopyFileElement]
) -> CopyFilesAction
```

A copy files action for the shared frameworks directory.
- Parameters:
  - name: Name of the build phase when the project gets generated.
  - subpath: Path to a folder inside the destination.
  - files: Relative paths to the files to be copied.
- Returns: Copy files action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | Name of the build phase when the project gets generated. |
| subpath | Path to a folder inside the destination. |
| files | Relative paths to the files to be copied. |

### `sharedSupport(name:subpath:files:)`

```swift
public static func sharedSupport(
    name: String,
    subpath: String? = nil,
    files: [CopyFileElement]
) -> CopyFilesAction
```

A copy files action for the shared support directory.
- Parameters:
  - name: Name of the build phase when the project gets generated.
  - subpath: Path to a folder inside the destination.
  - files: Relative paths to the files to be copied.
- Returns: Copy files action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | Name of the build phase when the project gets generated. |
| subpath | Path to a folder inside the destination. |
| files | Relative paths to the files to be copied. |

### `plugins(name:subpath:files:)`

```swift
public static func plugins(
    name: String,
    subpath: String? = nil,
    files: [CopyFileElement]
) -> CopyFilesAction
```

A copy files action for the plugins directory.
- Parameters:
  - name: Name of the build phase when the project gets generated.
  - subpath: Path to a folder inside the destination.
  - files: Relative paths to the files to be copied.
- Returns: Copy files action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | Name of the build phase when the project gets generated. |
| subpath | Path to a folder inside the destination. |
| files | Relative paths to the files to be copied. |