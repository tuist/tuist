**EXTENSION**

# `Template.Item`
```swift
extension Template.Item
```

## Methods
### `string(path:contents:)`

```swift
public static func string(path: String, contents: String) -> Template.Item
```

- Parameters:
    - path: Path where to generate file
    - contents: String Contents
- Returns: `Template.Item` that is `.string`

#### Parameters

| Name | Description |
| ---- | ----------- |
| path | Path where to generate file |
| contents | String Contents |

### `file(path:templatePath:)`

```swift
public static func file(path: String, templatePath: Path) -> Template.Item
```

- Parameters:
    - path: Path where to generate file
    - templatePath: Path of file where the template is defined
- Returns: `Template.Item` that is `.file`

#### Parameters

| Name | Description |
| ---- | ----------- |
| path | Path where to generate file |
| templatePath | Path of file where the template is defined |

### `directory(path:sourcePath:)`

```swift
public static func directory(path: String, sourcePath: Path) -> Template.Item
```

- Parameters:
    - path: Path where will be copied the folder
    - sourcePath: Path of folder which will be copied
- Returns: `Template.Item` that is `.directory`

#### Parameters

| Name | Description |
| ---- | ----------- |
| path | Path where will be copied the folder |
| sourcePath | Path of folder which will be copied |