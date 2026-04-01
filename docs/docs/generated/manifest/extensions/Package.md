**EXTENSION**

# `Package`
```swift
extension Package
```

## Methods
### `package(url:from:)`

```swift
public static func package(url: String, from version: Version) -> Package
```

Create a package dependency that uses the version requirement, starting with the given minimum version,
going up to the next major version.

This is the recommended way to specify a remote package dependency.
It allows you to specify the minimum version you require, allows updates that include bug fixes
and backward-compatible feature updates, but requires you to explicitly update to a new major version of the dependency.
This approach provides the maximum flexibility on which version to use,
while making sure you don't update to a version with breaking changes,
and helps to prevent conflicts in your dependency graph.

The following example allows the Swift package manager to select a version
like a  `1.2.3`, `1.2.4`, or `1.3.0`, but not `2.0.0`.

   .package(url: "https://example.com/example-package.git", from: "1.2.3"),

- Parameters:
    - url: The valid Git URL of the package.
    - version: The minimum version requirement.

#### Parameters

| Name | Description |
| ---- | ----------- |
| url | The valid Git URL of the package. |
| version | The minimum version requirement. |

### `package(url:_:)`

```swift
public static func package(url: String, _ requirement: Package.Requirement) -> Package
```

Add a remote package dependency given a version requirement.

- Parameters:
    - url: The valid Git URL of the package.
    - requirement: A dependency requirement. See static methods on `Package.Dependency.Requirement` for available options.

#### Parameters

| Name | Description |
| ---- | ----------- |
| url | The valid Git URL of the package. |
| requirement | A dependency requirement. See static methods on `Package.Dependency.Requirement` for available options. |

### `package(url:_:)`

```swift
public static func package(url: String, _ range: Range<Version>) -> Package
```

Add a package dependency starting with a specific minimum version, up to
but not including a specified maximum version.

The following example allows the Swift package manager to pick
versions `1.2.3`, `1.2.4`, `1.2.5`, but not `1.2.6`.

    .package(url: "https://example.com/example-package.git", "1.2.3"..<"1.2.6"),

- Parameters:
    - url: The valid Git URL of the package.
    - range: The custom version range requirement.

#### Parameters

| Name | Description |
| ---- | ----------- |
| url | The valid Git URL of the package. |
| range | The custom version range requirement. |

### `package(url:_:)`

```swift
public static func package(url: String, _ range: ClosedRange<Version>) -> Package
```

Add a package dependency starting with a specific minimum version, going
up to and including a specific maximum version.

The following example allows the Swift package manager to pick
versions 1.2.3, 1.2.4, 1.2.5, as well as 1.2.6.

    .package(url: "https://example.com/example-package.git", "1.2.3"..."1.2.6"),

- Parameters:
    - url: The valid Git URL of the package.
    - range: The closed version range requirement.

#### Parameters

| Name | Description |
| ---- | ----------- |
| url | The valid Git URL of the package. |
| range | The closed version range requirement. |

### `package(path:)`

```swift
public static func package(path: Path) -> Package
```

Add a dependency to a local package on the filesystem.

The Swift Package Manager uses the package dependency as-is
and does not perform any source control access. Local package dependencies
are especially useful during development of a new package or when working
on multiple tightly coupled packages.

- Parameter path: The path of the package.

#### Parameters

| Name | Description |
| ---- | ----------- |
| path | The path of the package. |

### `package(url:version:)`

### `package(url:branch:)`

### `package(url:revision:)`

### `package(url:range:)`
