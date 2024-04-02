**STRUCT**

# `Scheme`

**Contents**

- [Properties](#properties)
  - `name`
  - `shared`
  - `hidden`
  - `buildAction`
  - `testAction`
  - `runAction`
  - `archiveAction`
  - `profileAction`
  - `analyzeAction`
- [Methods](#methods)
  - `scheme(name:shared:hidden:buildAction:testAction:runAction:archiveAction:profileAction:analyzeAction:)`

```swift
public struct Scheme: Equatable, Codable
```

A custom scheme for a project.

A scheme defines a collection of targets to Build, Run, Test, Profile, Analyze and Archive.

## Properties
### `name`

```swift
public var name: String
```

The name of the scheme.

### `shared`

```swift
public var shared: Bool
```

Marks the scheme as shared (i.e. one that is checked in to the repository and is visible to xcodebuild from the command
line).

### `hidden`

```swift
public var hidden: Bool
```

When `true` the scheme doesn't show up in the dropdown scheme's list.

### `buildAction`

```swift
public var buildAction: BuildAction?
```

Action that builds the project targets.

### `testAction`

```swift
public var testAction: TestAction?
```

Action that runs the project tests.

### `runAction`

```swift
public var runAction: RunAction?
```

Action that runs project built products.

### `archiveAction`

```swift
public var archiveAction: ArchiveAction?
```

Action that runs the project archive.

### `profileAction`

```swift
public var profileAction: ProfileAction?
```

Action that profiles the project.

### `analyzeAction`

```swift
public var analyzeAction: AnalyzeAction?
```

Action that analyze the project.

## Methods
### `scheme(name:shared:hidden:buildAction:testAction:runAction:archiveAction:profileAction:analyzeAction:)`

```swift
public static func scheme(
    name: String,
    shared: Bool = true,
    hidden: Bool = false,
    buildAction: BuildAction? = nil,
    testAction: TestAction? = nil,
    runAction: RunAction? = nil,
    archiveAction: ArchiveAction? = nil,
    profileAction: ProfileAction? = nil,
    analyzeAction: AnalyzeAction? = nil
) -> Self
```

Creates a new instance of a scheme.
- Parameters:
  - name: Name of the scheme.
  - shared: Whether the scheme is shared.
  - hidden: When true, the scheme is hidden in the list of schemes from Xcode's dropdown.
  - buildAction: Action that builds the project targets.
  - testAction: Action that runs the project tests.
  - runAction: Action that runs project built products.
  - archiveAction: Action that runs the project archive.
  - profileAction: Action that profiles the project.
  - analyzeAction: Action that analyze the project.

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | Name of the scheme. |
| shared | Whether the scheme is shared. |
| hidden | When true, the scheme is hidden in the list of schemes from Xcode’s dropdown. |
| buildAction | Action that builds the project targets. |
| testAction | Action that runs the project tests. |
| runAction | Action that runs project built products. |
| archiveAction | Action that runs the project archive. |
| profileAction | Action that profiles the project. |
| analyzeAction | Action that analyze the project. |