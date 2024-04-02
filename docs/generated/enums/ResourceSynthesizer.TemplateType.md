**ENUM**

# `ResourceSynthesizer.TemplateType`

**Contents**

- [Cases](#cases)
  - `plugin(name:resourceName:)`
  - `defaultTemplate(resourceName:)`

```swift
public enum TemplateType: Codable, Equatable
```

Templates can be either a local template file, from a plugin, or a default template from tuist

## Cases
### `plugin(name:resourceName:)`

```swift
case plugin(name: String, resourceName: String)
```

Plugin template file
`name` is a name of a plugin
`resourceName` is a name of the resource - that is used for finding a template as well as naming the resulting
`.swift` file

### `defaultTemplate(resourceName:)`

```swift
case defaultTemplate(resourceName: String)
```

Default template defined `Tuist/{ProjectName}`, or if not present there, in tuist itself
`resourceName` is used for the name of the resulting `.swift` file
