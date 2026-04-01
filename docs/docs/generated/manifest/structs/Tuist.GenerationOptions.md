**STRUCT**

# `Tuist.GenerationOptions`

**Contents**

- [Properties](#properties)
  - `resolveDependenciesWithSystemScm`
  - `disablePackageVersionLocking`
  - `clonedSourcePackagesDirPath`
  - `staticSideEffectsWarningTargets`
  - `enforceExplicitDependencies`
  - `defaultConfiguration`
  - `optionalAuthentication`
- [Methods](#methods)
  - `options(resolveDependenciesWithSystemScm:disablePackageVersionLocking:clonedSourcePackagesDirPath:staticSideEffectsWarningTargets:defaultConfiguration:optionalAuthentication:)`
  - `options(resolveDependenciesWithSystemScm:disablePackageVersionLocking:clonedSourcePackagesDirPath:staticSideEffectsWarningTargets:enforceExplicitDependencies:defaultConfiguration:optionalAuthentication:)`

```swift
public struct GenerationOptions: Codable, Equatable, Sendable
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

### `defaultConfiguration`

```swift
public var defaultConfiguration: String?
```

The default configuration to be used when generating the project.
If not specified, Tuist generates for the first (when alphabetically sorted) debug configuration.

### `optionalAuthentication`

```swift
public var optionalAuthentication: Bool
```

Marks whether the Tuist server authentication is optional.
If present, the interaction with the Tuist server will be skipped (instead of failing) if a user is not authenticated.

## Methods
### `options(resolveDependenciesWithSystemScm:disablePackageVersionLocking:clonedSourcePackagesDirPath:staticSideEffectsWarningTargets:defaultConfiguration:optionalAuthentication:)`

```swift
public static func options(
    resolveDependenciesWithSystemScm: Bool = false,
    disablePackageVersionLocking: Bool = false,
    clonedSourcePackagesDirPath: Path? = nil,
    staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets = .all,
    defaultConfiguration: String? = nil,
    optionalAuthentication: Bool = false
) -> Self
```

### `options(resolveDependenciesWithSystemScm:disablePackageVersionLocking:clonedSourcePackagesDirPath:staticSideEffectsWarningTargets:enforceExplicitDependencies:defaultConfiguration:optionalAuthentication:)`

```swift
public static func options(
    resolveDependenciesWithSystemScm: Bool = false,
    disablePackageVersionLocking: Bool = false,
    clonedSourcePackagesDirPath: Path? = nil,
    staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets = .all,
    enforceExplicitDependencies: Bool,
    defaultConfiguration: String? = nil,
    optionalAuthentication: Bool = false
) -> Self
```
