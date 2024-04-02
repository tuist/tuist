**STRUCT**

# `TargetScript`

```swift
public struct TargetScript: Codable, Equatable
```

A build phase action used to run a script.

Target scripts, represented as target script build phases in the generated Xcode projects, are useful to define actions to be
executed before of after the build process of a target.

## Properties
### `name`

```swift
public var name: String
```

Name of the build phase when the project gets generated.

### `script`

```swift
public var script: Script
```

The script that is to be executed

### `order`

```swift
public var order: Order
```

Target script order.

### `inputPaths`

```swift
public var inputPaths: [FileListGlob]
```

List of input file paths

### `inputFileListPaths`

```swift
public var inputFileListPaths: [Path]
```

List of input filelist paths

### `outputPaths`

```swift
public var outputPaths: [Path]
```

List of output file paths

### `outputFileListPaths`

```swift
public var outputFileListPaths: [Path]
```

List of output filelist paths

### `basedOnDependencyAnalysis`

```swift
public var basedOnDependencyAnalysis: Bool?
```

Whether to skip running this script in incremental builds, if nothing has changed

### `runForInstallBuildsOnly`

```swift
public var runForInstallBuildsOnly: Bool
```

Whether this script only runs on install builds (default is false)

### `shellPath`

```swift
public var shellPath: String
```

The path to the shell which shall execute this script.

### `dependencyFile`

```swift
public var dependencyFile: Path?
```

The path to the dependency file

## Methods
### `pre(path:arguments:name:inputPaths:inputFileListPaths:outputPaths:outputFileListPaths:basedOnDependencyAnalysis:runForInstallBuildsOnly:shellPath:dependencyFile:)`

```swift
public static func pre(
    path: Path,
    arguments: String...,
    name: String,
    inputPaths: [FileListGlob] = [],
    inputFileListPaths: [Path] = [],
    outputPaths: [Path] = [],
    outputFileListPaths: [Path] = [],
    basedOnDependencyAnalysis: Bool? = nil,
    runForInstallBuildsOnly: Bool = false,
    shellPath: String = "/bin/sh",
    dependencyFile: Path? = nil
) -> TargetScript
```

Returns a target script that gets executed before the sources and resources build phase.

- Parameters:
  - path: Path to the script to execute.
  - arguments: Arguments that to be passed.
  - name: Name of the build phase when the project gets generated.
  - inputPaths: Glob pattern to the files.
  - inputFileListPaths: List of input filelist paths.
  - outputPaths: List of output file paths.
  - outputFileListPaths: List of output filelist paths.
  - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
  - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
  - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
  - dependencyFile: The path to the dependency file. Default is `nil`.
- Returns: Target script.

#### Parameters

| Name | Description |
| ---- | ----------- |
| path | Path to the script to execute. |
| arguments | Arguments that to be passed. |
| name | Name of the build phase when the project gets generated. |
| inputPaths | Glob pattern to the files. |
| inputFileListPaths | List of input filelist paths. |
| outputPaths | List of output file paths. |
| outputFileListPaths | List of output filelist paths. |
| basedOnDependencyAnalysis | Whether to skip running this script in incremental builds |
| runForInstallBuildsOnly | Whether this script only runs on install builds (default is false) |
| shellPath | The path to the shell which shall execute this script. Default is `/bin/sh`. |
| dependencyFile | The path to the dependency file. Default is `nil`. |

### `pre(path:arguments:name:inputPaths:inputFileListPaths:outputPaths:outputFileListPaths:basedOnDependencyAnalysis:runForInstallBuildsOnly:shellPath:dependencyFile:)`

```swift
public static func pre(
    path: Path,
    arguments: [String],
    name: String,
    inputPaths: [FileListGlob] = [],
    inputFileListPaths: [Path] = [],
    outputPaths: [Path] = [],
    outputFileListPaths: [Path] = [],
    basedOnDependencyAnalysis: Bool? = nil,
    runForInstallBuildsOnly: Bool = false,
    shellPath: String = "/bin/sh",
    dependencyFile: Path? = nil
) -> TargetScript
```

Returns a target script that gets executed before the sources and resources build phase.

- Parameters:
  - path: Path to the script to execute.
  - arguments: Arguments that to be passed.
  - name: Name of the build phase when the project gets generated.
  - inputPaths: Glob pattern to the files.
  - inputFileListPaths: List of input filelist paths.
  - outputPaths: List of output file paths.
  - outputFileListPaths: List of output filelist paths.
  - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
  - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
  - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
  - dependencyFile: The path to the dependency file. Default is `nil`.
- Returns: Target script.

#### Parameters

| Name | Description |
| ---- | ----------- |
| path | Path to the script to execute. |
| arguments | Arguments that to be passed. |
| name | Name of the build phase when the project gets generated. |
| inputPaths | Glob pattern to the files. |
| inputFileListPaths | List of input filelist paths. |
| outputPaths | List of output file paths. |
| outputFileListPaths | List of output filelist paths. |
| basedOnDependencyAnalysis | Whether to skip running this script in incremental builds |
| runForInstallBuildsOnly | Whether this script only runs on install builds (default is false) |
| shellPath | The path to the shell which shall execute this script. Default is `/bin/sh`. |
| dependencyFile | The path to the dependency file. Default is `nil`. |

### `post(path:arguments:name:inputPaths:inputFileListPaths:outputPaths:outputFileListPaths:basedOnDependencyAnalysis:runForInstallBuildsOnly:shellPath:dependencyFile:)`

```swift
public static func post(
    path: Path,
    arguments: String...,
    name: String,
    inputPaths: [FileListGlob] = [],
    inputFileListPaths: [Path] = [],
    outputPaths: [Path] = [],
    outputFileListPaths: [Path] = [],
    basedOnDependencyAnalysis: Bool? = nil,
    runForInstallBuildsOnly: Bool = false,
    shellPath: String = "/bin/sh",
    dependencyFile: Path? = nil
) -> TargetScript
```

Returns a target script that gets executed after the sources and resources build phase.

- Parameters:
  - path: Path to the script to execute.
  - arguments: Arguments that to be passed.
  - name: Name of the build phase when the project gets generated.
  - inputPaths: Glob pattern to the files.
  - inputFileListPaths: List of input filelist paths.
  - outputPaths: List of output file paths.
  - outputFileListPaths: List of output filelist paths.
  - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
  - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
  - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
  - dependencyFile: The path to the dependency file. Default is `nil`.
- Returns: Target script.

#### Parameters

| Name | Description |
| ---- | ----------- |
| path | Path to the script to execute. |
| arguments | Arguments that to be passed. |
| name | Name of the build phase when the project gets generated. |
| inputPaths | Glob pattern to the files. |
| inputFileListPaths | List of input filelist paths. |
| outputPaths | List of output file paths. |
| outputFileListPaths | List of output filelist paths. |
| basedOnDependencyAnalysis | Whether to skip running this script in incremental builds |
| runForInstallBuildsOnly | Whether this script only runs on install builds (default is false) |
| shellPath | The path to the shell which shall execute this script. Default is `/bin/sh`. |
| dependencyFile | The path to the dependency file. Default is `nil`. |

### `post(path:arguments:name:inputPaths:inputFileListPaths:outputPaths:outputFileListPaths:basedOnDependencyAnalysis:runForInstallBuildsOnly:shellPath:dependencyFile:)`

```swift
public static func post(
    path: Path,
    arguments: [String],
    name: String,
    inputPaths: [FileListGlob] = [],
    inputFileListPaths: [Path] = [],
    outputPaths: [Path] = [],
    outputFileListPaths: [Path] = [],
    basedOnDependencyAnalysis: Bool? = nil,
    runForInstallBuildsOnly: Bool = false,
    shellPath: String = "/bin/sh",
    dependencyFile: Path? = nil
) -> TargetScript
```

Returns a target script that gets executed after the sources and resources build phase.

- Parameters:
  - path: Path to the script to execute.
  - arguments: Arguments that to be passed.
  - name: Name of the build phase when the project gets generated.
  - inputPaths: Glob pattern to the files.
  - inputFileListPaths: List of input filelist paths.
  - outputPaths: List of output file paths.
  - outputFileListPaths: List of output filelist paths.
  - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
  - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
  - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
  - dependencyFile: The path to the dependency file. Default is `nil`.
- Returns: Target script.

#### Parameters

| Name | Description |
| ---- | ----------- |
| path | Path to the script to execute. |
| arguments | Arguments that to be passed. |
| name | Name of the build phase when the project gets generated. |
| inputPaths | Glob pattern to the files. |
| inputFileListPaths | List of input filelist paths. |
| outputPaths | List of output file paths. |
| outputFileListPaths | List of output filelist paths. |
| basedOnDependencyAnalysis | Whether to skip running this script in incremental builds |
| runForInstallBuildsOnly | Whether this script only runs on install builds (default is false) |
| shellPath | The path to the shell which shall execute this script. Default is `/bin/sh`. |
| dependencyFile | The path to the dependency file. Default is `nil`. |

### `pre(tool:arguments:name:inputPaths:inputFileListPaths:outputPaths:outputFileListPaths:basedOnDependencyAnalysis:runForInstallBuildsOnly:shellPath:dependencyFile:)`

```swift
public static func pre(
    tool: String,
    arguments: String...,
    name: String,
    inputPaths: [FileListGlob] = [],
    inputFileListPaths: [Path] = [],
    outputPaths: [Path] = [],
    outputFileListPaths: [Path] = [],
    basedOnDependencyAnalysis: Bool? = nil,
    runForInstallBuildsOnly: Bool = false,
    shellPath: String = "/bin/sh",
    dependencyFile: Path? = nil
) -> TargetScript
```

Returns a target script that gets executed before the sources and resources build phase.

- Parameters:
  - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
  - arguments: Arguments that to be passed.
  - name: Name of the build phase when the project gets generated.
  - inputPaths: Glob pattern to the files.
  - inputFileListPaths: List of input filelist paths.
  - outputPaths: List of output file paths.
  - outputFileListPaths: List of output filelist paths.
  - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
  - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
  - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
  - dependencyFile: The path to the dependency file. Default is `nil`.
- Returns: Target script.

#### Parameters

| Name | Description |
| ---- | ----------- |
| tool | Name of the tool to execute. Tuist will look up the tool on the environment’s PATH. |
| arguments | Arguments that to be passed. |
| name | Name of the build phase when the project gets generated. |
| inputPaths | Glob pattern to the files. |
| inputFileListPaths | List of input filelist paths. |
| outputPaths | List of output file paths. |
| outputFileListPaths | List of output filelist paths. |
| basedOnDependencyAnalysis | Whether to skip running this script in incremental builds |
| runForInstallBuildsOnly | Whether this script only runs on install builds (default is false) |
| shellPath | The path to the shell which shall execute this script. Default is `/bin/sh`. |
| dependencyFile | The path to the dependency file. Default is `nil`. |

### `pre(tool:arguments:name:inputPaths:inputFileListPaths:outputPaths:outputFileListPaths:basedOnDependencyAnalysis:runForInstallBuildsOnly:shellPath:dependencyFile:)`

```swift
public static func pre(
    tool: String,
    arguments: [String],
    name: String,
    inputPaths: [FileListGlob] = [],
    inputFileListPaths: [Path] = [],
    outputPaths: [Path] = [],
    outputFileListPaths: [Path] = [],
    basedOnDependencyAnalysis: Bool? = nil,
    runForInstallBuildsOnly: Bool = false,
    shellPath: String = "/bin/sh",
    dependencyFile: Path? = nil
) -> TargetScript
```

Returns a target script that gets executed before the sources and resources build phase.

- Parameters:
  - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
  - arguments: Arguments that to be passed.
  - name: Name of the build phase when the project gets generated.
  - inputPaths: Glob pattern to the files.
  - inputFileListPaths: List of input filelist paths.
  - outputPaths: List of output file paths.
  - outputFileListPaths: List of output filelist paths.
  - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
  - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
  - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
  - dependencyFile: The path to the dependency file. Default is `nil`.
- Returns: Target script.

#### Parameters

| Name | Description |
| ---- | ----------- |
| tool | Name of the tool to execute. Tuist will look up the tool on the environment’s PATH. |
| arguments | Arguments that to be passed. |
| name | Name of the build phase when the project gets generated. |
| inputPaths | Glob pattern to the files. |
| inputFileListPaths | List of input filelist paths. |
| outputPaths | List of output file paths. |
| outputFileListPaths | List of output filelist paths. |
| basedOnDependencyAnalysis | Whether to skip running this script in incremental builds |
| runForInstallBuildsOnly | Whether this script only runs on install builds (default is false) |
| shellPath | The path to the shell which shall execute this script. Default is `/bin/sh`. |
| dependencyFile | The path to the dependency file. Default is `nil`. |

### `post(tool:arguments:name:inputPaths:inputFileListPaths:outputPaths:outputFileListPaths:basedOnDependencyAnalysis:runForInstallBuildsOnly:shellPath:dependencyFile:)`

```swift
public static func post(
    tool: String,
    arguments: String...,
    name: String,
    inputPaths: [FileListGlob] = [],
    inputFileListPaths: [Path] = [],
    outputPaths: [Path] = [],
    outputFileListPaths: [Path] = [],
    basedOnDependencyAnalysis: Bool? = nil,
    runForInstallBuildsOnly: Bool = false,
    shellPath: String = "/bin/sh",
    dependencyFile: Path? = nil
) -> TargetScript
```

Returns a target script that gets executed after the sources and resources build phase.

- Parameters:
  - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
  - arguments: Arguments that to be passed.
  - name: Name of the build phase when the project gets generated.
  - inputPaths: Glob pattern to the files.
  - inputFileListPaths: List of input filelist paths.
  - outputPaths: List of output file paths.
  - outputFileListPaths: List of output filelist paths.
  - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
  - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
  - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
  - dependencyFile: The path to the dependency file. Default is `nil`.
- Returns: Target script.

#### Parameters

| Name | Description |
| ---- | ----------- |
| tool | Name of the tool to execute. Tuist will look up the tool on the environment’s PATH. |
| arguments | Arguments that to be passed. |
| name | Name of the build phase when the project gets generated. |
| inputPaths | Glob pattern to the files. |
| inputFileListPaths | List of input filelist paths. |
| outputPaths | List of output file paths. |
| outputFileListPaths | List of output filelist paths. |
| basedOnDependencyAnalysis | Whether to skip running this script in incremental builds |
| runForInstallBuildsOnly | Whether this script only runs on install builds (default is false) |
| shellPath | The path to the shell which shall execute this script. Default is `/bin/sh`. |
| dependencyFile | The path to the dependency file. Default is `nil`. |

### `post(tool:arguments:name:inputPaths:inputFileListPaths:outputPaths:outputFileListPaths:basedOnDependencyAnalysis:runForInstallBuildsOnly:shellPath:dependencyFile:)`

```swift
public static func post(
    tool: String,
    arguments: [String],
    name: String,
    inputPaths: [FileListGlob] = [],
    inputFileListPaths: [Path] = [],
    outputPaths: [Path] = [],
    outputFileListPaths: [Path] = [],
    basedOnDependencyAnalysis: Bool? = nil,
    runForInstallBuildsOnly: Bool = false,
    shellPath: String = "/bin/sh",
    dependencyFile: Path? = nil
) -> TargetScript
```

Returns a target script that gets executed after the sources and resources build phase.

- Parameters:
  - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
  - arguments: Arguments that to be passed.
  - name: Name of the build phase when the project gets generated.
  - inputPaths: Glob pattern to the files.
  - inputFileListPaths: List of input filelist paths.
  - outputPaths: List of output file paths.
  - outputFileListPaths: List of output filelist paths.
  - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
  - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
  - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
  - dependencyFile: The path to the dependency file. Default is `nil`.
- Returns: Target script.

#### Parameters

| Name | Description |
| ---- | ----------- |
| tool | Name of the tool to execute. Tuist will look up the tool on the environment’s PATH. |
| arguments | Arguments that to be passed. |
| name | Name of the build phase when the project gets generated. |
| inputPaths | Glob pattern to the files. |
| inputFileListPaths | List of input filelist paths. |
| outputPaths | List of output file paths. |
| outputFileListPaths | List of output filelist paths. |
| basedOnDependencyAnalysis | Whether to skip running this script in incremental builds |
| runForInstallBuildsOnly | Whether this script only runs on install builds (default is false) |
| shellPath | The path to the shell which shall execute this script. Default is `/bin/sh`. |
| dependencyFile | The path to the dependency file. Default is `nil`. |

### `pre(script:name:inputPaths:inputFileListPaths:outputPaths:outputFileListPaths:basedOnDependencyAnalysis:runForInstallBuildsOnly:shellPath:dependencyFile:)`

```swift
public static func pre(
    script: String,
    name: String,
    inputPaths: [FileListGlob] = [],
    inputFileListPaths: [Path] = [],
    outputPaths: [Path] = [],
    outputFileListPaths: [Path] = [],
    basedOnDependencyAnalysis: Bool? = nil,
    runForInstallBuildsOnly: Bool = false,
    shellPath: String = "/bin/sh",
    dependencyFile: Path? = nil
) -> TargetScript
```

Returns a target script that gets executed before the sources and resources build phase.

- Parameters:
  - script: The text of the script to run. This should be kept small.
  - arguments: Arguments that to be passed.
  - name: Name of the build phase when the project gets generated.
  - inputPaths: Glob pattern to the files.
  - inputFileListPaths: List of input filelist paths.
  - outputPaths: List of output file paths.
  - outputFileListPaths: List of output filelist paths.
  - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
  - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
  - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
  - dependencyFile: The path to the dependency file. Default is `nil`.
- Returns: Target script.

#### Parameters

| Name | Description |
| ---- | ----------- |
| script | The text of the script to run. This should be kept small. |
| arguments | Arguments that to be passed. |
| name | Name of the build phase when the project gets generated. |
| inputPaths | Glob pattern to the files. |
| inputFileListPaths | List of input filelist paths. |
| outputPaths | List of output file paths. |
| outputFileListPaths | List of output filelist paths. |
| basedOnDependencyAnalysis | Whether to skip running this script in incremental builds |
| runForInstallBuildsOnly | Whether this script only runs on install builds (default is false) |
| shellPath | The path to the shell which shall execute this script. Default is `/bin/sh`. |
| dependencyFile | The path to the dependency file. Default is `nil`. |

### `post(script:name:inputPaths:inputFileListPaths:outputPaths:outputFileListPaths:basedOnDependencyAnalysis:runForInstallBuildsOnly:shellPath:dependencyFile:)`

```swift
public static func post(
    script: String,
    name: String,
    inputPaths: [FileListGlob] = [],
    inputFileListPaths: [Path] = [],
    outputPaths: [Path] = [],
    outputFileListPaths: [Path] = [],
    basedOnDependencyAnalysis: Bool? = nil,
    runForInstallBuildsOnly: Bool = false,
    shellPath: String = "/bin/sh",
    dependencyFile: Path? = nil
) -> TargetScript
```

Returns a target script that gets executed after the sources and resources build phase.

- Parameters:
  - script: The script to be executed.
  - name: Name of the build phase when the project gets generated.
  - inputPaths: Glob pattern to the files.
  - inputFileListPaths: List of input filelist paths.
  - outputPaths: List of output file paths.
  - outputFileListPaths: List of output filelist paths.
  - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
  - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
  - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
  - dependencyFile: The path to the dependency file. Default is `nil`.
- Returns: Target script.

#### Parameters

| Name | Description |
| ---- | ----------- |
| script | The script to be executed. |
| name | Name of the build phase when the project gets generated. |
| inputPaths | Glob pattern to the files. |
| inputFileListPaths | List of input filelist paths. |
| outputPaths | List of output file paths. |
| outputFileListPaths | List of output filelist paths. |
| basedOnDependencyAnalysis | Whether to skip running this script in incremental builds |
| runForInstallBuildsOnly | Whether this script only runs on install builds (default is false) |
| shellPath | The path to the shell which shall execute this script. Default is `/bin/sh`. |
| dependencyFile | The path to the dependency file. Default is `nil`. |