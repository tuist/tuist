**ENUM**

# `TargetDependency`

```swift
public enum TargetDependency: Codable, Hashable
```

A target dependency.

## Cases
### `target(name:condition:)`

```swift
case target(name: String, condition: PlatformCondition? = nil)
```

Dependency on another target within the same project

- Parameters:
  - name: Name of the target to depend on
  - condition: condition under which to use this dependency, `nil` if this should always be used

### `project(target:path:condition:)`

```swift
case project(target: String, path: Path, condition: PlatformCondition? = nil)
```

Dependency on a target within another project

- Parameters:
  - target: Name of the target to depend on
  - path: Relative path to the other project directory
  - condition: condition under which to use this dependency, `nil` if this should always be used

### `framework(path:status:condition:)`

```swift
case framework(path: Path, status: FrameworkStatus = .required, condition: PlatformCondition? = nil)
```

Dependency on a prebuilt framework

- Parameters:
  - path: Relative path to the prebuilt framework
  - status: The dependency status (optional dependencies are weakly linked)
  - condition: condition under which to use this dependency, `nil` if this should always be used

### `library(path:publicHeaders:swiftModuleMap:condition:)`

```swift
case library(path: Path, publicHeaders: Path, swiftModuleMap: Path?, condition: PlatformCondition? = nil)
```

Dependency on prebuilt library

- Parameters:
  - path: Relative path to the prebuilt library
  - publicHeaders: Relative path to the library's public headers directory
  - swiftModuleMap: Relative path to the library's swift module map file
  - condition: condition under which to use this dependency, `nil` if this should always be used

### `package(product:type:condition:)`

```swift
case package(product: String, type: PackageType = .runtime, condition: PlatformCondition? = nil)
```

Dependency on a swift package manager product using Xcode native integration. It's recommended to use `external` instead.
For more info, check the [external dependencies documentation
](https://docs.tuist.io/documentation/tuist/dependencies/#External-dependencies).

- Parameters:
  - product: The name of the output product. ${PRODUCT_NAME} inside Xcode.
             e.g. RxSwift
  - type: The type of package being integrated.
  - condition: condition under which to use this dependency, `nil` if this should always be used

### `sdk(name:type:status:condition:)`

```swift
case sdk(name: String, type: SDKType, status: SDKStatus, condition: PlatformCondition? = nil)
```

Dependency on system library or framework

- Parameters:
  - name: Name of the system library or framework (not including extension)
           e.g. `ARKit`, `c++`
  - type: The dependency type
  - status: The dependency status (optional dependencies are weakly linked)
  - condition: condition under which to use this dependency, `nil` if this should always be used

### `xcframework(path:status:condition:)`

```swift
case xcframework(path: Path, status: FrameworkStatus = .required, condition: PlatformCondition? = nil)
```

Dependency on a xcframework

- Parameters:
  - path: Relative path to the xcframework
  - status: The dependency status (optional dependencies are weakly linked)
  - condition: condition under which to use this dependency, `nil` if this should always be used

### `xctest`

```swift
case xctest
```

Dependency on XCTest.

### `external(name:condition:)`

```swift
case external(name: String, condition: PlatformCondition? = nil)
```

Dependency on an external dependency imported through `Package.swift`.

- Parameters:
  - name: Name of the external dependency
  - condition: condition under which to use this dependency, `nil` if this should always be used

## Properties
### `typeName`

```swift
public var typeName: String
```

## Methods
### `sdk(name:type:condition:)`

```swift
public static func sdk(name: String, type: SDKType, condition: PlatformCondition? = nil) -> TargetDependency
```

Dependency on system library or framework

- Parameters:
  - name: Name of the system library or framework (including extension)
           e.g. `ARKit.framework`, `libc++.tbd`
  - type: Whether or not this dependecy is required. Defaults to `.required`
  - condition: condition under which to use this dependency, `nil` if this should always be used

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | Name of the system library or framework (including extension) e.g. `ARKit.framework`, `libc++.tbd` |
| type | Whether or not this dependecy is required. Defaults to `.required` |
| condition | condition under which to use this dependency, `nil` if this should always be used |

### `target(_:condition:)`

```swift
public static func target(_ target: Target, condition: PlatformCondition? = nil) -> TargetDependency
```

Dependency on another target within the same project. This is just syntactic sugar for `.target(name: target.name)`.

- Parameters:
  - target: Instance of the target to depend on
  - condition: condition under which to use this dependency, `nil` if this should always be used

#### Parameters

| Name | Description |
| ---- | ----------- |
| target | Instance of the target to depend on |
| condition | condition under which to use this dependency, `nil` if this should always be used |