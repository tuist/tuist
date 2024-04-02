**STRUCT**

# `Headers`

```swift
public struct Headers: Codable, Equatable
```

A group of public, private and project headers.

## Properties
### `umbrellaHeader`

```swift
public var umbrellaHeader: Path?
```

Path to an umbrella header, which will be used to get list of public headers.

### `public`

```swift
public var `public`: FileList?
```

Relative glob pattern that points to the public headers.

### `private`

```swift
public var `private`: FileList?
```

Relative glob pattern that points to the private headers.

### `project`

```swift
public var project: FileList?
```

Relative glob pattern that points to the project headers.

### `exclusionRule`

```swift
public var exclusionRule: AutomaticExclusionRule
```

Rule, which determines how to resolve found duplicates in public/private/project scopes

## Methods
### `headers(public:private:project:exclusionRule:)`

```swift
public static func headers(
    public: FileList? = nil,
    private: FileList? = nil,
    project: FileList? = nil,
    exclusionRule: AutomaticExclusionRule = .projectExcludesPrivateAndPublic
) -> Headers
```

### `allHeaders(from:umbrella:private:)`

```swift
public static func allHeaders(
    from list: FileList,
    umbrella: Path,
    private privateHeaders: FileList? = nil
) -> Headers
```

Headers from the file list are included as:
- `public`, if the header is present in the umbrella header
- `private`, if the header is present in the `private` list
- `project`, otherwise
- Parameters:
    - from: File list, which contains `public` and `project` headers
    - umbrella: File path to the umbrella header
    - private: File list, which contains `private` headers

#### Parameters

| Name | Description |
| ---- | ----------- |
| from | File list, which contains `public` and `project` headers |
| umbrella | File path to the umbrella header |
| private | File list, which contains `private` headers |

### `onlyHeaders(from:umbrella:private:)`

```swift
public static func onlyHeaders(
    from list: FileList,
    umbrella: Path,
    private privateHeaders: FileList? = nil
) -> Headers
```

Headers from the file list are included as:
- `public`, if the header is present in the umbrella header
- `private`, if the header is present in the `private` list
- not included, otherwise
- Parameters:
    - from: File list, which contains `public` and `project` headers
    - umbrella: File path to the umbrella header
    - private: File list, which contains `private` headers

#### Parameters

| Name | Description |
| ---- | ----------- |
| from | File list, which contains `public` and `project` headers |
| umbrella | File path to the umbrella header |
| private | File list, which contains `private` headers |