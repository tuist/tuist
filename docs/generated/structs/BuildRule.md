**STRUCT**

# `BuildRule`

```swift
public struct BuildRule: Codable, Equatable
```

A BuildRule is used to specify a method for transforming an input file in to an output file(s).

## Properties
### `compilerSpec`

```swift
public var compilerSpec: CompilerSpec
```

Compiler specification for element transformation.

### `filePatterns`

```swift
public var filePatterns: String?
```

Regex pattern when `sourceFilesWithNamesMatching` is used.

### `fileType`

```swift
public var fileType: FileType
```

File types which are processed by build rule.

### `name`

```swift
public var name: String?
```

Build rule name.

### `outputFiles`

```swift
public var outputFiles: [String]
```

Build rule output files.

### `inputFiles`

```swift
public var inputFiles: [String]
```

Build rule input files.

### `outputFilesCompilerFlags`

```swift
public var outputFilesCompilerFlags: [String]
```

Build rule output files compiler flags.

### `script`

```swift
public var script: String?
```

Build rule custom script when `customScript` is used.

### `runOncePerArchitecture`

```swift
public var runOncePerArchitecture: Bool?
```

Build rule run once per architecture.

## Methods
### `buildRule(name:fileType:filePatterns:compilerSpec:inputFiles:outputFiles:outputFilesCompilerFlags:script:runOncePerArchitecture:)`

```swift
public static func buildRule(
    name: String? = nil,
    fileType: FileType,
    filePatterns: String? = nil,
    compilerSpec: CompilerSpec,
    inputFiles: [String] = [],
    outputFiles: [String] = [],
    outputFilesCompilerFlags: [String] = [],
    script: String? = nil,
    runOncePerArchitecture: Bool = false
) -> Self
```
