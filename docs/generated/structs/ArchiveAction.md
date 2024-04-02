**STRUCT**

# `ArchiveAction`

```swift
public struct ArchiveAction: Equatable, Codable
```

An action that archives the built products.

It's initialized with the `.archiveAction` static method.

## Properties
### `configuration`

```swift
public var configuration: ConfigurationName
```

Indicates the build configuration to run the archive with.

### `revealArchiveInOrganizer`

```swift
public var revealArchiveInOrganizer: Bool
```

If set to true, Xcode will reveal the Organizer on completion.

### `customArchiveName`

```swift
public var customArchiveName: String?
```

Set if you want to override Xcode's default archive name.

### `preActions`

```swift
public var preActions: [ExecutionAction]
```

A list of actions that are executed before starting the archive process.

### `postActions`

```swift
public var postActions: [ExecutionAction]
```

A list of actions that are executed after the archive process.

## Methods
### `archiveAction(configuration:revealArchiveInOrganizer:customArchiveName:preActions:postActions:)`

```swift
public static func archiveAction(
    configuration: ConfigurationName,
    revealArchiveInOrganizer: Bool = true,
    customArchiveName: String? = nil,
    preActions: [ExecutionAction] = [],
    postActions: [ExecutionAction] = []
) -> ArchiveAction
```

Initialize a `ArchiveAction`
- Parameters:
  - configuration: Indicates the build configuration to run the archive with.
  - revealArchiveInOrganizer: If set to true, Xcode will reveal the Organizer on completion.
  - customArchiveName: Set if you want to override Xcode's default archive name.
  - preActions: A list of actions that are executed before starting the archive process.
  - postActions: A list of actions that are executed after the archive process.

#### Parameters

| Name | Description |
| ---- | ----------- |
| configuration | Indicates the build configuration to run the archive with. |
| revealArchiveInOrganizer | If set to true, Xcode will reveal the Organizer on completion. |
| customArchiveName | Set if you want to override Xcode’s default archive name. |
| preActions | A list of actions that are executed before starting the archive process. |
| postActions | A list of actions that are executed after the archive process. |