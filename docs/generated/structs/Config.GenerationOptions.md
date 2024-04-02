**STRUCT**

# `Config.GenerationOptions`

```swift
public struct GenerationOptions: Codable, Equatable
```

Options for project generation.

## Properties
### `resolveDependenciesWithSystemScm`

```swift
public var resolveDependenciesWithSystemScm: Bool
```

When passed, Xcode will resolve its Package Manager dependencies using the system-defined
accounts (for example, git) instead of the Xcode-defined accounts

### `disablePackageVersionLocking`

```swift
public var disablePackageVersionLocking: Bool
```

Disables locking Swift packages. This can speed up generation but does increase risk if packages are not locked
in their declarations.

### `clonedSourcePackagesDirPath`

```swift
public var clonedSourcePackagesDirPath: Path?
```

Allows setting a custom directory to be used when resolving package dependencies
This path is passed to `xcodebuild` via the `-clonedSourcePackagesDirPath` argument

### `staticSideEffectsWarningTargets`

```swift
public var staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets
```

Allows configuring which targets Tuist checks for potential side effects due multiple branches of the graph
including the same static library of framework as a transitive dependency.

### `enforceExplicitDependencies`

```swift
public let enforceExplicitDependencies: Bool
```

The generated project has build settings and build paths modified in such a way that projects with implicit
dependencies won't build until all dependencies are declared explicitly.

## Methods
### `options(resolveDependenciesWithSystemScm:disablePackageVersionLocking:clonedSourcePackagesDirPath:staticSideEffectsWarningTargets:enforceExplicitDependencies:)`

```swift
public static func options(
    resolveDependenciesWithSystemScm: Bool = false,
    disablePackageVersionLocking: Bool = false,
    clonedSourcePackagesDirPath: Path? = nil,
    staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets = .all,
    enforceExplicitDependencies: Bool = false
) -> Self
```
