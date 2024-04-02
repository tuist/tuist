**STRUCT**

# `ResourceSynthesizer`

```swift
public struct ResourceSynthesizer: Codable, Equatable
```

A resource synthesizer for given file extensions.

For example to synthesize resource accessors for strings, you can use:
- `.strings()` for tuist's default
- `.strings(parserOptions: ["separator": "/"])` to use strings template with SwiftGen Parser Options
- `.strings(plugin: "MyPlugin")` to use strings template from a plugin
- `.strings(templatePath: "Templates/Strings.stencil")` to use strings template at a given path

## Properties
### `templateType`

```swift
public var templateType: TemplateType
```

Templates can be of multiple types

### `parser`

```swift
public var parser: Parser
```

### `parserOptions`

```swift
public var parserOptions: [String: Parser.Option]
```

### `extensions`

```swift
public var extensions: Set<String>
```

## Methods
### `strings(parserOptions:)`

```swift
public static func strings(parserOptions: [String: Parser.Option] = [:]) -> Self
```

Default strings synthesizer defined in `Tuist/{ProjectName}` or tuist itself

### `strings(plugin:parserOptions:)`

```swift
public static func strings(
    plugin: String,
    parserOptions: [String: Parser.Option] = [:]
) -> Self
```

Strings synthesizer defined in a plugin

### `assets(parserOptions:)`

```swift
public static func assets(parserOptions: [String: Parser.Option] = [:]) -> Self
```

Default assets synthesizer defined in `Tuist/{ProjectName}` or tuist itself

### `assets(plugin:parserOptions:)`

```swift
public static func assets(
    plugin: String,
    parserOptions: [String: Parser.Option] = [:]
) -> Self
```

Assets synthesizer defined in a plugin

### `fonts(parserOptions:)`

```swift
public static func fonts(parserOptions: [String: Parser.Option] = [:]) -> Self
```

Default fonts synthesizer defined in `Tuist/{ProjectName}` or tuist itself

### `fonts(plugin:parserOptions:)`

```swift
public static func fonts(
    plugin: String,
    parserOptions: [String: Parser.Option] = [:]
) -> Self
```

Fonts synthesizer defined in a plugin

### `plists(parserOptions:)`

```swift
public static func plists(parserOptions: [String: Parser.Option] = [:]) -> Self
```

Default plists synthesizer defined in `Tuist/{ProjectName}` or tuist itself

### `plists(plugin:parserOptions:)`

```swift
public static func plists(
    plugin: String,
    parserOptions: [String: Parser.Option] = [:]
) -> Self
```

Plists synthesizer defined in a plugin

### `coreData(plugin:parserOptions:)`

```swift
public static func coreData(
    plugin: String,
    parserOptions: [String: Parser.Option] = [:]
) -> Self
```

CoreData synthesizer defined in a plugin

### `coreData(parserOptions:)`

```swift
public static func coreData(parserOptions: [String: Parser.Option] = [:]) -> Self
```

Default CoreData synthesizer defined in `Tuist/{ProjectName}`

### `interfaceBuilder(plugin:parserOptions:)`

```swift
public static func interfaceBuilder(
    plugin: String,
    parserOptions: [String: Parser.Option] = [:]
) -> Self
```

InterfaceBuilder synthesizer defined in a plugin

### `interfaceBuilder(parserOptions:)`

```swift
public static func interfaceBuilder(parserOptions: [String: Parser.Option] = [:]) -> Self
```

InterfaceBuilder synthesizer with a template defined in `Tuist/{ProjectName}`

### `json(plugin:parserOptions:)`

```swift
public static func json(plugin: String, parserOptions: [String: Parser.Option] = [:]) -> Self
```

JSON synthesizer defined in a plugin

### `json(parserOptions:)`

```swift
public static func json(parserOptions: [String: Parser.Option] = [:]) -> Self
```

JSON synthesizer with a template defined in `Tuist/{ProjectName}`

### `yaml(plugin:parserOptions:)`

```swift
public static func yaml(plugin: String, parserOptions: [String: Parser.Option] = [:]) -> Self
```

YAML synthesizer defined in a plugin

### `yaml(parserOptions:)`

```swift
public static func yaml(parserOptions: [String: Parser.Option] = [:]) -> Self
```

CoreData synthesizer with a template defined in `Tuist/{ProjectName}`

### `files(plugin:parserOptions:extensions:)`

```swift
public static func files(
    plugin: String,
    parserOptions: [String: Parser.Option] = [:],
    extensions: Set<String>
) -> Self
```

Files synthesizer defined in a plugin

### `files(parserOptions:extensions:)`

```swift
public static func files(
    parserOptions: [String: Parser.Option] = [:],
    extensions: Set<String>
) -> Self
```

Files synthesizer with a template defined in `Tuist/{ProjectName}`

### `custom(plugin:parser:parserOptions:extensions:resourceName:)`

```swift
public static func custom(
    plugin: String,
    parser: Parser,
    parserOptions: [String: Parser.Option] = [:],
    extensions: Set<String>,
    resourceName: String
) -> Self
```

Custom synthesizer from a plugin
- Parameters:
    - plugin: Name of a plugin where resource synthesizer template is located
    - parser: `Parser` to use for parsing the file to obtain its data
    - extensions: Set of extensions that should be parsed
    - resourceName: Name of the template file and the resulting `.swift` file

#### Parameters

| Name | Description |
| ---- | ----------- |
| plugin | Name of a plugin where resource synthesizer template is located |
| parser | `Parser` to use for parsing the file to obtain its data |
| extensions | Set of extensions that should be parsed |
| resourceName | Name of the template file and the resulting `.swift` file |

### `custom(name:parser:parserOptions:extensions:)`

```swift
public static func custom(
    name: String,
    parser: Parser,
    parserOptions: [String: Parser.Option] = [:],
    extensions: Set<String>
) -> Self
```

Custom local synthesizer defined `Tuist/ResourceSynthesizers/{name}.stencil`
- Parameters:
    - name: Name of synthesizer
    - parser: `Parser` to use for parsing the file to obtain its data
    - extensions: Set of extensions that should be parsed

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | Name of synthesizer |
| parser | `Parser` to use for parsing the file to obtain its data |
| extensions | Set of extensions that should be parsed |