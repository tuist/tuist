**ENUM**

# `FileHeaderTemplate`

```swift
public enum FileHeaderTemplate: Codable, Equatable, ExpressibleByStringInterpolation
```

A header template from a file or a string.

Lets you define custom file header template for built-in Xcode templates, e.g. when you create new Swift file you can
automatically have your custom define file header.

Tuist automatically performs several template transformations for you
 - if your template starts with comment slashes (`//`) we remove them as they are added automatically by Xcode
 - if your template doesn't start with comment and whitespace or newline, we add a space - otherwise your header would be
glued to implicit comment slashes which you probably do not want
 - if your template has trailing newline, we remove it as it is implicitly added by Xcode

## Cases
### `file(_:)`

```swift
case file(Path)
```

Load template stored in file

### `string(_:)`

```swift
case string(String)
```

Use inline string as template

## Methods
### `init(stringLiteral:)`

```swift
public init(stringLiteral value: String)
```

Creates file template as `.string(value)`
