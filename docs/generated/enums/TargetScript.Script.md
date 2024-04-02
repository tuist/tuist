**ENUM**

# `TargetScript.Script`

**Contents**

- [Cases](#cases)
  - `tool(path:args:)`
  - `scriptPath(path:args:)`
  - `embedded(_:)`

```swift
public enum Script: Equatable, Codable
```

Specifies how to execute the target script

- tool: Executes the tool with the given arguments. Tuist will look up the tool on the environment's PATH.
- scriptPath: Executes the file at the path with the given arguments.
- text: Executes the embedded script. This should be a short command.

## Cases
### `tool(path:args:)`

```swift
case tool(path: String, args: [String])
```

### `scriptPath(path:args:)`

```swift
case scriptPath(path: Path, args: [String])
```

### `embedded(_:)`

```swift
case embedded(String)
```
