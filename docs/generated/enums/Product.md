**ENUM**

# `Product`

**Contents**

- [Cases](#cases)
  - `app`
  - `staticLibrary`
  - `dynamicLibrary`
  - `framework`
  - `staticFramework`
  - `unitTests`
  - `uiTests`
  - `bundle`
  - `commandLineTool`
  - `appClip`
  - `appExtension`
  - `watch2App`
  - `watch2Extension`
  - `tvTopShelfExtension`
  - `messagesExtension`
  - `stickerPackExtension`
  - `xpc`
  - `systemExtension`
  - `extensionKitExtension`
  - `macro`

```swift
public enum Product: String, Codable, Equatable
```

Possible products types.

## Cases
### `app`

```swift
case app
```

An application.

### `staticLibrary`

```swift
case staticLibrary = "static_library"
```

A static library.

### `dynamicLibrary`

```swift
case dynamicLibrary = "dynamic_library"
```

A dynamic library.

### `framework`

```swift
case framework
```

A dynamic framework.

### `staticFramework`

```swift
case staticFramework
```

A static framework.

### `unitTests`

```swift
case unitTests = "unit_tests"
```

A unit tests bundle.

### `uiTests`

```swift
case uiTests = "ui_tests"
```

A UI tests bundle.

### `bundle`

```swift
case bundle
```

A custom bundle. (currently only iOS resource bundles are supported).

### `commandLineTool`

```swift
case commandLineTool
```

A command line tool (macOS platform only).

### `appClip`

```swift
case appClip
```

An appClip. (iOS platform only).

### `appExtension`

```swift
case appExtension = "app_extension"
```

An application extension.

### `watch2App`

```swift
case watch2App
```

A Watch application. (watchOS platform only) .

### `watch2Extension`

```swift
case watch2Extension
```

A Watch application extension. (watchOS platform only).

### `tvTopShelfExtension`

```swift
case tvTopShelfExtension
```

A TV Top Shelf Extension.

### `messagesExtension`

```swift
case messagesExtension
```

An iMessage extension. (iOS platform only)

### `stickerPackExtension`

```swift
case stickerPackExtension = "sticker_pack_extension"
```

A sticker pack extension.

### `xpc`

```swift
case xpc
```

An XPC. (macOS platform only).

### `systemExtension`

```swift
case systemExtension
```

An system extension. (macOS platform only).

### `extensionKitExtension`

```swift
case extensionKitExtension = "extension_kit_extension"
```

An ExtensionKit extension.

### `macro`

```swift
case macro
```

A Swift Macro
Although Apple doesn't officially support Swift Macro Xcode Project targets, we
enable them by adding a command line tool target, a target dependency in
the dependent targets, and the right build settings to use the macro executable.
