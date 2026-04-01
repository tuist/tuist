**STRUCT**

# `SourceFileGlob`

**Contents**

- [Properties](#properties)
  - `glob`
  - `excluding`
  - `compilerFlags`
  - `codeGen`
  - `compilationCondition`
  - `type`
- [Methods](#methods)
  - `glob(_:excluding:compilerFlags:codeGen:compilationCondition:)`
  - `glob(_:excluding:compilerFlags:codeGen:compilationCondition:)`
  - `generated(_:compilerFlags:codeGen:compilationCondition:)`

```swift
public struct SourceFileGlob: Codable, Equatable, Sendable
```

A glob pattern configuration representing source files and its compiler flags, if any.

## Properties
### `glob`

```swift
public var glob: Path
```

Glob pattern to the source files.

### `excluding`

```swift
public var excluding: [Path]
```

Glob patterns for source files that will be excluded.

### `compilerFlags`

```swift
public var compilerFlags: String?
```

The compiler flags to be set to the source files in the sources build phase.

### `codeGen`

```swift
public var codeGen: FileCodeGen?
```

The source file attribute to be set in the build phase.

### `compilationCondition`

```swift
public var compilationCondition: PlatformCondition?
```

Source file condition for compilation

### `type`

```swift
public var type: FileType
```

Type of the file.

## Methods
### `glob(_:excluding:compilerFlags:codeGen:compilationCondition:)`

```swift
public static func glob(
    _ glob: Path,
    excluding: [Path] = [],
    compilerFlags: String? = nil,
    codeGen: FileCodeGen? = nil,
    compilationCondition: PlatformCondition? = nil
) -> Self
```

Returns a source glob pattern configuration.
Used for file there were already present during the generation.

- Parameters:
  - glob: Glob pattern to the source files.
  - excluding: Glob patterns for source files that will be excluded.
  - compilerFlags: The compiler flags to be set to the source files in the sources build phase.
  - codeGen: The source file attribute to be set in the build phase.
  - compilationCondition: Condition for file compilation.

#### Parameters

| Name | Description |
| ---- | ----------- |
| glob | Glob pattern to the source files. |
| excluding | Glob patterns for source files that will be excluded. |
| compilerFlags | The compiler flags to be set to the source files in the sources build phase. |
| codeGen | The source file attribute to be set in the build phase. |
| compilationCondition | Condition for file compilation. |

### `glob(_:excluding:compilerFlags:codeGen:compilationCondition:)`

```swift
public static func glob(
    _ glob: Path,
    excluding: Path?,
    compilerFlags: String? = nil,
    codeGen: FileCodeGen? = nil,
    compilationCondition: PlatformCondition? = nil
) -> Self
```

### `generated(_:compilerFlags:codeGen:compilationCondition:)`

```swift
public static func generated(
    _ path: Path,
    compilerFlags: String? = nil,
    codeGen: FileCodeGen? = nil,
    compilationCondition: PlatformCondition? = nil
) -> Self
```

Returns a source generated source file configuration, for a single generated file.

- Parameters:
  - path: Path to the generated file. Assumed to be a specific path (as oppose to a glob pattern).
  - compilerFlags: The compiler flags to be set to the source files in the sources build phase.
  - codeGen: The source file attribute to be set in the build phase.
  - compilationCondition: Condition for file compilation.

#### Parameters

| Name | Description |
| ---- | ----------- |
| path | Path to the generated file. Assumed to be a specific path (as oppose to a glob pattern). |
| compilerFlags | The compiler flags to be set to the source files in the sources build phase. |
| codeGen | The source file attribute to be set in the build phase. |
| compilationCondition | Condition for file compilation. |